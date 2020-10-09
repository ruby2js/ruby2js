gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/camelCase'

describe Ruby2JS::Filter::CamelCase do
  
  def to_js( string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::CamelCase]).to_s)
  end

  def to_js_with_autoreturn(string)
    require 'ruby2js/filter/return'
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::CamelCase, Ruby2JS::Filter::Return]).to_s)
  end
 
  describe :camelCase do
    it "should handle variables" do
      to_js( 'foo_bar=baz_qux' ).must_equal 'var fooBar = bazQux'
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
    end

    it "should handle optional arguments" do
      to_js( 'def foo_bar(baz_qux=nil); end' ).
        must_equal "function fooBar(bazQux) {if (typeof bazQux === 'undefined') bazQux = null}"
    end

    it "should handle instance method definitions" do
      to_js( 'def instance.foo_bar(baz_qux); end' ).
        must_equal 'instance.fooBar = function(bazQux) {}'
    end

    it "should handle procs" do
      to_js( 'foo_bar {|baz_qux| return 1}' ).
        must_equal 'fooBar(function(bazQux) {return 1})'
    end

    it "should handle hashes" do
      to_js( '{foo_bar: 1}' ).must_equal '{fooBar: 1}'
    end

    it "should work with autoreturn filter" do
      to_js_with_autoreturn( 'foo_bar(123) {|a_b_c| x }' ).
        must_equal 'fooBar(123, function(aBC) {return x})'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include CamelCase" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::CamelCase
    end
  end
end
