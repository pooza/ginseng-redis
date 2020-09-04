module Ginseng
  module Redis
    class TestCaseFilter < Ginseng::TestCaseFilter
      include Package

      def self.create(name)
        Config.instance['/test/filters'].each do |entry|
          next unless entry['name'] == name
          return "Ginseng::Redis::#{name.camelize}TestCaseFilter".constantize.new(entry)
        end
      end

      def self.all
        return enum_for(__method__) unless block_given?
        Config.instance['/test/filters'].each do |entry|
          yield TestCaseFilter.create(entry['name'])
        end
      end
    end
  end
end
