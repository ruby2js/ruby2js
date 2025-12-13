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
// It imports shared infrastructure from the bundle to minimize duplication.

// Import from the transpiled bundle - this provides:
// - Ruby2JS.ast_node (AST node check)
// - Ruby2JS.Filter.SEXP (s, S, ast_node helpers)
// - Ruby2JS.Filter.Processor (AST walker with process/process_children/process_all)
// - Array polyfills (none, all, any, compact, etc.)
import { Ruby2JS } from '../ruby2js.mjs';

// Alias Parser.AST.Node to Ruby2JS.Node so transpiled code works
// (Ruby source uses Parser gem's AST nodes, JS uses Ruby2JS.Node)
const Parser = { AST: { Node: Ruby2JS.Node } };

// Get SEXP helpers from transpiled bundle
const SEXP = Ruby2JS.Filter.SEXP;
const s = SEXP.s.bind(SEXP);
const S = s;

// Setup: make include() a no-op (Ruby's include SEXP doesn't apply in JS)
const include = () => {};

// Setup: Filter global for exclude/include calls (no-op, handled by test harness)
const Filter = {
  exclude: (...methods) => {},
  include: (...methods) => {}
};

// Setup: DEFAULTS array for filter registration
const DEFAULTS = [];

// Filter infrastructure functions (bound by FilterProcessor at runtime)
// Default implementations return false/do nothing until bound
let excluded = () => false;
let included = () => false;
let process = (node) => node;
let process_all = (nodes) => nodes ? nodes.map(node => process(node)) : [];
let _options = {};

// ES level helper functions - use getter pattern so Ruby's `es2020` (no parens) works in JS
// These must be globals because filters use them without `this.` prefix
let _eslevel = 0;
Object.defineProperty(globalThis, 'es2015', { get: () => _eslevel >= 2015, configurable: true });
Object.defineProperty(globalThis, 'es2016', { get: () => _eslevel >= 2016, configurable: true });
Object.defineProperty(globalThis, 'es2017', { get: () => _eslevel >= 2017, configurable: true });
Object.defineProperty(globalThis, 'es2018', { get: () => _eslevel >= 2018, configurable: true });
Object.defineProperty(globalThis, 'es2019', { get: () => _eslevel >= 2019, configurable: true });
Object.defineProperty(globalThis, 'es2020', { get: () => _eslevel >= 2020, configurable: true });
Object.defineProperty(globalThis, 'es2021', { get: () => _eslevel >= 2021, configurable: true });
Object.defineProperty(globalThis, 'es2022', { get: () => _eslevel >= 2022, configurable: true });
Object.defineProperty(globalThis, 'es2023', { get: () => _eslevel >= 2023, configurable: true });
Object.defineProperty(globalThis, 'es2024', { get: () => _eslevel >= 2024, configurable: true });
Object.defineProperty(globalThis, 'es2025', { get: () => _eslevel >= 2025, configurable: true });

// Wrapper to provide 'this' context with _options for filter functions
const filterContext = {
  get _options() { return _options; }
};

// AST node structural comparison (Ruby's == compares structure, JS's === compares references)
// This is unique to filter testing - not in the Ruby sources
function nodesEqual(a, b) {
  if (a === b) return true;
  if (!a || !b) return false;
  if (typeof a !== 'object' || typeof b !== 'object') return a === b;
  if (a.type !== b.type) return false;
  if (!a.children || !b.children) return false;
  if (a.children.length !== b.children.length) return false;
  for (let i = 0; i < a.children.length; i++) {
    if (!nodesEqual(a.children[i], b.children[i])) return false;
  }
  return true;
}

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

# Replace this._options with _options (module-level variable)
js = js.gsub(/this\._options/, '_options')

# Replace AST node comparisons with nodesEqual (Ruby == compares structure, JS === compares refs)
# Pattern: target === s(...)  becomes  nodesEqual(target, s(...))
js = js.gsub(/(\w+) === (s\([^)]+\))/, 'nodesEqual(\1, \2)')

# Fix the compact polyfill to use non-mutating filter (needed for frozen arrays from PrismWalker)
js = js.gsub(
  /Object\.defineProperty\(Array\.prototype, "compact", \{\n  get\(\) \{\n    let i = this\.length - 1;\n\n    while \(i >= 0\) \{\n      if \(this\[i\] === null \|\| this\[i\] === undefined\) this\.splice\(i, 1\);\n      i--\n    \};\n\n    return this\n  \},\n\n  configurable: true\n\}\);/,
  'Object.defineProperty(Array.prototype, "compact", { get() { return this.filter(x => x !== null && x !== undefined); }, configurable: true });'
)

# Fix Hash.keys pattern: VAR_TO_ASSIGN.keys.includes() -> Object.keys(VAR_TO_ASSIGN).includes()
js = js.gsub(/(\w+)\.keys\.includes\(/, 'Object.keys(\1).includes(')

# Fix Ruby Regexp class usage to JavaScript RegExp
js = js.gsub(/\bRegexp\./, 'RegExp.')

# Fix Ruby Object constant becoming JS Object constructor
# s("const", null, Object) should be s("const", null, "Object")
js = js.gsub(/s\("const", null, Object\)/, 's("const", null, "Object")')

# Fix spread of regopt node - need to spread .children, not the node itself
# Pattern: ...before.children.last) or ...arg.children.last) where the node is a regopt
js = js.gsub(/\.\.\.(before|arg)\.children\.last\)/, '...(\1.children.last.children || []))')

# Add each_with_index handling in on_block (it's only in on_send, but blocks need it too)
# Insert before the final "return node" in on_block
js = js.gsub(
  /(\} else \{\n        return node\n      \}\n    \};\n\n    \/\/ compact with a block)/,
  '} else if (method === "each_with_index") {' + "\n" +
  '        call = call.updated(null, [call.children.first, "forEach"]);' + "\n" +
  '        return node.updated(null, [process(call), ...node.children.slice(1)])' + "\n" +
  '      \\1'
)

# The filter is now exposed as Functions variable (it's defined inside)

postamble = <<~JS

// Register the filter
DEFAULTS.push(#{filter_name});

// Register in Ruby2JS.Filter namespace for specs
Ruby2JS.Filter.#{filter_name} = #{filter_name};

// Setup function to bind filter infrastructure
#{filter_name}._setup = function(opts) {
  if (opts.excluded) excluded = opts.excluded;
  if (opts.included) included = opts.included;
  if (opts.process) process = opts.process;
  if (opts._options) {
    _options = opts._options;
    _eslevel = opts._options.eslevel || 0;
  }
};

// Export the filter for ES module usage
export { #{filter_name} as default, #{filter_name} };
JS

puts preamble + js + postamble
