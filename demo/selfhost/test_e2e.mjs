import { Converter, s } from "./selfhost_converter.mjs";

const tests = [
  ['integer', s('int', 42)],
  ['string', s('str', 'hello')],
  ['boolean true', s('true')],
  ['boolean false', s('false')],
  ['nil', s('nil')],
  ['self', s('self')],
  ['local var', s('lvar', 'x')],
  ['assignment', s('lvasgn', 'x', s('int', 42))],
  ['instance var', s('ivar', '@x')],
  ['instance assign', s('ivasgn', '@x', s('int', 1))],
  ['array', s('array', s('int', 1), s('int', 2))],
  ['hash', s('hash', s('pair', s('sym', 'a'), s('int', 1)))],
  ['method call', s('send', s('lvar', 'x'), 'foo')],
  ['method with arg', s('send', s('lvar', 'x'), 'bar', s('int', 1))],
  ['def', s('def', 'greet', s('args'), s('str', 'hi'))],
  ['def with args', s('def', 'add', s('args', s('arg', 'a'), s('arg', 'b')), s('send', s('lvar', 'a'), '+', s('lvar', 'b')))],
  ['if/else', s('if', s('true'), s('int', 1), s('int', 2))],
  ['begin block', s('begin', s('lvasgn', 'x', s('int', 1)), s('lvasgn', 'y', s('int', 2)))],
];

console.log('Self-hosted Converter Tests:\n');
for (const [name, ast] of tests) {
  try {
    const c = new Converter(ast, new Map());
    c.convert();
    const js = c.to_s().replace(/\n/g, ' ').replace(/  +/g, ' ').trim();
    console.log(`✓ ${name}: ${js}`);
  } catch (e) {
    console.log(`✗ ${name}: ${e.message}`);
  }
}
