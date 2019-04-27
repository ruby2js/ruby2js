gem 'minitest'
require 'minitest/autorun'

describe "ES2018 support" do
  
  def to_js(string)
    Ruby2JS.convert(string, eslevel: 2018, filters: []).to_s
  end
  
  def to_js_fn(string)
    Ruby2JS.convert(string, eslevel: 2018,
      filters: [Ruby2JS::Filter::Functions]).to_s
  end
  
  describe :Hash_Spread do
    it "should convert merge to Object spread" do
      to_js_fn( 'a.merge(b)' ).must_equal '{...a, ...b}'
      to_js_fn( 'a.merge(b: 1)' ).must_equal '{...a, b: 1}'
    end
  end

  describe 'keyword arguments' do
    it 'should handle keyword arguments' do
      to_js('def a(q, a:, b: 2, **r); end').
        must_equal('function a(q, { a, b = 2, ...r }) {}')
    end
  end
end
