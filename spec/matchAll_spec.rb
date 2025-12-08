require 'minitest/autorun'
require 'ruby2js/filter/matchAll'
require 'ruby2js/filter/functions'

describe "matchAll support" do
  
  def to_js(string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::MatchAll]).to_s)
  end
  
  def to_js_fn1(string)
    _(Ruby2JS.convert(string, 
      filters: [Ruby2JS::Filter::Functions, Ruby2JS::Filter::MatchAll]).to_s)
  end
  
  def to_js_2020(string)
    _(Ruby2JS.convert(string, eslevel: 2020,
      filters: [Ruby2JS::Filter::MatchAll]).to_s)
  end

  def to_js_fn2(string)
    _(Ruby2JS.convert(string, 
      filters: [Ruby2JS::Filter::MatchAll, Ruby2JS::Filter::Functions]).to_s)
  end
  
  describe "without filter functions" do
    it "should leave String.matchAll alone for ES2020+" do
      to_js( 'str.matchAll(pattern).forEach {|match| console.log match}' ).
        must_equal 'str.matchAll(pattern).forEach(match => console.log(match))'
    end

    it "should leave String.matchAll alone for ESLevel 2020" do
      to_js_2020( 'str.matchAll(pattern).forEach {|match| console.log match}' ).
        must_equal 'str.matchAll(pattern).forEach(match => console.log(match))'
    end
  end

  describe "with filter functions" do
    it "should convert with filter functions first" do
      to_js_fn1( 'str.matchAll(pattern).each {|match| puts match}' ).
        must_equal 'for (let match of str.matchAll(pattern)) {console.log(match)}'
    end

    it "should convert with filter functions second" do
      to_js_fn2( 'str.matchAll(pattern).each {|match| puts match}' ).
        must_equal 'for (let match of str.matchAll(pattern)) {console.log(match)}'
    end

  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include MatchAll" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::MatchAll
    end
  end
end
