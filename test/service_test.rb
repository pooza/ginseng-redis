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
