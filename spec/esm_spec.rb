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
      to_js('import "*", as: X, from: "x.js"').
        must_include 'import * as X from "x.js"'
    end

    it "should handle multiple named imports" do
      to_js('import [ X, Y, Z ], "xyz.js"').
        must_include 'import { X, Y, Z } from "xyz.js"'
    end

    it "should handle multiple named imports with from" do
      to_js('import [ X, Y, Z ], from: "xyz.js"').
        must_include 'import { X, Y, Z } from "xyz.js"'
    end

    it "should handle default and multiple named imports" do
      to_js('import X, [ Y, Z ], "xyz.js"').
        must_include 'import X, { Y, Z } from "xyz.js"'
    end

    it "should handle default and multiple named imports with from" do
      to_js('import X, [ Y, Z ], from: "xyz.js"').
        must_include 'import X, { Y, Z } from "xyz.js"'
    end
  end

  describe "require" do
    it "should handle top level requires" do
      to_js('require "./foo.js"').
        must_include 'import "./foo.js"'
    end

    it "should convert require to import with explicit exports" do
      # Skip in browser context (no filesystem access) or selfhost (no Ruby2JS.parse)
      return skip() if defined?(Window) or !Ruby2JS.respond_to?(:parse)
      to_js('require "require/test4.rb"', file: __FILE__).
        must_equal 'import Whoa, { Foo } from "./require/test4.rb"'
    end

    it "should convert require to import with auto exports" do
      # Skip in browser context (no filesystem access) or selfhost (no Ruby2JS.parse)
      return skip() if defined?(Window) or !Ruby2JS.respond_to?(:parse)
      to_js('require "require/test5.rb"', file: __FILE__, autoexports: true).
        must_equal 'import { Foo } from "./require/test5.rb"'
    end

    it "should convert require to import with auto exports default" do
      # Skip in browser context (no filesystem access) or selfhost (no Ruby2JS.parse)
      return skip() if defined?(Window) or !Ruby2JS.respond_to?(:parse)
      to_js('require "require/test5.rb"', file: __FILE__, autoexports: :default).
        must_equal 'import Foo from "./require/test5.rb"'
    end

    it "should handle require_recursive" do
      # Skip in browser context (no filesystem access) or selfhost (no Ruby2JS.parse)
      return skip() if defined?(Window) or !Ruby2JS.respond_to?(:parse)
      to_js('require "require/test7.rb"', file: __FILE__, autoexports: :default, require_recursive: true).
        must_equal 'import A from "./require/sub1/test8.rb"; ' +
          'import B from "./require/sub1/sub2/test9.rb"; ' +
          'import C from "./require/sub1/test10.rb"'
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

    it "should merge standalone export default with following function" do
      to_js("export default\ndef Show(x:)\n  x\nend").
        must_include "export default function Show"
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

      to_js("export [one, two, three, four: alias1, five: alias2]").
        must_include "export { one, two, three, alias1 as four, alias2 as five }"
    end

    it "should handle export * from" do
      to_js('export "*", from: "./foo.js"').
        must_equal 'export * from "./foo.js"'
    end
  end

  describe "import as a function" do
    it "should leave import function calls alone" do
      to_js('X = await import("x.js")').
        must_equal 'const X = await import("x.js")'
    end
  end

  describe "import.meta" do
    it "should handle import.meta.url" do
      to_js('import.meta.url').
        must_equal 'import.meta.url'
    end

    it "should handle import.meta in expressions" do
      to_js('URL.new("./file.wasm", import.meta.url)').
        must_equal 'new URL("./file.wasm", import.meta.url)'
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

    it "should autoexport modules with constants" do
      to_js('module Foo; BAR = 1; def baz; BAR; end; end', autoexports: true).
        must_include 'export const Foo = '
    end

    it "should autoexport even when imports are present" do
      to_js("import 'foo.js'; class Bar; end", autoexports: true).
        must_equal 'import "foo.js"; export class Bar {}'
    end
  end

  describe "autoexports default option" do
    it "should autoexport as default if there is only one export" do
      to_js('Foo = 1', autoexports: :default).
        must_equal 'export default Foo = 1'
    end

    it "explicit export should override autoexport as default" do
      to_js('export Foo = 1', autoexports: :default).
        must_equal 'export const Foo = 1'
    end

    it "should autoexport as named if there are multiple exports" do
      to_js('Foo = 1; Bar = 1', autoexports: :default).
        must_equal 'export const Foo = 1; export const Bar = 1'
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
      # Skip in selfhost - Ruby procs don't translate to JS
      return skip() unless defined?(Proc)
      to_js('Foo.bar', autoimports: proc {|name| "#{name.downcase}.js"}).
        must_equal 'import Foo from "foo.js"; Foo.bar'
    end

    it "should allow named autoimports" do
      to_js('func(1)', autoimports: {[:func, :another] => 'func.js'}).
        must_equal 'import { func, another } from "func.js"; func(1)'
    end

    it "should not autoimport if magic comment is present" do
      # Skip in selfhost - pragma filter is auto-applied in Ruby but not in selfhost
      # (selfhost only applies explicitly listed filters)
      # Check for import.meta which only exists in ES module (JS) context
      return skip() if defined?(import.meta)
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

  describe "__FILE__" do
    it "should convert __FILE__ to import.meta.url" do
      to_js('__FILE__').must_equal 'import.meta.url'
    end

    it "should convert __FILE__ in expressions" do
      to_js('puts __FILE__').must_equal 'puts(import.meta.url)'
    end
  end

  describe "__dir__" do
    it "should convert __dir__ to import.meta.dirname" do
      to_js('__dir__').must_equal 'import.meta.dirname'
    end

    it "should convert __dir__ in expressions" do
      to_js('puts __dir__').must_equal 'puts(import.meta.dirname)'
    end
  end

  describe "component import resolution" do
    def to_js_with_components(string, file_path, component_map = {})
      _(Ruby2JS.convert(string,
        eslevel: 2017,
        filters: [Ruby2JS::Filter::ESM],
        component_map: component_map,
        file_path: file_path
      ).to_s)
    end

    it "should resolve component imports to relative paths" do
      component_map = {
        "components/Button" => "app/components/Button.js"
      }
      to_js_with_components(
        'import Button from "components/Button"',
        "app/views/articles/Index.rb",
        component_map
      ).must_include 'import Button from "../../components/Button.js"'
    end

    it "should resolve imports from within components directory" do
      component_map = {
        "components/Button" => "app/components/Button.js"
      }
      to_js_with_components(
        'import Button from "components/Button"',
        "app/components/Card.rb",
        component_map
      ).must_include 'import Button from "./Button.js"'
    end

    it "should not resolve non-component imports" do
      component_map = {
        "components/Button" => "app/components/Button.js"
      }
      to_js_with_components(
        'import React from "react"',
        "app/views/articles/Index.rb",
        component_map
      ).must_include 'import React from "react"'
    end

    it "should not resolve relative imports" do
      component_map = {
        "components/Button" => "app/components/Button.js"
      }
      to_js_with_components(
        'import Utils from "./utils"',
        "app/views/articles/Index.rb",
        component_map
      ).must_include 'import Utils from "./utils"'
    end

    it "should handle import with from: syntax" do
      component_map = {
        "components/Card" => "app/components/Card.js"
      }
      to_js_with_components(
        'import Card, from: "components/Card"',
        "app/views/articles/Index.rb",
        component_map
      ).must_include 'import Card from "../../components/Card.js"'
    end

    it "should handle bare import (no default)" do
      component_map = {
        "components/styles" => "app/components/styles.js"
      }
      to_js_with_components(
        'import "components/styles"',
        "app/components/Card.rb",
        component_map
      ).must_include 'import "./styles.js"'
    end

    it "should work without component_map option" do
      to_js_with_components(
        'import Button from "components/Button"',
        "app/views/Index.rb",
        {}
      ).must_include 'import Button from "components/Button"'
    end

    it "should resolve nested component paths" do
      component_map = {
        "components/users/Avatar" => "app/components/users/Avatar.js"
      }
      to_js_with_components(
        'import Avatar from "components/users/Avatar"',
        "app/views/articles/Index.rb",
        component_map
      ).must_include 'import Avatar from "../../components/users/Avatar.js"'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include ESM" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::ESM
    end
  end
end
