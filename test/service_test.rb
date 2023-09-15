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

      def test_save
        assert(@service.save)
      end
    end
  end
end
