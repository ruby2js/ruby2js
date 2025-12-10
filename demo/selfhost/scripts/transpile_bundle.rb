#!/usr/bin/env ruby
# Transpile bundle.rb - creates a standalone ruby2js.mjs with all sources inlined
#
# The bundle.rb uses require_relative to pull in all necessary sources:
# - runtime (source buffer, source range, comments)
# - namespace (class/module scope tracking)
# - node (AST node representation)
# - prism_walker (Prism AST to Parser-compatible format)
# - serializer (output formatting)
# - converter (main conversion + all handlers)
#
# The Require filter processes these require_relative calls and inlines the code.

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

bundle_file = File.expand_path('../../../lib/ruby2js/selfhost/bundle.rb', __dir__)
source = File.read(bundle_file)

js = Ruby2JS.convert(source,
  eslevel: 2022,
  comparison: :identity,
  underscored_private: true,
  nullish_to_s: true,
  include: [:call],
  require_recursive: true,
  file: bundle_file,
  filters: [
    Ruby2JS::Filter::Pragma,
    Ruby2JS::Filter::Require,
    Ruby2JS::Filter::Combiner,
    Ruby2JS::Filter::Selfhost::Core,
    Ruby2JS::Filter::Selfhost::Walker,
    Ruby2JS::Filter::Selfhost::Converter,
    Ruby2JS::Filter::Polyfill,
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM
  ]
).to_s

# Add preamble for ES module compatibility
preamble = <<~JS
// Ruby2JS Self-hosted Bundle
// Generated from lib/ruby2js/selfhost/bundle.rb
//
// This is a standalone JavaScript module that can:
// - Run as CLI: node ruby2js.mjs [options] [file]
// - Be imported: import { convert } from './ruby2js.mjs'
//
// External dependencies: @ruby/prism only

// Preamble: Ruby built-ins needed by the transpiled code
class NotImplementedError extends Error {
  constructor(message) {
    super(message);
    this.name = 'NotImplementedError';
  }
}

JS

puts preamble + js
