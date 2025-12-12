// CLI smoke tests for ruby2js.mjs
// Tests that the CLI works correctly end-to-end

import { execSync } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const cli = join(__dirname, 'ruby2js.mjs');

// Simple test framework
let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`  \u2713 ${name}`);
  } catch (e) {
    failed++;
    console.log(`  \u2717 ${name}`);
    console.log(`    ${e.message}`);
  }
}

function run(input, args = '') {
  const result = execSync(`echo '${input}' | node ${cli} ${args}`, {
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe']
  });
  return result.trim();
}

function runWithStderr(input, args = '') {
  try {
    const result = execSync(`echo '${input}' | node ${cli} ${args} 2>&1`, {
      encoding: 'utf-8'
    });
    return { stdout: result.trim(), stderr: '', exitCode: 0 };
  } catch (e) {
    return { stdout: e.stdout?.trim() || '', stderr: e.stderr?.trim() || '', exitCode: e.status };
  }
}

// Tests
console.log('\nCLI Smoke Tests\n');

console.log('Basic conversion:');

test('simple puts', () => {
  const output = run('puts "hello"');
  if (output !== 'puts("hello")') {
    throw new Error(`Expected 'puts("hello")', got '${output}'`);
  }
});

test('variable assignment', () => {
  const output = run('x = 1');
  if (output !== 'let x = 1') {
    throw new Error(`Expected 'let x = 1', got '${output}'`);
  }
});

test('class definition', () => {
  const output = run('class Foo; def bar; end; end');
  if (!output.includes('class Foo')) {
    throw new Error(`Expected class definition, got '${output}'`);
  }
});

test('method with arguments', () => {
  const output = run('def add(a, b); a + b; end');
  if (!output.includes('function add(a, b)')) {
    throw new Error(`Expected function definition, got '${output}'`);
  }
});

console.log('\nAST modes:');

test('--ast shows s-expression', () => {
  const output = run('x = 1', '--ast');
  if (!output.includes('s(:lvasgn') || !output.includes('"x"')) {
    throw new Error(`Expected s-expression AST, got '${output}'`);
  }
});

test('--prism-ast shows Prism AST', () => {
  const output = run('x = 1', '--prism-ast');
  if (!output.includes('ProgramNode') || !output.includes('LocalVariableWriteNode')) {
    throw new Error(`Expected Prism AST output, got '${output}'`);
  }
});

console.log('\nOptions:');

test('--help shows usage', () => {
  const output = run('', '--help');
  if (!output.includes('Usage:') || !output.includes('--ast')) {
    throw new Error(`Expected help output, got '${output}'`);
  }
});

test('-e inline code', () => {
  const output = execSync(`node ${cli} -e 'puts "hello"'`, { encoding: 'utf-8' }).trim();
  if (output !== 'puts("hello")') {
    throw new Error(`Expected 'puts("hello")', got '${output}'`);
  }
});

test('--underscored_private', () => {
  const output = execSync(`node ${cli} --underscored_private -e '@x = 1'`, { encoding: 'utf-8' }).trim();
  if (!output.includes('_x')) {
    throw new Error(`Expected underscored private, got '${output}'`);
  }
});

console.log('\nNo WASI warning:');

test('WASI warning is suppressed', () => {
  const { stdout, stderr } = runWithStderr('puts "hello"');
  if (stderr.includes('WASI') || stdout.includes('ExperimentalWarning')) {
    throw new Error(`WASI warning should be suppressed, got stderr: '${stderr}'`);
  }
});

// Summary
console.log('\n' + '-'.repeat(40));
console.log(`Results: ${passed} passed, ${failed} failed\n`);

process.exit(failed > 0 ? 1 : 0);
