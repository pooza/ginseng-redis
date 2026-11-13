module Ginseng
  module Redis
    # 🔴 サブクラスが `self.dsn` を上書きしたら、`url` を渡さない `new` はそれを使う。
    # `Service.dsn` と決め打ちしていたので、利用側は `initialize` を丸ごと写すしかなかった。
    class SubclassDSNTest < TestCase
      class CustomService < Service
        def self.dsn
          return DSN.parse('redis://localhost:6379/7')
        end
      end

      def test_subclass_dsn
        assert_equal(7, CustomService.new.redis.config.db)
      end

      def test_url_param_wins
        assert_equal(3, CustomService.new(url: 'redis://localhost:6379/3').redis.config.db)
      end
    end
  end
end
