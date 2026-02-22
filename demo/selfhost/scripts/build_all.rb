#!/usr/bin/env ruby
# Consolidated build script for selfhost
# Loads Ruby2JS once and transpiles all files in a single process
# Much faster than spawning separate Ruby processes for each file

require 'json'
require 'fileutils'

ROOT = File.expand_path('../../..', __dir__)
SELFHOST = File.expand_path('..', __dir__)
DIST = File.join(SELFHOST, 'dist')
FILTERS_DIR = File.join(SELFHOST, 'filters')

$LOAD_PATH.unshift File.join(ROOT, 'lib')

# Shared filter configurations
require_relative 'filter_config'

# Additional requires for build_all (polyfill for some filters)
require 'ruby2js/filter/polyfill'

# Load manifest
def manifest
  @manifest ||= JSON.parse(File.read(File.join(SELFHOST, 'spec_manifest.json')))
end

# Exceptions to the naming convention (spec name => filter name)
# Convention: X_spec.rb => X, rails_X_spec.rb => rails/X
FILTER_NAME_EXCEPTIONS = {
  'camelcase_spec.rb' => 'camelCase'
}.freeze

def filter_for_spec(spec_name)
  return FILTER_NAME_EXCEPTIONS[spec_name] if FILTER_NAME_EXCEPTIONS[spec_name]

  base = spec_name.sub('_spec.rb', '')
  # rails_X => rails/X
  base.sub(/^rails_/, 'rails/')
end

def transpile_spec(spec_file, output_path)
  source = File.read(spec_file)

  # Add skip pragmas to all requires
  source = source.gsub(/^(require\s+['"][^'"]*['"])/) do
    "#{$1} # Pragma: skip"
  end

  js = Ruby2JS.convert(source,
    eslevel: 2022,
    comparison: :identity,
    underscored_private: true,
    file: spec_file,
    filters: SPEC_FILTERS
  ).to_s

  FileUtils.mkdir_p(File.dirname(output_path))
  File.write(output_path, js)
end

def transpile_filter(filter_file, output_path)
  source = File.read(filter_file)

  js = Ruby2JS.convert(source,
    eslevel: 2022,
    comparison: :identity,
    underscored_private: true,
    nullish_to_s: true,
    include: [:call, :keys],
    file: filter_file,
    filters: FILTER_FILTERS
  ).to_s

  FileUtils.mkdir_p(File.dirname(output_path))
  File.write(output_path, js)
end

# Build specs helper (used by 'specs' and 'all' commands)
def build_specs(spec_list)
  FileUtils.mkdir_p(DIST)

  spec_list.each do |spec_name|
    spec_path = File.join(ROOT, 'spec', spec_name)
    output_path = File.join(DIST, spec_name.sub('.rb', '.mjs'))

    if File.exist?(spec_path)
      print "  #{spec_name}..."
      transpile_spec(spec_path, output_path)
      puts " done"
    else
      puts "  #{spec_name} (skipped - not found)"
    end
  end
end

# Build filters helper (used by 'filters' and 'all' commands)
def build_filters(filter_list)
  FileUtils.mkdir_p(FILTERS_DIR)

  filter_list.each do |name|
    src = File.join(ROOT, 'lib/ruby2js/filter', "#{name}.rb")
    output = File.join(FILTERS_DIR, "#{name}.js")

    if File.exist?(src)
      print "  #{name}..."
      transpile_filter(src, output)
      puts " done"
    else
      puts "  #{name} (skipped - not found)"
    end
  end
end

# Get list of specs to build
def specs_to_build(target = nil)
  if target
    [target]
  else
    manifest['ready'] + manifest['partial'].map { |e| e.is_a?(Hash) ? e['spec'] : e }
  end
end

# Extra filter dependencies (not tied to specs)
# These are shared modules required by other filters
EXTRA_FILTERS = ['rails/active_record', 'rails/concern', 'rails/logger', 'active_support'].freeze

# Get list of filters to build
def filters_to_build(target = nil)
  if target
    [target]
  else
    specs = manifest['ready'] + manifest['partial'].map { |e| e.is_a?(Hash) ? e['spec'] : e }
    filters = specs.map { |s| filter_for_spec(s) }
    # Add extra dependencies
    filters += EXTRA_FILTERS
    filters.uniq.select { |name| File.exist?(File.join(ROOT, 'lib/ruby2js/filter', "#{name}.rb")) }
  end
end

# Parse command line
command = ARGV[0] || 'all'
target = ARGV[1]

case command
when 'specs'
  # Build all specs (or specific one)
  build_specs(specs_to_build(target))

when 'filters'
  # Build all filters (or specific one)
  build_filters(filters_to_build(target))

when 'all'
  # Build both specs and filters in a single process (avoids Ruby startup overhead)
  puts "Building specs..."
  build_specs(specs_to_build)

  puts ""
  puts "Building filters..."
  build_filters(filters_to_build)

when 'ready'
  # Build only ready specs
  FileUtils.mkdir_p(DIST)

  manifest['ready'].each do |spec_name|
    spec_path = File.join(ROOT, 'spec', spec_name)
    output_path = File.join(DIST, spec_name.sub('.rb', '.mjs'))

    print "  #{spec_name}..."
    transpile_spec(spec_path, output_path)
    puts " done"
  end

when 'partial'
  # Build only partial specs
  FileUtils.mkdir_p(DIST)

  manifest['partial'].each do |entry|
    spec_name = entry.is_a?(Hash) ? entry['spec'] : entry
    spec_path = File.join(ROOT, 'spec', spec_name)
    output_path = File.join(DIST, spec_name.sub('.rb', '.mjs'))

    print "  #{spec_name}..."
    transpile_spec(spec_path, output_path)
    puts " done"
  end

else
  puts "Usage: build_all.rb [specs|filters|all|ready|partial] [target]"
  puts ""
  puts "Commands:"
  puts "  specs   - Build all spec files (or specific one if target given)"
  puts "  filters - Build all filter files (or specific one if target given)"
  puts "  all     - Build both specs and filters"
  puts "  ready   - Build only ready specs"
  puts "  partial - Build only partial specs"
  exit 1
end
