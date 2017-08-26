gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/vue'

describe Ruby2JS::Filter::Vue do
  
  def to_js(string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Vue], scope: self).to_s
  end
  
  describe :createClass do
    it "should create classes" do
      to_js( 'class FooBar<Vue; end' ).
        must_equal 'var FooBar = Vue.component("foo-bar", {})'
    end

    it "should convert initialize methods to data" do
      to_js( 'class Foo<Vue; def initialize(); end; end' ).
        must_include 'data: function() {return {}}'
    end

    it "should initialize, accumulate, and return state" do
      to_js( 'class Foo<Vue; def initialize; @a=1; b=2; @b = b; end; end' ).
        must_include 'data: function() {var $_ = {}; $_.a = 1; ' +
          'var b = 2; $_.b = b; return $_}}'
    end

    it "should collapse instance variable assignments into a return" do
      to_js( 'class Foo<Vue; def initialize; @a=1; @b=2; end; end' ).
        must_include 'data: function() {return {a: 1, b: 2}}'
    end
  end

  describe "Wunderbar/JSX processing" do
    it "should create elements for HTML tags" do
      to_js( 'class Foo<Vue; def render; _a; end; end' ).
        must_include '$h("a")'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include React" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::Vue
    end
  end
end
