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

// Helper for filter composition: wrap methods to inject correct _parent for super calls
// Ruby's super is dynamic, but JS super is lexically bound. When methods are copied
// via Object.defineProperties, we need each method to have its own parent reference.
// This MUST be a regular function (not arrow) so `this` binds to the calling instance.
function wrapMethodsWithParent(proto, parentProto) {
  for (const key of Object.getOwnPropertyNames(proto)) {
    if (key === 'constructor') continue;
    const desc = Object.getOwnPropertyDescriptor(proto, key);
    if (typeof desc.value !== 'function') continue;

    const originalFn = desc.value;
    // Regular function preserves dynamic `this` binding
    desc.value = function(...args) {
      const oldParent = this._parent;
      this._parent = parentProto;
      try {
        return originalFn.apply(this, args);
      } finally {
        this._parent = oldParent;
      }
    };
    Object.defineProperty(proto, key, desc);
  }
}

// Parser stub - the Ruby source uses defined?(Parser::AST::Node) checks
// which transpile to typeof Parser.AST.Node !== 'undefined'.
// We define Parser with AST.Node = undefined so the check safely returns false.
// Note: This is reassigned and exported by filter_runtime section at end of file.
export let Parser = { AST: { Node: undefined } };

JS

# Append filter runtime (provides exports for transpiled filters)
filter_runtime_file = File.expand_path('../filter_runtime.js', __dir__)
filter_runtime = File.read(filter_runtime_file)

# Remove the import, change Parser to reassignment, remove duplicate Ruby2JS export
filter_runtime = filter_runtime
  .sub(/import \{ Ruby2JS \} from '\.\/ruby2js\.js';\n+/, '')
  .sub(/export const Parser =/, 'Parser =')
  .sub(/\n\/\/ Re-export Ruby2JS.*\nexport \{ Ruby2JS \};/, '')

puts preamble + js + "\n\n// Filter Runtime Infrastructure\n" + filter_runtime
