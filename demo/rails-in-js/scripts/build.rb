#!/usr/bin/env ruby
# Build script for Rails-in-JS demo
# Transpiles Ruby models and controllers to JavaScript
#
# Can be run directly: ruby scripts/build.rb [dist_dir]
# Or transpiled to JS and imported as: import { SelfhostBuilder } from './build.mjs'

require 'fileutils'
require 'json'

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
require_relative '../lib/erb_compiler'

class SelfhostBuilder
  DEMO_ROOT = File.expand_path('..', __dir__)

  # Browser databases - these run in the browser with IndexedDB or WASM
  BROWSER_DATABASES = ['dexie', 'indexeddb', 'sqljs', 'sql.js'].freeze

  # Map DATABASE env var to adapter source file
  ADAPTER_FILES = {
    # Browser adapters
    'sqljs' => 'active_record_sqljs.mjs',
    'sql.js' => 'active_record_sqljs.mjs',
    'dexie' => 'active_record_dexie.mjs',
    'indexeddb' => 'active_record_dexie.mjs',
    # Node.js adapters
    'better_sqlite3' => 'active_record_better_sqlite3.mjs',
    'sqlite3' => 'active_record_better_sqlite3.mjs',  # Alias
    'pg' => 'active_record_pg.mjs',
    'postgres' => 'active_record_pg.mjs',
    'postgresql' => 'active_record_pg.mjs'
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
  ERB_OPTIONS = {
    eslevel: 2022,
    include: [:class, :call],
    filters: [
      Ruby2JS::Filter::Erb,
      Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::Return
    ]
  }.freeze

  def initialize(dist_dir = nil)
    @dist_dir = dist_dir || File.join(DEMO_ROOT, 'dist')
    @database = nil  # Set during build from config
    @target = nil    # Derived from database: 'browser' or 'node'
  end

  # Note: Using explicit () on all method calls for JS transpilation compatibility
  def build()
    # Clean and create dist directory
    FileUtils.rm_rf(@dist_dir)
    FileUtils.mkdir_p(@dist_dir)

    puts("=== Building Rails-in-JS Demo ===")
    puts("")

    # Copy database adapter and derive target
    puts("Database Adapter:")
    db_config = self.load_database_config()
    @database = db_config['adapter'] || db_config[:adapter] || 'sqljs'
    @target = BROWSER_DATABASES.include?(@database) ? 'browser' : 'node'
    self.copy_database_adapter(db_config)
    puts("  Target: #{@target}")
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

    # Transpile controllers
    puts("Controllers:")
    self.transpile_directory(
      File.join(DEMO_ROOT, 'app/controllers'),
      File.join(@dist_dir, 'controllers')
    )
    puts("")

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

    # Transpile views (ERB templates only)
    puts("Views:")
    self.transpile_erb_directory()
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
      require 'yaml'
      config = YAML.load_file(config_path)
      if config && config[env] && config[env]['adapter']
        puts("  Using config/database.yml [#{env}]")
        return config[env]
      end
    end

    # Default: sqljs
    puts("  Using default adapter: sqljs")
    { 'adapter' => 'sqljs', 'database' => 'rails_in_js' }
  end

  def copy_database_adapter(db_config)
    adapter = db_config['adapter'] || db_config[:adapter] || 'sqljs'
    adapter_file = ADAPTER_FILES[adapter]

    unless adapter_file
      valid = ADAPTER_FILES.keys.join(', ')
      raise "Unknown DATABASE adapter: #{adapter}. Valid options: #{valid}"
    end

    adapter_src = File.join(DEMO_ROOT, 'lib/adapters', adapter_file)
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

    # Copy target-specific files (rails.js from targets/browser or targets/node)
    target_src = File.join(DEMO_ROOT, 'lib/targets', @target)
    Dir.glob(File.join(target_src, '*.js')).each do |src_path|
      dest_path = File.join(lib_dest, File.basename(src_path))
      FileUtils.cp(src_path, dest_path)
      puts("  Copying: targets/#{@target}/#{File.basename(src_path)}")
      puts("    -> #{dest_path}")
    end

    # Copy shared lib files (erb_runtime.mjs, etc.) - exclude old rails.js
    lib_src = File.join(DEMO_ROOT, 'lib')
    Dir.glob(File.join(lib_src, '*.mjs')).each do |src_path|
      dest_path = File.join(lib_dest, File.basename(src_path))
      FileUtils.cp(src_path, dest_path)
      puts("  Copying: #{File.basename(src_path)}")
      puts("    -> #{dest_path}")
    end
  end

  def transpile_file(src_path, dest_path)
    puts("Transpiling: #{File.basename(src_path)}")
    source = File.read(src_path)

    # Use relative path for cleaner display in browser debugger
    relative_src = src_path.sub(DEMO_ROOT + '/', '')
    result = Ruby2JS.convert(source, OPTIONS.merge(file: relative_src))
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

    ruby_src = ErbCompiler.new(template).src
    # Pass database option for target-aware link generation
    erb_options = ERB_OPTIONS.merge(database: @database)
    js = Ruby2JS.convert(ruby_src, erb_options).to_s
    js = js.sub(/^function render/, 'export function render')

    FileUtils.mkdir_p(File.dirname(dest_path))
    File.write(dest_path, js)
    puts("  -> #{dest_path}")
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

  def transpile_directory(src_dir, dest_dir, pattern = '**/*.rb', skip: [])
    Dir.glob(File.join(src_dir, pattern)).each do |src_path|
      basename = File.basename(src_path)
      next if skip.include?(basename)

      relative = src_path.sub(src_dir + '/', '')
      dest_path = File.join(dest_dir, relative.sub(/\.rb$/, '.js'))
      self.transpile_file(src_path, dest_path)
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

    # Generate paths.js first (with only path helpers)
    puts("Transpiling: routes.rb -> paths.js")
    paths_options = OPTIONS.merge(file: relative_src, paths_only: true)
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
    routes_options = OPTIONS.merge(file: relative_src, paths_file: './paths.js')
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
