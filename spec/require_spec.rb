require 'minitest/autorun'
require 'ruby2js/filter/require'

describe Ruby2JS::Filter::Require do

  def to_js_bare(string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Require],
      file: __FILE__)
  end

  def to_js(string)
    _(to_js_bare(string).to_s)
  end

  describe :statement do
    it "should handle require statements" do
      to_js( 'require "require/test1.rb"' ).
        must_equal 'console.log("test2"); console.log("test3")'
    end

    it "should support implicit '.rb' extensions" do
      to_js( 'require "require/test1"' ).
        must_equal 'console.log("test2"); console.log("test3")'
    end

    it "should process each file only once" do
      to_js( 'require "require/test6"' ).
        must_equal 'console.log("test2"); console.log("test3"); console.log("test6")'
    end

    it "should skip requires with Pragma: skip comment" do
      # test8_skip.rb has: require 'json' # Pragma: skip
      # followed by: require_relative 'test2'
      # The 'json' require should be skipped entirely, test2 should be inlined
      to_js( 'require "require/test8_skip"' ).
        must_equal 'console.log("test2")'
    end
  end
  
  describe :timestamps do
    it "should gather timestamps from require statements" do
      timestamps = to_js_bare( 'require "require/test1.rb"' ).timestamps
      test1 = File.expand_path('../require/test1.rb', __FILE__)
      test2 = File.expand_path('../require/test2.rb', __FILE__)
      test3 = File.expand_path('../require/test3.js.rb', __FILE__)

      _(timestamps.keys.length).must_equal 4
      _(timestamps[__FILE__]).must_equal File.mtime(__FILE__)
      _(timestamps[test1]).must_equal File.mtime(test1)
      _(timestamps[test2]).must_equal File.mtime(test2)
      _(timestamps[test3]).must_equal File.mtime(test3)
    end
  end

  describe :expression do
    it "should leave local variable assignment expressions alone" do
      to_js( 'fs = require("fs")' ).
        must_equal 'let fs = require("fs")'
    end

    it "should leave constant assignment expressions alone" do
      to_js( 'React = require("React")' ).
        must_equal 'const React = require("React")'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Require" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Require
    end
  end
end
