require 'redis'

module Ginseng
  module Redis
    class Service < ::Redis
      def initialize
        dsn = Service.dsn
        dsn.db ||= 1
        @logger = Logger.new
        @config = Config.instance
        raise Error, "Invalid DSN '#{dsn}'" unless dsn.absolute?
        raise Error, "Invalid scheme '#{dsn.scheme}'" unless dsn.scheme == 'redis'
        super(url: dsn.to_s)
      end

      def get(key)
        return super
      rescue => e
        raise Error, e.message, e.backtrace
      end

      def set(key, value)
        return super
      rescue => e
        raise Error, e.message, e.backtrace
      end

      def unlink(key)
        return super
      rescue => e
        raise Error, e.message, e.backtrace
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

      def self.dsn
        return DSN.parse(Config.instance['/redis/dsn'])
      end
    end
  end
end
