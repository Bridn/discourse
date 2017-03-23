require_dependency 'distributed_cache'
require_dependency 'stylesheet/compiler'

class DiscourseStylesheets

  CACHE_PATH ||= 'tmp/stylesheet-cache'
  MANIFEST_DIR ||= "#{Rails.root}/tmp/cache/assets/#{Rails.env}"
  MANIFEST_FULL_PATH ||= "#{MANIFEST_DIR}/stylesheet-manifest"

  @lock = Mutex.new

  def self.cache
    return {} if Rails.env.development?
    @cache ||= DistributedCache.new("discourse_stylesheet")
  end

  def self.stylesheet_link_tag(target = :desktop, media = 'all', theme_id = -1)

    tag = cache[target]

    return tag.dup.html_safe if tag

    @lock.synchronize do
      builder = self.new(target, theme_id)
      builder.compile unless File.exists?(builder.stylesheet_fullpath)
      builder.ensure_digestless_file
      tag = %[<link href="#{Rails.env.production? ? builder.stylesheet_cdnpath : builder.stylesheet_relpath_no_digest}" media="#{media}" rel="stylesheet" />]

      cache[target] = tag

      tag.dup.html_safe
    end
  end

  def self.compile(target = :desktop, opts={})
    @lock.synchronize do
      FileUtils.rm(MANIFEST_FULL_PATH, force: true) if opts[:force]
      builder = self.new(target, @theme_id)
      builder.compile(opts)
      builder.stylesheet_filename
    end
  end

  def self.last_file_updated
    if Rails.env.production?
      @last_file_updated ||= if File.exists?(MANIFEST_FULL_PATH)
        File.readlines(MANIFEST_FULL_PATH, 'r')[0]
      else
        mtime = max_file_mtime
        FileUtils.mkdir_p(MANIFEST_DIR)
        File.open(MANIFEST_FULL_PATH, "w") { |f| f.print(mtime) }
        mtime
      end
    else
      max_file_mtime
    end
  end

  def self.max_file_mtime
    globs = ["#{Rails.root}/app/assets/stylesheets/**/*.*css"]

    Discourse.plugins.map { |plugin| File.dirname(plugin.path) }.each do |path|
      globs += [
        "#{path}/plugin.rb",
        "#{path}/**/*.*css",
      ]
    end

    globs.map do |pattern|
      Dir.glob(pattern).map { |x| File.mtime(x) }.max
    end.compact.max.to_i
  end

  def initialize(target = :desktop, theme_id)
    @target = target
    @theme_id = theme_id
  end

  def compile(opts={})
    unless opts[:force]
      if File.exists?(stylesheet_fullpath)
        unless StylesheetCache.where(target: @target, digest: digest).exists?
          begin
            source_map = File.read(source_map_fullpath) rescue nil
            StylesheetCache.add(@target, digest, File.read(stylesheet_fullpath), source_map)
          rescue => e
            Rails.logger.warn "Completely unexpected error adding contents of '#{stylesheet_fullpath}' to cache #{e}"
          end
        end
        return true
      end
    end

    rtl = @target.to_s =~ /_rtl$/
    css,source_map = begin
      Stylesheet::Compiler.compile_asset(@target, rtl: rtl, theme_id: @theme_id)
    rescue SassC::SyntaxError => e
      Rails.logger.error "Failed to compile #{@target} stylesheet: #{e.message}"
      [Stylesheet::Compiler.error_as_css(e, "#{@target} stylesheet"), nil]
    end

    FileUtils.mkdir_p(cache_fullpath)

    File.open(stylesheet_fullpath, "w") do |f|
      f.puts css
    end

    if source_map.present?
      File.open(source_map_fullpath, "w") do |f|
        f.puts source_map
      end
    end

    begin
      StylesheetCache.add(@target, digest, css, source_map)
    rescue => e
      Rails.logger.warn "Completely unexpected error adding item to cache #{e}"
    end
    css
  end

  def ensure_digestless_file
    # file without digest is only for auto-reloading css in dev env
    unless Rails.env.production? || (File.exist?(stylesheet_fullpath_no_digest) && File.mtime(stylesheet_fullpath) == File.mtime(stylesheet_fullpath_no_digest))
      FileUtils.cp(stylesheet_fullpath, stylesheet_fullpath_no_digest)
    end
  end

  def self.cache_fullpath
    "#{Rails.root}/#{CACHE_PATH}"
  end

  def cache_fullpath
    self.class.cache_fullpath
  end

  def stylesheet_fullpath
    "#{cache_fullpath}/#{stylesheet_filename}"
  end

  def source_map_fullpath
    "#{cache_fullpath}/#{stylesheet_filename}.map"
  end

  def stylesheet_fullpath_no_digest
    "#{cache_fullpath}/#{stylesheet_filename_no_digest}"
  end

  def stylesheet_cdnpath
    "#{GlobalSetting.cdn_url}#{stylesheet_relpath}?__ws=#{Discourse.current_hostname}"
  end

  def root_path
    "#{GlobalSetting.relative_url_root}/"
  end

  # using uploads cause we already have all the routing in place
  def stylesheet_relpath
    "#{root_path}stylesheets/#{stylesheet_filename}"
  end

  def stylesheet_relpath_no_digest
    "#{root_path}stylesheets/#{stylesheet_filename_no_digest}"
  end

  def stylesheet_filename
    "#{@target}_#{digest}.css"
  end
  def stylesheet_filename_no_digest
    "#{@target}.css"
  end

  # digest encodes the things that trigger a recompile
  def digest
    @digest ||= begin
      theme = (cs = Theme.find(@theme_id).color_scheme) ? "#{cs.id}-#{cs.version}" : false
      category_updated = Category.where("uploaded_background_id IS NOT NULL").last_updated_at

      if theme || category_updated > 0
        Digest::SHA1.hexdigest "#{RailsMultisite::ConnectionManagement.current_db}-#{theme}-#{DiscourseStylesheets.last_file_updated}-#{category_updated}"
      else
        digest_string = "defaults-#{DiscourseStylesheets.last_file_updated}"

        if cdn_url = GlobalSetting.cdn_url
          digest_string = "#{digest_string}-#{cdn_url}"
        end

        Digest::SHA1.hexdigest digest_string
      end
    end
  end
end
