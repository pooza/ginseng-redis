require 'redis-client'

module Ginseng
  module Redis
    class Service
      include Package

      # `url:` の経路で通すスキーム（redis-client の `URLConfig` が受けるもの）。→ `create_pool`
      URL_SCHEMES = ['redis', 'rediss', 'unix', nil].freeze

      # 例外メッセージで userinfo の代わりに出す文字列。→ `filter_password`
      FILTERED = '[FILTERED]'.freeze

      attr_reader :redis, :config

      def initialize(params = {})
        @logger = logger_class.new
        @config = config_class.instance
        unless params[:url]
          dsn = configured_dsn
          # ⚠ 未設定（`/redis/dsn: null`）やサブクラスが DSN 以外を返すと、下の `db` で原因の分からない
          # NoMethodError になっていた。
          unless dsn.is_a?(DSN)
            raise Error, "DSN is not configured (#{self.class}.dsn returned #{dsn.class})"
          end
          # ⚠ **DB 番号の無い DSN は DB 0 につながる (#82)。** 以前は `dsn.db ||= 1` があったが、`DSN#db` は
          # 番号が無くても `0`（真）を返すので代入されず、`DSN#db=` も無いので、何もしていなかった。
          # ⚠⚠ 意図どおり DB 1 に倒すと、番号を書かずに使っている利用側が別の DB を見る（破壊的）ので、
          # 実際の挙動（redis-client の既定と同じ DB 0）を仕様にした。
          # 🔴 **DSN をそのまま載せない。** `//:pass@host` の形でパスワードが例外メッセージに平文で出ていた。
          raise Error, "Invalid DSN '#{filter_password(dsn)}'" unless dsn.absolute?
          raise Error, "Invalid scheme '#{dsn.scheme}'" unless dsn.scheme == 'redis'
          params[:url] = dsn.to_s
        end
        @redis = create_pool(params[:url])
      end

      def [](key)
        return get(key)
      end

      def []=(key, value)
        set(key, value)
      end

      def get(key)
        return retrying('GET', key) {redis.call('GET', create_key(key))}
      end

      def set(key, value)
        value = '' if value.nil?
        return retrying('SET', key) {redis.call('SET', create_key(key), value)}
      end

      def setex(key, ttl, value)
        return retrying('SETEX', key) {redis.call('SETEX', create_key(key), ttl, value)}
      end

      # 🔴🔴 **`INCR` だけは再送しない (#56)。**
      #
      # ⚠⚠ **冪等ではないので、「届いたか分からない」失敗で撃ち直すとカウンタが
      # 二重に進む**。応答を受け取る前に切れただけなら、Redis 側では**実行済みかもしれない**。
      # 🔴 1 回の呼び出しで `retry_limit` 回まで進みうる（利用側の例:
      # `mulukhiya-toot-proxy` のヒステリシスのカウンタ — 多めに進むと**早すぎる通知**になる）。
      #
      # ⚠ **再送してよいのは「確実に届いていない」ときだけ** — 接続そのものが張れなかった
      # （`CannotConnectError`）場合。🔴 `ReadTimeoutError` / `WriteTimeoutError` / 素の
      # `ConnectionError` は**曖昧**なので再送しない。⚠⚠ `CommandError`（値が数字でない等）は
      # サーバが答えているので、再送しても同じ結果になる。
      #
      # ⚠ **他のコマンド（`GET` / `SET` / `SETEX` / `EXISTS` / `UNLINK` / `SAVE`）は実質冪等**なので
      # 従来のまま（`retrying`）。
      #
      # 🔴🔴 **ここで止めても、下の層が撃ち直したら意味がない。** ⚠⚠ `redis-client` は
      # `reconnect_attempts` の既定が `false` なので**自分では再送しない**（0.30.0 で実測）。
      # ⚠ `Service#initialize` はこの値を渡さないので開きようがないが、**開けば静かに元へ戻る**
      # 性質の前提なので、`test_the_client_itself_does_not_resend` で固定してある。
      def incr(key)
        cnt ||= 0
        return redis.call('INCR', create_key(key))
      rescue RedisClient::CannotConnectError => e
        cnt += 1
        # ⚠⚠ **再送した側にも同じ印を付ける。** 🔴 `command` と `retried` が片側にしか
        # 無いと、**`command: 'INCR'` で絞った operator から再送の経路だけが消える**。
        @logger.error(error: e, count: cnt, **log_target('INCR', key), retried: true)
        raise Error, e.message, e.backtrace unless cnt < retry_limit
        sleep(retry_seconds)
        retry
      rescue => e
        # ⚠ **上げ直す前に残す。** 🔴 再送しないと決めた以上、**この 1 行が
        # 「進んだかもしれない」唯一の跡**になる。
        # ⚠⚠ **数えてから出す (#56 Codex P2)。** 🔴 そのまま出すと初回は `count: 0` になり、
        # **他の経路（再送側）と数が食い違う** — 唯一の跡が実際より少なく見える。
        cnt += 1
        @logger.error(error: e, count: cnt, **log_target('INCR', key), retried: false)
        raise Error, e.message, e.backtrace
      end

      # ⚠⚠ **`KEYS` で引かない (#70)。** `KEYS` はキーを**パターン**として読むので、
      # `*` / `?` / `[` / `\` を含むキーで答えが狂う。🔴 URL の形のキー
      # （`?tags[]=a`）では**格納済みなのに false** になり、利用側のキャッシュが効かなかった。
      # ⚠ `KEYS` はキー空間全体を走査するブロッキング命令でもある。
      def key?(key)
        return retrying('EXISTS', key) {redis.call('EXISTS', create_key(key)).positive?}
      end

      alias exist? key?

      def unlink(key)
        return retrying('UNLINK', key) {redis.call('UNLINK', create_key(key))}
      end

      alias del unlink

      def save
        return retrying('SAVE') {redis.call('SAVE')}
      end

      def clear
        all_keys.each {|k| unlink(k)}
      end

      def keys(key)
        return redis.call('KEYS', key)
      end

      def all_keys
        return keys('*') unless prefix
        return keys("#{prefix}:*")
      end

      # prefix 付きのキーを作る。既に prefix が付いていれば二重付与しない。
      #
      # ⚠ 引数は変更しないこと。以前は `key.to_s.sub!` で呼び出し側の String を
      # 破壊しており（to_s は String に対して self を返す）、frozen なリテラルを
      # 渡すと FrozenError、使い回された String では 2 回目以降に prefix が
      # 剥がれた別のキーを引く、という二つの形で壊れていた (#51)。
      def create_key(key)
        return key unless prefix
        return "#{prefix}:#{key.to_s.sub(/^#{prefix}:/, '')}"
      end

      def prefix
        return nil
      end

      def retry_limit
        return config['/redis/retry/limit']
      end

      def retry_seconds
        return config['/redis/retry/seconds']
      end

      def self.dsn
        return DSN.parse(Config.instance['/redis/dsn'])
      end

      private

      # 🔴 **URL として読めない DSN の例外に、DSN を載せない (#85)。** `RedisClient.config` は
      # stdlib の `URI::InvalidURIError` を上げ、メッセージに URL を丸ごと載せる
      # （`redis://:p%ss@h/1` → `bad URI (is not URI?): "redis://:p%ss@h/1"`）。`url:` を渡す
      # 経路も同じ。⚠ 伏せた DSN を載せる（読めれば）。元の例外は `cause` に残さない
      # （メッセージに平文が載っているので、`cause` を辿るログ・Sentry から漏れる）。
      #
      # 🔴 **スキームは `RedisClient.config` より先に見る（2.1.2 のリリース前レビュー）。** 知らない
      # スキームの `ArgumentError` も URL を丸ごと載せる（`Unknown URL scheme: "http://:pass@h/1"`）。
      # ⚠ 通すのは redis-client が受けるもの（`redis` / `rediss` / `unix` / 無し）。`url:` の経路では
      # `rediss` を受けてきたので、`.dsn` の経路（`redis` だけ）とは揃えない。
      #
      # 🔴🔴 **redis-client の `ArgumentError` も包む (#92)。** `URLConfig` は DSN を読む段で
      # `Integer()` や `%` の復号に失敗すると `ArgumentError` を上げ、**メッセージに DSN の断片を
      # そのまま載せる**（`redis:/:pass@h/1` → `invalid value for Integer(): ":pass@h/1"`）。
      # ⚠ ここで受けているのは `url:` だけなので、`ArgumentError` は DSN の形が原因と読んでよい。
      def create_pool(url)
        dsn = DSN.parse(url)
        raise Error, "Invalid scheme '#{dsn.scheme}'" unless URL_SCHEMES.include?(dsn.scheme)
        return RedisClient.config(url: dsn.to_s).new_pool
      rescue ::URI::InvalidURIError, Addressable::URI::InvalidURIError, ArgumentError => e
        shown = dsn ? " '#{filter_password(dsn)}'" : ''
        raise Error, "Invalid DSN#{shown} (#{e.class})", cause: nil
      end

      # ⚠ 設定の DSN が読めないときも同じく包む。Addressable の文言には userinfo が載る形がある
      # （`Cannot assemble URI string with ambiguous path: ':pass@h'`）。
      def configured_dsn
        return self.class.dsn
      rescue Addressable::URI::InvalidURIError => e
        raise Error, "Invalid DSN (#{e.class})", cause: nil
      end

      # 例外メッセージに載せる DSN。パスワードだけ伏せる（ユーザー名・ホスト・DB は原因の手掛かりとして残す）。
      # 🔴 **パスワードの無い userinfo はユーザー名ごと伏せる（2.1.2 のリリース前レビュー）。**
      # redis-client は `redis://<secret>@h` の `<secret>` をパスワードとして読む（`URLConfig#password`）。
      #
      # 🔴🔴 **伏せ字を Addressable の setter に通さない (#90)。** addressable 2.10.0 は `password=` /
      # `user=` で `[` `]` を弾くので、`'[FILTERED]'` を代入すると `InvalidURIError` が上がり、
      # `create_pool` の rescue の中から**平文の DSN を `cause` に付けたまま**抜けていた。
      # userinfo を外した文字列に、伏せた userinfo を差し込んで組む。
      # ⚠ それでも組めなければ DSN ごと伏せる（伏せる処理の失敗で平文を持ち出さない）。
      #
      # 🔴🔴 **ホストの無い DSN に `@` があれば、DSN ごと伏せる (#92)。** スラッシュが足りない typo
      # （`redis:/:pass@h/1` / `redis:pass@h/1`）は、Addressable が userinfo ではなくパスとして読むので、
      # userinfo を見て伏せるだけでは**平文のまま出ていた**。
      def filter_password(dsn)
        return FILTERED if dsn.host.to_s.empty? && dsn.to_s.include?('@')
        return dsn.to_s unless dsn.password || dsn.user
        userinfo = dsn.password ? "#{dsn.user}:#{FILTERED}" : FILTERED
        filtered = dsn.dup
        filtered.userinfo = nil
        authority = "//#{filtered.authority}"
        return filtered.to_s.sub(authority) {"//#{userinfo}@#{filtered.authority}"}
      rescue Addressable::URI::InvalidURIError
        return FILTERED
      end

      # 失敗したら `retry_limit` 回まで撃ち直す（冪等なコマンド用。⚠ `INCR` には使わない）。
      def retrying(command, key = nil)
        cnt ||= 0
        return yield
      rescue => e
        cnt += 1
        @logger.error(error: e, count: cnt, **log_target(command, key))
        raise Error, e.message, e.backtrace unless cnt < retry_limit
        sleep(retry_seconds)
        retry
      end

      # 失敗の行に載せる、何をしていたかの手掛かり (#73)。
      #
      # ⚠ **`command:` は全部の行に付ける。** 付いていなかった頃は、`GET` の再送と
      # `EXISTS` の再送をログで区別できなかった。
      #
      # 🔴 **ここで例外を上げない (#78 Codex P2)。** rescue の中で呼ばれるので、上がると
      # ログも再送も飛ばして、`Error` ではない例外が利用側へ漏れる。
      def log_target(command, key)
        return {command:} if key.nil?
        return {command:, key_prefix: key_prefix(key)}
      rescue
        return {command:, key_prefix: nil}
      end

      # キーの頭だけを返す (#73)。`prefix` と、利用側のキーの最初の `:` まで。
      #
      # 🔴 **キーを丸ごと出さない。** キーは利用側が作るので、資格情報が混じりうる
      # （トークンでキャッシュを引く設計は珍しくない）。⚠ `ginseng-core` の `Masking` は
      # 使わない — この gem の gemspec は core に依存していない（core は利用側が持ち、logger もそこから
      # 解決する）うえ、`Masking` は名前で伏せる仕組みで、キーに埋まった値は見分けられない。
      # ⚠ 頭に秘密があれば出る（`"<トークン>:timeline"` → `"<トークン>:"`）。利用側のキーは、
      # 区切りの前に秘密を置かない形にすること（2026-11-08 に mulukhiya のキーを見て該当なし）。
      # ⚠ 利用側のキーに `:` が無ければ、利用側の部分は 1 文字も出さない（キー全体が
      # トークンの形もありうる）。`prefix` も無ければ `nil`。
      # 🔴 **バイト列として切る (#78 Codex P2)。** 文字列のまま正規表現を当てると、不正な UTF-8 を
      # 含むキー（`"cache:\xFF"`）で `ArgumentError` になる。⚠ `create_key` も通さない（同じ理由で上がる）。
      def key_prefix(key)
        rest = key.to_s.b
        rest = rest.delete_prefix("#{prefix}:".b) if prefix
        head = rest[/\A[^:]*:/n]&.force_encoding(Encoding::UTF_8)&.scrub
        return [prefix && "#{prefix}:", head].join.then {|v| v.empty? ? nil : v}
      end
    end
  end
end
