module Ginseng
  module Redis
    class ServiceTest < TestCase
      def setup
        @service = Service.new
      end

      def test_key?
        key = SecureRandom.hex

        assert_false(@service.key?(key))
        @service[key] = 1

        assert(@service.key?(key))
        @service[key] = nil

        assert(@service.key?(key))
        @service.del(key)

        assert_false(@service.key?(key))
      end

      def test_edit
        assert_equal('OK', @service.set(__dir__, '一兆度の炎'))
        assert_equal('一兆度の炎', @service.get(__dir__))
        assert_equal(1, @service.del(__dir__))
      end

      # 失敗だけを返すクライアント。⚠ **何回撃ったか**を測るのが目的。
      class RaisingClient
        attr_reader :calls

        def initialize(error)
          @error = error
          @calls = 0
        end

        def call(*_args)
          @calls += 1
          raise @error
        end
      end

      # 記録だけする logger。⚠ **再送しない以上、ログの中身が唯一の跡**になる。
      class Recorder
        attr_reader :logs

        def initialize
          @logs = []
        end

        [:error, :warn, :info, :debug, :fatal].each do |severity|
          define_method(severity) do |message = nil|
            @logs.push([severity, message])
            return true
          end
        end
      end

      # 🔴 **数えてから出す (#56 Codex P2)。** ⚠⚠ そのまま出すと初回が `count: 0` になり、
      # **再送側の経路と数が食い違う**。
      def test_incr_counts_the_failure_it_did_not_retry
        client = RaisingClient.new(RedisClient::ReadTimeoutError)
        logger = Recorder.new
        @service.instance_variable_set(:@redis, client)
        @service.instance_variable_set(:@logger, logger)

        assert_raise(Error) {@service.incr(SecureRandom.hex)}
        assert_equal(1, logger.logs.last.last[:count])
        assert_false(logger.logs.last.last[:retried])
      end

      # 🔴🔴 **曖昧な失敗では撃ち直さない (#56)。**
      #
      # ⚠⚠ `INCR` は冪等ではないので、応答を受け取る前に切れただけなら
      # **Redis 側では実行済みかもしれない**。🔴 撃ち直すとカウンタが二重に進む。
      def test_incr_does_not_retry_an_ambiguous_failure
        client = RaisingClient.new(RedisClient::ReadTimeoutError)
        @service.instance_variable_set(:@redis, client)

        assert_raise(Error) {@service.incr(SecureRandom.hex)}
        assert_equal(1, client.calls, '曖昧な失敗では撃ち直さないこと')
      end

      # ⚠ **サーバが答えている失敗も撃ち直さない**（値が数字でない等）。
      # 🔴 同じ結果になるだけで、待ち時間を伸ばすだけ。
      def test_incr_does_not_retry_a_command_error
        client = RaisingClient.new(RedisClient::CommandError.new('ERR value is not an integer'))
        @service.instance_variable_set(:@redis, client)

        assert_raise(Error) {@service.incr(SecureRandom.hex)}
        assert_equal(1, client.calls)
      end

      # 🔴🔴 **前提そのものを固定する (#56)。**
      #
      # ⚠⚠ `incr` が撃ち直さないと決めても、**下の層が撃ち直したら二重に進む**。
      # `redis-client` は `reconnect_attempts` の既定が `false` なので再送しないが、
      # ⚠ **開いても何も落ちない**（テストは全部 fake client を刺すので下の層を通らない）ため、
      # ここで素の設定を直に測る。🔴 `reconnect_attempts: 1` を足すと**この 1 件だけが落ちる**。
      def test_the_client_itself_does_not_resend
        assert_false(
          @service.redis.config.retry_connecting?(0, RedisClient::ConnectionError.new('x')),
          'redis-client 自身が再送しないこと',
        )
      end

      # ⚠ **再送した側にも同じ印が付くこと。** 🔴 片側にしか無いと、
      # `command: 'INCR'` で絞った operator から**再送の経路だけが消える**。
      def test_incr_marks_the_retried_failure_too
        client = RaisingClient.new(RedisClient::CannotConnectError)
        logger = Recorder.new
        @service.instance_variable_set(:@redis, client)
        @service.instance_variable_set(:@logger, logger)
        @service.define_singleton_method(:retry_seconds) {0}

        assert_raise(Error) {@service.incr(SecureRandom.hex)}
        assert_equal('INCR', logger.logs.last.last[:command])
        assert_true(logger.logs.last.last[:retried])
      end

      # ⚠ **確実に届いていないときは従来どおり再送する (#56)。**
      # 🔴🔴 ここまで止めると、**一過性の接続失敗で毎回落ちる**ことになる。
      def test_incr_retries_when_the_connection_could_not_be_made
        client = RaisingClient.new(RedisClient::CannotConnectError)
        @service.instance_variable_set(:@redis, client)
        @service.define_singleton_method(:retry_seconds) {0}

        assert_raise(Error) {@service.incr(SecureRandom.hex)}
        assert_equal(3, client.calls, '接続が張れないときは再送すること')
      end

      def test_incr
        key = SecureRandom.hex
        @service.del(key)

        assert_equal(1, @service.incr(key))
        assert_equal(2, @service.incr(key))
        assert_equal('2', @service.get(key))
        @service.del(key)
      end

      def test_save
        assert(@service.save)
      end

      class PrefixedService < Service
        def prefix
          return 'ginseng_redis_test'
        end
      end

      # create_key が引数の String を破壊しないこと。破壊していた頃は、同じ
      # String を使い回すと 2 回目以降に prefix が剥がれた別のキーを引いていた (#51)。
      def test_create_key_does_not_mutate_argument
        service = PrefixedService.new
        key = +'ginseng_redis_test:hoge'

        assert_equal('ginseng_redis_test:hoge', service.create_key(key))
        assert_equal('ginseng_redis_test:hoge', key)
        assert_equal('ginseng_redis_test:hoge', service.create_key(key))
      end

      # Ruby 4 の frozen literal でも FrozenError にならないこと (#51)。
      def test_create_key_accepts_frozen_string
        service = PrefixedService.new

        frozen = 'hoge'.freeze

        assert_equal('ginseng_redis_test:hoge', service.create_key(frozen))
      end

      # 既に prefix が付いたキーを二重に付与しない（元の挙動の維持）。
      def test_create_key_does_not_duplicate_prefix
        service = PrefixedService.new

        assert_equal('ginseng_redis_test:hoge', service.create_key('ginseng_redis_test:hoge'))
      end
    end
  end
end
