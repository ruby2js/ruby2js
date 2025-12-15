#!/usr/bin/env ruby
# Transpile a Ruby filter to JavaScript for selfhost use

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

require 'ruby2js'
require 'ruby2js/filter/combiner'
require 'ruby2js/filter/pragma'
require 'ruby2js/filter/selfhost'
require 'ruby2js/filter/selfhost/filter'
require 'ruby2js/filter/polyfill'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'

filter_file = ARGV[0] || raise("Usage: transpile_filter.rb <filter_file>")
source = File.read(filter_file)

# Skip requires that are external dependencies
source = source.gsub(/^require ['"]ruby2js['"]/) { "#{$&} # Pragma: skip" }
source = source.gsub(/^require ['"]regexp_parser.*['"]/) { "#{$&} # Pragma: skip" }
source = source.gsub(/^require ['"]pathname['"]/) { "#{$&} # Pragma: skip" }
source = source.gsub(/^require ['"]set['"]/) { "#{$&} # Pragma: skip" }
source = source.gsub(/^require_relative ['"]\.\.\/filter['"]/) { "#{$&} # Pragma: skip" }

js = Ruby2JS.convert(source,
  eslevel: 2022,
  comparison: :identity,
  underscored_private: true,
  nullish_to_s: true,
  include: [:call, :keys],
  file: filter_file,
  filters: [
    Ruby2JS::Filter::Pragma,
    Ruby2JS::Filter::Combiner,
    Ruby2JS::Filter::Selfhost::Filter,
    Ruby2JS::Filter::Selfhost::Core,
    Ruby2JS::Filter::Selfhost::Converter,
    Ruby2JS::Filter::Polyfill,
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM
  ]
).to_s

# Extract the filter name from transpiled output (matches the Ruby module name)
# Look for: const FilterName = (() => {
if match = js.match(/^\s*const\s+(\w+)\s*=\s*\(\(\)\s*=>\s*\{/m)
  filter_name = match[1]
else
  # Fallback: derive from filename
  filter_name = File.basename(filter_file, '.rb').split('_').map(&:capitalize).join
end

# Generate minimal wrapper using shared runtime
puts <<~JS
// Transpiled Ruby2JS Filter: #{filter_name}
// Generated from #{filter_file}

import {
  Parser, SEXP, s, S, ast_node, include, Filter, DEFAULTS,
  excluded, included, process, process_children, process_all,
  _options, filterContext, nodesEqual, registerFilter, Ruby2JS
} from '../filter_runtime.js';

#{js}

// Register the filter
registerFilter('#{filter_name}', #{filter_name});

// Export the filter
export { #{filter_name} as default, #{filter_name} };
JS
