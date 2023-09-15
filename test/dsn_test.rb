module Ginseng
  module Redis
    class DSNTest < TestCase
      def setup
        @dsn = DSN.parse('redis://localhost:6379/1')
      end

      def test_parse
        assert_kind_of(DSN, @dsn)
      end

      def test_scheme
        assert_equal('redis', @dsn.scheme)
      end

      def test_host
        assert_equal('localhost', @dsn.host)
      end

      def test_port
        assert_equal(6379, @dsn.port)
      end

      def test_db
        assert_equal(1, @dsn.db)
      end
    end
  end
end
