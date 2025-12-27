#!/usr/bin/env ruby
# Build script for Ruby2JS-on-Rails demo
# Transpiles Ruby models and controllers to JavaScript
#
# Can be run directly: ruby scripts/build.rb [dist_dir]
# Or transpiled to JS and imported as: import { SelfhostBuilder } from './build.mjs'

require 'fileutils'
require 'json'
require 'yaml'

# Ensure we're using the local ruby2js
$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)
require 'ruby2js'
# Explicitly require each Rails sub-filter for JS transpilation compatibility
require 'ruby2js/filter/rails/model'
require 'ruby2js/filter/rails/controller'
require 'ruby2js/filter/rails/routes'
require 'ruby2js/filter/rails/schema'
require 'ruby2js/filter/rails/seeds'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/return'
require 'ruby2js/filter/erb'
require 'ruby2js/filter/rails/helpers'
require 'ruby2js/filter/phlex'
require 'ruby2js/filter/stimulus'
require 'ruby2js/filter/camelCase'
require_relative '../lib/erb_compiler'

class SelfhostBuilder
  # JS (Node.js): use process.cwd() since bin commands run from app root
  # Ruby: resolve from scripts/ up one level to app root
  DEMO_ROOT = if defined?(process)
    process.cwd()
  else
    File.expand_path('..', __dir__)
  end

  # Browser databases - these run in the browser with IndexedDB or WASM
  BROWSER_DATABASES = ['dexie', 'indexeddb', 'sqljs', 'sql.js', 'pglite'].freeze

  # Server-side JavaScript runtimes
  SERVER_RUNTIMES = ['node', 'bun', 'deno', 'cloudflare'].freeze

  # Databases that require a specific runtime
  RUNTIME_REQUIRED = {
    'd1' => 'cloudflare'
  }.freeze

  # Map DATABASE env var to adapter source file
  ADAPTER_FILES = {
    # Browser adapters
    'sqljs' => 'active_record_sqljs.mjs',
    'sql.js' => 'active_record_sqljs.mjs',
    'dexie' => 'active_record_dexie.mjs',
    'indexeddb' => 'active_record_dexie.mjs',
    'pglite' => 'active_record_pglite.mjs',
    # Node.js adapters
    'better_sqlite3' => 'active_record_better_sqlite3.mjs',
    'sqlite3' => 'active_record_better_sqlite3.mjs',  # Alias
    'pg' => 'active_record_pg.mjs',
    'postgres' => 'active_record_pg.mjs',
    'postgresql' => 'active_record_pg.mjs',
    'mysql2' => 'active_record_mysql2.mjs',
    'mysql' => 'active_record_mysql2.mjs',
    # Cloudflare adapters
    'd1' => 'active_record_d1.mjs'
  }.freeze

  # Common transpilation options for Ruby files
  OPTIONS = {
    eslevel: 2022,
    include: [:class, :call],
    autoexports: true,
    filters: [
      Ruby2JS::Filter::Rails::Model,
      Ruby2JS::Filter::Rails::Controller,
      Ruby2JS::Filter::Rails::Routes,
      Ruby2JS::Filter::Rails::Schema,
      Ruby2JS::Filter::Rails::Seeds,
      Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::ESM,
      Ruby2JS::Filter::Return
    ]
  }.freeze

  # Options for ERB templates
  # Note: Rails::Helpers must come BEFORE Erb for method overrides to work
  ERB_OPTIONS = {
    eslevel: 2022,
    include: [:class, :call],
    filters: [
      Ruby2JS::Filter::Rails::Helpers,
      Ruby2JS::Filter::Erb,
      Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::Return
    ]
  }.freeze

  def initialize(dist_dir = nil)
    @dist_dir = dist_dir || File.join(DEMO_ROOT, 'dist')
    @database = nil  # Set during build from config
    @target = nil    # Derived from database: 'browser' or 'server'
    @runtime = nil   # For server targets: 'node', 'bun', or 'deno'
  end

  # Note: Using explicit () on all method calls for JS transpilation compatibility
  def build()
    # Clean and create dist directory
    FileUtils.rm_rf(@dist_dir)
    FileUtils.mkdir_p(@dist_dir)

    puts("=== Building Ruby2JS-on-Rails Demo ===")
    puts("")

    # Load database config and derive target
    puts("Database Adapter:")
    db_config = self.load_database_config()
    @database = db_config['adapter'] || db_config[:adapter] || 'sqljs'
    @target = BROWSER_DATABASES.include?(@database) ? 'browser' : 'server'

    # Validate and set runtime based on database type
    requested_runtime = ENV['RUNTIME']
    requested_runtime = requested_runtime.downcase if requested_runtime

    if @target == 'browser'
      # Browser databases only work with browser target
      if requested_runtime && requested_runtime != 'browser'
        raise "Database '#{@database}' is browser-only. Cannot use RUNTIME=#{requested_runtime}.\n" \
              "Browser databases: #{BROWSER_DATABASES.join(', ')}"
      end
      @runtime = nil  # Browser target doesn't use a JS runtime
    else
      # Check if database requires a specific runtime
      required_runtime = RUNTIME_REQUIRED[@database]
      if required_runtime
        if requested_runtime && requested_runtime != required_runtime
          raise "Database '#{@database}' requires RUNTIME=#{required_runtime}. Cannot use RUNTIME=#{requested_runtime}."
        end
        @runtime = required_runtime
      else
        # Server databases work with node, bun, or deno (default: node)
        @runtime = requested_runtime || 'node'
      end

      unless SERVER_RUNTIMES.include?(@runtime)
        raise "Unknown runtime: #{@runtime}. Valid options for server databases: #{SERVER_RUNTIMES.join(', ')}"
      end
    end

    self.copy_database_adapter(db_config)
    puts("  Target: #{@target}")
    puts("  Runtime: #{@runtime}") if @runtime
    puts("")

    # Copy target-specific lib files (rails.js framework)
    puts("Library:")
    self.copy_lib_files()
    puts("")

    # Generate ApplicationRecord wrapper and transpile models
    puts("Models:")
    self.generate_application_record()
    self.transpile_directory(
      File.join(DEMO_ROOT, 'app/models'),
      File.join(@dist_dir, 'models'),
      '**/*.rb',
      skip: ['application_record.rb']
    )
    self.generate_models_index()
    puts("")

    # Transpile controllers (use 'controllers' section from ruby2js.yml if present)
    puts("Controllers:")
    self.transpile_directory(
      File.join(DEMO_ROOT, 'app/controllers'),
      File.join(@dist_dir, 'controllers'),
      '**/*.rb',
      section: 'controllers'
    )
    puts("")

    # Transpile components (Phlex views, use 'components' section from ruby2js.yml)
    components_dir = File.join(DEMO_ROOT, 'app/components')
    if File.exist?(components_dir)
      puts("Components:")
      self.copy_phlex_runtime()
      self.transpile_directory(
        components_dir,
        File.join(@dist_dir, 'components'),
        '**/*.rb',
        section: 'components'
      )
      puts("")
    end

    # Transpile Stimulus controllers (app/javascript/controllers/)
    stimulus_dir = File.join(DEMO_ROOT, 'app/javascript/controllers')
    if File.exist?(stimulus_dir)
      puts("Stimulus Controllers:")
      self.transpile_directory(
        stimulus_dir,
        File.join(@dist_dir, 'javascript/controllers'),
        '**/*.rb',
        section: 'stimulus'
      )
      puts("")
    end

    # Transpile config (skip routes.rb, handled separately)
    puts("Config:")
    self.transpile_directory(
      File.join(DEMO_ROOT, 'config'),
      File.join(@dist_dir, 'config'),
      '**/*.rb',
      skip: ['routes.rb']
    )
    self.transpile_routes_files()
    puts("")

    # Transpile views (ERB templates and layout)
    puts("Views:")
    self.transpile_erb_directory()
    self.transpile_layout() if @target == 'server'
    puts("")

    # Transpile helpers
    puts("Helpers:")
    self.transpile_directory(
      File.join(DEMO_ROOT, 'app/helpers'),
      File.join(@dist_dir, 'helpers')
    )
    puts("")

    # Transpile db (seeds)
    puts("Database:")
    self.transpile_directory(
      File.join(DEMO_ROOT, 'db'),
      File.join(@dist_dir, 'db')
    )
    puts("")

    puts("=== Build Complete ===")
  end

  def load_ruby2js_config(section = nil)
    env = ENV['RAILS_ENV'] || ENV['NODE_ENV'] || 'development'
    config_path = File.join(DEMO_ROOT, 'config/ruby2js.yml')

    return {} unless File.exist?(config_path)

    # Ruby 3.4+ requires aliases: true for YAML anchors
    config = YAML.load_file(config_path, aliases: true)

    # If a specific section is requested (e.g., 'controllers', 'components')
    if section && config.key?(section)
      return config[section]
    end

    # Support environment-specific or flat config
    if config.key?(env)
      config[env]
    elsif config.key?('default')
      config['default']
    else
      config
    end
  end

  def build_options(section = nil)
    # Load section-specific config if section is specified, otherwise default
    base = self.load_ruby2js_config(section)

    # Start with hardcoded OPTIONS as base (using spread for JS compatibility)
    options = { **OPTIONS }

    # Merge YAML config values (string keys converted to symbols)
    base.each do |key, value| # Pragma: entries
      sym_key = key.to_s.to_sym
      # Convert filter names to module references
      if sym_key == :filters && value.is_a?(Array)
        options[sym_key] = self.resolve_filters(value)
      else
        options[sym_key] = value
      end
    end

    options
  end

  # Map filter names (strings) to Ruby2JS filter modules
  # Supports both short names ('phlex') and full paths ('rails/helpers')
  FILTER_MAP = {
    # Core filters
    'functions' => Ruby2JS::Filter::Functions,
    'esm' => Ruby2JS::Filter::ESM,
    'return' => Ruby2JS::Filter::Return,
    'erb' => Ruby2JS::Filter::Erb,
    'camelcase' => Ruby2JS::Filter::CamelCase,
    'camelCase' => Ruby2JS::Filter::CamelCase,

    # Framework filters
    'phlex' => Ruby2JS::Filter::Phlex,
    'stimulus' => Ruby2JS::Filter::Stimulus,

    # Rails sub-filters
    'rails/model' => Ruby2JS::Filter::Rails::Model,
    'rails/controller' => Ruby2JS::Filter::Rails::Controller,
    'rails/routes' => Ruby2JS::Filter::Rails::Routes,
    'rails/schema' => Ruby2JS::Filter::Rails::Schema,
    'rails/seeds' => Ruby2JS::Filter::Rails::Seeds,
    'rails/helpers' => Ruby2JS::Filter::Rails::Helpers
  }.freeze

  def resolve_filters(filter_names)
    filter_names.map do |name|
      # Already a filter (not a string)? Pass through
      # In Ruby, filters are Modules; in JS, they're prototype objects
      return name unless name.is_a?(String)

      # Normalize: strip, downcase for lookup (but preserve camelCase key)
      normalized = name.to_s.strip
      lookup_key = FILTER_MAP.key?(normalized) ? normalized : normalized.downcase

      filter = FILTER_MAP[lookup_key]
      unless filter
        valid_filters = FILTER_MAP.keys.uniq.sort.join(', ')
        raise "Unknown filter: '#{name}'. Valid filters: #{valid_filters}"
      end
      filter
    end
  end

  def load_runtime_config()
    # Priority 1: RUNTIME environment variable
    if ENV['RUNTIME']
      return ENV['RUNTIME'].downcase
    end

    # Priority 2: database.yml runtime key
    db_config = self.load_database_config()
    if db_config['runtime']
      return db_config['runtime'].downcase
    end

    # Priority 3: ruby2js.yml runtime key
    r2js_config = self.load_ruby2js_config()
    if r2js_config['runtime']
      return r2js_config['runtime'].downcase
    end

    # Default: node
    'node'
  end

  def load_database_config()
    # Use || instead of fetch for JS compatibility
    env = ENV['RAILS_ENV'] || ENV['NODE_ENV'] || 'development'

    # Priority 1: DATABASE environment variable
    if ENV['DATABASE']
      puts("  Using DATABASE=#{ENV['DATABASE']} from environment")
      return { 'adapter' => ENV['DATABASE'].downcase }
    end

    # Priority 2: config/database.yml
    config_path = File.join(DEMO_ROOT, 'config/database.yml')
    if File.exist?(config_path)
      config = YAML.load_file(config_path)
      if config && config[env] && config[env]['adapter']
        puts("  Using config/database.yml [#{env}]")
        return config[env]
      end
    end

    # Default: sqljs
    puts("  Using default adapter: sqljs")
    { 'adapter' => 'sqljs', 'database' => 'ruby2js_rails' }
  end

  def copy_database_adapter(db_config)
    adapter = db_config['adapter'] || db_config[:adapter] || 'sqljs'
    adapter_file = ADAPTER_FILES[adapter]

    unless adapter_file
      valid = ADAPTER_FILES.keys.join(', ')
      raise "Unknown DATABASE adapter: #{adapter}. Valid options: #{valid}"
    end

    # Check for npm-installed package first, fall back to development vendor directory
    npm_adapter_dir = File.join(DEMO_ROOT, 'node_modules/ruby2js-rails/adapters')
    vendor_adapter_dir = File.join(DEMO_ROOT, 'vendor/ruby2js/adapters')
    adapter_dir = File.exist?(npm_adapter_dir) ? npm_adapter_dir : vendor_adapter_dir
    adapter_src = File.join(adapter_dir, adapter_file)
    adapter_dest = File.join(@dist_dir, 'lib/active_record.mjs')
    FileUtils.mkdir_p(File.dirname(adapter_dest))

    # Read adapter and inject config
    adapter_code = File.read(adapter_src)
    adapter_code = adapter_code.sub('const DB_CONFIG = {};', "const DB_CONFIG = #{JSON.generate(db_config)};")
    File.write(adapter_dest, adapter_code)

    puts("  Adapter: #{adapter} -> lib/active_record.mjs")
    if db_config['database'] || db_config[:database]
      puts("  Database: #{db_config['database'] || db_config[:database]}")
    end
  end

  def copy_lib_files()
    lib_dest = File.join(@dist_dir, 'lib')
    FileUtils.mkdir_p(lib_dest)

    # Determine source directory: browser or runtime-specific server target
    if @target == 'browser'
      target_dir = 'browser'
    else
      target_dir = @runtime  # node, bun, or deno
    end

    # Check for npm-installed package first, fall back to development vendor directory
    npm_package_dir = File.join(DEMO_ROOT, 'node_modules/ruby2js-rails')
    vendor_package_dir = File.join(DEMO_ROOT, 'vendor/ruby2js')
    package_dir = File.exist?(npm_package_dir) ? npm_package_dir : vendor_package_dir

    # Copy target-specific files (rails.js from targets/browser, node, bun, or deno)
    target_src = File.join(package_dir, 'targets', target_dir)
    Dir.glob(File.join(target_src, '*.js')).each do |src_path|
      dest_path = File.join(lib_dest, File.basename(src_path))
      FileUtils.cp(src_path, dest_path)
      puts("  Copying: targets/#{target_dir}/#{File.basename(src_path)}")
      puts("    -> #{dest_path}")
    end

    # Copy runtime lib files (erb_runtime.mjs only - build tools stay in vendor)
    runtime_libs = ['erb_runtime.mjs']
    runtime_libs.each do |filename|
      src_path = File.join(package_dir, filename)
      next unless File.exist?(src_path)
      dest_path = File.join(lib_dest, filename)
      FileUtils.cp(src_path, dest_path)
      puts("  Copying: #{filename}")
      puts("    -> #{dest_path}")
    end
  end

  def copy_phlex_runtime()
    lib_dest = File.join(@dist_dir, 'lib')
    FileUtils.mkdir_p(lib_dest)

    # Check for npm-installed package first, fall back to development vendor directory
    npm_package_dir = File.join(DEMO_ROOT, 'node_modules/ruby2js-rails')
    vendor_package_dir = File.join(DEMO_ROOT, 'vendor/ruby2js')
    package_dir = File.exist?(npm_package_dir) ? npm_package_dir : vendor_package_dir

    src_path = File.join(package_dir, 'phlex_runtime.mjs')
    return unless File.exist?(src_path)

    dest_path = File.join(lib_dest, 'phlex_runtime.mjs')
    FileUtils.cp(src_path, dest_path)
    puts("  Copying: phlex_runtime.mjs")
    puts("    -> #{dest_path}")
  end

  def transpile_file(src_path, dest_path, section = nil)
    puts("Transpiling: #{File.basename(src_path)}")
    source = File.read(src_path)

    # Use relative path for cleaner display in browser debugger
    relative_src = src_path.sub(DEMO_ROOT + '/', '')
    options = self.build_options(section).merge(file: relative_src)
    result = Ruby2JS.convert(source, options)
    js = result.to_s

    FileUtils.mkdir_p(File.dirname(dest_path))

    # Generate sourcemap
    map_path = "#{dest_path}.map"
    sourcemap = result.sourcemap
    sourcemap[:sourcesContent] = [source]

    # Compute relative path from sourcemap location back to source file
    map_dir = File.dirname(dest_path).sub(DEMO_ROOT + '/', '')
    depth = map_dir.split('/').length
    source_from_map = ('../' * depth) + relative_src

    sourcemap[:sources] = [source_from_map]

    # Add sourcemap reference to JS file
    js_with_map = "#{js}\n//# sourceMappingURL=#{File.basename(map_path)}\n"
    File.write(dest_path, js_with_map)
    File.write(map_path, JSON.generate(sourcemap))

    puts("  -> #{dest_path}")
    puts("  -> #{map_path}")
  end

  def transpile_erb_file(src_path, dest_path)
    puts("Transpiling ERB: #{File.basename(src_path)}")
    template = File.read(src_path)

    # Compile ERB to Ruby and get position mapping
    compiler = ErbCompiler.new(template)
    ruby_src = compiler.src

    # Use relative path for cleaner display in browser debugger
    relative_src = src_path.sub(DEMO_ROOT + '/', '')

    # Pass database option for target-aware link generation
    # Also pass ERB source and position map for source map generation
    erb_options = ERB_OPTIONS.merge(
      database: @database,
      file: relative_src
    )
    result = Ruby2JS.convert(ruby_src, erb_options)

    # Set ERB source map data on the result (which is the Serializer/Converter)
    result.erb_source = template
    result.erb_position_map = compiler.position_map

    js = result.to_s
    js = js.sub(/^function render/, 'export function render')

    FileUtils.mkdir_p(File.dirname(dest_path))

    # Generate source map
    map_path = "#{dest_path}.map"
    sourcemap = result.sourcemap
    sourcemap[:sourcesContent] = [template]  # Use original ERB, not Ruby

    # Compute relative path from sourcemap location back to source file
    map_dir = File.dirname(dest_path).sub(DEMO_ROOT + '/', '')
    depth = map_dir.split('/').length
    source_from_map = ('../' * depth) + relative_src
    sourcemap[:sources] = [source_from_map]

    # Add sourcemap reference to JS file
    js_with_map = "#{js}\n//# sourceMappingURL=#{File.basename(map_path)}\n"
    File.write(dest_path, js_with_map)
    File.write(map_path, JSON.generate(sourcemap))

    puts("  -> #{dest_path}")
    puts("  -> #{map_path}")
    js
  end

  def transpile_erb_directory()
    erb_dir = File.join(DEMO_ROOT, 'app/views/articles')
    return unless Dir.exist?(erb_dir)

    renders = {}
    Dir.glob(File.join(erb_dir, '**/*.html.erb')).each do |src_path|
      basename = File.basename(src_path, '.html.erb')
      js = self.transpile_erb_file(src_path, File.join(@dist_dir, 'views/erb', "#{basename}.js"))
      renders[basename] = js
    end

    # Create a combined module that exports all render functions
    erb_views_js = <<~JS
      // Article views - auto-generated from .html.erb templates
      // Each exported function is a render function that takes { article } or { articles }

    JS

    render_exports = []
    Dir.glob(File.join(erb_dir, '*.html.erb')).sort.each do |erb_path|
      name = File.basename(erb_path, '.html.erb')
      erb_views_js += "import { render as #{name}_render } from './erb/#{name}.js';\n"
      render_exports << "#{name}: #{name}_render"
    end

    erb_views_js += <<~JS

      // Export ArticleViews - method names match controller action names
      export const ArticleViews = {
        #{render_exports.join(",\n  ")},
        // $new alias for 'new' (JS reserved word handling)
        $new: new_render
      };
    JS

    File.write(File.join(@dist_dir, 'views/articles.js'), erb_views_js)
    puts("  -> dist/views/articles.js (combined ERB module)")
  end

  def transpile_layout()
    layout_path = File.join(DEMO_ROOT, 'app/views/layouts/application.html.erb')
    return unless File.exist?(layout_path)

    puts("Transpiling layout: application.html.erb")
    template = File.read(layout_path)

    # Simple transformation: replace <%= yield %> with ${content}
    js_template = template.gsub('<%=', '${').gsub('%>', '}')
    js_template = js_template.gsub('${yield}', '${content}').gsub('${ yield }', '${content}')

    # Wrap in a template literal function
    js = <<~JS
      // Application layout - wraps view content
      // Generated from app/views/layouts/application.html.erb
      export function layout(content) {
        return `#{js_template}`;
      }
    JS

    dest_dir = File.join(@dist_dir, 'views/layouts')
    FileUtils.mkdir_p(dest_dir)
    File.write(File.join(dest_dir, 'application.js'), js)
    puts("  -> dist/views/layouts/application.js")
  end

  def transpile_directory(src_dir, dest_dir, pattern = '**/*.rb', skip: [], section: nil)
    Dir.glob(File.join(src_dir, pattern)).each do |src_path|
      basename = File.basename(src_path)
      next if skip.include?(basename)

      relative = src_path.sub(src_dir + '/', '')
      dest_path = File.join(dest_dir, relative.sub(/\.rb$/, '.js'))
      self.transpile_file(src_path, dest_path, section)
    end
  end

  def generate_application_record()
    wrapper = <<~JS
      // ApplicationRecord - wraps ActiveRecord from adapter
      // This file is generated by the build script
      import { ActiveRecord } from '../lib/active_record.mjs';

      export class ApplicationRecord extends ActiveRecord {
        // Subclasses (Article, Comment) extend this and add their own validations
      }
    JS
    dest_dir = File.join(@dist_dir, 'models')
    FileUtils.mkdir_p(dest_dir)
    File.write(File.join(dest_dir, 'application_record.js'), wrapper)
    puts("  -> models/application_record.js (wrapper for ActiveRecord)")
  end

  def transpile_routes_files()
    src_path = File.join(DEMO_ROOT, 'config/routes.rb')
    dest_dir = File.join(@dist_dir, 'config')
    source = File.read(src_path)
    relative_src = src_path.sub(DEMO_ROOT + '/', '')
    base_options = self.build_options()

    # Generate paths.js first (with only path helpers)
    puts("Transpiling: routes.rb -> paths.js")
    paths_options = base_options.merge(file: relative_src, paths_only: true)
    result = Ruby2JS.convert(source, paths_options)
    paths_js = result.to_s

    paths_path = File.join(dest_dir, 'paths.js')
    FileUtils.mkdir_p(dest_dir)
    File.write(paths_path, paths_js)
    puts("  -> #{paths_path}")

    # Generate sourcemap for paths.js
    map_path = "#{paths_path}.map"
    sourcemap = result.sourcemap
    sourcemap[:sourcesContent] = [source]
    File.write(map_path, JSON.generate(sourcemap))
    puts("  -> #{map_path}")

    # Generate routes.js (imports path helpers from paths.js)
    puts("Transpiling: routes.rb -> routes.js")
    routes_options = base_options.merge(file: relative_src, paths_file: './paths.js', database: @database)
    result = Ruby2JS.convert(source, routes_options)
    routes_js = result.to_s

    routes_path = File.join(dest_dir, 'routes.js')
    File.write(routes_path, routes_js)
    puts("  -> #{routes_path}")

    # Generate sourcemap for routes.js
    map_path = "#{routes_path}.map"
    sourcemap = result.sourcemap
    sourcemap[:sourcesContent] = [source]
    File.write(map_path, JSON.generate(sourcemap))
    puts("  -> #{map_path}")
  end

  def generate_models_index()
    models_dir = File.join(@dist_dir, 'models')
    model_files = Dir.glob(File.join(models_dir, '*.js'))
      .map { |f| File.basename(f, '.js') }
      .reject { |name| name == 'application_record' || name == 'index' }
      .sort

    return unless model_files.any?

    index_js = model_files.map do |name|
      # Use explicit capitalization for JS compatibility
      class_name = name.split('_').map { |s| s[0].upcase + s[1..-1] }.join
      "export { #{class_name} } from './#{name}.js';"
    end.join("\n") + "\n"

    File.write(File.join(models_dir, 'index.js'), index_js)
    puts("  -> #{File.join(models_dir, 'index.js')} (re-exports)")
  end
end

# CLI entry point - only run if this file is executed directly
if __FILE__ == $0
  dist_dir = ARGV[0] ? File.expand_path(ARGV[0]) : nil
  builder = SelfhostBuilder.new(dist_dir)
  builder.build()
end
