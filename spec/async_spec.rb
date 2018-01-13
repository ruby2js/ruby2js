gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/async'
require 'ruby2js/filter/es2015'

describe Ruby2JS::Filter::Async do
  
  def to_js( string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Async]).to_s
  end
  
  def to_js2015( string)
    Ruby2JS.convert(string, 
      filters: [Ruby2JS::Filter::Async, Ruby2JS::Filter::ES2015]).to_s
  end
  
  describe :async do
    it "should handle named functions" do
      to_js( 'async def f(x); end' ).must_equal 'async function f(x) {}'
    end

    it "should handle named methods" do
      to_js( 'class F; async def m(x); end; end' ).
        must_include 'F.prototype.m = async function(x) {}'
    end

    it "should handle multiple named methods" do
      to_js( 'class F; async def m1(x); end; def m2(x); end; end' ).
        must_include '{m1: async function(x) {},'
    end

    it "should handle ES2015 named methods" do
      to_js2015( 'class F; async def m(x); end; end' ).
        must_include 'class F {async m(x) {}}'
    end

    it "should handle class methods" do
      to_js( 'class F; async def self.m(x); end; end' ).
        must_include 'F.m = function(x) {}'
    end

    it "should handle ES2015 class methods" do
      to_js2015( 'class F; async def self.m(x); end; end' ).
        must_equal 'class F {static async m(x) {}}'
    end

    it "should handle instance methods" do
      to_js( 'async def o.m(x); end' ).
        must_include 'o.m = async function(x) {}'
    end

    it "should handle ES2015 instance methods" do
      to_js2015( 'async def o.m(x); end' ).
        must_include 'o.m = async function(x) {}'
    end

    it "should handle lambda functions" do
      to_js( 'async lambda {|x| x}' ).
        must_equal 'async function(x) {return x}'
    end

    it "should handle procs" do
      to_js( 'async proc {|x| x}' ).
        must_equal 'async function(x) {x}'
    end

    it "should handle arrow functions" do
      to_js( 'async -> (x) {x}' ).
        must_equal 'async function(x) {return x}'
    end
  end

  describe :async do
    it "should handle simple method calls" do
      to_js( 'await f(x)' ).must_equal 'await f(x)'
    end

    it "should handle nested method calls" do
      to_js( 'await o.f(x)' ).must_equal 'await o.f(x)'
    end

    it "should handle calls with blocks" do
      to_js( 'await f(x) {|y| y}' ).must_equal 'await f(x, function(y) {y})'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Strict" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::Async
    end
  end
end
