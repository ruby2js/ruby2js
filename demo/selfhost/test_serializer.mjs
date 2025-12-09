// Test the transpiled Serializer class directly
// Import the test harness first to get polyfills (rindex, etc.)
import { initPrism } from './test_harness.mjs';
await initPrism();

// Import the converter module which contains Serializer, Token, Line classes
const { Ruby2JS: ConverterModule } = await import('./dist/converter.mjs');

const { Serializer, Token, Line } = ConverterModule;

let passed = 0;
let failed = 0;

function describe(name, fn) {
  console.log(`\n${name}`);
  fn();
}

function it(name, fn) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (e) {
    console.log(`  ✗ ${name}`);
    console.log(`    ${e.message}`);
    failed++;
  }
}

function assertEqual(actual, expected, msg = '') {
  const actualStr = JSON.stringify(actual);
  const expectedStr = JSON.stringify(expected);
  if (actualStr !== expectedStr) {
    throw new Error(`${msg}\nExpected: ${expectedStr}\nActual:   ${actualStr}`);
  }
}

// Tests
describe('reindent', () => {
  it('should indent content inside braces', () => {
    const s = new Serializer();
    s.enable_vertical_whitespace;
    s.puts('{');
    s.puts('content');
    s.puts('}');
    s.reindent(s._lines);
    assertEqual(s._lines.map(l => l.indent), [0, 2, 0, 0]);
  });

  it('should indent content inside brackets', () => {
    const s = new Serializer();
    s.enable_vertical_whitespace;
    s.puts('[');
    s.puts('item');
    s.puts(']');
    s.reindent(s._lines);
    assertEqual(s._lines.map(l => l.indent), [0, 2, 0, 0]);
  });

  it('should indent content inside parentheses', () => {
    const s = new Serializer();
    s.enable_vertical_whitespace;
    s.puts('(');
    s.puts('arg');
    s.puts(')');
    s.reindent(s._lines);
    assertEqual(s._lines.map(l => l.indent), [0, 2, 0, 0]);
  });

  it('should handle nested braces', () => {
    const s = new Serializer();
    s.enable_vertical_whitespace;
    s.puts('if (true) {');
    s.puts('if (false) {');
    s.puts('inner');
    s.puts('}');
    s.puts('}');
    s.reindent(s._lines);
    assertEqual(s._lines.map(l => l.indent), [0, 2, 4, 2, 0, 0]);
  });

  it('should handle closing brace at start of line', () => {
    const s = new Serializer();
    s.enable_vertical_whitespace;
    s.puts('function() {');
    s.puts('body');
    s.puts('}');
    s.reindent(s._lines);
    assertEqual(s._lines.map(l => l.indent), [0, 2, 0, 0]);
  });

  it('should handle empty lines', () => {
    const s = new Serializer();
    s.enable_vertical_whitespace;
    s.puts('{');
    s.puts('');
    s.puts('content');
    s.puts('}');
    s.reindent(s._lines);
    assertEqual(s._lines.map(l => l.indent), [0, 2, 2, 0, 0]);
  });
});

describe('respace', () => {
  it('should add blank line before indented block', () => {
    const s = new Serializer();
    s.enable_vertical_whitespace;
    s.puts('x()');
    s.puts('if (true) {');
    s.puts('a()');
    s.put('}');
    const result = s.to_s;
    assertEqual(result, "x()\n\nif (true) {\n  a()\n}");
  });

  it('should add blank line after indented block', () => {
    const s = new Serializer();
    s.enable_vertical_whitespace;
    s.puts('if (true) {');
    s.puts('a()');
    s.puts('}');
    s.put('x()');
    const result = s.to_s;
    assertEqual(result, "if (true) {\n  a()\n}\n\nx()");
  });

  it('should NOT add blank lines inside blocks', () => {
    const s = new Serializer();
    s.enable_vertical_whitespace;
    s.puts('if (true) {');
    s.puts('a();');
    s.puts('b()');
    s.put('}');
    const result = s.to_s;
    assertEqual(result, "if (true) {\n  a();\n  b()\n}");
  });

  it('should add single blank line between blocks', () => {
    const s = new Serializer();
    s.enable_vertical_whitespace;
    s.puts('if (true) {');
    s.puts('a()');
    s.puts('}');
    s.puts('if (false) {');
    s.puts('b()');
    s.put('}');
    const result = s.to_s;
    assertEqual(result, "if (true) {\n  a()\n}\n\nif (false) {\n  b()\n}");
  });
});

console.log(`\n----------------------------------------`);
console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
