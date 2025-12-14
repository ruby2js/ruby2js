#!/usr/bin/env ruby
# Transpile bundle.rb - creates ruby2js.js library with all sources inlined
#
# The bundle.rb uses require_relative to pull in all necessary sources:
# - runtime (source buffer, source range, comments)
# - namespace (class/module scope tracking)
# - node (AST node representation)
# - prism_walker (Prism AST to Parser-compatible format)
# - serializer (output formatting)
# - converter (main conversion + all handlers)
# - filter/processor (filter infrastructure)
# - pipeline (orchestration)
#
# The Require filter processes these require_relative calls and inlines the code.
#
# Output: ruby2js.js (library only, no CLI)

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
// Ruby2JS Self-hosted Library
// Generated from lib/ruby2js/selfhost/bundle.rb
//
// This is the core Ruby2JS library. Import it to convert Ruby to JavaScript:
//   import { convert, Ruby2JS } from './ruby2js.js'
//
// For CLI usage, see ruby2js-cli.js
//
// External dependencies: @ruby/prism only

// Suppress the "WASI is an experimental feature" warning from @ruby/prism
// This MUST run before any imports that load @ruby/prism (which uses WASI internally).
if (typeof process !== 'undefined' && process.emit) {
  const originalEmit = process.emit.bind(process);
  process.emit = function(event, ...args) {
    if (event === 'warning' && args[0]?.name === 'ExperimentalWarning' &&
        args[0]?.message?.includes('WASI')) {
      return false;
    }
    return originalEmit(event, ...args);
  };
}

// Preamble: Ruby built-ins needed by the transpiled code
class NotImplementedError extends Error {
  constructor(message) {
    super(message);
    this.name = 'NotImplementedError';
  }
}

// Parser stub - the Ruby source uses defined?(Parser::AST::Node) checks
// which transpile to typeof Parser.AST.Node !== 'undefined'.
// We define Parser with AST.Node = undefined so the check safely returns false.
const Parser = { AST: { Node: undefined } };

JS

puts preamble + js
