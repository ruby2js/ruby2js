gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::ESM do
  
  def to_js(string, options={})
    _(Ruby2JS.convert(string, options.merge(
      eslevel: 2017,
      filters: [Ruby2JS::Filter::ESM],
      scope: self
    )).to_s)
  end
  
  describe "imports" do
    it "should handle a file import" do
      to_js('import "x.css"').
        must_include 'import "x.css"'
    end

    it "should handle a default import" do
      to_js('import X, "x.js"').
        must_include 'import X from "x.js"'
    end

    it "should handle a default import with from" do
      to_js('import X  from "x.js"').
        must_include 'import X from "x.js"'

      to_js('import X, from: "x.js"').
        must_include 'import X from "x.js"'
    end

    it "should handle a default import as start" do
      to_js('import X, as: "*", from: "x.js"').
        must_include 'import X as * from "x.js"'
    end

    it "should handle multiple named imports" do
      to_js('import [ X, Y, Z ], "xyz.js"').
        must_include 'import { X, Y, Z } from "xyz.js"'
    end

    it "should handle multiple named imports with from" do
      to_js('import [ X, Y, Z ], from: "xyz.js"').
        must_include 'import { X, Y, Z } from "xyz.js"'
    end
  end

  describe "exports" do
    it "should handle a default class" do
      to_js("export default class X < Y\nend").
        must_include "export default class X extends Y {"
    end

    it "should handle a default expression" do
      to_js("export default func = ->() { 123 } ").
        must_include "export default func = () => 123"

      to_js("export default hash = { a: 123 } ").
        must_include "export default hash = {a: 123}"
    end

    it "should handle named exports" do
      to_js("export class X < Y\nend").
        must_include "export class X extends Y {"

      to_js("export func = ->() { 123 } ").
        must_include "export const func = () => 123"
    end

    it "should handle final export statements" do
      to_js("export [ A, B ]").
        must_include "export { A, B }"

      to_js("export default A").
        must_include "export default A"

      to_js("export [ A, default: B ]").
        must_include "export { A, B as default }"
    end
  end

  describe "import as a function" do
    it "should leave import function calls alone" do
      to_js('X = await import("x.js")').
        must_equal 'const X = await import("x.js")'
    end
  end

  describe "autoexports option" do
    it "should autoexport top level modules" do
      to_js('module Foo; def bar; end; end', autoexports: true).
        must_equal 'export const Foo = {get bar() {}}'
    end

    it "should autoexport top level classes" do
      to_js('class Foo; def bar; end; end', autoexports: true).
        must_equal 'export class Foo {get bar() {}}'
    end

    it "should autoexport top level methods" do
      to_js('def f; end', autoexports: true).
        must_equal 'export function f() {}'
    end

    it "should autoexport top level constants" do
      to_js('Foo=1', autoexports: true).
        must_equal 'export const Foo = 1'
    end
  end

  describe "autoimports option" do
    it "should autoimport for constants" do
      to_js('Foo.bar', autoimports: {Foo: 'foo.js'}).
        must_equal 'import Foo from "foo.js"; Foo.bar'
    end

    it "should autoimport for non-constants" do
      to_js('foo.bar', autoimports: {foo: 'foo.js'}).
        must_equal 'import foo from "foo.js"; foo.bar'
    end

    it "should autoimport for functions" do
      to_js('func(1)', autoimports: {func: 'func.js'}).
        must_equal 'import func from "func.js"; func(1)'
    end

    it "should handle autoimport as a proc" do
      to_js('Foo.bar', autoimports: proc {|name| "#{name.downcase}.js"}).
        must_equal 'import Foo from "foo.js"; Foo.bar'
    end

    it "should allow named autoimports" do
      to_js('func(1)', autoimports: {[:func, :another] => 'func.js'}).
        must_equal 'import { func, another } from "func.js"; func(1)'
    end

    it "should not autoimport if magic comment is present" do
      to_js("# autoimports: false\nfunc(1)", autoimports: {[:func, :another] => 'func.js'}).
        must_equal "// autoimports: false\nfunc(1)"
    end

  describe "defs option" do
    it "should define a method" do
      to_js('class C < Foo; def f; x; end; end',
          defs: {Foo: [:x]}, autoimports: {Foo: 'foo.js'}).
        must_equal 'import Foo from "foo.js"; ' +
         'class C extends Foo {get f() {return this.x.bind(this)}}'
    end

    it "should define a property" do
      to_js('class C < Foo; def f; x; end; end',
          defs: {Foo: [:@x]}, autoimports: {Foo: 'foo.js'}).
        must_equal 'import Foo from "foo.js"; ' +
         'class C extends Foo {get f() {return this.x}}'
    end
  end

    it "should not autoimport if explicit import is present" do
      to_js('import Foo from "bar.js"; Foo.bar', autoimports: {Foo: 'foo.js'}).
        must_equal 'import Foo from "bar.js"; Foo.bar'

      to_js('import Foo, from: "bar.js"; Foo.bar', autoimports: {Foo: 'foo.js'}).
        must_equal 'import Foo from "bar.js"; Foo.bar'
    end

    it "should not autoimport if imported name is redefined" do
      to_js('class Foo;end; Foo.bar', autoimports: {Foo: 'foo.js'}).
        must_equal 'class Foo {}; Foo.bar'

      to_js('def func(x);end;func(1)', autoimports: {func: 'func.js'}).
        must_equal 'function func(x) {}; func(1)'

      to_js('func = ->(x) {};func(1)', autoimports: {func: 'func.js'}).
        must_equal 'let func = (x) => {}; func(1)'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include ESM" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::ESM
    end
  end
end
