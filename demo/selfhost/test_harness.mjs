// Minimal test harness for selfhosted specs
// Provides describe/it/must_equal compatible with transpiled Minitest specs

import * as Prism from '@ruby/prism';

// Set up Prism global before importing walker (which extends Prism.Visitor)
globalThis.Prism = Prism;

// PrismSourceBuffer - provides source buffer for location tracking
class PrismSourceBuffer {
  constructor(source, file) {
    this.source = source;
    this.name = file || '(eval)';
    // Build line offsets for line/column calculation
    this._lineOffsets = [0];
    for (let i = 0; i < source.length; i++) {
      if (source[i] === '\n') {
        this._lineOffsets.push(i + 1);
      }
    }
  }

  lineForPosition(pos) {
    let idx = this._lineOffsets.findIndex(offset => offset > pos);
    return idx === -1 ? this._lineOffsets.length : idx;
  }

  columnForPosition(pos) {
    let lineIdx = this._lineOffsets.findIndex(offset => offset > pos);
    if (lineIdx === -1) lineIdx = this._lineOffsets.length;
    return pos - this._lineOffsets[lineIdx - 1];
  }
}
globalThis.PrismSourceBuffer = PrismSourceBuffer;

// PrismSourceRange - provides source range for location tracking
class PrismSourceRange {
  constructor(sourceBuffer, beginPos, endPos) {
    this.source_buffer = sourceBuffer;
    this.begin_pos = beginPos;
    this.end_pos = endPos;
  }

  get source() {
    return this.source_buffer.source.slice(this.begin_pos, this.end_pos);
  }

  get line() {
    return this.source_buffer.lineForPosition(this.begin_pos);
  }

  get column() {
    return this.source_buffer.columnForPosition(this.begin_pos);
  }
}
globalThis.PrismSourceRange = PrismSourceRange;

// Mock RUBY_VERSION as latest - all version-gated tests should run
globalThis.RUBY_VERSION = "3.4.0";
globalThis.RUBY2JS_PARSER = "prism";

// Import transpiled modules (must be after Prism setup)
const { Ruby2JS: WalkerModule } = await import('./dist/walker.mjs');
const { Ruby2JS: ConverterModule } = await import('./dist/converter.mjs');

// Ruby2JS placeholder - will be replaced after Prism init
globalThis.Ruby2JS = {
  convert(source, opts = {}) {
    return {
      toString() {
        return `[ERROR: Prism not initialized. Call initPrism() first]`;
      }
    };
  }
};

// Since Prism.loadPrism() is async, we need to initialize it
let prismParse = null;

export async function initPrism() {
  if (!prismParse) {
    prismParse = await Prism.loadPrism();
  }
  return prismParse;
}

// Updated convert that uses the initialized parser
Ruby2JS.convert = function(source, opts = {}) {
  if (!prismParse) {
    return {
      toString() {
        return `[ERROR: Prism not initialized. Call initPrism() first]`;
      }
    };
  }

  try {
    // Step 1: Parse Ruby source using Prism WASM
    const parseResult = prismParse(source);

    // Step 2: Walk Prism AST to create Parser-compatible AST
    const walker = new WalkerModule.PrismWalker(source, opts.file || null);
    const ast = walker.visit(parseResult.value);

    // Step 3: Extract comments
    const comments = {};
    if (parseResult.comments) {
      comments[ast] = parseResult.comments;
      comments._raw = parseResult.comments;
    }

    // Step 4: Create converter and generate JavaScript
    const converter = new ConverterModule.Converter(ast, comments, {});

    // Apply options
    if (opts.eslevel) converter.eslevel = opts.eslevel;
    if (opts.comparison) converter.comparison = opts.comparison;
    if (opts.strict) converter.strict = opts.strict;

    // convert is a getter (no-arg method becomes getter in ES6 class)
    converter.convert;

    return {
      toString() {
        // to_s is also a getter
        return converter.to_s;
      }
    };
  } catch (e) {
    return {
      toString() {
        return `[ERROR: ${e.message}]`;
      },
      error: e
    };
  }
};

let currentDescribe = [];
let testCount = 0;
let passCount = 0;
let failCount = 0;
let skipCount = 0;
let failures = [];

export function describe(name, fn) {
  currentDescribe.push(typeof name === 'function' ? name.name : name);
  fn();
  currentDescribe.pop();
}

export function it(name, fn) {
  testCount++;
  const fullName = [...currentDescribe, name].join(' > ');
  try {
    fn();
    passCount++;
  } catch (e) {
    if (e.message === 'SKIP') {
      skipCount++;
      passCount--; // Undo the implicit pass
    } else {
      failCount++;
      failures.push({ name: fullName, error: e });
    }
  }
}

export function skip(reason) {
  throw new Error('SKIP');
}

// before/after hooks (simplified - just run them)
let beforeEachFn = null;
export function before(fn) {
  // For now, just execute it once
  fn();
}

// Ruby's rindex with block - find last index where block returns true
if (!Array.prototype.rindex) {
  Array.prototype.rindex = function(fn) {
    for (let i = this.length - 1; i >= 0; i--) {
      if (fn(this[i])) return i;
    }
    return null;  // Ruby returns nil when not found
  };
}

// Ruby Hash class placeholder - Hash === x patterns in Ruby source have been
// changed to x.is_a?(Hash) which transpiles to x instanceof Hash.
// This class exists for compatibility but is not currently used.
class Hash {}
globalThis.Hash = Hash;

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
globalThis.initPrism = initPrism;
