#!/usr/bin/env ruby
# Build script for Ink Console demo
# Transpiles Ruby components to JavaScript for Ink terminal UI

require 'fileutils'
require 'json'
require 'yaml'

# Ensure we're using the local ruby2js
$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)
require 'ruby2js'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/return'
require 'ruby2js/filter/ink'
require 'ruby2js/filter/rails/model'

class InkConsoleBuilder
  DEMO_ROOT = File.expand_path('..', __dir__)

  # Map DATABASE env var to adapter source file
  ADAPTER_FILES = {
    'sqlite' => 'active_record_better_sqlite3.mjs',
    'better_sqlite3' => 'active_record_better_sqlite3.mjs',
    'sqlite3' => 'active_record_better_sqlite3.mjs',
    'pg' => 'active_record_pg.mjs',
    'postgres' => 'active_record_pg.mjs',
    'postgresql' => 'active_record_pg.mjs',
    'mysql2' => 'active_record_mysql2.mjs',
    'mysql' => 'active_record_mysql2.mjs'
  }.freeze

  # Common transpilation options
  OPTIONS = {
    eslevel: 2022,
    include: [:class, :call],
    autoexports: true,
    filters: [
      Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::ESM,
      Ruby2JS::Filter::Return
    ]
  }.freeze

  # Options for model files
  MODEL_OPTIONS = {
    eslevel: 2022,
    include: [:class, :call],
    autoexports: true,
    filters: [
      Ruby2JS::Filter::Rails::Model,
      Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::ESM,
      Ruby2JS::Filter::Return
    ]
  }.freeze

  # Options for Ink components
  COMPONENT_OPTIONS = {
    eslevel: 2022,
    include: [:class, :call],
    autoexports: true,
    comparison: :identity,
    filters: [
      Ruby2JS::Filter::Ink,
      Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::ESM,
      Ruby2JS::Filter::Return
    ]
  }.freeze

  def initialize(dist_dir = nil)
    @dist_dir = dist_dir || File.join(DEMO_ROOT, 'dist')
    @database = nil
  end

  def build
    FileUtils.rm_rf(@dist_dir)
    FileUtils.mkdir_p(@dist_dir)

    puts "=== Building Ink Console ==="
    puts ""

    # Load database config
    puts "Database Adapter:"
    db_config = load_database_config
    @database = db_config['adapter'] || 'sqlite'
    copy_database_adapter(db_config)
    puts ""

    # Copy lib files
    puts "Library:"
    copy_lib_files
    puts ""

    # Copy/transpile components
    puts "Components:"
    transpile_directory(
      File.join(DEMO_ROOT, 'app/components'),
      File.join(@dist_dir, 'components'),
      '**/*.rb',
      component: true
    )
    puts ""

    # Copy/transpile models (if any)
    if Dir.exist?(File.join(DEMO_ROOT, 'app/models'))
      puts "Models:"
      generate_application_record
      transpile_directory(
        File.join(DEMO_ROOT, 'app/models'),
        File.join(@dist_dir, 'models'),
        '**/*.rb',
        model: true
      )
      generate_models_index
      puts ""
    end

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

    puts "  Using default adapter: sqlite"
    { 'adapter' => 'sqlite', 'database' => 'db/development.sqlite3' }
  end

  def copy_database_adapter(db_config)
    adapter = db_config['adapter'] || 'sqlite'
    adapter_file = ADAPTER_FILES[adapter]

    unless adapter_file
      puts "  WARNING: Unknown adapter '#{adapter}', falling back to sqlite"
      adapter = 'sqlite'
      adapter_file = ADAPTER_FILES[adapter]
    end

    package_dir = File.join(DEMO_ROOT, '../../packages/juntos')
    adapter_src = File.join(package_dir, 'adapters', adapter_file)

    unless File.exist?(adapter_src)
      puts "  WARNING: Adapter file not found: #{adapter_src}"
      return
    end

    lib_dest = File.join(@dist_dir, 'lib')
    FileUtils.mkdir_p(lib_dest)

    adapter_code = File.read(adapter_src)
    adapter_code = adapter_code.sub('const DB_CONFIG = {};', "const DB_CONFIG = #{JSON.generate(db_config)};")
    File.write(File.join(lib_dest, 'active_record.mjs'), adapter_code)

    puts "  Adapter: #{adapter} -> lib/active_record.mjs"

    # Copy dialect files
    dialects_src = File.join(package_dir, 'adapters/dialects')
    dialects_dest = File.join(lib_dest, 'dialects')
    if Dir.exist?(dialects_src)
      FileUtils.mkdir_p(dialects_dest)
      Dir.glob(File.join(dialects_src, '*.mjs')).each do |src|
        FileUtils.cp(src, dialects_dest)
        puts "  Dialect: #{File.basename(src)} -> lib/dialects/"
      end
    end
  end

  def copy_lib_files
    lib_dest = File.join(@dist_dir, 'lib')
    FileUtils.mkdir_p(lib_dest)

    # Copy ink runtime
    runtime_src = File.join(DEMO_ROOT, 'lib/ink_runtime.mjs')
    if File.exist?(runtime_src)
      FileUtils.cp(runtime_src, File.join(lib_dest, 'ink_runtime.mjs'))
      puts "  Copying: ink_runtime.mjs"
    end

    # Copy query evaluator
    evaluator_src = File.join(DEMO_ROOT, 'lib/query_evaluator.mjs')
    if File.exist?(evaluator_src)
      FileUtils.cp(evaluator_src, File.join(lib_dest, 'query_evaluator.mjs'))
      puts "  Copying: query_evaluator.mjs"
    end

    # Copy model loader
    loader_src = File.join(DEMO_ROOT, 'lib/model_loader.mjs')
    if File.exist?(loader_src)
      FileUtils.cp(loader_src, File.join(lib_dest, 'model_loader.mjs'))
      puts "  Copying: model_loader.mjs"
    end
  end

  def transpile_file(src_path, dest_path, component: false, model: false)
    puts "  Transpiling: #{File.basename(src_path)}"
    source = File.read(src_path)

    relative_src = src_path.sub(DEMO_ROOT + '/', '')
    base_options = model ? MODEL_OPTIONS : (component ? COMPONENT_OPTIONS : OPTIONS)
    options = base_options.merge(file: relative_src)
    result = Ruby2JS.convert(source, options)
    js = result.to_s

    FileUtils.mkdir_p(File.dirname(dest_path))
    File.write(dest_path, js)

    puts "    -> #{dest_path.sub(DEMO_ROOT + '/', '')}"
  end

  def transpile_directory(src_dir, dest_dir, pattern = '**/*.rb', skip: [], component: false, model: false)
    return unless Dir.exist?(src_dir)

    files = Dir.glob(File.join(src_dir, pattern))
    if files.empty?
      puts "  (no files)"
      return
    end

    files.each do |src_path|
      basename = File.basename(src_path)
      next if skip.include?(basename)

      relative = src_path.sub(src_dir + '/', '')
      dest_path = File.join(dest_dir, relative.sub(/\.rb$/, '.js'))
      transpile_file(src_path, dest_path, component: component, model: model)
    end
  end

  def generate_application_record
    wrapper = <<~JS
      // ApplicationRecord - wraps ActiveRecord from adapter
      import { ActiveRecord, CollectionProxy } from '../lib/active_record.mjs';

      export { CollectionProxy };

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
  builder = InkConsoleBuilder.new(dist_dir)
  builder.build
end
