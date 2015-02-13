gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/rubyjs'

describe Ruby2JS::Filter::RubyJS do
  
  def to_js( string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::RubyJS])
  end
  
  describe 'conversions' do
    it "should handle strftime" do
      to_js( 'Date.new().strftime("%Y")' ).
        must_equal '_t.strftime(new Date(), "%Y")'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Functions" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::Functions
    end
  end
end
