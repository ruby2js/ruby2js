gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/strict'

describe Ruby2JS::Filter::Strict do
  
  def to_js( string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Strict]).to_s
  end
  
  describe :strict do
    it "should handle one line scripts" do
      to_js( 'a=1' ).must_equal '"use strict"; var a = 1'
    end

    it "should handle multi line scripts" do
      to_js( 'a=1; b=1' ).must_equal '"use strict"; var a = 1; var b = 1'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Strict" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::Strict
    end
  end
end
