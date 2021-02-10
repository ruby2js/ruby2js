gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/stimulus'

describe Ruby2JS::Filter::Stimulus do
  
  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2022,
      filters: [Ruby2JS::Filter::Stimulus]).to_s)
  end
  
  def to_js_skypack(string)
    _(Ruby2JS.convert(string, eslevel: 2022, import_from_skypack: true,
      filters: [Ruby2JS::Filter::Stimulus]).to_s)
  end
  
  describe "class aliases" do
    it "handles ruby scope syntax" do
      to_js( 'class Foo<Stimulus::Controller; end' ).
        must_equal 'import * as Stimulus from "stimulus"; ' +
          'class Foo extends Stimulus.Controller {}'
    end

    it "handles JS scope syntax" do
      to_js( 'class Foo<Stimulus.Controller; end' ).
        must_equal 'import * as Stimulus from "stimulus"; ' +
          'class Foo extends Stimulus.Controller {}'
    end

    it "handles shorthand" do
      to_js( 'class Foo<Stimulus; end' ).
        must_equal 'import * as Stimulus from "stimulus"; ' +
          'class Foo extends Stimulus.Controller {}'
    end
  end

  describe "common stimulus properties" do
    it "must handle application property" do
      to_js( 'class Foo<Stimulus; def reg(); application.register("x", Class.new {}); end; end' ).
        must_include 'this.application.register("x", class {})'
    end

    it "must handle element property" do
      to_js( 'class Foo<Stimulus; def clear(); element.textContent = ""; end; end' ).
        must_include 'this.element.textContent = ""'
    end
  end

  describe "initialize method" do
    it "must NOT map initialize to constructor" do
      to_js( 'class Foo<Stimulus; def initialize(); @index=0; end; end' ).
        must_include 'initialize() {this.#index = 0}'
    end
  end

  describe "targets" do
    it "should handle xTarget" do
      to_js( 'class Foo<Stimulus; def bar(); xTarget; end; end' ).
        must_include 'static targets = ["x"]; bar() {this.xTarget}'
    end

    it "should handle xTargets" do
      to_js( 'class Foo<Stimulus; def bar(); xTargets; end; end' ).
        must_include 'static targets = ["x"]; bar() {this.xTargets}'
    end

    it "should handle hasXTarget" do
      to_js( 'class Foo<Stimulus; def bar(); hasXTarget; end; end' ).
        must_include 'static targets = ["x"]; bar() {this.hasXTarget}'
    end
  end

  describe "values" do
    it "should handle xValue" do
      to_js( 'class Foo<Stimulus; def bar(); xValue; end; end' ).
        must_include 'static values = {x: String}; bar() {this.xValue}'
    end

    it "should handle xValue=1" do
      to_js( 'class Foo<Stimulus; def bar(); xValue=1; end; end' ).
        must_include 'static values = {x: String}; bar() {this.xValue = 1}'
    end

    it "should handle hasXValue" do
      to_js( 'class Foo<Stimulus; def bar(); hasXValue; end; end' ).
        must_include 'static values = {x: String}; bar() {this.hasXValue}'
    end

    it "should not override value type" do
      to_js( 'class Foo<Stimulus; self.values = {x: Numeric}; def bar(); hasXValue; end; end' ).
        must_include 'static values = {x: Numeric}; bar() {this.hasXValue}'
    end
  end

  describe "classes" do
    it "should handle xClass" do
      to_js( 'class Foo<Stimulus; def bar(); xClass; end; end' ).
        must_include 'static classes = ["x"]; bar() {this.xClass}'
    end

    it "should handle hasXClass" do
      to_js( 'class Foo<Stimulus; def bar(); hasXClass; end; end' ).
        must_include 'static classes = ["x"]; bar() {this.hasXClass}'
    end
  end

  describe "inheritance" do
    it "must inherit element property" do
      to_js( 'class Base<Stimulus; end; class Foo< Base; def clear(); element.textContent = ""; end; end' ).
        must_include 'this.element.textContent = ""'
    end
  end

  describe "skypack" do
    it "imports from skypack" do
      to_js_skypack( 'class Foo<Stimulus::Controller; end' ).
        must_equal 'import * as Stimulus from "https://cdn.skypack.dev/stimulus"; ' +
          'class Foo extends Stimulus.Controller {}'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Stimulus" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Stimulus
    end
  end
end
