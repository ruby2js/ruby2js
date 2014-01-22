gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/return'

describe Ruby2JS::Filter::Return do
  
  def to_js( string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Return])
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

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Return" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::Return
    end
  end
end
