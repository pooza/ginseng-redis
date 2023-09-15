module Ginseng
  module Redis
    class ErrorTest < TestCase
      def setup
        raise Error, 'hoge'
      rescue => e
        @error = e
      end

      def test_create
        assert_kind_of(Error, @error)
      end

      def test_status
        assert_equal(500, @error.status)
      end
    end
  end
end
