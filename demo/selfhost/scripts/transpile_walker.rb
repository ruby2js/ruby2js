#!/usr/bin/env ruby
# Transpile the PrismWalker to JavaScript

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

require 'ruby2js'
require 'ruby2js/filter/combiner'
require 'ruby2js/filter/pragma'
require 'ruby2js/filter/require'
require 'ruby2js/filter/selfhost'
require 'ruby2js/filter/polyfill'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'

walker_file = File.expand_path('../../../lib/ruby2js/prism_walker.rb', __dir__)
source = File.read(walker_file)

js = Ruby2JS.convert(source,
  eslevel: 2022,
  comparison: :identity,
  underscored_private: true,
  file: walker_file,
  filters: [
    Ruby2JS::Filter::Pragma,
    Ruby2JS::Filter::Require,
    Ruby2JS::Filter::Combiner,
    Ruby2JS::Filter::Selfhost::Core,
    Ruby2JS::Filter::Selfhost::Walker,
    Ruby2JS::Filter::Polyfill,
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM
  ]
).to_s

# Add export prefix for ES module
# Replace the const/let assignment statement with export version
# Handle leading semicolons, comments, and whitespace
js = js.sub(/\A;\s*/, '') # Remove leading semicolon
js = js.sub(/^(const|let)\s+Ruby2JS\s*=/, 'export const Ruby2JS =')
puts js
