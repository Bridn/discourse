require 'sassc'

module Stylesheet

  ASSET_ROOT = "#{Rails.root}/app/assets/stylesheets"

  class Importer < SassC::Importer

    @special_imports = {}

    def self.special_imports
      @special_imports
    end

    def self.register_import(name, &blk)
      @special_imports[name] = blk
    end

    def self.import_files(files)
      files.map do |file|
        # we never want inline css imports, they are a mess
        # this tricks libsass so it imports inline instead
        if file =~ /\.css$/
          file = file[0..-5]
        end
        Import.new(file)
      end
    end

    register_import "plugins" do
      import_files(DiscoursePluginRegistry.stylesheets)
    end

    register_import "plugins_mobile" do
      import_files(DiscoursePluginRegistry.mobile_stylesheets)
    end

    register_import "plugins_desktop" do
      import_files(DiscoursePluginRegistry.desktop_stylesheets)
    end

    register_import "plugins_variables" do
      import_files(DiscoursePluginRegistry.sass_variables)
    end

    register_import "theme_variables" do
      contents = ""
      ColorScheme.base_colors.each do |n, base_hex|
        hex_val = ColorScheme.hex_for_name(n) || base_hex
        contents << "$#{n}: ##{hex_val} !default;\n"
      end

      Import.new("theme_variable.scss", source: contents)
    end

    def self.apply_cdn(url)
      "#{GlobalSetting.cdn_url}#{url}"
    end

    def self.category_css(category)
      "body.category-#{category.full_slug} { background-image: url(#{apply_cdn(category.uploaded_background.url)}) }\n"
    end

    register_import "category_backgrounds" do
      contents = ""
      Category.where('uploaded_background_id IS NOT NULL').each do |c|
        contents << category_css(c) if c.uploaded_background
      end

      Import.new("categoy_background.scss", source: contents)
    end

    register_import "desktop_theme" do
      if @theme_id
        css = Theme.where(id: @theme_id).pluck(:stylesheet).first.to_s
        if css.present?
          Import.new("desktop_theme.css", css)
        end
      end
    end

    def initialize(options)
      @theme_id = options[:theme_id]
    end


    def imports(asset, parent_path)
      if asset[-1] == "*"
        Dir["#{Stylesheet::ASSET_ROOT}/#{asset}.scss"].map do |path|
          Import.new(asset[0..-2] + File.basename(path, ".*"))
        end
      elsif callback = Importer.special_imports[asset]
        callback.call
      else
        Import.new(asset + ".scss")
      end
    end
  end

  class Compiler


    def self.error_as_css(error, label)
      error = error.message
      error.gsub!("\n", '\A ')
      error.gsub!("'", '\27 ')

      "footer { white-space: pre; }
      footer:after { content: '#{error}' }"
    end

    def self.compile_asset(asset, options={})

      if Importer.special_imports[asset.to_s]
        filename = "theme.scss"
        file = "@import \"#{asset}\";"
      else
        filename = "#{asset}.scss"
        path = "#{ASSET_ROOT}/#{filename}"
        file = File.read path
      end

      compile(file,filename,options)

    end

    def self.compile(stylesheet, filename, options={})

      engine = SassC::Engine.new(stylesheet,
                                 importer: Importer,
                                 filename: filename,
                                 style: :compressed,
                                 source_map_file: "#{filename.sub(".scss","")}.css.map",
                                 source_map_contents: true,
                                 load_paths: [ASSET_ROOT])


      result = engine.render

      if options[:rtl]
        require 'r2'
        [R2.r2(result), nil]
      else
        source_map = engine.source_map
        source_map.force_encoding("UTF-8")

        [result, source_map]
      end
    end
  end
end
