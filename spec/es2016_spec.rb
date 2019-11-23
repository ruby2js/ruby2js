gem 'minitest'
require 'minitest/autorun'

describe "ES2016 support" do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2016, filters: []).to_s)
  end

  def to_js_fn(string)
    _(Ruby2JS.convert(string, eslevel: 2016,
      filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  describe :operator do
    it "should parse exponential operators" do
      to_js( '2 ** 0.5' ).must_equal '2 ** 0.5'
    end

    it "should support includes for include?" do
      to_js_fn( 'a.include? b' ).must_equal 'a.includes(b)'
    end
  end
end
