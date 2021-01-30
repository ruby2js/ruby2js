gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/return'

describe Ruby2JS::Filter::Return do
  
  def to_js( string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Return]).to_s)
  end
  
  describe :lambda do
    it "should handle no line lambdas" do
      to_js( 'lambda {|x|}' ).must_equal 'function(x) {return null}'
    end

    it "should handle single line lambdas" do
      to_js( 'lambda {|x| x}' ).must_equal 'function(x) {return x}'
    end

    it "should handle multi line lambdas" do
      to_js( 'lambda {|x| x; x}' ).must_equal 'function(x) {x; return x}'
    end
  end
  
  describe :proc do
    it "should handle no line procs" do
      to_js( 'Proc.new {|x|}' ).must_equal 'function(x) {return null}'
    end

    it "should handle single line procs" do
      to_js( 'Proc.new {|x| x}' ).must_equal 'function(x) {return x}'
    end

    it "should handle multi line procs" do
      to_js( 'Proc.new {|x| x; x}' ).must_equal 'function(x) {x; return x}'
    end
  end
  
  describe :def do
    it "should handle no line definitions" do
      to_js( 'def f(x) end' ).must_equal 'function f(x) {return null}'
    end

    it "should handle single line definitions" do
      to_js( 'def f(x) x; end' ).must_equal 'function f(x) {return x}'
    end

    it "should handle multi line definitions" do
      to_js( 'def f(x) x; x; end' ).must_equal 'function f(x) {x; return x}'
    end

    it "should skip constructor" do
      to_js( 'class X; def initialize(x) x; end; end' ).must_equal 'function X(x) {x}'
      to_js( 'class X; def constructor(x) x; end; end' ).must_equal 'function X() {}; X.prototype.constructor = function(x) {x}'
    end
  end

  describe :defs do
    it "should handle no line definitions" do
      to_js( 'class C; def self.f(x) end; end' ).
        must_equal 'function C() {}; C.f = function(x) {return null}'
    end

    it "should handle single line definitions" do
      to_js( 'class C; def self.f(x) x; end; end' ).
        must_equal 'function C() {}; C.f = function(x) {return x}'
    end

    it "should handle multi line definitions" do
      to_js( 'class C; def self.f(x) x; x; end; end' ).
        must_equal 'function C() {}; C.f = function(x) {x; return x}'
    end
  end

  describe 'data types' do
    it "should handle integers" do
      to_js( 'lambda {|x| 1}' ).must_equal 'function(x) {return 1}'
    end

    it "should handle floats" do
      to_js( 'lambda {|x| 1.2}' ).must_equal 'function(x) {return 1.2}'
    end

    it "should handle hashes" do
      to_js( 'lambda {|x| {x:x}}' ).must_equal 'function(x) {return {x: x}}'
    end

    it "should handle arrays" do
      to_js( 'lambda {|x| [x]}' ).must_equal 'function(x) {return [x]}'
    end

    it "should handle method calls" do
      to_js( 'lambda {|x| x+x}' ).must_equal 'function(x) {return x + x}'
    end
  end

  describe 'flow control statements' do
    it "should handle if statements" do
      to_js( 'lambda {|x| if false; a; elsif false; b; else c; end}' ).
        must_equal 'function(x) {if (false) {return a} else if (false) {return b} else {return c}}'
    end

    it "should handle case statements" do
      to_js( 'lambda {|x| case false; when true; a; when false; b; else c; end}' ).
        must_equal 'function(x) {switch (false) {case true: return a; case false: return b; default: return c}}'
    end

    it "should handle case statements without else clause" do
      to_js( 'lambda {|x| case false; when true; a; when false; b; end}' ).
        must_equal 'function(x) {switch (false) {case true: return a; case false: return b}}'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Return" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Return
    end
  end
end
