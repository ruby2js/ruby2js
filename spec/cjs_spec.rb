require 'minitest/autorun'
require 'ruby2js/filter/cjs'

describe Ruby2JS::Filter::CJS do
  
  def to_js(string, options= {})
    _(Ruby2JS.convert(string, options.merge(filters: [Ruby2JS::Filter::CJS],
      file: __FILE__, eslevel: 2017)).to_s)
  end

  def to_js_fn(string)
    _(Ruby2JS.convert(string,
      filters: [Ruby2JS::Filter::CJS, Ruby2JS::Filter::Functions],
      file: __FILE__, eslevel: 2017).to_s)
  end
  
  describe :exports do
    it "should export a simple function" do
      to_js( 'export def f(a); return a; end' ).
        must_equal 'exports.f = a => a'
    end

    it "should export an async function" do
      to_js( 'export async def f(a, b); return a; end' ).
        must_equal 'exports.f = async (a, b) => a'
    end

    it "should export a value" do
      to_js( 'export foo = 1' ).
        must_equal 'exports.foo = 1'
    end

    it "should export a constant" do
      to_js( 'export Foo = 1' ).
        must_equal 'exports.Foo = 1'
    end

    it "should export a class" do
      to_js( 'export class C; end' ).
        must_equal 'exports.C = class {}'
    end

    it "should export a subclass" do
      to_js( 'export class C < D; end' ).
        must_equal 'exports.C = class extends D {}'
    end

    it "should export a module" do
      to_js( 'export module C; def x; 42; end; end' ).
        must_equal 'exports.C = {get x() {return 42}}'
    end

    it "should convert .inspect into JSON.stringify()" do
      to_js_fn( 'export async def f(a, b); return {input: a}.inspect; end' ).
        must_equal 'exports.f = async (a, b) => JSON.stringify({input: a})'
    end
  end

  describe :default do
    it "should export a simple function" do
      to_js( 'export default proc do |a|; return a; end' ).
        must_equal 'module.exports = a => a'
    end

    it "should export an async function" do
      to_js( 'export default async proc do |a, b| return a; end' ).
        must_equal 'module.exports = async (a, b) => a'
    end

    it "should export a value" do
      to_js( 'export default 1' ).
        must_equal 'module.exports = 1'
    end
  end

  describe "autoexports option" do
    it "should autoexport top level modules" do
      to_js('module Foo; def bar; end; end', autoexports: true).
        must_equal 'exports.Foo = {get bar() {}}'
    end

    it "should autoexport top level classes" do
      to_js('class Foo; def bar; end; end', autoexports: true).
        must_equal 'exports.Foo = class {get bar() {}}'
    end

    it "should autoexport top level methods" do
      to_js('def f; end', autoexports: true).
        must_equal 'exports.f = () => {}'
    end

    it "should autoexport top level constants" do
      to_js('Foo=1', autoexports: true).
        must_equal 'exports.Foo = 1'
    end
  end

  describe "autoexports default option" do
    it "should autoexport as default if there is only one export" do
      to_js('Foo = 1', autoexports: :default).
        must_equal 'module.exports = Foo = 1'
    end

    it "explicit export should override autoexport as default" do
      to_js('export Foo = 1', autoexports: :default).
        must_equal 'exports.Foo = 1'
    end

    it "should autoexport as named if there are multiple exports" do
      to_js('Foo = 1; Bar = 1', autoexports: :default).
        must_equal 'exports.Foo = 1; exports.Bar = 1'
    end
  end

  describe "__FILE__" do
    it "should convert __FILE__ to __filename" do
      to_js('__FILE__').must_equal '__filename'
    end

    it "should convert __FILE__ in expressions" do
      to_js('puts __FILE__').must_equal 'puts(__filename)'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include CJS" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::CJS
    end
  end
end
