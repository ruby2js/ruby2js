#!/usr/bin/env ruby
# Transpile ErbCompiler from Ruby to JavaScript for selfhost use

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

require 'ruby2js'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'

erb_compiler_file = File.expand_path('../../rails-in-js/lib/erb_compiler.rb', __dir__)
source = File.read(erb_compiler_file)

js = Ruby2JS.convert(source,
  eslevel: 2022,
  filters: [
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM
  ]
).to_s

# Add export statement
js = js.sub(/^class ErbCompiler/, 'export class ErbCompiler')

puts js
