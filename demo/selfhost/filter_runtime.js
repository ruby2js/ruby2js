// Shared runtime infrastructure for transpiled Ruby2JS filters
//
// This module provides the runtime environment that filters need to operate.
// Each transpiled filter imports from here instead of having inline preamble.

import { Ruby2JS } from './ruby2js.js';

// Array.prototype.dup - Ruby's dup creates a shallow copy
if (!Array.prototype.dup) {
  Array.prototype.dup = function() {
    return this.slice();
  };
}

// Array.prototype.first - Ruby's first returns the first element
if (!Array.prototype.first) {
  Object.defineProperty(Array.prototype, 'first', {
    get() { return this[0]; },
    configurable: true
  });
}

// Array.prototype.last - Ruby's last returns the last element
if (!Array.prototype.last) {
  Object.defineProperty(Array.prototype, 'last', {
    get() { return this[this.length - 1]; },
    configurable: true
  });
}

// Array.prototype.uniqBy - Ruby's uniq { |x| ... } with block for key extraction
// Note: Simple .uniq is handled by the getter in the main bundle
if (!Array.prototype.uniqBy) {
  Array.prototype.uniqBy = function(fn) {
    const seen = new Map();
    const result = [];
    for (const item of this) {
      const key = fn(item);
      const keyStr = JSON.stringify(key);
      if (!seen.has(keyStr)) {
        seen.set(keyStr, true);
        result.push(item);
      }
    }
    return result;
  };
}

// Array.prototype.compact - Ruby's compact removes nil/null/undefined
if (!Array.prototype.compact) {
  Object.defineProperty(Array.prototype, 'compact', {
    get() { return this.filter(x => x != null); },
    configurable: true
  });
}

// Array.prototype.partition - Ruby's partition splits array by predicate
// Returns [truthy_items, falsy_items]
if (!Array.prototype.partition) {
  Array.prototype.partition = function(fn) {
    const truthy = [];
    const falsy = [];
    for (const item of this) {
      if (fn(item)) {
        truthy.push(item);
      } else {
        falsy.push(item);
      }
    }
    return [truthy, falsy];
  };
}

// RegExp.escape - escapes special regex characters in a string
// Always use Ruby-compatible escape (native ES2025 escapes more characters like \a \x61)
RegExp.escape = function(string) {
  return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
};

// Error.prototype.set_backtrace - Ruby method, no-op in JS
if (!Error.prototype.set_backtrace) {
  Error.prototype.set_backtrace = function(backtrace) {
    // In Ruby, this sets the backtrace; in JS we ignore it
    return backtrace;
  };
}

// String.prototype.capitalize - Ruby's capitalize (first char upper, rest lower)
if (!String.prototype.capitalize) {
  Object.defineProperty(String.prototype, 'capitalize', {
    get() {
      if (this.length === 0) return '';
      return this.charAt(0).toUpperCase() + this.slice(1).toLowerCase();
    },
    configurable: true
  });
}

// Alias Parser.AST.Node to Ruby2JS.Node so transpiled code works
// (Ruby source uses Parser gem's AST nodes, JS uses Ruby2JS.Node)
export const Parser = { AST: { Node: Ruby2JS.Node } };

// Get SEXP helpers from transpiled bundle
export const SEXP = Ruby2JS.Filter.SEXP;
export const s = SEXP.s.bind(SEXP);
export let S = s;  // S is reassigned by _setup to use @ast.updated() for location preservation

// AST node type checker (Ruby's ast_node? method)
// Checks if an object is an AST node (has type and children properties)
export const ast_node = (node) => {
  if (!node || typeof node !== 'object') return false;
  return 'type' in node && 'children' in node;
};

// Setup: make include() a no-op (Ruby's include SEXP doesn't apply in JS)
export const include = () => {};

// Setup: Add exclude/include no-ops to Ruby2JS.Filter for filter class definitions
// (these are used by filters to declare method exclusions, which are no-ops at JS runtime)
Ruby2JS.Filter.exclude = (...methods) => {};
Ruby2JS.Filter.include = (...methods) => {};

// Export the real Ruby2JS.Filter so imports get the live object with registered filters
export const Filter = Ruby2JS.Filter;

// Setup: DEFAULTS array for filter registration
export const DEFAULTS = [];

// Filter infrastructure functions (bound by Pipeline via _setup at runtime)
// Default implementations return false/do nothing until bound
// Note: 'process' renamed to 'processNode' to avoid conflict with Node.js global
export let excluded = () => false;
export let included = () => false;
export let processNode = (node) => node;
export let process_children = (node) => node;
export let process_all = (nodes) => nodes ? nodes.map(node => processNode(node)) : [];
export let _options = {};

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
export const filterContext = {
  get _options() { return _options; }
};

// AST node structural comparison (Ruby's == compares structure, JS's === compares references)
export function nodesEqual(a, b) {
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

// Setup function factory - creates a _setup function for a filter
export function createSetup(filterObj) {
  return function(opts) {
    if (opts.excluded) excluded = opts.excluded;
    if (opts.included) included = opts.included;
    if (opts.process) processNode = opts.process;
    if (opts.process_children) process_children = opts.process_children;
    if (opts.S) S = opts.S;
    if (opts._options) {
      _options = opts._options;
      _eslevel = opts._options.eslevel || 0;
    }
  };
}

// Register a filter in the Ruby2JS namespace
// Class-based filters have non-enumerable prototype methods, so we make them enumerable
// for compatibility with Object.assign in the pipeline
// Set addToDefaults=false for filters that shouldn't be auto-included (like Combiner)
export function registerFilter(name, filterObj, addToDefaults = true) {
  // Make all prototype methods enumerable so Object.assign can copy them
  for (const key of Object.getOwnPropertyNames(filterObj)) {
    if (key !== 'constructor') {
      const desc = Object.getOwnPropertyDescriptor(filterObj, key);
      if (desc && !desc.enumerable) {
        Object.defineProperty(filterObj, key, { ...desc, enumerable: true });
      }
    }
  }
  // Push to Ruby2JS.Filter.DEFAULTS unless explicitly disabled
  if (addToDefaults) {
    Ruby2JS.Filter.DEFAULTS.push(filterObj);
  }
  Ruby2JS.Filter[name] = filterObj;
  filterObj._setup = createSetup(filterObj);
}

// Re-export Ruby2JS for filters that need it
export { Ruby2JS };

// Export scanRegexpGroups (defined in bundle, used by Functions filter for regex group parsing)
export { scanRegexpGroups };

// Note: Ruby2JS.Inflector is now transpiled from lib/ruby2js/inflector.rb
// and included in the bundle via require_relative in bundle.rb
