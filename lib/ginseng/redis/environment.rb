module Ginseng::Redis
  class Environment < Ginseng::Environment
    def self.name
      return File.basename(dir)
    end

    def self.dir
      return Ginseng::Redis.dir
    end
  end
end
