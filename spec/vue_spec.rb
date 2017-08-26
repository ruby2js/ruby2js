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
    # https://github.com/vuejs/babel-plugin-transform-vue-jsx#difference-from-react-jsx
    it "should create elements for HTML tags" do
      to_js( 'class Foo<Vue; def render; _a; end; end' ).
        must_include '$h("a")'
    end

    it "should create elements with attributes and text" do
      to_js( 'class Foo<Vue; def render; _a "name", href: "link"; end; end' ).
        must_include '$h("a", {attrs: {href: "link"}}, "name")'
    end

    it "should create elements with DOM Propoerties" do
      to_js( 'class Foo<Vue; def render; _a domPropsTextContent: "name"; end; end' ).
        must_include '$h("a", {domProps: {textContent: "name"}})'
    end

    it "should create elements with event listeners" do
      to_js( 'class Foo<Vue; def render; _a onClick: self.click; end; end' ).
        must_include '$h("a", {on: {click: this.click}})'
    end

    it "should create elements with native event listeners" do
      to_js( 'class Foo<Vue; def render; _a nativeOnClick: self.click; end; end' ).
        must_include '$h("a", {nativeOn: {click: this.click}})'
    end

    it "should create elements with class expressions" do
      to_js( 'class Foo<Vue; def render; _a class: {foo: true}; end; end' ).
        must_include '$h("a", {class: {foo: true}})'
    end

    it "should create elements with style expressions" do
      to_js( 'class Foo<Vue; def render; _a style: {color: "red"}; end; end' ).
        must_include '$h("a", {style: {color: "red"}})'
    end

    it "should create elements with a key value" do
      to_js( 'class Foo<Vue; def render; _a key: "key"; end; end' ).
        must_include '$h("a", {key: "key"})'
    end

    it "should create elements with a ref value" do
      to_js( 'class Foo<Vue; def render; _a ref: "ref"; end; end' ).
        must_include '$h("a", {ref: "ref"})'
    end

    it "should create elements with a refInFor value" do
      to_js( 'class Foo<Vue; def render; _a refInFor: true; end; end' ).
        must_include '$h("a", {refInFor: true})'
    end

    it "should create elements with a slot value" do
      to_js( 'class Foo<Vue; def render; _a slot: "slot"; end; end' ).
        must_include '$h("a", {slot: "slot"})'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include React" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::Vue
    end
  end
end
