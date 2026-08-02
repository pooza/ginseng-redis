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

      def incr(key)
        cnt ||= 0
        return redis.call('INCR', create_key(key))
      rescue => e
        cnt += 1
        @logger.error(error: e, count: cnt)
        raise Error, e.message, e.backtrace unless cnt < retry_limit
        sleep(retry_seconds)
        retry
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
