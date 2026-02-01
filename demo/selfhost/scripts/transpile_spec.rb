#!/usr/bin/env ruby
# Transpile a Ruby spec file to JavaScript

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

require 'ruby2js'
require 'ruby2js/filter/combiner'
require 'ruby2js/filter/pragma'
require 'ruby2js/filter/selfhost'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/node'

spec_file = ARGV[0] || raise("Usage: transpile_spec.rb <spec_file>")
source = File.read(spec_file)

# Add skip pragmas to all requires (they're external dependencies)
source = source.gsub(/^(require\s+['"][^'"]*['"])/) do
  "#{$1} # Pragma: skip"
end

js = Ruby2JS.convert(source,
  eslevel: 2022,
  comparison: :identity,
  underscored_private: true,
  file: spec_file,
  filters: [
    Ruby2JS::Filter::Pragma,
    Ruby2JS::Filter::Node,
    Ruby2JS::Filter::Combiner,
    Ruby2JS::Filter::Selfhost::Core,
    Ruby2JS::Filter::Selfhost::Walker,
    Ruby2JS::Filter::Selfhost::Spec,
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM
  ]
).to_s

puts js
