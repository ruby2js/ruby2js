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

    it "should handle lifecycle methods" do
      to_js( 'class Foo<Vue; def updated; console.log "."; end; end' ).
        must_include ', {updated: function() {return console.log(".")}}'
    end

    it "should handle other methods" do
      to_js( 'class Foo<Vue; def clicked; @counter+=1; end; end' ).
        must_include '{methods: {clicked: function() {this.$data.counter++}}}'
    end
  end

  describe "Wunderbar/JSX processing" do
    # https://github.com/vuejs/babel-plugin-transform-vue-jsx#difference-from-react-jsx
    it "should create components" do
      to_js( 'class Foo<Vue; def render; _A; end; end' ).
        must_include '$h(A)'
    end

    it "should create components with properties" do
      to_js( 'class Foo<Vue; def render; _A title: "foo"; end; end' ).
        must_include '$h(A, {props: {title: "foo"}})'
    end

    it "should create elements with event listeners" do
      to_js( 'class Foo<Vue; def render; _A onAlert: self.alert; end; end' ).
        must_include '$h(A, {on: {alert: this.alert}})'
    end

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

    it "should create simple nested elements" do
      to_js( 'class Foo<Vue; def render; _a {_b}; end; end' ).
        must_include '{render: function($h) {return $h("a", [$h("b")])}}'
    end

    it "should handle options with blocks" do
      to_js( 'class Foo<Vue; def render; _a options do _b; end; end; end' ).
        must_include '{render: function($h) ' +
          '{return $h("a", options, [$h("b")])}}'
    end

    it "should create complex nested elements" do
      result = to_js('class Foo<Vue; def render; _a {c="c"; _b c}; end; end')

      result.must_include 'return $h("a", function() {'
      result.must_include 'var $_ = []; var c = "c"; $_.push($h("b", c));'
      result.must_include 'return $_}())'
    end
  end

  describe "map gvars/ivars/cvars to refs/state/prop" do
    it "should map instance variables to state" do
      to_js( 'class Foo<Vue; def method; @x; end; end' ).
        must_include 'this.$data.x'
    end

    it "should map setting instance variables to setting properties" do
      to_js( 'class Foo<Vue; def method; @x=1; end; end' ).
        must_include 'this.$data.x = 1'
    end

    it "should handle parallel instance variables assignment" do
      to_js( 'class Foo<Vue; def method(); @x=@y=1; end; end' ).
        must_include 'this.$data.x = this.$data.y = 1'
    end

    it "should enumerate properties" do
      to_js( 'class Foo<Vue; def render; _span @@x + @@y; end; end' ).
        must_include '{props: ["x", "y"]'
    end

    it "should map class variables to properties" do
      to_js( 'class Foo<Vue; def method; @@x; end; end' ).
        must_include 'this.$props.x'
    end

    it "should not support assigning to class variables" do
      proc { 
        to_js( 'class Foo<Vue; def method; @@x=1; end; end' )
      }.must_raise NotImplementedError
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include vue" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::Vue
    end
  end
end
