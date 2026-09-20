require 'redis-client'

module Ginseng
  module Redis
    class Service
      include Package

      attr_reader :redis, :config

      def initialize(params = {})
        @logger = logger_class.new
        @config = config_class.instance
        unless params[:url]
          dsn = Service.dsn
          dsn.db ||= 1
          raise Error, "Invalid DSN '#{dsn}'" unless dsn.absolute?
          raise Error, "Invalid scheme '#{dsn.scheme}'" unless dsn.scheme == 'redis'
          params[:url] = dsn.to_s
        end
        dsn = DSN.parse(params[:url])
        @redis = RedisClient.config(url: dsn.to_s).new_pool
      end

      def [](key)
        return get(key)
      end

      def []=(key, value)
        set(key, value)
      end

      def get(key)
        cnt ||= 0
        return redis.call('GET', create_key(key))
      rescue => e
        cnt += 1
        @logger.error(error: e, count: cnt)
        raise Error, e.message, e.backtrace unless cnt < retry_limit
        sleep(retry_seconds)
        retry
      end

      def set(key, value)
        cnt ||= 0
        value = '' if value.nil?
        return redis.call('SET', create_key(key), value)
      rescue => e
        cnt += 1
        @logger.error(error: e, count: cnt)
        raise Error, e.message, e.backtrace unless cnt < retry_limit
        sleep(retry_seconds)
        retry
      end

      def setex(key, ttl, value)
        cnt ||= 0
        return redis.call('SETEX', create_key(key), ttl, value)
      rescue => e
        cnt += 1
        @logger.error(error: e, count: cnt)
        raise Error, e.message, e.backtrace unless cnt < retry_limit
        sleep(retry_seconds)
        retry
      end

      # 🔴🔴 **`INCR` だけは再送しない (#56)。**
      #
      # ⚠⚠ **冪等ではないので、「届いたか分からない」失敗で撃ち直すとカウンタが
      # 二重に進む**。応答を受け取る前に切れただけなら、Redis 側では**実行済みかもしれない**。
      # 🔴 1 回の呼び出しで `retry_limit` 回まで進みうる（利用側の例:
      # `mulukhiya-toot-proxy` のヒステリシスのカウンタ — 多めに進むと**早すぎる通知**になる）。
      #
      # ⚠ **再送してよいのは「確実に届いていない」ときだけ** — 接続そのものが張れなかった
      # （`CannotConnectError`）場合。🔴 `ReadTimeoutError` / `WriteTimeoutError` / 素の
      # `ConnectionError` は**曖昧**なので再送しない。⚠⚠ `CommandError`（値が数字でない等）は
      # サーバが答えているので、再送しても同じ結果になる。
      #
      # ⚠ **他のコマンド（`GET` / `SET` / `SETEX` / `UNLINK`）は実質冪等**なので従来のまま。
      #
      # 🔴🔴 **ここで止めても、下の層が撃ち直したら意味がない。** ⚠⚠ `redis-client` は
      # `reconnect_attempts` の既定が `false` なので**自分では再送しない**（0.30.0 で実測）。
      # ⚠ `Service#initialize` はこの値を渡さないので開きようがないが、**開けば静かに元へ戻る**
      # 性質の前提なので、`test_the_client_itself_does_not_resend` で固定してある。
      def incr(key)
        cnt ||= 0
        return redis.call('INCR', create_key(key))
      rescue RedisClient::CannotConnectError => e
        cnt += 1
        # ⚠⚠ **再送した側にも同じ印を付ける。** 🔴 `command` と `retried` が片側にしか
        # 無いと、**`command: 'INCR'` で絞った operator から再送の経路だけが消える**。
        @logger.error(error: e, count: cnt, command: 'INCR', retried: true)
        raise Error, e.message, e.backtrace unless cnt < retry_limit
        sleep(retry_seconds)
        retry
      rescue => e
        # ⚠ **上げ直す前に残す。** 🔴 再送しないと決めた以上、**この 1 行が
        # 「進んだかもしれない」唯一の跡**になる。
        # ⚠⚠ **数えてから出す (#56 Codex P2)。** 🔴 そのまま出すと初回は `count: 0` になり、
        # **他の経路（再送側）と数が食い違う** — 唯一の跡が実際より少なく見える。
        cnt += 1
        @logger.error(error: e, count: cnt, command: 'INCR', retried: false)
        raise Error, e.message, e.backtrace
      end

      def key?(key)
        return keys(create_key(key)).present?
      end

      alias exist? key?

      def unlink(key)
        cnt ||= 0
        return redis.call('UNLINK', create_key(key))
      rescue => e
        cnt += 1
        @logger.error(error: e, count: cnt)
        raise Error, e.message, e.backtrace unless cnt < retry_limit
        sleep(retry_seconds)
        retry
      end

      alias del unlink

      def save
        cnt ||= 0
        return redis.call('SAVE')
      rescue => e
        cnt += 1
        @logger.error(error: e, count: cnt)
        raise Error, e.message, e.backtrace unless cnt < retry_limit
        sleep(retry_seconds)
        retry
      end

      def clear
        all_keys.each {|k| unlink(k)}
      end

      def keys(key)
        return redis.call('KEYS', key)
      end

      def all_keys
        return keys('*') unless prefix
        return keys("#{prefix}:*")
      end

      # prefix 付きのキーを作る。既に prefix が付いていれば二重付与しない。
      #
      # ⚠ 引数は変更しないこと。以前は `key.to_s.sub!` で呼び出し側の String を
      # 破壊しており（to_s は String に対して self を返す）、frozen なリテラルを
      # 渡すと FrozenError、使い回された String では 2 回目以降に prefix が
      # 剥がれた別のキーを引く、という二つの形で壊れていた (#51)。
      def create_key(key)
        return key unless prefix
        return "#{prefix}:#{key.to_s.sub(/^#{prefix}:/, '')}"
      end

      def prefix
        return nil
      end

      def retry_limit
        return config['/redis/retry/limit']
      end

      def retry_seconds
        return config['/redis/retry/seconds']
      end

      def self.dsn
        return DSN.parse(Config.instance['/redis/dsn'])
      end
    end
  end
end
