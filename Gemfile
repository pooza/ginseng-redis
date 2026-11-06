source 'https://rubygems.org'
gemspec
gem 'ginseng-core', github: 'pooza/ginseng-core', require: 'ginseng'

group :development, :test do
  # ⚠ rubocop 本体とプラグインはこの gem が依存として持つ。設定の正本も同じ場所。
  # ⚠⚠ タグではなく SHA で固定する（pooza/ginseng-style#75）。タグは付け替えられる。
  gem 'ginseng-style', github: 'pooza/ginseng-style',
    ref: '127c2854e76811eeec41e21c7bf262b4a527d2b7', require: false # v1.1.15
  gem 'ricecream'
  gem 'test-unit'
end
