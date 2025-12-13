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

// Setup: SEXP placeholder (Ruby's include SEXP provides s/S/ast_node helpers)
const SEXP = {};

// Setup: make include() a no-op (Ruby's include SEXP doesn't apply in JS)
const include = () => {};

// Setup: Filter global for exclude/include calls
const Filter = {
  exclude: (...methods) => {},
  include: (...methods) => {}
};

// Setup: DEFAULTS array for filter registration
const DEFAULTS = [];

// Polyfill: RegExp.escape (not in JS standard)
if (!RegExp.escape) {
  RegExp.escape = function(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  };
}

// Setup: Ruby2JS namespace for ast_node helper
const Ruby2JS = {
  ast_node: (obj) => typeof obj === 'object' && obj !== null && 'type' in obj && 'children' in obj
};

// Filter infrastructure functions (these get bound by FilterProcessor at runtime)
// Default implementations return false/do nothing
let excluded = () => false;
let included = () => false;
let process = (node) => node;
let _options = {};

// ES level helper functions - use getter pattern so Ruby's `es2020` (no parens) works in JS
// When Ruby2JS transpiles `es2020`, it becomes `es2020` not `es2020()`, so we use getters
let _eslevel = 0;
Object.defineProperty(globalThis, 'es2015', { get: () => _eslevel >= 2015, configurable: true });
Object.defineProperty(globalThis, 'es2016', { get: () => _eslevel >= 2016, configurable: true });
Object.defineProperty(globalThis, 'es2017', { get: () => _eslevel >= 2017, configurable: true });
Object.defineProperty(globalThis, 'es2018', { get: () => _eslevel >= 2018, configurable: true });
Object.defineProperty(globalThis, 'es2019', { get: () => _eslevel >= 2019, configurable: true });
Object.defineProperty(globalThis, 'es2020', { get: () => _eslevel >= 2020, configurable: true });
Object.defineProperty(globalThis, 'es2021', { get: () => _eslevel >= 2021, configurable: true });
Object.defineProperty(globalThis, 'es2022', { get: () => _eslevel >= 2022, configurable: true });

// Wrapper to provide 'this' context with _options for filter functions
const filterContext = {
  get _options() { return _options; }
};

// AST node structural comparison (Ruby's == compares structure, JS's === compares references)
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

// AST node creation helpers
function s(type, ...children) {
  // For send nodes, is_method should be true if there are args (children beyond target & method)
  // This ensures console.log("hi") outputs the args
  const hasArgs = type === "send" && children.length > 2;

  return {
    type,
    children,
    updated: function(newType, newChildren) {
      return s(newType ?? this.type, ...(newChildren ?? this.children));
    },
    is_method() {
      // For send nodes with args, treat as method call
      // For others, check _is_method flag
      return hasArgs || (this._is_method ?? false);
    },
    get first() { return this.children[0]; },
    get last() { return this.children[this.children.length - 1]; }
  };
}

function S(type, ...children) {
  // S updates the current node - same as s for our purposes
  return s(type, ...children);
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

# Fix spread of regopt node - need to spread .children, not the node itself
js = js.gsub(/\.\.\.before\.children\.last\)/, '...(before.children.last.children || []))')

# The filter is now exposed as Functions variable (it's defined inside)

postamble = <<~JS

// Register the filter
DEFAULTS.push(Functions);

// Setup function to bind filter infrastructure
Functions._setup = function(opts) {
  if (opts.excluded) excluded = opts.excluded;
  if (opts.included) included = opts.included;
  if (opts.process) process = opts.process;
  if (opts._options) {
    _options = opts._options;
    _eslevel = opts._options.eslevel || 0;
  }
};

// Export the filter for ES module usage
export { Functions as default, Functions };
JS

puts preamble + js + postamble
