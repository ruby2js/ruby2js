// Minimal test harness mimicking Minitest/RSpec style
// Provides describe/it/must_equal for transpiled Ruby specs

let currentDescribe = [];
let results = { passed: 0, failed: 0, errors: [] };

export function describe(name, fn) {
  currentDescribe.push(name);
  console.log(`\n${'  '.repeat(currentDescribe.length - 1)}${name}`);
  fn();
  currentDescribe.pop();
}

export function it(name, fn) {
  const fullName = [...currentDescribe, name].join(' > ');
  try {
    fn();
    results.passed++;
    console.log(`${'  '.repeat(currentDescribe.length)}✓ ${name}`);
  } catch (e) {
    results.failed++;
    results.errors.push({ name: fullName, error: e });
    console.log(`${'  '.repeat(currentDescribe.length)}✗ ${name}`);
    console.log(`${'  '.repeat(currentDescribe.length + 1)}${e.message}`);
  }
}

// Add must_equal to String prototype for Minitest compatibility
String.prototype.must_equal = function(expected) {
  const actual = this.toString();
  if (actual !== expected) {
    throw new Error(`Expected: ${JSON.stringify(expected)}\n       Got: ${JSON.stringify(actual)}`);
  }
};

export function printResults() {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Results: ${results.passed} passed, ${results.failed} failed`);
  if (results.errors.length > 0) {
    console.log('\nFailures:');
    results.errors.forEach((e, i) => {
      console.log(`  ${i + 1}) ${e.name}`);
      console.log(`     ${e.error.message}`);
    });
  }
  return results.failed === 0;
}

export function resetResults() {
  results = { passed: 0, failed: 0, errors: [] };
}
