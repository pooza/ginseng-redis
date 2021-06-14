require 'bundler/setup'

module Ginseng
  module Redis
    def self.dir
      return File.expand_path('../..', __dir__)
    end

    def self.loader
      config = YAML.load_file(File.join(dir, 'config/autoload.yaml'))
      loader = Zeitwerk::Loader.new
      loader.inflector.inflect(config['inflections'])
      loader.push_dir(File.join(dir, 'lib/ginseng/redis'), namespace: Ginseng::Redis)
      return loader
    end

    def self.setup_debug
      Ricecream.disable
      return unless Environment.development?
      Ricecream.enable
      Ricecream.include_context = true
      Ricecream.colorize = true
      Ricecream.prefix = "#{Package.name} | "
      Ricecream.define_singleton_method(:arg_to_s, proc {|v| PP.pp(v)})
    end

    Bundler.require
    loader.setup
    setup_debug
  end
end
