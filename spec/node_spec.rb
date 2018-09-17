gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/node'

describe Ruby2JS::Filter::Functions do
  
  def to_js( string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Node]).to_s
  end
  
  describe 'globals' do
    it 'should handle __FILE__' do
      to_js( '__FILE__' ).must_equal '__filename'
    end

    it 'should handle __dir__' do
      to_js( '__dir__' ).must_equal '__dirname'
    end
  end

  describe 'ARGV' do
    it 'should map ARGV to process.argv' do
      to_js( 'ARGV' ).must_equal 'var ARGV = process.argv.slice(1); ARGV'
    end
  end
  
  describe 'child_process' do
    it 'should handle backtics' do
      to_js('`echo hi`').
        must_equal 'var child_process = require("child_process"); ' +
          'child_process.execSync("echo hi", {encoding: "utf8"})'
    end

    it 'should handle system with single argument' do
      to_js('system "echo hi"').
        must_equal 'var child_process = require("child_process"); ' +
          'child_process.execSync("echo hi", {stdio: "inherit"})'
    end

    it 'should handle system with multiple arguments' do
      to_js('system "echo", "hi"').
        must_equal 'var child_process = require("child_process"); ' +
          'child_process.execFileSync("echo", ["hi"], {stdio: "inherit"})'
    end
  end

  describe 'fs' do
    it 'should handle IO.read' do
      to_js( 'IO.read("foo")' ).
        must_equal 'var fs = require("fs"); fs.readFileSync("foo", "utf8")'
    end

    it 'should handle File.read' do
      to_js( 'File.read("foo")' ).
        must_equal 'var fs = require("fs"); fs.readFileSync("foo", "utf8")'
    end

    it 'should handle IO.write' do
      to_js( 'IO.write("foo", "bar")' ).
        must_equal 'var fs = require("fs"); fs.writeFileSync("foo", "bar")'
    end
  end
  
  describe 'dir' do
    it 'should handle simple Dir.chdir' do
      to_js( 'Dir.chdir("..")' ).must_equal 'process.chdir("..")'
    end

    it 'should handle block Dir.chdir' do
      to_js( 'Dir.chdir("..") {foo()}' ).
        must_equal 'var $oldwd = process.cwd(); try {process.chdir(".."); ' +
          'foo()} finally {process.chdir($oldwd)}'
    end

    it 'should handle Dir.pwd' do
      to_js( 'Dir.pwd' ).must_equal 'process.cwd()'
    end
  end
end
