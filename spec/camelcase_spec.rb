gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/camelCase'
require 'ruby2js/filter/lit'
require 'ruby2js/filter/return'

describe Ruby2JS::Filter::CamelCase do
  
  def to_js( string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::CamelCase]).to_s)
  end

  def to_js_with_autoreturn(string)
    require 'ruby2js/filter/return'
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::CamelCase, Ruby2JS::Filter::Return]).to_s)
  end

  def to_js_2020(string)
    _(Ruby2JS.convert(string, eslevel: 2020, filters: [Ruby2JS::Filter::CamelCase]).to_s)
  end


  def to_js_with_lit(string)
    require 'ruby2js/filter/lit'
    _(Ruby2JS.convert(string, eslevel: 2021,
      filters: [Ruby2JS::Filter::CamelCase, Ruby2JS::Filter::Lit]).to_s)
  end
 
  describe :camelCase do
    it "should handle variables" do
      to_js( 'foo_bar=baz_qux' ).must_equal 'let fooBar = bazQux'
    end

    it "should handle method calls" do
      to_js( 'foo_bar(baz_qux)' ).must_equal 'fooBar(bazQux)'
    end

    it "should handle underscore prefixes" do
      to_js( '_foo_bar(_baz_qux)' ).must_equal '_fooBar(_bazQux)'
    end

    it "should handle method calls with suffixes" do
      to_js( 'self.foo_bar!()' ).must_equal 'this.fooBar()'
      to_js( 'self.foo_bar?' ).must_equal 'this.fooBar'
      to_js( 'self.foo_bar = 123' ).must_equal 'this.fooBar = 123'
    end

    it "should handle numbers" do
      to_js( '_foo_bar_123(_baz_qux_456)' ).must_equal '_fooBar123(_bazQux456)'
    end

    it "should handle method definitions" do
      to_js( 'def foo_bar(baz_qux); end' ).
        must_equal 'function fooBar(bazQux) {}'
      to_js( 'def foo_zar?(baz_qux); end' ).
        must_equal 'function fooZar(bazQux) {}'
      to_js( 'def foo_zar!(baz_qux); end' ).
        must_equal 'function fooZar(bazQux) {}'
    end

    it "should handle optional arguments" do
      to_js( 'def foo_bar(baz_qux=nil); end' ).
        must_equal "function fooBar(bazQux=null) {}"
    end

    it "should handle instance method definitions" do
      to_js( 'def instance.foo_bar(baz_qux); end' ).
        must_equal 'instance.fooBar = function(bazQux) {}'
    end

    it "should handle procs" do
      to_js( 'foo_bar {|baz_qux| return 1}' ).
        must_equal 'fooBar(bazQux => 1)'
    end

    it "should handle hashes" do
      to_js( '{foo_bar: 1}' ).must_equal '{fooBar: 1}'
    end

    it "should preserve ivar index access" do
      to_js( '@iv_ar[123]' ).must_equal 'this._ivAr[123]'
    end

    it "should work with autoreturn filter" do
      to_js_with_autoreturn( 'foo_bar(123) {|a_b_c| x }' ).
        must_equal 'fooBar(123, aBC => x)'
    end

    it "should handle lonely operator for ES2020" do
      to_js( 'a_a&.b_b&.c_c' ).must_equal 'aA?.bB?.cC'
    end

    it "should handle kwargs" do
      to_js_2020( 'def meth(arg_one:, arg_two:);end ').must_equal 'function meth({ argOne, argTwo }) {}'
    end

    it "should intelligently handle common exceptions such as innerHTML" do
      to_js( 'x.inner_html' ).must_equal 'x.innerHTML'
      to_js( 'x.inner_html=""' ).must_equal 'x.innerHTML = ""'
      to_js( 'encode_uri_component()' ).must_equal 'encodeURIComponent()'
    end

    it "should not mess with allowed method names" do
      to_js( 'x.is_a?(String)' ).must_equal '(x instanceof String)'
    end

    unless (RUBY_VERSION.split('.').map(&:to_i) <=> [3, 0, 0]) == -1
      it "should handle the => operator" do
        to_js('a_bcd => x_yz').must_equal 'let xYz = aBcd'
      end
    end

    it "should handle Lit element properties" do
      a = to_js_with_lit('class C < LitElement; def initialize; @a_b_c = foo_bar; end; def foo_bar; "y" + @a_b_c || "x"; end; end')
      a.must_include 'static get properties() {return {aBC: {type: Object}}}'
      a.must_include 'constructor() {super(); this.aBC = this.fooBar}'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include CamelCase" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::CamelCase
    end
  end
end
