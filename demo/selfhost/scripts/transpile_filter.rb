#!/usr/bin/env ruby
# Transpile a Ruby filter to JavaScript for selfhost use

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

require 'ruby2js'
require 'ruby2js/filter/combiner'
require 'ruby2js/filter/pragma'
require 'ruby2js/filter/selfhost'
require 'ruby2js/filter/polyfill'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'

filter_file = ARGV[0] || raise("Usage: transpile_filter.rb <filter_file>")
source = File.read(filter_file)

# Skip requires that are external dependencies
source = source.gsub(/^require ['"]ruby2js['"]/) { "#{$&} # Pragma: skip" }
source = source.gsub(/^require ['"]regexp_parser.*['"]/) { "#{$&} # Pragma: skip" }
source = source.gsub(/^require_relative ['"]\.\.\/filter['"]/) { "#{$&} # Pragma: skip" }

js = Ruby2JS.convert(source,
  eslevel: 2022,
  comparison: :identity,
  underscored_private: true,
  nullish_to_s: true,
  include: [:call],
  file: filter_file,
  filters: [
    Ruby2JS::Filter::Pragma,
    Ruby2JS::Filter::Combiner,
    Ruby2JS::Filter::Selfhost::Core,
    Ruby2JS::Filter::Selfhost::Converter,
    Ruby2JS::Filter::Polyfill,
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM
  ]
).to_s

# Extract the filter name from file
filter_name = File.basename(filter_file, '.rb').split('_').map(&:capitalize).join

# Add ES module wrapper for selfhost use
preamble = <<~JS
// Transpiled Ruby2JS Filter: #{filter_name}
// Generated from #{filter_file}
//
// This is an ES module that exports the filter for use with the selfhost test harness.

// Setup: SEXP placeholder (Ruby's include SEXP provides s/S/ast_node helpers)
const SEXP = {};

// Setup: make include() a no-op (Ruby's include SEXP doesn't apply in JS)
const include = () => {};

// Setup: Filter global for exclude/include calls
const Filter = {
  exclude: (...methods) => {},
  include: (...methods) => {}
};

// Setup: DEFAULTS array for filter registration
const DEFAULTS = [];

// Setup: Ruby2JS namespace for ast_node helper
const Ruby2JS = {
  ast_node: (obj) => typeof obj === 'object' && obj !== null && 'type' in obj && 'children' in obj
};

JS

# Fix issues in transpiled output:
# 1. Remove the const Ruby2JS = { assignment wrapper
# 2. Remove the trailing return {Functions} and IIFE wrapper

# Replace the problematic module wrapper pattern
js = js.gsub(/^const Ruby2JS = \{Filter: \(\(\) => \{\n/, '')
js = js.gsub(/\n  DEFAULTS\.push\(Functions\);\n  return \{Functions\}\n\}\)\(\)\}$/, '')

# Fix incomplete expressions from 'super' calls that become empty
# In Ruby filters, super calls the next filter or returns the node unchanged
# Replace empty ternary else branches with 'node'
js = js.gsub(/: (\s*}\s*(?:else|$))/, ': node\1')
js = js.gsub(/: (\s*;)/, ': node\1')
# Replace empty assignments with processChildren(node) or node
js = js.gsub(/= ;/, '= this.processChildren ? this.processChildren(node) : node;')
# Replace empty return statements
js = js.gsub(/return (\s*}\s*(?:else|$))/, 'return node\1')
js = js.gsub(/return (\s*;)/, 'return node\1')

# The filter is now exposed as Functions variable (it's defined inside)

postamble = <<~JS

// Register the filter
DEFAULTS.push(Functions);

// Export the filter for ES module usage
export { Functions as default, Functions };
JS

puts preamble + js + postamble
