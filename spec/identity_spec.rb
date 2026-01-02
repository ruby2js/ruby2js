require 'minitest/autorun'

describe 'use strict' do
  
  def to_js( string)
    _(Ruby2JS.convert(string, comparison: :identity, filters: []).to_s)
  end
  
  describe :strict do
    it "should handle equality comparisons" do
      to_js( 'a==1' ).must_equal 'a === 1'
    end

    it "should handle inequality comparisons" do
      to_js( 'a!=1' ).must_equal 'a !== 1'
    end

    it "should leave triple equal alone" do
      to_js( 'a===1' ).must_equal 'a === 1'
    end

    it "should preserve == for null checks (catches both null and undefined)" do
      # x == null is idiomatic JS for checking both null and undefined
      to_js( 'a == nil' ).must_equal 'a == null'
      to_js( 'nil == a' ).must_equal 'null == a'
    end

    it "should preserve != for null checks" do
      to_js( 'a != nil' ).must_equal 'a != null'
      to_js( 'nil != a' ).must_equal 'null != a'
    end
  end
end
