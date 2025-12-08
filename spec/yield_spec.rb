require 'minitest/autorun'
require 'ruby2js/filter/functions'

describe "yield suport" do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2015, filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  describe "yield" do
    it "should add implicit block arg" do
      to_js( 'def func(); puts "yielding:"; yield; end' ).
        must_include 'function func(_implicitBlockYield=null) {console.log("yielding:"); _implicitBlockYield()}'
    end

    it "should work with existing arguments" do
      to_js( 'def func(x); yield; end' ).
        must_include 'function func(x, _implicitBlockYield=null) {_implicitBlockYield()}'
    end

    it "should allow yield arguments" do
      to_js( 'def func(x); yield :sym; end' ).
        must_include 'function func(x, _implicitBlockYield=null) {_implicitBlockYield("sym")}'
    end
  end

  describe "block_given?" do
    it "should check for presence of implicit block" do
      to_js( 'def func(); yield if block_given?; end' ).
        must_include 'function func(_implicitBlockYield=null) {if (_implicitBlockYield) {_implicitBlockYield()}}'
    end
  end

end