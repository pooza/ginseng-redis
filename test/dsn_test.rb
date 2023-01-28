module Ginseng::Redis
  class DSNTest < TestCase
    def setup
      @dsn = DSN.parse('redis://localhost:6379/1')
    end

    def test_parse
      assert_kind_of(DSN, @dsn)
    end

    def test_scheme
      assert_equal(@dsn.scheme, 'redis')
    end

    def test_host
      assert_equal(@dsn.host, 'localhost')
    end

    def test_port
      assert_equal(@dsn.port, 6379)
    end

    def test_db
      assert_equal(@dsn.db, 1)
    end
  end
end
