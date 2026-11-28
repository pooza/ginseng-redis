# ginseng-redis

Redis を使うためのライブラリです。
[redis-client](https://github.com/redis-rb/redis-client) の上に、DSN による接続、キーの接頭辞、リトライ、例外メッセージでのパスワードの伏せ字を足しています。

`ginseng-core` の上に作っています。

## このリポジトリについて

pooza の自作アプリケーション群のための内部ライブラリです。
MIT ライセンスで公開していますが、GitHub に置いている以上の配布（rubygems.org への公開など）は予定していません。

- 互換性は利用側のアプリの都合で変え、破壊的な変更も major を上げて行います
- 外部での利用を想定したサポートや問い合わせへの対応は行いません
- Issue・PR は受け付けますが、取り込むか・いつ返答するかはお約束できません

## 導入

rubygems.org には無いので、`Gemfile` で GitHub のタグを指定して参照します。
最新のタグは [Releases](https://github.com/pooza/ginseng-redis/releases) を見てください。

```ruby
gem 'ginseng-core', github: 'pooza/ginseng-core', tag: 'vX.Y.Z', require: 'ginseng'
gem 'ginseng-redis', github: 'pooza/ginseng-redis', tag: 'vX.Y.Z', require: 'ginseng/redis'
```

⚠ `ginseng-core` も git で宣言してください。宣言が無いと、Bundler は rubygems.org から同じ名前の gem を探しに行きます。

Ruby 3.4 以上が必要です。

## 使い方

`ginseng-core` と同じく、アプリ側で `Ginseng::Package` を include し、必要なクラスを継承して使います。
`Ginseng::Redis::Package` も同じ形で、`*_class` を上書きすると gem の内部もアプリのクラスを使うようになります。
詳しくは [ginseng-core の README](https://github.com/pooza/ginseng-core#使い方) を見てください。

## 主なクラス

| クラス | 役割 |
| --- | --- |
| `Ginseng::Redis::Service` | Redis のクライアント。`get` / `set` / `setex` / `incr` / `unlink` / `keys` など。サブクラスで `self.dsn` を上書きすると接続先を変えられる |
| `Ginseng::Redis::DSN` | `redis://` 形式の接続先 |
| `Ginseng::Redis::Error` | この gem の例外 |

詳しい振る舞いはソースのコメントにあります。

## ライセンス

[MIT](LICENSE.txt)
