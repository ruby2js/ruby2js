gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/es2017'

describe "ES2017 support" do
  
  def to_js(string)
    Ruby2JS.convert(string, 
      filters: [Ruby2JS::Filter::ES2017, Ruby2JS::Filter::Functions]).to_s
  end
  
  describe :Hash do
    it "should convert hash.each_pair" do
      to_js( 'h.each_pair {|k,v| x+=v}' ).
        must_equal 'Object.entries(h).forEach(([k, v]) => {x += v})'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include ES2017" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::ES2017
    end
  end
end
