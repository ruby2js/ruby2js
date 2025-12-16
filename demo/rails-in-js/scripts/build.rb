#!/usr/bin/env ruby
# Build script for Rails-in-JS demo
# Transpiles Ruby models and controllers to JavaScript

require 'fileutils'
require 'json'

# Ensure we're using the local ruby2js
$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)
require 'ruby2js'
require 'ruby2js/filter/rails'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/return'
require 'ruby2js/filter/erb'
require 'ruby2js/erubi'

DEMO_ROOT = File.expand_path('..', __dir__)
DIST_DIR = File.join(DEMO_ROOT, 'dist')

# Common transpilation options for Ruby files
# Rails filters run first to transform idiomatic Rails to micro-framework,
# then Functions/ESM/Return handle the JavaScript output
OPTIONS = {
  eslevel: 2022,
  include: [:class, :call],
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
}

# Options for ERB templates
ERB_OPTIONS = {
  eslevel: 2022,
  include: [:class, :call],
  filters: [
    Ruby2JS::Filter::Erb,
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return
  ]
}

def transpile_file(src_path, dest_path)
  puts "Transpiling: #{File.basename(src_path)}"
  source = File.read(src_path)

  # Use relative path for cleaner display in browser debugger
  relative_src = src_path.sub(DEMO_ROOT + '/', '')
  result = Ruby2JS.convert(source, OPTIONS.merge(file: relative_src))
  js = result.to_s

  FileUtils.mkdir_p(File.dirname(dest_path))

  # Generate sourcemap
  map_path = "#{dest_path}.map"
  sourcemap = result.sourcemap
  # Include original Ruby source so browser doesn't need to fetch .rb files
  sourcemap[:sourcesContent] = [source]

  # Compute relative path from sourcemap location back to source file
  # e.g., from dist/controllers/ back to app/controllers/article.rb -> ../../app/controllers/article.rb
  map_dir = File.dirname(dest_path).sub(DEMO_ROOT + '/', '')
  depth = map_dir.split('/').length
  source_from_map = ('../' * depth) + relative_src

  # Update sources array with correct relative path
  sourcemap[:sources] = [source_from_map]

  # Add sourcemap reference to JS file
  js_with_map = "#{js}\n//# sourceMappingURL=#{File.basename(map_path)}"
  File.write(dest_path, js_with_map)
  File.write(map_path, JSON.generate(sourcemap))

  puts "  -> #{dest_path}"
  puts "  -> #{map_path}"
end

def transpile_erb_file(src_path, dest_path)
  puts "Transpiling ERB: #{File.basename(src_path)}"
  template = File.read(src_path)

  # Convert ERB to Ruby, then to JavaScript
  ruby_src = Ruby2JS::Erubi.new(template).src
  js = Ruby2JS.convert(ruby_src, ERB_OPTIONS.merge(file: src_path)).to_s

  # Add export keyword to make it importable
  js = js.sub(/^function render/, 'export function render')

  FileUtils.mkdir_p(File.dirname(dest_path))
  File.write(dest_path, js)
  puts "  -> #{dest_path}"
  js
end

def transpile_erb_directory(src_dir, dest_dir)
  # Collect all ERB templates and their transpiled render functions
  renders = {}

  Dir.glob(File.join(src_dir, '**/*.html.erb')).each do |src_path|
    basename = File.basename(src_path, '.html.erb')
    js = transpile_erb_file(src_path, File.join(dest_dir, "#{basename}.js"))
    renders[basename] = js
  end

  renders
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

# Copy static lib files (rails.js framework)
puts "Library:"
lib_src = File.join(DEMO_ROOT, 'lib')
lib_dest = File.join(DIST_DIR, 'lib')
FileUtils.mkdir_p(lib_dest)
Dir.glob(File.join(lib_src, '*.js')).each do |src_path|
  dest_path = File.join(lib_dest, File.basename(src_path))
  FileUtils.cp(src_path, dest_path)
  puts "  Copying: #{File.basename(src_path)}"
  puts "    -> #{dest_path}"
end
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

# Transpile views (ERB templates only)
puts "Views:"

erb_dir = File.join(DEMO_ROOT, 'app/views/articles')
if Dir.exist?(erb_dir)
  renders = transpile_erb_directory(erb_dir, File.join(DIST_DIR, 'views/erb'))

  # Create a combined module that exports all render functions
  erb_views_js = <<~JS
    // Article views - auto-generated from .html.erb templates
    // Each exported function is a render function that takes { article } or { articles }

  JS

  # Import individual render functions and re-export with proper names
  render_exports = []
  Dir.glob(File.join(erb_dir, '*.html.erb')).sort.each do |erb_path|
    name = File.basename(erb_path, '.html.erb')
    erb_views_js += "import { render as #{name}_render } from './erb/#{name}.js';\n"
    render_exports << "#{name}: #{name}_render"
  end

  # Export ArticleViews with method names matching controller expectations
  erb_views_js += <<~JS

    // Export ArticleViews - method names match controller action names
    export const ArticleViews = {
      #{render_exports.join(",\n  ")},
      // $new alias for 'new' (JS reserved word handling)
      $new: new_render
    };
  JS

  File.write(File.join(DIST_DIR, 'views/articles.js'), erb_views_js)
  puts "  -> dist/views/articles.js (combined ERB module)"
end
puts

# Transpile helpers
puts "Helpers:"
transpile_directory(
  File.join(DEMO_ROOT, 'app/helpers'),
  File.join(DIST_DIR, 'helpers')
)
puts

# Transpile db (seeds)
puts "Database:"
transpile_directory(
  File.join(DEMO_ROOT, 'db'),
  File.join(DIST_DIR, 'db')
)
puts

puts "=== Build Complete ==="
