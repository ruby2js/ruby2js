gem 'minitest'
require 'minitest/autorun'

describe "ES2017 support" do
  
  def to_js_fn(string)
    Ruby2JS.convert(string, eslevel: 2017,
      filters: [Ruby2JS::Filter::Functions]).to_s
  end
  
  describe :Hash do
    it "should convert hash.each_pair" do
      to_js_fn( 'h.each_pair {|k,v| x+=v}' ).
        must_equal 'Object.entries(h).forEach(([k, v]) => {x += v})'
    end
  end
end
