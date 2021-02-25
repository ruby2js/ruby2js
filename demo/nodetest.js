// minimal sanity test to verify usage of Ruby2JS under Node

const assert = require('assert');
const Ruby2JS = require('../docs/src/demo/ruby2js.js');

function to_js(string, options={}) {
  return Ruby2JS.convert(string, options).toString()
}

assert.strictEqual(
  to_js('foo = 1'),
  'var foo = 1');

assert.strictEqual(
  to_js('foo = 1', {eslevel: 2015}),
  'let foo = 1');

assert.strictEqual(
  to_js('foo.empty?', {filters: ['functions']}),
  'foo.length == 0');
