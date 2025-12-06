gem 'minitest'
require 'minitest/autorun'

describe 'use strict' do
  
  def to_js( string)
    _(Ruby2JS.convert(string, strict: true, filters: []).to_s)
  end
  
  describe :strict do
    it "should handle one line scripts" do
      to_js( 'a=1' ).must_equal '"use strict"; let a = 1'
    end

    it "should handle multi statement scripts" do
      to_js( 'a=1; b=1' ).must_equal '"use strict"; let a = 1; let b = 1'
    end

    it "should handle multi line scripts" do
      to_js( "a=1;\nb=1" ).must_equal "\"use strict\";\nlet a = 1;\nlet b = 1"
    end
  end
end
