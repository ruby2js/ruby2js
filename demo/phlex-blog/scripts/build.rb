#!/usr/bin/env ruby
# Build script for Phlex Blog demo
# Transpiles Ruby models, controllers, and Phlex components to JavaScript

require 'fileutils'
require 'json'
require 'yaml'

# Ensure we're using the local ruby2js
$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)
require 'ruby2js'
require 'ruby2js/filter/rails/model'
require 'ruby2js/filter/rails/controller'
require 'ruby2js/filter/rails/routes'
require 'ruby2js/filter/rails/migration'
require 'ruby2js/filter/rails/seeds'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/return'
require 'ruby2js/filter/pragma'
require 'ruby2js/filter/phlex'

class PhlexBlogBuilder
  DEMO_ROOT = File.expand_path('..', __dir__)

  # Browser databases
  BROWSER_DATABASES = ['dexie', 'indexeddb', 'sqljs', 'sql.js'].freeze

  # Map DATABASE env var to adapter source file
  ADAPTER_FILES = {
    'sqljs' => 'active_record_sqljs.mjs',
    'sql.js' => 'active_record_sqljs.mjs',
    'dexie' => 'active_record_dexie.mjs',
    'indexeddb' => 'active_record_dexie.mjs',
    'better_sqlite3' => 'active_record_better_sqlite3.mjs',
    'sqlite3' => 'active_record_better_sqlite3.mjs'
  }.freeze

  # Common transpilation options
  OPTIONS = {
    eslevel: 2022,
    include: [:class, :call],
    autoexports: true,
    filters: [
      Ruby2JS::Filter::Rails::Model,
      Ruby2JS::Filter::Rails::Controller,
      Ruby2JS::Filter::Rails::Routes,
      Ruby2JS::Filter::Rails::Migration,
      Ruby2JS::Filter::Rails::Seeds,
      Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::ESM,
      Ruby2JS::Filter::Return
    ]
  }.freeze

  # Options for Phlex components
  COMPONENT_OPTIONS = {
    eslevel: 2022,
    include: [:class, :call],
    autoexports: true,
    comparison: :identity,
    filters: [
      Ruby2JS::Filter::Pragma,
      Ruby2JS::Filter::Phlex,
      Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::ESM,
      Ruby2JS::Filter::Return
    ]
  }.freeze

  def initialize(dist_dir = nil)
    @dist_dir = dist_dir || File.join(DEMO_ROOT, 'dist')
    @database = nil
    @target = nil
  end

  def build
    FileUtils.rm_rf(@dist_dir)
    FileUtils.mkdir_p(@dist_dir)

    puts "=== Building Phlex Blog Demo ==="
    puts ""

    # Load database config
    puts "Database Adapter:"
    db_config = load_database_config
    @database = db_config['adapter'] || 'sqljs'
    @target = BROWSER_DATABASES.include?(@database) ? 'browser' : 'server'
    copy_database_adapter(db_config)
    puts "  Target: #{@target}"
    puts ""

    # Copy lib files
    puts "Library:"
    copy_lib_files
    puts ""

    # Generate ApplicationRecord and transpile models
    puts "Models:"
    generate_application_record
    transpile_directory(
      File.join(DEMO_ROOT, 'app/models'),
      File.join(@dist_dir, 'models'),
      '**/*.rb'
    )
    generate_models_index
    puts ""

    # Transpile controllers
    puts "Controllers:"
    transpile_directory(
      File.join(DEMO_ROOT, 'app/controllers'),
      File.join(@dist_dir, 'controllers'),
      '**/*.rb'
    )
    puts ""

    # Transpile Phlex components
    puts "Components:"
    copy_phlex_runtime
    transpile_directory(
      File.join(DEMO_ROOT, 'app/components'),
      File.join(@dist_dir, 'components'),
      '**/*.rb',
      component: true
    )
    # Also transpile application_view from views
    transpile_directory(
      File.join(DEMO_ROOT, 'app/views'),
      File.join(@dist_dir, 'views'),
      '**/*.rb',
      component: true
    )
    puts ""

    # Transpile config
    puts "Config:"
    transpile_directory(
      File.join(DEMO_ROOT, 'config'),
      File.join(@dist_dir, 'config'),
      '**/*.rb',
      skip: ['routes.rb']
    )
    transpile_routes_files
    puts ""

    # Transpile db
    puts "Database:"
    transpile_directory(
      File.join(DEMO_ROOT, 'db'),
      File.join(@dist_dir, 'db'),
      '**/*.rb'
    )
    puts ""

    puts "=== Build Complete ==="
  end

  def load_database_config
    env = ENV['RAILS_ENV'] || ENV['NODE_ENV'] || 'development'

    if ENV['DATABASE']
      puts "  Using DATABASE=#{ENV['DATABASE']} from environment"
      return { 'adapter' => ENV['DATABASE'].downcase }
    end

    config_path = File.join(DEMO_ROOT, 'config/database.yml')
    if File.exist?(config_path)
      config = YAML.load_file(config_path)
      if config && config[env] && config[env]['adapter']
        puts "  Using config/database.yml [#{env}]"
        return config[env]
      end
    end

    puts "  Using default adapter: sqljs"
    { 'adapter' => 'sqljs', 'database' => 'phlex_blog' }
  end

  def copy_database_adapter(db_config)
    adapter = db_config['adapter'] || 'sqljs'
    adapter_file = ADAPTER_FILES[adapter]

    unless adapter_file
      raise "Unknown DATABASE adapter: #{adapter}"
    end

    package_dir = File.join(DEMO_ROOT, '../../packages/juntos')
    adapter_src = File.join(package_dir, 'adapters', adapter_file)
    adapter_dest = File.join(@dist_dir, 'lib/active_record.mjs')
    FileUtils.mkdir_p(File.dirname(adapter_dest))

    adapter_code = File.read(adapter_src)
    adapter_code = adapter_code.sub('const DB_CONFIG = {};', "const DB_CONFIG = #{JSON.generate(db_config)};")
    File.write(adapter_dest, adapter_code)

    puts "  Adapter: #{adapter} -> lib/active_record.mjs"
  end

  def copy_lib_files
    lib_dest = File.join(@dist_dir, 'lib')
    FileUtils.mkdir_p(lib_dest)

    target_dir = @target == 'browser' ? 'browser' : 'node'
    package_dir = File.join(DEMO_ROOT, '../../packages/juntos')

    target_src = File.join(package_dir, 'targets', target_dir)
    Dir.glob(File.join(target_src, '*.js')).each do |src_path|
      dest_path = File.join(lib_dest, File.basename(src_path))
      FileUtils.cp(src_path, dest_path)
      puts "  Copying: targets/#{target_dir}/#{File.basename(src_path)}"
    end
  end

  def copy_phlex_runtime
    lib_dest = File.join(@dist_dir, 'lib')
    FileUtils.mkdir_p(lib_dest)

    package_dir = File.join(DEMO_ROOT, '../../packages/juntos')
    src_path = File.join(package_dir, 'phlex_runtime.mjs')
    return unless File.exist?(src_path)

    dest_path = File.join(lib_dest, 'phlex_runtime.mjs')
    FileUtils.cp(src_path, dest_path)
    puts "  Copying: phlex_runtime.mjs"
  end

  def transpile_file(src_path, dest_path, component: false)
    puts "Transpiling: #{File.basename(src_path)}"
    source = File.read(src_path)

    relative_src = src_path.sub(DEMO_ROOT + '/', '')
    options = (component ? COMPONENT_OPTIONS : OPTIONS).merge(file: relative_src)
    result = Ruby2JS.convert(source, options)
    js = result.to_s

    FileUtils.mkdir_p(File.dirname(dest_path))

    # Generate sourcemap
    map_path = "#{dest_path}.map"
    sourcemap = result.sourcemap
    sourcemap[:sourcesContent] = [source]

    map_dir = File.dirname(dest_path).sub(DEMO_ROOT + '/', '')
    depth = map_dir.split('/').length
    source_from_map = ('../' * depth) + relative_src
    sourcemap[:sources] = [source_from_map]

    js_with_map = "#{js}\n//# sourceMappingURL=#{File.basename(map_path)}\n"
    File.write(dest_path, js_with_map)
    File.write(map_path, JSON.generate(sourcemap))

    puts "  -> #{dest_path}"
  end

  def transpile_directory(src_dir, dest_dir, pattern = '**/*.rb', skip: [], component: false)
    return unless Dir.exist?(src_dir)

    Dir.glob(File.join(src_dir, pattern)).each do |src_path|
      basename = File.basename(src_path)
      next if skip.include?(basename)

      relative = src_path.sub(src_dir + '/', '')
      dest_path = File.join(dest_dir, relative.sub(/\.rb$/, '.js'))
      transpile_file(src_path, dest_path, component: component)
    end
  end

  def transpile_routes_files
    src_path = File.join(DEMO_ROOT, 'config/routes.rb')
    dest_dir = File.join(@dist_dir, 'config')
    source = File.read(src_path)
    relative_src = src_path.sub(DEMO_ROOT + '/', '')

    # Generate paths.js
    puts "Transpiling: routes.rb -> paths.js"
    paths_options = OPTIONS.merge(file: relative_src, paths_only: true)
    result = Ruby2JS.convert(source, paths_options)
    paths_path = File.join(dest_dir, 'paths.js')
    FileUtils.mkdir_p(dest_dir)
    File.write(paths_path, result.to_s)
    puts "  -> #{paths_path}"

    # Generate routes.js
    puts "Transpiling: routes.rb -> routes.js"
    routes_options = OPTIONS.merge(file: relative_src, paths_file: './paths.js', database: @database)
    result = Ruby2JS.convert(source, routes_options)
    routes_path = File.join(dest_dir, 'routes.js')
    File.write(routes_path, result.to_s)
    puts "  -> #{routes_path}"
  end

  def generate_application_record
    wrapper = <<~JS
      // ApplicationRecord - wraps ActiveRecord from adapter
      import { ActiveRecord } from '../lib/active_record.mjs';

      export class ApplicationRecord extends ActiveRecord {
      }
    JS
    dest_dir = File.join(@dist_dir, 'models')
    FileUtils.mkdir_p(dest_dir)
    File.write(File.join(dest_dir, 'application_record.js'), wrapper)
    puts "  -> models/application_record.js"
  end

  def generate_models_index
    models_dir = File.join(@dist_dir, 'models')
    model_files = Dir.glob(File.join(models_dir, '*.js'))
      .map { |f| File.basename(f, '.js') }
      .reject { |name| name == 'application_record' || name == 'index' }
      .sort

    return unless model_files.any?

    index_js = model_files.map do |name|
      class_name = name.split('_').map(&:capitalize).join
      "export { #{class_name} } from './#{name}.js';"
    end.join("\n") + "\n"

    File.write(File.join(models_dir, 'index.js'), index_js)
    puts "  -> models/index.js"
  end
end

if __FILE__ == $0
  dist_dir = ARGV[0] ? File.expand_path(ARGV[0]) : nil
  builder = PhlexBlogBuilder.new(dist_dir)
  builder.build
end
