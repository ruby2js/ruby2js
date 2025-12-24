#!/usr/bin/env ruby
# Build script for Phlex + Stimulus demo

require 'fileutils'
require 'yaml'

DEMO_ROOT = File.expand_path('..', __dir__)
DIST_DIR = File.join(DEMO_ROOT, 'dist')

# Add lib to load path
$LOAD_PATH.unshift File.expand_path('../../../lib', DEMO_ROOT)
require 'ruby2js'
require 'ruby2js/filter/phlex'
require 'ruby2js/filter/stimulus'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/camelCase'

def load_config(section = nil)
  config_path = File.join(DEMO_ROOT, 'config/ruby2js.yml')
  config = YAML.load_file(config_path, aliases: true)
  
  if section && config[section]
    config[section]
  else
    config['default'] || {}
  end
end

def resolve_filters(filter_names)
  filter_names.map do |name|
    case name.downcase
    when 'phlex' then Ruby2JS::Filter::Phlex
    when 'stimulus' then Ruby2JS::Filter::Stimulus
    when 'functions' then Ruby2JS::Filter::Functions
    when 'esm' then Ruby2JS::Filter::ESM
    when 'camelcase' then Ruby2JS::Filter::CamelCase
    else
      raise "Unknown filter: #{name}"
    end
  end
end

def transpile_file(src_path, dest_path, section = nil)
  config = load_config(section)
  
  options = {
    eslevel: config['eslevel'] || 2022,
    comparison: config['comparison']&.to_sym || :identity,
    autoexports: config['autoexports'] != false
  }
  
  if config['include']
    options[:include] = config['include'].map(&:to_sym)
  end
  
  if config['filters']
    options[:filters] = resolve_filters(config['filters'])
  end
  
  source = File.read(src_path)
  result = Ruby2JS.convert(source, options)
  
  FileUtils.mkdir_p(File.dirname(dest_path))
  File.write(dest_path, result.to_s)
  
  # Write sourcemap
  if result.respond_to?(:sourcemap)
    File.write("#{dest_path}.map", result.sourcemap)
  end
  
  puts "  #{File.basename(src_path)} -> #{dest_path}"
end

def transpile_directory(src_dir, dest_dir, section)
  Dir.glob(File.join(src_dir, '**/*.rb')).each do |src_path|
    relative = src_path.sub(src_dir + '/', '')
    dest_path = File.join(dest_dir, relative.sub(/\.rb$/, '.js'))
    transpile_file(src_path, dest_path, section)
  end
end

puts "=== Building Phlex + Stimulus Demo ==="
puts

# Clean dist
FileUtils.rm_rf(DIST_DIR)
FileUtils.mkdir_p(DIST_DIR)

# Transpile components
components_dir = File.join(DEMO_ROOT, 'app/components')
if File.exist?(components_dir)
  puts "Components:"
  transpile_directory(components_dir, File.join(DIST_DIR, 'components'), 'components')
  puts
end

# Transpile Stimulus controllers
controllers_dir = File.join(DEMO_ROOT, 'app/javascript/controllers')
if File.exist?(controllers_dir)
  puts "Stimulus Controllers:"
  transpile_directory(controllers_dir, File.join(DIST_DIR, 'javascript/controllers'), 'stimulus')
  puts
end

puts "=== Build Complete ==="
