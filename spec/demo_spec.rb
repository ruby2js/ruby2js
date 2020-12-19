gem 'minitest'
require 'minitest/autorun'
require 'ruby2js'

describe "demo" do

  DEMO = File.expand_path('../demo/ruby2js.rb', __dir__)

  def to_js(string, options=[])
    stdin, stdout, verbose = $stdin, $stdout, $VERBOSE
    $stdout = StringIO.new
    $stdin = StringIO.new(string)
    $VERBOSE = nil
    ARGV.clear
    ARGV.push(*options)
    load DEMO
    _($stdout.string.chomp)
  ensure
    $stdin, $stdout, $VERBOSE = stdin, stdout, verbose
  end

  describe "filters" do
    it "should work without filters" do
      to_js("x = 123; puts x").
        must_equal('var x = 123; puts(x)')
    end

    it "should work with a filter" do
      to_js("x = 123; puts x", %w(--filter functions)).
        must_equal('var x = 123; console.log(x)')
    end
  end

  describe "options" do
    it "should work without options" do
      to_js("x = 123").
        must_equal('var x = 123')
    end

    it "should work with an option" do
      to_js("x = 123", %w(--strict --es2017)).
        must_equal('"use strict"; let x = 123')
    end
  end

  describe "include" do
    it "should work without options" do
      to_js("x.class", %w(--filter functions)).
        must_equal('x.class')
    end

    it "should work with an option" do
      to_js("x.class", %w(--filter functions --include class)).
        must_equal('x.constructor')
    end
  end
end
