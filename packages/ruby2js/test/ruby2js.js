// minimal sanity test to verify usage of Ruby2JS under Node

const assert = require('assert');
const fs = require('fs');
const Ruby2JS = require('../ruby2js.js');

function to_js(string, options={}) {
  return Ruby2JS.convert(string, options).toString()
}

describe('ruby2js package', () => {
  // clear any options loaded by prior tests
  Ruby2JS.load_options();

  it('does a basic conversion', () => {
    assert.strictEqual(
      to_js('foo = 1'),
      'var foo = 1');
  });

  it('handles eslevel option', () => {
    assert.strictEqual(
      to_js('foo = 1', {eslevel: 2015}),
      'let foo = 1');
  });

  it('invokes filter function', () => {
    assert.strictEqual(
      to_js('foo.empty?', {filters: ['functions']}),
      'foo.length == 0');
  });

  it('generates AST', () => {
    let ast = Ruby2JS.convert('String', {file: 'a.rb'}).ast
    assert.strictEqual(ast.constructor, Ruby2JS.AST.Node)
    assert.strictEqual(ast.type, "const")
    assert.strictEqual(ast.children.length, 2)
    assert.strictEqual(ast.children[0], Ruby2JS.nil)
    assert.strictEqual(ast.children[1], "String")
  });

  it('produces a sourcemap', () => {
    let sourcemap = Ruby2JS.convert('a=1', {file: 'a.rb'}).sourcemap
    assert.strictEqual(sourcemap.version, 3)
    assert.strictEqual(sourcemap.file, 'a.rb')
    assert.strictEqual(sourcemap.sources.length, 1)
    assert.strictEqual(sourcemap.sources[0], 'a.rb')
    assert.strictEqual(sourcemap.names.length, 1)
    assert.strictEqual(sourcemap.names[0], 'a')
    assert.strictEqual(sourcemap.mappings, 'AAAAA,QAAE')
  });
});

describe('ruby2js external options', () => {
  it('supports rb2js.config.rb', async () => {
    try {
      fs.writeFileSync(`rb2js.config.rb`, `
        require "ruby2js/filter/functions"
        module Ruby2JS
          class Loader
            def self.options
              {eslevel: 2021}
            end
          end
        end
      `);

      Ruby2JS.load_options()
    } finally {
      fs.unlinkSync(`rb2js.config.rb`)
    }

    assert.strictEqual(
      to_js('puts "0x2A = #{"2A".to_i(16)}"'),
      'console.log(`0x2A = ${parseInt("2A", 16)}`)'
    )
  });

  it('supports RUBY2JS_OPTIONS environment variable', async () => {
    try {
      process.env.RUBY2JS_OPTIONS = '{"eslevel": 2021, "filters": ["functions"]}';
      Ruby2JS.load_options()
    } finally {
      delete process.env.RUBY2JS_OPTIONS
    }

    assert.strictEqual(
      to_js('puts "0x2A = #{"2A".to_i(16)}"'),
      'console.log(`0x2A = ${parseInt("2A", 16)}`)'
    )
  });
})

