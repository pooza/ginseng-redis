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

      # ⚠ DB 番号の無い DSN は DB 0（#82。以前の `dsn.db ||= 1` は効いていなかった）。
      def test_dsn_without_db_uses_db0
        service_class = Class.new(Service) {define_singleton_method(:dsn) {DSN.parse('redis://localhost:6379')}}

        assert_equal(0, service_class.new.redis.config.db)
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

      # 🔴 URL として読めない DSN でも、例外（と `cause`）にパスワードを載せない (#85)。
      # ⚠ 経路は 2 つ（`url:` を渡す／サブクラスの `dsn`）。
      def test_unparsable_dsn_hides_the_password
        ['redis://:p%ss@localhost/1', 'redis://:pa ss@localhost/1', 'redis://:pass@[localhost/1'].each do |url|
          secret = url[%r{//:([^@]+)@}, 1]
          [
            -> {Service.new(url:)},
            -> {Class.new(Service) {define_singleton_method(:dsn) {DSN.parse(url)}}.new},
          ].each do |create|
            error = assert_raise(Error, url) {create.call}

            assert_not_include(error.message, secret, url)
            assert_nil(error.cause, url)
          end
        end
      end

      # 🔴 パスワードの無い userinfo（`redis://<secret>@h`）も伏せる。redis-client はこれをパスワードとして読む。
      def test_user_only_userinfo_is_hidden
        ['redis://secretX@localhost/1%', 'redis://secretX@localhost/1 '].each do |url|
          error = assert_raise(Error, url) {Service.new(url:)}

          assert_not_include(error.message, 'secretX', url)
          assert_include(error.message, '[FILTERED]@localhost', url)
          assert_nil(error.cause, url)
        end
        service_class = Class.new(Service) {define_singleton_method(:dsn) {DSN.parse('//secretX@localhost:6379/1')}}
        error = assert_raise(Error) {service_class.new}

        assert_not_include(error.message, 'secretX')
      end

      # 🔴🔴 伏せ字を Addressable の setter に通さない (#90)。addressable 2.10.0 は `[` `]` を弾くので、
      # 代入で組むと伏せる処理そのものが落ち、平文の DSN を `cause` に付けたまま抜けていた。
      # ⚠ ポート・IPv6・スキーム無し・ユーザー名だけ・userinfo 無しの形を固定する。
      def test_filter_password_keeps_the_shape
        service = Service.new(url: 'redis://localhost:6379/1')

        {
          'redis://:s3cret@localhost/1' => 'redis://:[FILTERED]@localhost/1',
          'redis://user:s3cret@localhost:6380/2' => 'redis://user:[FILTERED]@localhost:6380/2',
          'redis://s3cret@localhost/1' => 'redis://[FILTERED]@localhost/1',
          'redis://user:s3cret@[::1]:6379/2' => 'redis://user:[FILTERED]@[::1]:6379/2',
          '//:s3cret@localhost:6379/1' => '//:[FILTERED]@localhost:6379/1',
          'redis://localhost/1' => 'redis://localhost/1',
        }.each do |src, expected|
          assert_equal(expected, service.send(:filter_password, DSN.parse(src)), src)
        end
      end

      # ⚠ 組めなければ DSN ごと伏せる。伏せる処理の失敗で平文を持ち出さない (#90)。
      def test_filter_password_hides_everything_when_it_cannot_build
        service = Service.new(url: 'redis://localhost:6379/1')
        dsn = DSN.parse('redis://:s3cret@localhost/1')
        dsn.define_singleton_method(:dup) {raise Addressable::URI::InvalidURIError, 'redis://:s3cret@localhost/1'}

        assert_equal('[FILTERED]', service.send(:filter_password, dsn))
      end

      # ⚠ 読める DSN は、伏せた形をメッセージに残す（原因の手掛かり）。
      def test_unparsable_dsn_keeps_the_filtered_dsn
        error = assert_raise(Error) {Service.new(url: 'redis://:p%ss@localhost/1')}

        assert_include(error.message, 'redis://:[FILTERED]@localhost/1')
      end

      # ⚠ `DSN.parse` 自体が落ちる（Addressable の例外）入力。`url:` の経路と、設定（`.dsn`）の経路。
      def test_addressable_error_is_wrapped
        ['redis://:secretX@local host/1', 'redis://:secretX@localhost:-1/1'].each do |url|
          error = assert_raise(Error, url) {Service.new(url:)}

          assert_not_include(error.message, 'secretX', url)
          assert_nil(error.cause, url)
        end
        [':secretX@localhost', 'redis://[:secretX@localhost]/1'].each do |value|
          service_class = Class.new(Service) {define_singleton_method(:dsn) {DSN.parse(value)}}
          error = assert_raise(Error, value) {service_class.new}

          assert_not_include(error.message, 'secretX', value)
          assert_nil(error.cause, value)
        end
      end

      # 🔴🔴 redis-client の `ArgumentError` も包む。Addressable が userinfo を読めない形（スラッシュが
      # 足りない typo・パスワードの `/`）は秘密がパスへ回るので、DSN ごと伏せる (#92)。⚠ 経路は 2 つ（`url:` を渡す／サブクラスの `dsn`）。
      def test_argument_error_hides_the_password
        [
          'redis:/:secretX@localhost/1',
          'redis://:secretX@localhost/1?db=%zz',
          # ⚠ パスワードにエンコードしない `/`（`/` の手前がホストとして読まれる）。
          'redis://default:/secretX@localhost:6379/1',
          'redis://ab/cdsecretX@localhost:6379/1',
        ].each do |url|
          [
            -> {Service.new(url:)},
            -> {Class.new(Service) {define_singleton_method(:dsn) {DSN.parse(url)}}.new},
          ].each do |create|
            error = assert_raise(Error, url) {create.call}

            assert_not_include(error.message, 'secretX', url)
            assert_nil(error.cause, url)
          end
        end
      end

      # ⚠ ホストのある DSN は、これまでどおり伏せた形を残す（原因の手掛かり）。
      def test_argument_error_keeps_the_filtered_dsn
        error = assert_raise(Error) {Service.new(url: 'redis://:secretX@localhost/abc')}

        assert_include(error.message, "'redis://:[FILTERED]@localhost/abc' (ArgumentError)")
      end

      # 🔴 知らないスキームの `ArgumentError` は URL を丸ごと載せるので、`url:` の経路でも先に見る。
      def test_unknown_scheme_hides_the_url
        ['http://:secretX@localhost/1', 'valkey://:secretX@localhost/1', 'tcp://secretX@localhost/1'].each do |url|
          error = assert_raise(Error, url) {Service.new(url:)}

          assert_not_include(error.message, 'secretX', url)
          assert_include(error.message, 'Invalid scheme', url)
        end
      end

      def test_url_param_wins
        assert_equal(3, CustomService.new(url: 'redis://localhost:6379/3').redis.config.db)
      end
    end
  end
end
