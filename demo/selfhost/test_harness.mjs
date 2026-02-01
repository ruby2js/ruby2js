// Minimal test harness for selfhosted specs
// Provides describe/it/must_equal compatible with transpiled Minitest specs

// Polyfill for Ruby's Array#uniq - returns new array with unique elements
if (!Array.prototype.uniq) {
  Object.defineProperty(Array.prototype, "uniq", {
    get() { return [...new Set(this)] },
    configurable: true
  });
}

// Polyfill for Ruby's Array#dup - returns shallow copy
if (!Array.prototype.dup) {
  Object.defineProperty(Array.prototype, "dup", {
    value() { return [...this] },
    configurable: true
  });
}

// Polyfill for Ruby's Array#delete_at - removes element at index, returns it
if (!Array.prototype.delete_at) {
  Object.defineProperty(Array.prototype, "delete_at", {
    value(index) {
      if (index < 0 || index >= this.length) return null;
      return this.splice(index, 1)[0];
    },
    configurable: true
  });
}

// Polyfill for Ruby's Array#insert - inserts element(s) at index
if (!Array.prototype.insert) {
  Object.defineProperty(Array.prototype, "insert", {
    value(index, ...items) {
      this.splice(index, 0, ...items);
      return this;
    },
    configurable: true
  });
}

// Polyfill for Ruby's Array#partition - splits into two arrays based on predicate
if (!Array.prototype.partition) {
  Object.defineProperty(Array.prototype, "partition", {
    value(fn) {
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
    },
    configurable: true
  });
}

// Polyfill for Ruby's Pathname - path manipulation class
import nodePath from 'node:path';
globalThis.Pathname = class Pathname {
  constructor(path) { this._path = path || '.'; }
  join(other) { return new Pathname(nodePath.join(this._path, other)); }
  get parent() { return new Pathname(nodePath.dirname(this._path)); }
  toString() { return this._path; }
};

// Polyfill for Ruby's Struct - creates a factory function for named attributes
globalThis.Struct = function Struct(...args) {
  // Handle keyword_init option
  let options = {};
  if (typeof args[args.length - 1] === 'object' && args[args.length - 1] !== null) {
    const lastArg = args[args.length - 1];
    if (lastArg.keywordInit !== undefined) {
      options = lastArg;
      args = args.slice(0, -1);
    }
  }

  const fields = args;

  // Return a factory function that creates objects with the given fields
  // Can be called with or without 'new' (both work)
  const factory = function(values = {}) {
    const obj = {};
    if (options.keywordInit || typeof values === 'object') {
      for (const field of fields) {
        obj[field] = values[field];
      }
    }
    return obj;
  };

  return factory;
};

// Import from the unified bundle (same code used by CLI and browser)
import {
  Ruby2JS,
  Prism,
  PrismSourceBuffer,
  PrismSourceRange,
  PrismComment,
  Hash,
  setupGlobals,
  associateComments,
  initPrism as sharedInitPrism,
  getPrismParse,
  convert as bundleConvert,
  parse as bundleParse
} from './ruby2js.js';

// Import Node.js module system for require shim
import { createRequire } from 'module';
const nodeRequire = createRequire(import.meta.url);

// Set up globals
setupGlobals(Ruby2JS);
globalThis.Namespace = Ruby2JS.Namespace;
globalThis.Ruby2JS = Ruby2JS;

// Provide a require shim for transpiled specs that use inline require
// (e.g., require 'ruby2js/filter/return' inside a function)
// Filters should already be loaded by run_all_specs.mjs, so this is a no-op

globalThis.require = function(path) {
  // Handle Node.js built-in modules (used by ESM filter for file analysis)
  if (path === 'fs' || path === 'path' || path === 'url') {
    return nodeRequire(path);
  }

  // Extract filter name from path like "ruby2js/filter/return"
  const match = path.match(/ruby2js\/filter\/(\w+)/);
  if (match) {
    const requestedName = match[1].toLowerCase();
    // Case-insensitive lookup: ESM filter registers as "ESM" not "Esm"
    const filterNames = Object.keys(Ruby2JS.Filter);
    const actualName = filterNames.find(n => n.toLowerCase() === requestedName);
    if (!actualName) {
      throw new Error(`Filter ${match[1]} not loaded. Load it via run_all_specs.mjs or import manually.`);
    }
    // Filter already loaded, nothing to do
    return;
  }
  throw new Error(`require not supported for: ${path}`);
};

// Alias Parser.AST.Node to Ruby2JS.Node so transpiled SEXP.s works
// (Ruby source uses Parser gem's AST nodes, JS uses Ruby2JS.Node)
globalThis.Parser = { AST: { Node: Ruby2JS.Node } };

// ============================================================================
// Filter Infrastructure
// ============================================================================

// Create Filter namespace (transpiled filters will attach here)
Ruby2JS.Filter = Ruby2JS.Filter || {};

// Global include/exclude tracking for filters
Ruby2JS.Filter._included = new Set();
Ruby2JS.Filter._excluded = new Set();
Ruby2JS.Filter.DEFAULTS = Ruby2JS.Filter.DEFAULTS || [];

Ruby2JS.Filter.include = function(...methods) {
  methods.forEach(m => Ruby2JS.Filter._included.add(m));
};

Ruby2JS.Filter.exclude = function(...methods) {
  methods.forEach(m => Ruby2JS.Filter._excluded.add(m));
};

Ruby2JS.Filter.included_methods = function() {
  return Ruby2JS.Filter._included;
};

Ruby2JS.Filter.excluded_methods = function() {
  return Ruby2JS.Filter._excluded;
};

// Ruby polyfills are now auto-generated by the polyfill filter in the bundle.
// Only Object#to_a is defined here since it's not used by the main code
// but may be needed by transpiled specs.
// Array#to_a returns self in Ruby
if (!Array.prototype.to_a) {
  Object.defineProperty(Array.prototype, 'to_a', {
    get: function() {
      return this;
    },
    configurable: true
  });
}
// Object#to_a converts to entries array
if (!Object.prototype.to_a) {
  Object.defineProperty(Object.prototype, 'to_a', {
    get: function() {
      return Object.entries(this);
    },
    configurable: true
  });
}

// Export SEXP globally for transpiled filters
// (Bundle's SEXP.s already creates Node instances with updated() method)
const SEXP = Ruby2JS.Filter.SEXP;
Ruby2JS.SEXP = SEXP;
globalThis.SEXP = SEXP;

// AST node type checker - used by transpiled filters (e.g., Ruby2JS.ast_node(node))
Ruby2JS.ast_node = Ruby2JS.ast_node || function(obj) {
  return typeof obj === 'object' && obj !== null && 'type' in obj && 'children' in obj;
};
// camelCase alias for transformers (transpiled with CamelCase filter)
Ruby2JS.astNode = Ruby2JS.ast_node;

// Re-export initPrism from bundle (already initialized at module load)
export async function initPrism() {
  return await sharedInitPrism();
}

// Convert function - delegates to bundle's convert which uses Pipeline
// Pipeline now correctly handles class-based filters via Object.assign
Ruby2JS.convert = function(source, opts = {}) {
  // Default eslevel to 2020 (same as Ruby2JS default)
  if (opts.eslevel === undefined) {
    opts.eslevel = 2020;
  }

  try {
    const result = bundleConvert(source, opts);
    // Result is now a Serializer object with toString() and sourcemap() methods
    return result;
  } catch (e) {
    return { toString: () => `[ERROR: ${e.message}]`, error: e };
  }
};

// Expose convert, parse, and ast_node as globals for transpiled specs
// (The selfhost filter transforms Ruby2JS.convert() to convert() etc.)
globalThis.convert = Ruby2JS.convert;
globalThis.parse = bundleParse;
globalThis.ast_node = Ruby2JS.ast_node;
globalThis.astNode = Ruby2JS.ast_node;

let currentDescribe = [];
let testCount = 0;
let passCount = 0;
let failCount = 0;
let skipCount = 0;
let failures = [];

// Store before hooks per describe level
let beforeHooks = [];

// Reset test state between spec runs
export function resetTests() {
  currentDescribe = [];
  testCount = 0;
  passCount = 0;
  failCount = 0;
  skipCount = 0;
  failures = [];
  beforeHooks = [];
}

// Get current test results without logging
export function getTestResults() {
  return {
    total: testCount,
    passed: passCount,
    failed: failCount,
    skipped: skipCount,
    failures: failures.slice() // return a copy
  };
}

export function describe(name, fn) {
  // Handle different name types: functions use .name, objects need special handling
  let displayName;
  if (typeof name === 'function') {
    displayName = name.name || 'Anonymous';
  } else if (typeof name === 'object' && name !== null) {
    // Check for well-known module objects (like Ruby2JS which has convert method)
    if (name === globalThis.Ruby2JS) {
      displayName = 'Ruby2JS';
    } else {
      displayName = name.constructor?.name !== 'Object' ? name.constructor.name : 'Object';
    }
  } else {
    displayName = String(name);
  }
  currentDescribe.push(displayName);
  const prevBeforeHooksLength = beforeHooks.length;
  fn();
  // Remove any before hooks added at this level
  beforeHooks.length = prevBeforeHooksLength;
  currentDescribe.pop();
}

export function it(name, fn) {
  testCount++;
  const fullName = [...currentDescribe, name].join(' > ');
  try {
    // Run all before hooks first
    for (const hook of beforeHooks) {
      hook();
    }
    fn();
    passCount++;
  } catch (e) {
    if (e.message === 'SKIP') {
      skipCount++;
      // Note: passCount was never incremented (fn() threw before the passCount++ line)
    } else {
      failCount++;
      failures.push({ name: fullName, error: e });
    }
  }
}

export function skip(reason) {
  throw new Error('SKIP');
}

// Minitest assert-style assertions
export function assert_equal(expected, actual) {
  const exp = typeof expected === 'object' ? JSON.stringify(expected) : expected;
  const act = typeof actual === 'object' ? JSON.stringify(actual) : actual;
  if (exp !== act) {
    throw new Error(`Expected:\n  "${expected}"\nbut got:\n  "${actual}"`);
  }
}

export function assert_includes(collection, item) {
  if (typeof collection === 'string') {
    if (!collection.includes(item)) {
      throw new Error(`Expected "${collection}" to include "${item}"`);
    }
  } else if (Array.isArray(collection)) {
    if (!collection.includes(item)) {
      throw new Error(`Expected array to include ${JSON.stringify(item)}`);
    }
  } else {
    throw new Error(`assert_includes expects string or array, got ${typeof collection}`);
  }
}

export function refute_includes(collection, item) {
  if (typeof collection === 'string') {
    if (collection.includes(item)) {
      throw new Error(`Expected "${collection}" NOT to include "${item}"`);
    }
  } else if (Array.isArray(collection)) {
    if (collection.includes(item)) {
      throw new Error(`Expected array NOT to include ${JSON.stringify(item)}`);
    }
  } else {
    throw new Error(`refute_includes expects string or array, got ${typeof collection}`);
  }
}

export function assert_raises(fnOrClass, maybeFn) {
  // Ruby's assert_raises can be called two ways:
  // 1. assert_raises { block } - returns the exception
  // 2. assert_raises(ErrorClass) { block } - checks error type, returns exception
  let fn, errorClass;
  if (typeof fnOrClass === 'function' && maybeFn === undefined) {
    fn = fnOrClass;
    errorClass = null;
  } else {
    errorClass = fnOrClass;
    fn = maybeFn;
  }

  try {
    fn();
    throw new Error(`Expected an exception to be raised, but nothing was raised`);
  } catch (e) {
    // Check if it's our "nothing raised" error
    if (e.message.startsWith('Expected') && e.message.includes('to be raised')) {
      throw e;
    }
    // If no error class specified, just return the exception
    if (!errorClass) {
      return e;
    }
    // Check if it's the expected error type
    if (errorClass === SyntaxError && e instanceof SyntaxError) return e;
    if (errorClass === RangeError && e instanceof RangeError) return e;
    if (errorClass === TypeError && e instanceof TypeError) return e;
    if (errorClass === Error && e instanceof Error) return e;
    // Also handle string class names
    if (typeof errorClass === 'string' && e.name === errorClass) return e;
    if (typeof errorClass === 'string' && e.constructor.name === errorClass) return e;
    // If error type doesn't match, re-throw with details
    throw new Error(`Expected ${errorClass.name || errorClass} but got ${e.constructor.name}: ${e.message}`);
  }
}

globalThis.assert_equal = assert_equal;
globalThis.assert_includes = assert_includes;
globalThis.refute_includes = refute_includes;
globalThis.assert_raises = assert_raises;

// Error.prototype.set_backtrace - Ruby method, no-op in JS
if (!Error.prototype.set_backtrace) {
  Error.prototype.set_backtrace = function(backtrace) {
    // Store it but don't modify the actual stack trace
    this.rubyBacktrace = backtrace;
  };
}

// before hooks - store to run before each test
export function before(fn) {
  beforeHooks.push(fn);
}

// Extend String prototype with must_equal for chaining
String.prototype.must_equal = function(expected) {
  if (this.valueOf() !== expected) {
    throw new Error(`Expected:\n  "${expected}"\nbut got:\n  "${this.valueOf()}"`);
  }
  return this;
};

// Also support must_include, must_match
String.prototype.must_include = function(substring) {
  if (!this.includes(substring)) {
    throw new Error(`Expected "${this.valueOf()}" to include "${substring}"`);
  }
  return this;
};

String.prototype.must_match = function(pattern) {
  if (!pattern.test(this.valueOf())) {
    throw new Error(`Expected "${this.valueOf()}" to match ${pattern}`);
  }
  return this;
};

// Negative assertions for String
String.prototype.wont_include = function(substring) {
  if (this.includes(substring)) {
    throw new Error(`Expected "${this.valueOf()}" NOT to include "${substring}"`);
  }
  return this;
};

String.prototype.wont_match = function(pattern) {
  if (pattern.test(this.valueOf())) {
    throw new Error(`Expected "${this.valueOf()}" NOT to match ${pattern}`);
  }
  return this;
};

// Boolean assertions
Boolean.prototype.must_equal = function(expected) {
  if (this.valueOf() !== expected) {
    throw new Error(`Expected ${expected} but got ${this.valueOf()}`);
  }
  return this;
};

// Array assertions
Array.prototype.must_equal = function(expected) {
  const actual = JSON.stringify(this);
  const exp = JSON.stringify(expected);
  if (actual !== exp) {
    throw new Error(`Expected ${exp} but got ${actual}`);
  }
  return this;
};

Array.prototype.must_include = function(item) {
  if (!this.includes(item)) {
    throw new Error(`Expected array to include ${item}`);
  }
  return this;
};

// Array must_be_empty / wont_be_empty
Object.defineProperty(Array.prototype, 'must_be_empty', {
  get: function() {
    if (this.length !== 0) {
      throw new Error(`Expected array to be empty but had ${this.length} items`);
    }
    return this;
  },
  configurable: true
});

Object.defineProperty(Array.prototype, 'wont_be_empty', {
  get: function() {
    if (this.length === 0) {
      throw new Error(`Expected array not to be empty`);
    }
    return this;
  },
  configurable: true
});

// Array wont_include - check array doesn't contain item
Array.prototype.wont_include = function(item) {
  if (this.includes(item)) {
    throw new Error(`Expected array not to include ${item}`);
  }
  return this;
};

// Number/value must_be - comparison assertions like x.must_be(:>, 5)
// In Ruby: x.must_be :>, 5 checks x > 5
Number.prototype.must_be = function(operator, value) {
  const num = this.valueOf();
  let pass = false;
  switch (operator) {
    case '>': pass = num > value; break;
    case '<': pass = num < value; break;
    case '>=': pass = num >= value; break;
    case '<=': pass = num <= value; break;
    case '==': pass = num == value; break;
    case '===': pass = num === value; break;
    default: throw new Error(`Unknown operator: ${operator}`);
  }
  if (!pass) {
    throw new Error(`Expected ${num} ${operator} ${value}`);
  }
  return this;
};

// Object/value wont_be_nil
Object.defineProperty(Object.prototype, 'wont_be_nil', {
  get: function() {
    if (this === null || this === undefined) {
      throw new Error(`Expected value not to be nil/null/undefined`);
    }
    return this;
  },
  configurable: true
});

// Object must_include for strings in objects
Object.defineProperty(Object.prototype, 'must_include', {
  value: function(item) {
    if (typeof this === 'string' || this instanceof String) {
      if (!this.includes(item)) {
        throw new Error(`Expected "${this.valueOf()}" to include "${item}"`);
      }
    } else if (Array.isArray(this)) {
      if (!this.includes(item)) {
        throw new Error(`Expected array to include ${item}`);
      }
    } else {
      throw new Error(`must_include not supported on ${typeof this}`);
    }
    return this;
  },
  configurable: true,
  writable: true
});

// Number assertions
Number.prototype.must_equal = function(expected) {
  if (this.valueOf() !== expected) {
    throw new Error(`Expected ${expected} but got ${this.valueOf()}`);
  }
  return this;
};

// Ruby's send method - call methods dynamically by name
if (!Object.prototype.send) {
  Object.defineProperty(Object.prototype, 'send', {
    value: function(methodName, ...args) {
      const method = this[methodName];
      if (typeof method === 'function') {
        return method.apply(this, args);
      }
      throw new Error(`undefined method '${methodName}' for ${this.constructor.name}`);
    },
    writable: true,
    configurable: true
  });
}

export function runTests() {
  console.log(`\nTests: ${testCount}, Passed: ${passCount}, Failed: ${failCount}, Skipped: ${skipCount}`);
  if (failures.length > 0) {
    console.log('\nFailures:');
    failures.slice(0, 20).forEach(f => {
      console.log(`\n  ${f.name}`);
      console.log(`    ${f.error.message.split('\n').join('\n    ')}`);
    });
    if (failures.length > 20) {
      console.log(`\n  ... and ${failures.length - 20} more failures`);
    }
  }
  return failCount === 0;
}

// Export globals for non-module usage
globalThis.describe = describe;
globalThis.it = it;
globalThis.skip = skip;
globalThis.before = before;
globalThis.runTests = runTests;
globalThis.resetTests = resetTests;
globalThis.getTestResults = getTestResults;
globalThis.initPrism = initPrism;
