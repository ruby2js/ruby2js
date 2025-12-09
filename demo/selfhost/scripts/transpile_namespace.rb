#!/usr/bin/env ruby
# Transpiles lib/ruby2js/namespace.rb to shared/namespace.mjs
#
# This generates the Namespace class from Ruby source, ensuring
# the Ruby and JavaScript implementations stay in sync.

require_relative '../../../lib/ruby2js'
require_relative '../../../lib/ruby2js/filter/functions'
require_relative '../../../lib/ruby2js/filter/return'
require_relative '../../../lib/ruby2js/filter/esm'
require_relative '../../../lib/ruby2js/filter/pragma'

source_file = File.expand_path('../../../lib/ruby2js/namespace.rb', __dir__)
source = File.read(source_file)

# Extract just the class body (without the module wrapper) and add export
# Remove `require 'json'` and the module wrapper, keep only the class
source = source.sub(/^require 'json'\n\n/, '')
source = source.sub(/^module Ruby2JS\s*\n\s*/, '')  # Remove "module Ruby2JS"
source = source.sub(/^end\s*$/, '')                  # Remove final "end"
source = source.sub(/^(\s*class )/, 'export \1')    # Add export before class

js = Ruby2JS.convert(source,
  eslevel: 2022,
  filters: [
    Ruby2JS::Filter::Pragma,
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM,
  ]
).to_s

puts js
