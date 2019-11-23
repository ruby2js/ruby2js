gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/minitest-jasmine'

describe Ruby2JS::Filter::MiniTestJasmine do
  
  def to_js( string, opts={} )
    _(Ruby2JS.convert(string,
      filters: [Ruby2JS::Filter::MiniTestJasmine]).to_s)
  end
  
  describe 'assertions' do
    it "should handle base assertions" do
      to_js( "assert true" ).must_equal 'expect(true).toBeTruthy()'
      to_js( "assert_equal 2, 1+1" ).must_equal 'expect(1 + 1).toBe(2)'
      to_js( "assert_equal a, a" ).must_equal 'expect(a).toEqual(a)'
      to_js( "assert_in_delta 3.1416, Math.PI" ).
        must_equal 'expect(Math.PI).toBeCloseTo(3.1416, 0.001)'
      to_js( "assert_includes [1,2,3], 2" ).
        must_equal 'expect([1, 2, 3]).toContain(2)'
      to_js( "assert_match /z+/, 'xyzzy'" ).
        must_equal 'expect("xyzzy").toMatch(/z+/)'
      to_js( "assert_nil @foo" ).
        must_equal 'expect(this._foo).toBeNull()'
    end

    it "should handle operator assertions" do
      to_js( "assert_operator 1, :<=, 2" ).
        must_equal 'expect(2).toBeGreaterThan(1)'
      to_js( "assert_operator 1, :<, 2" ).
        must_equal 'expect(1).toBeLessThan(2)'
      to_js( "assert_operator 1, :==, 1" ).
        must_equal 'expect(1).toBe(1)'
      to_js( "assert_operator 2, :>, 1" ).
        must_equal 'expect(2).toBeGreaterThan(1)'
      to_js( "assert_operator 2, :>=, 1" ).
        must_equal 'expect(1).toBeLessThan(2)'
    end

    it "should handle base refutions" do
      to_js( "refute true" ).must_equal 'expect(true).toBeFalsy()'
      to_js( "refute_equal 3, 1+1" ).must_equal 'expect(1 + 1).not.toBe(3)'
      to_js( "refute_equal a, a+1" ).must_equal 'expect(a + 1).not.toEqual(a)'
      to_js( "refute_in_delta 3.1416, Math.E" ).
        must_equal 'expect(Math.E).toBeCloseTo(3.1416, 0.001)'
      to_js( "refute_includes [1,2,3], 2" ).
        must_equal 'expect([1, 2, 3]).not.toContain(2)'
      to_js( "'xyzzy'.cant_match /a+/" ).
        must_equal 'expect("xyzzy").not.toMatch(/a+/)'
      to_js( "refute_nil @foo" ).
        must_equal 'expect(this._foo).not.toBeNull()'
    end

    it "should handle operator refutions" do
      to_js( "refute_operator 2, :<=, 1" ).
        must_equal 'expect(2).toBeGreaterThan(1)'
      to_js( "refute_operator 2, :<, 1" ).
        must_equal 'expect(1).not.toBeLessThan(2)'
      to_js( "refute_operator 2, :==, 1" ).
        must_equal 'expect(2).not.toBe(1)'
      to_js( "refute_operator 1, :>, 2" ).
        must_equal 'expect(1).not.toBeGreaterThan(2)'
      to_js( "refute_operator 1, :>=, 2" ).
        must_equal 'expect(1).toBeLessThan(2)'
    end
  end
  
  describe 'expectations' do
    it "should handle must expectations" do
      to_js( "(1+1).must_equal 2" ).must_equal 'expect(1 + 1).toBe(2)'
      to_js( "a.must_equal a" ).must_equal 'expect(a).toEqual(a)'
      to_js( "3.1416.must_be_within_delta Math.PI" ).
        must_equal 'expect(Math.PI).toBeCloseTo(3.1416, 0.001)'
      to_js( "3.1416.must_be_close_to Math.PI" ).
        must_equal 'expect(Math.PI).toBeCloseTo(3.1416, 0.001)'
      to_js( "[1,2,3].must_include 2" ).
        must_equal 'expect([1, 2, 3]).toContain(2)'
      to_js( "'xyzzy'.must_match /z+/" ).
        must_equal 'expect("xyzzy").toMatch(/z+/)'
      to_js( "@foo.must_be_nil" ).
        must_equal 'expect(this._foo).toBeNull()'
    end

    it "should handle must_be operator expectations" do
      to_js( "1.must_be :<=, 2" ).
        must_equal 'expect(2).toBeGreaterThan(1)'
      to_js( "1.must_be :<, 2" ).
        must_equal 'expect(1).toBeLessThan(2)'
      to_js( "1.must_be :==, 1" ).
        must_equal 'expect(1).toBe(1)'
      to_js( "2.must_be :>, 1" ).
        must_equal 'expect(2).toBeGreaterThan(1)'
      to_js( "2.must_be :>=, 1" ).
        must_equal 'expect(1).toBeLessThan(2)'
    end

    it "should handle cant expectations" do
      to_js( "(1+1).cant_equal 3" ).must_equal 'expect(1 + 1).not.toBe(3)'
      to_js( "(a+1).cant_equal a" ).must_equal 'expect(a + 1).not.toEqual(a)'
      to_js( "3.1416.cant_be_within_delta Math.E" ).
        must_equal 'expect(Math.E).toBeCloseTo(3.1416, 0.001)'
      to_js( "3.1416.cant_be_close_to Math.E" ).
        must_equal 'expect(Math.E).toBeCloseTo(3.1416, 0.001)'
      to_js( "[2,4,6].cant_include 3" ).
        must_equal 'expect([2, 4, 6]).not.toContain(3)'
      to_js( "'xyzzy'.cant_match /a+/" ).
        must_equal 'expect("xyzzy").not.toMatch(/a+/)'
      to_js( "@foo.cant_be_nil" ).
        must_equal 'expect(this._foo).not.toBeNull()'
    end

    it "should handle cant_be operator expectations" do
      to_js( "2.cant_be :<=, 1" ).
        must_equal 'expect(2).toBeGreaterThan(1)'
      to_js( "2.cant_be :<, 1" ).
        must_equal 'expect(1).not.toBeLessThan(2)'
      to_js( "2.cant_be :==, 1" ).
        must_equal 'expect(2).not.toBe(1)'
      to_js( "1.cant_be :>, 2" ).
        must_equal 'expect(1).not.toBeGreaterThan(2)'
      to_js( "1.cant_be :>=, 2" ).
        must_equal 'expect(1).toBeLessThan(2)'
    end
  end

  describe "classic test syntax" do
    it "should handle test functions" do
      to_js("class TestMeme < Minitest::Test; " +
        "def test_me; assert_nil nil; end; end").
        must_equal 'describe("TestMeme", function() {it("me", function() ' +
          '{expect(null).toBeNull()})})'
    end

    it "should handle setup and teardown functions" do
      to_js("class TestMeme < Minitest::Test; def setup; @x=1; end; " +
        "def teardown; @x=nil; end; end").
        must_equal 'describe("TestMeme", function() {beforeEach(' +
         'function() {this._x = 1}); afterEach(function() {this._x = null})})'
    end
  end

  describe "behavioral spec syntax" do
    it "should handle describe and it functions" do
      to_js("describe 'test' do; it 'works' do; nil.must_be_nil; end; end").
        must_equal 'describe("test", function() {it("works", function() ' +
          '{expect(null).toBeNull()})})'
    end

    it "should handle before and after functions" do
      to_js("describe 'test' do; before do @x=1; end; " +
        "after do @x=nil; end; end").
        must_equal 'describe("test", function() {beforeEach(function() ' +
          '{this._x = 1}); afterEach(function() {this._x = null})})'
    end
  end
end
