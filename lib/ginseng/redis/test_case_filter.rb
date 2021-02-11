module Ginseng
  module Redis
    class TestCaseFilter < Ginseng::TestCaseFilter
      include Package

      def self.create(name)
        all do |filter|
          return filter if filter.name == name
        end
      end

      def self.all
        return enum_for(__method__) unless block_given?
        Config.instance.raw.dig('test', 'filters').each do |entry|
          yield "Ginseng::Redis::#{entry['name'].camelize}TestCaseFilter".constantize.new(entry)
        end
      end
    end
  end
end
