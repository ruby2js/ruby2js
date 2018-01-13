gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/es2016'

describe "ES2016 support" do
  
  def to_js(string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::ES2016]).to_s
  end
  
  describe :operator do
    it "should parse exponential operators" do
      to_js( '2 ** 0.5' ).must_equal '2 ** 0.5'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include ES2016" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::ES2016
    end
  end
end
