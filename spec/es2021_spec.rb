gem 'minitest'
require 'minitest/autorun'

describe "ES2021 support" do
  
  def to_js( string)
    _(Ruby2JS.convert(string, eslevel: 2021, filters: []).to_s)
  end

  def to_js_nullish( string)
    _(Ruby2JS.convert(string, eslevel: 2021, or: :nullish, filters: []).to_s)
  end

  it "should do short circuit assign - logical (default)" do
    to_js( 'a = nil; a ||= 1').must_equal 'let a = null; a ||= 1'
    to_js( '@a ||= 1').must_equal 'this._a ||= 1'
    to_js( '@@a ||= 1').must_equal 'this.constructor._a ||= 1'
    to_js( 'self.p ||= 1').must_equal 'this.p ||= 1'
    to_js( 'a[i] ||= 1').must_equal 'a[i] ||= 1'
  end

  it "should do short circuit assign - nullish" do
    to_js_nullish( 'a = nil; a ||= 1').must_equal 'let a = null; a ??= 1'
    to_js_nullish( '@a ||= 1').must_equal 'this._a ??= 1'
    to_js_nullish( '@@a ||= 1').must_equal 'this.constructor._a ??= 1'
    to_js_nullish( 'self.p ||= 1').must_equal 'this.p ??= 1'
    to_js_nullish( 'a[i] ||= 1').must_equal 'a[i] ??= 1'
  end

  it "should do short circuit and" do
    to_js( 'a = nil; a &&= 1').must_equal 'let a = null; a &&= 1'
    to_js( '@a &&= 1').must_equal 'this._a &&= 1'
    to_js( '@@a &&= 1').must_equal 'this.constructor._a &&= 1'
    to_js( 'self.p &&= 1').must_equal 'this.p &&= 1'
    to_js( 'a[i] &&= 1').must_equal 'a[i] &&= 1'
  end

  it "should format large numbers with separators" do
    to_js( '1000000' ).must_equal '1_000_000'
    to_js( '1000000.000001' ).must_equal '1_000_000.000_001'
  end
    
end
