gem 'minitest'
require 'minitest/autorun'

describe "ES2021 support" do
  
  def to_js( string)
    _(Ruby2JS.convert(string, eslevel: 2021, filters: []).to_s)
  end

  def to_js_fn( string)
    _(Ruby2JS.convert(string, eslevel: 2021,
      filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  def to_js_logical( string)
    _(Ruby2JS.convert(string, eslevel: 2021, or: :logical, filters: []).to_s)
  end

  it "should do short circuit assign - nullish (default)" do
    to_js( 'a = nil; a ||= 1').must_equal 'let a = null; a ??= 1'
    to_js( '@a ||= 1').must_equal 'this._a ??= 1'
    to_js( '@@a ||= 1').must_equal 'this.constructor._a ??= 1'
    to_js( 'self.p ||= 1').must_equal 'this.p ??= 1'
    to_js( 'a[i] ||= 1').must_equal 'a[i] ??= 1'
  end

  it "should do short circuit assign - logical" do
    to_js_logical( 'a = nil; a ||= 1').must_equal 'let a = null; a ||= 1'
    to_js_logical( '@a ||= 1').must_equal 'this._a ||= 1'
    to_js_logical( '@@a ||= 1').must_equal 'this.constructor._a ||= 1'
    to_js_logical( 'self.p ||= 1').must_equal 'this.p ||= 1'
    to_js_logical( 'a[i] ||= 1').must_equal 'a[i] ||= 1'
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

  it "should convert gsub to replaceAll" do
    to_js_fn( 'x.gsub("a", "b")' ).must_equal 'x.replaceAll("a", "b")'
    to_js_fn( 'x.gsub(/a/, "b")' ).must_equal 'x.replaceAll(/a/g, "b")'
  end

  it "should convert 'a = b if a.nil?' to nullish assignment" do
    to_js( 'a = b if a.nil?' ).must_equal 'a ??= b'
    to_js( '@a = b if @a.nil?' ).must_equal 'this._a ??= b'
    to_js( '@@a = b if @@a.nil?' ).must_equal 'this.constructor._a ??= b'
    to_js( 'self.foo = b if self.foo.nil?' ).must_equal 'this.foo ??= b'
    to_js( 'a[i] = b if a[i].nil?' ).must_equal 'a[i] ??= b'
  end

end
