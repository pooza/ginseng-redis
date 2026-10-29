module Ginseng
  module Redis
    # load / names / dir は ginseng-core の TestCase に任せる（pooza/ginseng-style#132）。
    # 写しを持つと、読めなかったテストファイルを失敗にする検出（pooza/ginseng-core#696）が届かない。
    class TestCase < Ginseng::TestCase
      include Package
    end
  end
end
