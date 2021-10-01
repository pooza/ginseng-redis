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
        assert_equal(@service.set(__dir__, '一兆度の炎'), 'OK')
        assert_equal(@service.get(__dir__), '一兆度の炎')
        assert_equal(@service.del(__dir__), 1)
      end
    end
  end
end
