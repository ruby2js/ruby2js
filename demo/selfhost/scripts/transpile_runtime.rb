#!/usr/bin/env ruby
# Transpile runtime.rb to JavaScript

$LOAD_PATH.unshift File.expand_path('../../../../lib', __FILE__)

require 'ruby2js'
require 'ruby2js/filter/selfhost'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'

runtime_file = File.expand_path('../../../../lib/ruby2js/selfhost/runtime.rb', __FILE__)
source = File.read(runtime_file)

js = Ruby2JS.convert(source,
  eslevel: 2022,
  comparison: :identity,
  underscored_private: true,
  file: runtime_file,
  filters: [
    Ruby2JS::Filter::Selfhost::Core,
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM
  ]
).to_s

puts js
