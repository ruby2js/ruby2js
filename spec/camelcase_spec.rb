gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/camelCase'

describe Ruby2JS::Filter::CamelCase do
  
  def to_js( string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::CamelCase]).to_s)
  end
  
  describe :camelCase do
    it "should handle variables" do
      to_js( 'foo_bar=baz_qux' ).must_equal 'var fooBar = bazQux'
    end

    it "should handle method calls" do
      to_js( 'foo_bar(baz_qux)' ).must_equal 'fooBar(bazQux)'
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
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include CamelCase" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::CamelCase
    end
  end
end
