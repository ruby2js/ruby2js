gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/require'

describe Ruby2JS::Filter::Require do
  
  def to_js( string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Require],
      file: __FILE__)
  end
  
  describe :statement do
    it "should handle require statements" do
      to_js( 'require "require/test1.rb"' ).to_s.
        must_equal 'console.log("test2"); console.log("test3")'
    end

    it "should support implicit '.rb' extensions" do
      to_js( 'require "require/test1"' ).to_s.
        must_equal 'console.log("test2"); console.log("test3")'
    end
  end
  
  describe :timestamps do
    it "should gather timestamps from require statements" do
      timestamps = to_js( 'require "require/test1.rb"' ).timestamps
      test1 = File.expand_path('../require/test1.rb', __FILE__)
      test2 = File.expand_path('../require/test2.rb', __FILE__)
      test3 = File.expand_path('../require/test3.js.rb', __FILE__)

      timestamps.keys.length.must_equal 4
      timestamps[__FILE__].must_equal File.mtime(__FILE__)
      timestamps[test1].must_equal File.mtime(test1)
      timestamps[test2].must_equal File.mtime(test2)
      timestamps[test3].must_equal File.mtime(test3)
    end
  end

  describe :expression do
    it "should leave local variable assignment expressions alone" do
      to_js( 'fs = require("fs")' ).to_s.
        must_equal 'var fs = require("fs")'
    end

    it "should leave constant assignment expressions alone" do
      to_js( 'React = require("React")' ).to_s.
        must_equal 'var React = require("React")'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Require" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::Require
    end
  end
end
