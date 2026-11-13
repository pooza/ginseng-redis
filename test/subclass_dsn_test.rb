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

      # ⚠ 未設定やサブクラスが DSN 以外を返したら、NoMethodError ではなく原因の分かる Error にする。
      def test_unconfigured_dsn
        [nil, 'redis://localhost:6379/1'].each do |value|
          service_class = Class.new(Service) {define_singleton_method(:dsn) {value}}
          error = assert_raise(Error, value.inspect) {service_class.new}

          assert_include(error.message, 'DSN is not configured', value.inspect)
        end
      end

      # 🔴 不正な DSN の例外メッセージにパスワードを載せない。
      def test_invalid_dsn_hides_the_password
        service_class = Class.new(Service) {define_singleton_method(:dsn) {DSN.parse('//:s3cret@localhost:6379/1')}}
        error = assert_raise(Error) {service_class.new}

        assert_not_include(error.message, 's3cret')
        assert_include(error.message, 'localhost')
      end

      def test_url_param_wins
        assert_equal(3, CustomService.new(url: 'redis://localhost:6379/3').redis.config.db)
      end
    end
  end
end
