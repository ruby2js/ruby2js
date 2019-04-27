gem 'minitest'
require 'minitest/autorun'

describe "ES2019 support" do
  
  def to_js( string)
    Ruby2JS.convert(string, eslevel: 2019, filters: []).to_s
  end
  
  def to_js_fn(string)
    Ruby2JS.convert(string, eslevel: 2019,
      filters: [Ruby2JS::Filter::Functions]).to_s
  end
  
  describe :Exception do
    it "should handle rescue without a variable" do
      to_js( 'begin; boom(); rescue; end' ).
        must_equal 'try {boom()} catch {}'
      to_js( 'begin; boom(); rescue; console.log $!; end' ).
        must_equal 'try {boom()} catch ($EXCEPTION) {console.log($EXCEPTION)}'
    end
  end

  describe :Array do
    it "should handle flatten" do
      to_js_fn( 'a.flatten()' ).must_equal 'a.flat(Infinity)'
    end

    it "should handle to_h" do
      to_js_fn( 'a.to_h' ).must_equal 'Object.fromEntries(a)'
    end
  end

  describe :String do
    it "should handle lstrip" do
      to_js_fn( 'a.lstrip()' ).must_equal 'a.trimEnd()'
    end

    it "should handle rstrip" do
      to_js_fn( 'a.rstrip()' ).must_equal 'a.trimStart()'
    end
  end
end
