// Unit tests for the transpiled PrismWalker
// Tests that the JavaScript walker correctly transforms Prism AST to Parser-compatible AST

// Import from the unified bundle (same code used by CLI and browser)
import { Ruby2JS, setupGlobals, initPrism } from './ruby2js.mjs';

// Set up globals
setupGlobals(Ruby2JS);

const prismParse = await initPrism();

// Test helper
function parse(source) {
  const result = prismParse(source);
  const walker = new Ruby2JS.PrismWalker(source, null);
  return walker.visit(result.value);
}

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

function assertEqual(actual, expected, msg = '') {
  const actualStr = JSON.stringify(actual);
  const expectedStr = JSON.stringify(expected);
  if (actualStr !== expectedStr) {
    throw new Error(`${msg}\nExpected: ${expectedStr}\nActual: ${actualStr}`);
  }
}

// Tests
console.log('\nPrismWalker Tests\n');

console.log('Literals:');

test('integer', () => {
  const ast = parse('42');
  assertEqual(ast._type, 'int');
  assertEqual(ast._children, [42]);
});

test('float', () => {
  const ast = parse('3.14');
  assertEqual(ast._type, 'float');
  assertEqual(ast._children, [3.14]);
});

test('string', () => {
  const ast = parse('"hello"');
  assertEqual(ast._type, 'str');
  assertEqual(ast._children, ['hello']);
});

test('symbol', () => {
  const ast = parse(':foo');
  assertEqual(ast._type, 'sym');
  assertEqual(ast._children, ['foo']);
});

test('true', () => {
  const ast = parse('true');
  assertEqual(ast._type, 'true');
});

test('false', () => {
  const ast = parse('false');
  assertEqual(ast._type, 'false');
});

test('nil', () => {
  const ast = parse('nil');
  assertEqual(ast._type, 'nil');
});

console.log('\nVariables:');

test('local variable read', () => {
  const ast = parse('x = 1; x');
  assertEqual(ast._type, 'begin');
  assertEqual(ast._children[1]._type, 'lvar');
  assertEqual(ast._children[1]._children, ['x']);
});

test('local variable assignment', () => {
  const ast = parse('x = 1');
  assertEqual(ast._type, 'lvasgn');
  assertEqual(ast._children[0], 'x');
  assertEqual(ast._children[1]._type, 'int');
});

test('instance variable', () => {
  const ast = parse('@foo');
  assertEqual(ast._type, 'ivar');
  assertEqual(ast._children, ['@foo']);
});

test('instance variable assignment', () => {
  const ast = parse('@foo = 1');
  assertEqual(ast._type, 'ivasgn');
  assertEqual(ast._children[0], '@foo');
});

console.log('\nOperators:');

test('addition', () => {
  const ast = parse('1 + 2');
  assertEqual(ast._type, 'send');
  assertEqual(ast._children[1], '+');
  assertEqual(ast._children[0]._type, 'int');
  assertEqual(ast._children[2]._type, 'int');
});

test('comparison', () => {
  const ast = parse('a == b');
  assertEqual(ast._type, 'send');
  assertEqual(ast._children[1], '==');
});

test('logical and', () => {
  const ast = parse('a && b');
  assertEqual(ast._type, 'and');
});

test('logical or', () => {
  const ast = parse('a || b');
  assertEqual(ast._type, 'or');
});

console.log('\nMethod calls:');

test('method call without args', () => {
  const ast = parse('foo.bar');
  assertEqual(ast._type, 'send');
  assertEqual(ast._children[1], 'bar');
});

test('method call with args', () => {
  const ast = parse('foo.bar(1, 2)');
  assertEqual(ast._type, 'send');
  assertEqual(ast._children[1], 'bar');
  assertEqual(ast._children.length, 4); // receiver, method, arg1, arg2
});

test('method call with block', () => {
  const ast = parse('[1,2].map { |x| x * 2 }');
  assertEqual(ast._type, 'block');
  assertEqual(ast._children[0]._type, 'send');
});

console.log('\nCollections:');

test('array literal', () => {
  const ast = parse('[1, 2, 3]');
  assertEqual(ast._type, 'array');
  assertEqual(ast._children.length, 3);
});

test('hash literal', () => {
  const ast = parse('{a: 1, b: 2}');
  assertEqual(ast._type, 'hash');
  assertEqual(ast._children.length, 2);
  assertEqual(ast._children[0]._type, 'pair');
});

console.log('\nControl flow:');

test('if statement', () => {
  const ast = parse('if x then y end');
  assertEqual(ast._type, 'if');
});

test('ternary', () => {
  const ast = parse('x ? y : z');
  assertEqual(ast._type, 'if');
});

test('while loop', () => {
  const ast = parse('while x; y; end');
  assertEqual(ast._type, 'while');
});

test('case/when', () => {
  const ast = parse('case x; when 1; y; end');
  assertEqual(ast._type, 'case');
});

console.log('\nDefinitions:');

test('method definition', () => {
  const ast = parse('def foo(x); x + 1; end');
  assertEqual(ast._type, 'def');
  assertEqual(ast._children[0], 'foo');
});

test('class definition', () => {
  const ast = parse('class Foo; end');
  assertEqual(ast._type, 'class');
});

test('lambda', () => {
  const ast = parse('-> { 1 }');
  assertEqual(ast._type, 'block');
  // Lambda is represented as (send nil :lambda) in Parser gem
  assertEqual(ast._children[0]._type, 'send');
  assertEqual(ast._children[0]._children[0], null);
  assertEqual(ast._children[0]._children[1], 'lambda');
});

console.log('\nLocation info (is_method detection):');

test('property access has selector location for is_method detection', () => {
  // self.p ||= 1 should NOT be detected as a method call
  // The AST node for the property read should have selector info
  const ast = parse('self.p ||= 1');
  assertEqual(ast._type, 'or_asgn');
  // The left side is the property access (send self :p)
  const sendNode = ast._children[0];
  assertEqual(sendNode._type, 'send');
  assertEqual(sendNode._children[0]._type, 'self');
  assertEqual(sendNode._children[1], 'p');
  // Key test: location should have selector info (not nil)
  // This enables is_method? to detect it's a property, not a method call
  const loc = sendNode._location;
  if (!loc || !loc.selector) {
    throw new Error('send node should have selector location for is_method? detection');
  }
});

test('method call without parens has selector location', () => {
  // foo.bar should have selector location
  const ast = parse('foo.bar');
  assertEqual(ast._type, 'send');
  const loc = ast._location;
  if (!loc || !loc.selector) {
    throw new Error('send node should have selector location');
  }
});

console.log('\n----------------------------------------');
console.log(`Results: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
