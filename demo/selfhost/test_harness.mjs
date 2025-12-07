// Minimal test harness for selfhosted specs
// Provides describe/it/must_equal compatible with transpiled Minitest specs

// Mock RUBY_VERSION as latest - all version-gated tests should run
globalThis.RUBY_VERSION = "3.4.0";

let currentDescribe = [];
let testCount = 0;
let passCount = 0;
let failCount = 0;
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
    failCount++;
    failures.push({ name: fullName, error: e });
  }
}

// Extend String prototype with must_equal for chaining
String.prototype.must_equal = function(expected) {
  if (this.valueOf() !== expected) {
    throw new Error(`Expected "${expected}" but got "${this.valueOf()}"`);
  }
};

// Also support must_include, must_match
String.prototype.must_include = function(substring) {
  if (!this.includes(substring)) {
    throw new Error(`Expected "${this.valueOf()}" to include "${substring}"`);
  }
};

String.prototype.must_match = function(pattern) {
  if (!pattern.test(this.valueOf())) {
    throw new Error(`Expected "${this.valueOf()}" to match ${pattern}`);
  }
};

export function runTests() {
  console.log(`\nTests: ${testCount}, Passed: ${passCount}, Failed: ${failCount}`);
  if (failures.length > 0) {
    console.log('\nFailures:');
    failures.forEach(f => {
      console.log(`  ${f.name}`);
      console.log(`    ${f.error.message}`);
    });
  }
  return failCount === 0;
}

// Export globals for non-module usage
globalThis.describe = describe;
globalThis.it = it;
globalThis.runTests = runTests;
