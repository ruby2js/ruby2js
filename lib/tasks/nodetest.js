// minimal sanity test to verify usage of Ruby2JS under Node

const assert = require('assert');

const Ruby2JS = require('@ruby2js/ruby2js');
// const Ruby2JS =
// require('/home/rubys/git/ruby2js/docs/src/demo/ruby2js.js');

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

let ast = Ruby2JS.convert('String', {file: 'a.rb'}).ast
assert.strictEqual(ast.constructor, Ruby2JS.AST.Node)
assert.strictEqual(ast.type, "const")
assert.strictEqual(ast.children.length, 2)
assert.strictEqual(ast.children[0], Ruby2JS.nil)
assert.strictEqual(ast.children[1], "String")

let sourcemap = Ruby2JS.convert('a=1', {file: 'a.rb'}).sourcemap
assert.strictEqual(sourcemap.version, 3)
assert.strictEqual(sourcemap.file, 'a.rb')
assert.strictEqual(sourcemap.sources.length, 1)
assert.strictEqual(sourcemap.sources[0], 'a.rb')
assert.strictEqual(sourcemap.mappings, 'QAAE')

console.log(to_js(`
class C < LitElement
  def render
    x.empty?
    '<h1>title</h1>'
  end
end

`, {eslevel: 2020, filters: ['lit-element', 'esm', 'functions']}))
