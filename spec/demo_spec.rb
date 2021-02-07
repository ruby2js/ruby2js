gem 'minitest'
require 'minitest/autorun'
require 'ruby2js'

describe "demo" do

  DEMO = File.expand_path('../demo/ruby2js.rb', __dir__)

  def to_js(string, options=[])
    stdin, stdout, verbose = $stdin, $stdout, $VERBOSE
    $stdout = StringIO.new
    $stdin = StringIO.new(string)
    $VERBOSE = nil
    ARGV.clear
    ARGV.push(*options)
    load DEMO
    _($stdout.string.chomp)
  ensure
    $stdin, $stdout, $VERBOSE = stdin, stdout, verbose
  end

  describe "filters" do
    it "should work without filters" do
      to_js("x = 123; puts x").
        must_equal('var x = 123; puts(x)')
    end

    it "should work with a filter" do
      to_js("x = 123; puts x", %w(--filter functions)).
        must_equal('var x = 123; console.log(x)')
    end
  end

  describe "options" do
    it "should work without options" do
      to_js("x = 123").
        must_equal('var x = 123')
    end

    it "should work with an option" do
      to_js("x = 123", %w(--strict --es2017)).
        must_equal('"use strict"; let x = 123')
    end

    describe "exclude/include" do
      it "should work without options" do
        to_js("x.class; x.downcase()", %w(--filter functions)).
          must_equal('x.class; x.toLowerCase()')
      end

      it "should work with an option once included" do
        to_js("x.class; x.downcase()", %w(--filter functions --include class)).
          must_equal('x.constructor; x.toLowerCase()')
      end

      it "should work with an option when all are included" do
        to_js("x.class; x.downcase()", %w(--filter functions --include-all)).
          must_equal('x.constructor; x.toLowerCase()')
      end

      it "should work with only the options that are included" do
        to_js("x.class; x.downcase()", %w(--filter functions --include-only class)).
          must_equal('x.constructor; x.downcase()')
      end

      it "should work with an option when all are included" do
        to_js("x.class; x.downcase()", %w(--filter functions --exclude downcase)).
          must_equal('x.class; x.downcase()')
      end
    end

    describe "ESM exports/imports" do
      it "should handle automatic exports" do
        to_js("A = 1", %w(--filter esm --autoexports)).
          must_equal('export const A = 1')

        to_js("A = 1", %w(--filter esm --autoexports default)).
          must_equal('export default A = 1')
      end

      it "should handle automatic imports" do
        to_js("A.foo", %w(--filter esm --autoimports A)).
          must_equal('import A from "A"; A.foo')

        to_js("A.foo", %w(--filter esm --autoimports A:foo.js)).
          must_equal('import A from "foo.js"; A.foo')
      end

      it "should handle module/class definitions" do
        to_js("class C < A; def f; x; end; end",
          %w(--filter esm --es2019 --autoimports A:a.js --defs A:[x,@y,:z],b:[q])).
          must_equal('import A from "a.js"; ' +
            'class C extends A {get f() {return this.x.bind(this)}}')
      end
    end

    describe "comparison: equality/identity" do
      it "should handle equality" do
        to_js("A == B", %w(--equality)).
          must_equal('A == B')
      end

      it "should handle identity" do
        to_js("A == B", %w(--identity)).
          must_equal('A === B')
      end
    end

    it "should handle ivars" do
      to_js("@x", %w(--ivars @x:fromhost)).
        must_equal('"fromhost"')
    end

    describe "or: logical/nullish" do
      it "should handle logical" do
        to_js("A || B", %w(--logical)).
          must_equal('A || B')
      end

      it "should handle nullish" do
        to_js("A || B", %w(--es2020 --nullish)).
          must_equal('A ?? B')
      end
    end

    it "should handle template literal tags" do
      to_js("color 'red'", %w(--es2015 --filter tagged_templates --template_literal_tags color)).
        must_equal('color`red`')
    end

    describe "underscored private" do
      it "without underscored private" do
        to_js("class C; def initialize; @a=1; end; end", %w(--es2022)).
          must_equal('class C {#a = 1; }')
      end

      it "with underscored private" do
        to_js("class C; def initialize; @a=1; end; end", %w(--es2022 --underscored_private)).
          must_equal('class C {constructor() {this._a = 1}}')
      end
    end
  end
end
