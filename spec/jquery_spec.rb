require 'minitest/autorun'
require 'ruby2js/filter/jquery'

describe Ruby2JS::Filter::JQuery do
  
  def to_js(string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::JQuery])
  end
  
  def to_js2(string)
    Ruby2JS.convert(string, 
      filters: [Ruby2JS::Filter::JQuery, Ruby2JS::Filter::Functions])
  end

  describe :gvars do
    it "should handle jquery calls" do
      to_js( '$$.("span")' ).must_equal '$("span")'
    end
  end
  
  describe 'array' do
    it "should leave $.each alone" do
      to_js2( 'a = 0; $$.each([1,2,3]) {|n, i| a += n}').
        must_equal 'var a = 0; $.each([1, 2, 3], function(n, i) {a += n})'
    end

    it "should leave jquery.each alone" do
      to_js2( 'a = 0; jQuery.each([1,2,3]) {|n, i| a += n}').
        must_equal 'var a = 0; jQuery.each([1, 2, 3], function(n, i) {a += n})'
    end

    it "should still map each_with_index to forEach" do
      to_js2( 'a = 0; [1,2,3].each_with_index {|n, i| a += n}').
        must_equal 'var a = 0; [1, 2, 3].forEach(function(n, i) {a += n})'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Functions" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::Functions
    end
  end
end
