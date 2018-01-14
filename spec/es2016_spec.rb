gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/es2016'

describe "ES2016 support" do
  
  def to_js(string)
    Ruby2JS.convert(string, eslevel: 2016, filters: []).to_s
  end
  
  describe :operator do
    it "should parse exponential operators" do
      to_js( '2 ** 0.5' ).must_equal '2 ** 0.5'
    end
  end
end
