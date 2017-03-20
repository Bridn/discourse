# frozen_string_literal: true
require_dependency 'stylesheet/compiler'
require_dependency 'stylesheet/watcher'

module Middleware
  class Stylesheets

    @@mutex = Mutex.new

    @@source_maps = {}

    def initialize(app, settings={})
      @app = app
    end

    # this is only meant to run in dev and only under puma really
    def ensure_css_watcher
      return if @watcher || !defined? Puma

      @@mutex.synchronize do
        return if @watcher
        STDERR.puts "Staring CSS change watcher"
        @watcher = Stylesheet::Watcher.watch
      end
    end

    def call(env)

      ensure_css_watcher

      root = "#{GlobalSetting.relative_url_root}/stylesheets/"
      request_path = env["REQUEST_PATH"]
      is_stylesheet = request_path&.starts_with?(root)

      is_css = is_stylesheet && request_path.ends_with?(".css")
      is_map = is_stylesheet && request_path.ends_with?(".css.map")

      if is_css
        name = request_path[root.length..-5]
        css,source_map = Stylesheet::Compiler.compile(name)

        @@source_maps[name] = source_map

        return [200, {}, ["#{css}"]]

      elsif is_map

        name = request_path[root.length..-9]
        return [200, {}, ["#{@@source_maps[name]}"]]

      end

      @app.call(env)
    end
  end
end

