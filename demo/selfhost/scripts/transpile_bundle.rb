#!/usr/bin/env ruby
# Transpile bundle.rb - the entry point that re-exports all modules

$LOAD_PATH.unshift File.expand_path('../../../../lib', __FILE__)

require 'ruby2js'
require 'ruby2js/filter/esm'

bundle_file = File.expand_path('../../../../lib/ruby2js/selfhost/bundle.rb', __FILE__)
source = File.read(bundle_file)

js = Ruby2JS.convert(source,
  eslevel: 2022,
  file: bundle_file,
  filters: [Ruby2JS::Filter::ESM]
).to_s

puts js
