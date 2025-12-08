// Minimal test harness for selfhosted specs
// Provides describe/it/must_equal compatible with transpiled Minitest specs

// Mock RUBY_VERSION as latest - all version-gated tests should run
globalThis.RUBY_VERSION = "3.4.0";
globalThis.RUBY2JS_PARSER = "prism";

// Mock Ruby2JS - this will be replaced with the real selfhosted converter
// For now, all tests will fail because convert() returns a placeholder
globalThis.Ruby2JS = {
  convert(source, opts = {}) {
    return {
      toString() {
        return `[NOT IMPLEMENTED: Ruby2JS.convert]`;
      }
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
