require 'redis'

module Ginseng
  module Redis
    class Service < ::Redis
      include Package

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
        super
      end

      def get(key)
        return super
      rescue => e
        raise Error, e.message, e.backtrace
      end

      def set(key, value)
        cnt ||= 0
        return super
      rescue => e
        cnt += 1
        @logger.error(error: e, count: cnt)
        raise Error, e.message, e.backtrace unless cnt < retry_limit
        sleep(retry_seconds)
        retry
      end

      def unlink(key)
        cnt ||= 0
        return super
      rescue => e
        cnt += 1
        @logger.error(error: e, count: cnt)
        raise Error, e.message, e.backtrace unless cnt < retry_limit
        sleep(retry_seconds)
        retry
      end

      alias del unlink

      def all_keys
        return keys('*') unless prefix
        return keys("#{prefix}:*")
      end

      def create_key(key)
        return key unless prefix
        return "#{prefix}:#{key}"
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
