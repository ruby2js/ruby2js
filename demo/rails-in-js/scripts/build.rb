#!/usr/bin/env ruby
# Build script for Rails-in-JS demo
# Transpiles Ruby models and controllers to JavaScript

require 'fileutils'

# Ensure we're using the local ruby2js
$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)
require 'ruby2js'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/return'

DEMO_ROOT = File.expand_path('..', __dir__)
DIST_DIR = File.join(DEMO_ROOT, 'dist')

# Common transpilation options
OPTIONS = {
  eslevel: 2022,
  include: [:class, :call],
  filters: [
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::ESM,
    Ruby2JS::Filter::Return
  ]
}

def transpile_file(src_path, dest_path)
  puts "Transpiling: #{File.basename(src_path)}"
  source = File.read(src_path)

  js = Ruby2JS.convert(source, OPTIONS.merge(file: src_path)).to_s

  FileUtils.mkdir_p(File.dirname(dest_path))
  File.write(dest_path, js)
  puts "  -> #{dest_path}"
end

def transpile_directory(src_dir, dest_dir, pattern = '**/*.rb')
  Dir.glob(File.join(src_dir, pattern)).each do |src_path|
    relative = src_path.sub(src_dir + '/', '')
    dest_path = File.join(dest_dir, relative.sub(/\.rb$/, '.js'))
    transpile_file(src_path, dest_path)
  end
end

# Create dist directory
FileUtils.mkdir_p(DIST_DIR)

puts "=== Building Rails-in-JS Demo ==="
puts

# Transpile models
puts "Models:"
transpile_directory(
  File.join(DEMO_ROOT, 'app/models'),
  File.join(DIST_DIR, 'models')
)
puts

# Transpile controllers
puts "Controllers:"
transpile_directory(
  File.join(DEMO_ROOT, 'app/controllers'),
  File.join(DIST_DIR, 'controllers')
)
puts

# Transpile config
puts "Config:"
transpile_directory(
  File.join(DEMO_ROOT, 'config'),
  File.join(DIST_DIR, 'config')
)
puts

puts "=== Build Complete ==="
