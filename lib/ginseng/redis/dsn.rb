module Ginseng
  module Redis
    class DSN < Ginseng::URI
      def db
        return path.sub(%r{^/}, '').to_i
      end
    end
  end
end
