gem 'minitest'
require 'minitest/autorun'

describe "ES2016 support" do

  def to_js(string, filters=[])
    Ruby2JS.convert(string, eslevel: 2016, filters: filters).to_s
  end

  describe :operator do
    it "should parse exponential operators" do
      to_js( '2 ** 0.5' ).must_equal '2 ** 0.5'
    end

    it "should support includes for include?" do
      filters = [Ruby2JS::Filter::Functions]
      to_js( 'a.include? b', filters).must_equal 'a.includes(b)'
    end
  end
end
