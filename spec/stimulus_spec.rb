require 'minitest/autorun'
require 'ruby2js/filter/stimulus'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::Stimulus do
  
  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2022,
      filters: [Ruby2JS::Filter::Stimulus]).to_s)
  end
  
  def to_js_esm(string)
    _(Ruby2JS.convert(string, eslevel: 2022,
      filters: [Ruby2JS::Filter::Stimulus, Ruby2JS::Filter::ESM]).to_s)
  end
  
  describe "class aliases" do
    it "handles ruby scope syntax" do
      to_js( 'class Foo<Stimulus::Controller; end' ).
        must_equal 'class Foo extends Controller {}'
    end

    it "handles JS scope syntax" do
      to_js( 'class Foo<Stimulus.Controller; end' ).
        must_equal 'class Foo extends Controller {}'
    end

    it "handles shorthand" do
      to_js( 'class Foo<Stimulus; end' ).
        must_equal 'class Foo extends Controller {}'
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

  describe "outlets" do
    it "should handle xOutlet" do
      to_js( 'class Foo<Stimulus; def bar(); modalOutlet; end; end' ).
        must_include 'static outlets = ["modal"]; bar() {this.modalOutlet}'
    end

    it "should handle xOutlets" do
      to_js( 'class Foo<Stimulus; def bar(); modalOutlets; end; end' ).
        must_include 'static outlets = ["modal"]; bar() {this.modalOutlets}'
    end

    it "should handle hasXOutlet" do
      to_js( 'class Foo<Stimulus; def bar(); hasModalOutlet; end; end' ).
        must_include 'static outlets = ["modal"]; bar() {this.hasModalOutlet}'
    end

    it "should detect outlet from lifecycle method" do
      to_js( 'class Foo<Stimulus; def modalOutletConnected(outlet); end; end' ).
        must_include 'static outlets = ["modal"]'
    end

    it "should detect outlet from disconnected lifecycle method" do
      to_js( 'class Foo<Stimulus; def modalOutletDisconnected(outlet); end; end' ).
        must_include 'static outlets = ["modal"]'
    end

    it "should not override explicit outlets" do
      result = to_js( 'class Foo<Stimulus; self.outlets = ["dialog"]; def bar(); hasModalOutlet; end; end' )
      result.must_include 'static outlets = '
      result.must_include '"dialog"'
      result.must_include '"modal"'
    end
  end

  describe "inheritance" do
    it "must inherit element property" do
      to_js( 'class Base<Stimulus; end; class Foo< Base; def clear(); element.textContent = ""; end; end' ).
        must_include 'this.element.textContent = ""'
    end
  end

  describe "modules" do
    it "imports from Stimulus" do
      to_js_esm( 'class Foo<Stimulus::Controller; end' ).
        must_equal 'import { Controller } from "@hotwired/stimulus"; ' +
          'class Foo extends Controller {}'
    end
  end

  describe "method definitions" do
    it "should generate methods not getters for all defs" do
      result = to_js('class Foo<Stimulus; def connect; end; def greet; end; end')
      # Both should be methods with parentheses, not getters
      result.must_include 'connect()'
      result.must_include 'greet()'
      result.wont_include 'get connect'
      result.wont_include 'get greet'
    end

    it "should call class methods with this. and parentheses" do
      result = to_js('class Foo<Stimulus; def greet; scroll_to_bottom; end; def scroll_to_bottom; end; end')
      # Internal method call should have this. prefix and parentheses
      result.must_include 'this.scroll_to_bottom()'
    end

    it "should handle methods calling other methods" do
      result = to_js('class Foo<Stimulus; def a; b; c; end; def b; end; def c; end; end')
      result.must_include 'this.b()'
      result.must_include 'this.c()'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Stimulus" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Stimulus
    end
  end
end
