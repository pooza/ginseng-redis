source 'https://rubygems.org'
gemspec
gem 'ginseng-core', github: 'pooza/ginseng-core', require: 'ginseng'

group :development, :test do
  # ⚠ rubocop 本体とプラグインはこの gem が依存として持つ。設定の正本も同じ場所。
  # ⚠⚠ タグではなく SHA で固定する（pooza/ginseng-style#75）。タグは付け替えられる。
  gem 'ginseng-style', github: 'pooza/ginseng-style',
      ref: 'e5917622d069be324c6879c2a1d2522069d48d2c', require: false # v1.1.10
end
