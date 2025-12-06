gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/node'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::Functions do
  
  def to_js( string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Node],
    module: :cjs).to_s)
  end
  
  def to_js_esm( string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Node]).to_s)
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
      to_js( 'ARGV' ).must_equal 'let ARGV = process.argv.slice(2); ARGV'
    end
  end
  
  describe 'child_process' do
    it 'should handle backtics' do
      to_js('`echo hi`').
        must_equal 'let child_process = require("child_process"); ' +
          'child_process.execSync("echo hi", {encoding: "utf8"})'
      to_js('`echo #{hi}`').
        must_equal 'let child_process = require("child_process"); ' +
          'child_process.execSync("echo " + hi, {encoding: "utf8"})'
    end

    it 'should handle system with single argument' do
      to_js('system "echo hi"').
        must_equal 'let child_process = require("child_process"); ' +
          'child_process.execSync("echo hi", {stdio: "inherit"})'
    end

    it 'should handle system with multiple arguments' do
      to_js('system "echo", "hi"').
        must_equal 'let child_process = require("child_process"); ' +
          'child_process.execFileSync("echo", ["hi"], {stdio: "inherit"})'
    end
  end

  describe 'fs' do
    it 'should handle IO.read' do
      to_js( 'IO.read("foo")' ).
        must_equal 'let fs = require("fs"); fs.readFileSync("foo", "utf8")'
    end

    it 'should handle File.read' do
      to_js( 'File.read("foo")' ).
        must_equal 'let fs = require("fs"); fs.readFileSync("foo", "utf8")'
    end

    it 'should handle IO.write' do
      to_js( 'IO.write("foo", "bar")' ).
        must_equal 'let fs = require("fs"); fs.writeFileSync("foo", "bar")'
    end

    it 'should handle File.chmod' do
      to_js( 'File.chmod(0755, "foo", "bar")' ).
        must_equal 'let fs = require("fs"); fs.chmodSync("foo", 0755); ' +
          'fs.chmodSync("bar", 0755)'
    end

    it 'should handle File.lchmod' do
      to_js( 'File.lchmod(0755, "foo", "bar")' ).
        must_equal 'let fs = require("fs"); fs.lchmodSync("foo", 0755); ' +
          'fs.lchmodSync("bar", 0755)'
    end

    it 'should handle File.chown' do
      to_js( 'File.chown(0, 0, "foo", "bar")' ).
        must_equal 'let fs = require("fs"); fs.chownSync("foo", 0, 0); ' +
          'fs.chownSync("bar", 0, 0)'
    end

    it 'should handle File.lchown' do
      to_js( 'File.lchown(0, 0, "foo", "bar")' ).
        must_equal 'let fs = require("fs"); fs.lchownSync("foo", 0, 0); ' +
          'fs.lchownSync("bar", 0, 0)'
    end

    it 'should handle File.exist' do
      to_js( 'File.exist?("foo")' ).
        must_equal 'let fs = require("fs"); fs.existsSync("foo")'
    end

    it 'should handle File.readlink' do
      to_js( 'File.readlink("foo")' ).
        must_equal 'let fs = require("fs"); fs.readlinkSync("foo")'
    end

    it 'should handle File.realpath' do
      to_js( 'File.realpath("foo")' ).
        must_equal 'let fs = require("fs"); fs.realpathSync("foo")'
    end

    it 'should handle File.rename' do
      to_js( 'FileUtils.mv("foo", "bar")' ).
        must_equal 'let fs = require("fs"); fs.renameSync("foo", "bar")'
      to_js( 'File.rename("foo", "bar")' ).
        must_equal 'let fs = require("fs"); fs.renameSync("foo", "bar")'
    end

    it 'should handle File.link' do
      to_js( 'File.link("foo", "bar")' ).
        must_equal 'let fs = require("fs"); fs.linkSync("foo", "bar")'
      to_js( 'File.ln("foo", "bar")' ).
        must_equal 'let fs = require("fs"); fs.linkSync("foo", "bar")'
      to_js( 'FileUtils.ln("foo", "bar")' ).
        must_equal 'let fs = require("fs"); fs.linkSync("foo", "bar")'
    end

    it 'should handle File.symlink' do
      to_js( 'File.symlink("foo", "bar")' ).
        must_equal 'let fs = require("fs"); fs.symlinkSync("foo", "bar")'
      to_js( 'FileUtils.ln_s("foo", "bar")' ).
        must_equal 'let fs = require("fs"); fs.symlinkSync("foo", "bar")'
    end

    it 'should handle File.truncate' do
      to_js( 'File.truncate("foo", 0)' ).
        must_equal 'let fs = require("fs"); fs.truncateSync("foo", 0)'
    end

    it 'should handle File.stat' do
      to_js( 'File.stat("foo")' ).
        must_equal 'let fs = require("fs"); fs.statSync("foo")'
    end

    it 'should handle File.lstat' do
      to_js( 'File.lstat("foo")' ).
        must_equal 'let fs = require("fs"); fs.lstatSync("foo")'
    end

    it 'should handle File.unlink' do
      to_js( 'File.unlink("foo")' ).
        must_equal 'let fs = require("fs"); fs.unlinkSync("foo")'
      to_js( 'FileUtils.rm("foo")' ).
        must_equal 'let fs = require("fs"); fs.unlinkSync("foo")'
    end

    it 'should handle FileUtils.cp' do
      to_js( 'FileUtils.cp("foo", "bar")' ).
        must_equal 'let fs = require("fs"); fs.copyFileSync("foo", "bar")'

      to_js( 'FileUtils.copy("foo", "bar")' ).
        must_equal 'let fs = require("fs"); fs.copyFileSync("foo", "bar")'
    end

    it 'should handle Dir.mkdir' do
      to_js( 'Dir.mkdir("foo")' ).
        must_equal 'let fs = require("fs"); fs.mkdirSync("foo")'
      to_js( 'FileUtils.mkdir("foo")' ).
        must_equal 'let fs = require("fs"); fs.mkdirSync("foo")'
    end

    it 'should handle Dir.rmdir' do
      to_js( 'Dir.rmdir("foo")' ).
        must_equal 'let fs = require("fs"); fs.rmdirSync("foo")'
      to_js( 'FileUtils.rmdir("foo")' ).
        must_equal 'let fs = require("fs"); fs.rmdirSync("foo")'
    end

    it 'should handle Dir.entries' do
      to_js( 'Dir.entries("foo")' ).
        must_equal 'let fs = require("fs"); fs.readdirSync("foo")'
    end

    it 'should handle Dir.mktmpdir' do
      to_js( 'Dir.mktmpdir' ).
        must_equal 'let fs = require("fs"); fs.mkdtempSync("d")'
      to_js( 'Dir.mktmpdir("foo")' ).
        must_equal 'let fs = require("fs"); fs.mkdtempSync("foo")'
    end
  end
  
  describe 'path' do
    it 'should handle File.absolute_path' do
      to_js( 'File.absolute_path("foo")' ).
        must_equal 'let path = require("path"); path.resolve("foo")'
    end

    it 'should handle File.absolute_path?' do
      to_js( 'File.absolute_path?("foo")' ).
        must_equal 'let path = require("path"); path.isAbsolute("foo")'
    end

    it 'should handle File.basename' do
      to_js( 'File.basename("foo")' ).
        must_equal 'let path = require("path"); path.basename("foo")'
    end

    it 'should handle File.dirname' do
      to_js( 'File.dirname("foo")' ).
        must_equal 'let path = require("path"); path.dirname("foo")'
    end

    it 'should handle File.extname' do
      to_js( 'File.extname("foo")' ).
        must_equal 'let path = require("path"); path.extname("foo")'
    end

    it 'should handle File.join' do
      to_js( 'File.join("foo", "bar")' ).
        must_equal 'let path = require("path"); path.join("foo", "bar")'
    end

    it 'should handle File::PATH_SEPARATOR' do
      to_js( 'File::PATH_SEPARATOR' ).
        must_equal 'let path = require("path"); path.delimiter'
    end

    it 'should handle File::SEPARATOR' do
      to_js( 'File::SEPARATOR' ).
        must_equal 'let path = require("path"); path.sep'
    end
  end

  describe 'os' do
    it 'should handle Dir.home' do
      to_js( 'Dir.home' ).must_equal 'let os = require("os"); os.homedir()'
    end

    it 'should handle Dir.tmpdir' do
      to_js( 'Dir.tmpdir' ).must_equal 'let os = require("os"); os.tmpdir()'
    end
  end

  describe 'process' do
    it 'should handle simple Dir.chdir' do
      to_js( 'Dir.chdir("..")' ).must_equal 'process.chdir("..")'
    end

    it 'should handle block Dir.chdir' do
      to_js( 'Dir.chdir("..") {foo()}' ).
        must_equal 'let $oldwd = process.cwd(); try {process.chdir(".."); ' +
          'foo()} finally {process.chdir($oldwd)}'
    end

    it 'should handle Fileutils.cd' do
      to_js( 'FileUtils.cd("..")' ).must_equal 'process.chdir("..")'
    end

    it 'should handle Dir.pwd' do
      to_js( 'Dir.pwd' ).must_equal 'process.cwd()'
    end

    it 'should handle FileUtils.pwd' do
      to_js( 'FileUtils.pwd' ).must_equal 'process.cwd()'
    end

    it 'should handle exit' do
      to_js( 'exit' ).must_equal 'process.exit()'
    end

    it 'should handle ENV' do
      to_js( 'ENV' ).must_equal 'process.env'
    end

    it 'should handle STDIN' do
      to_js( 'STDIN' ).must_equal 'process.stdin'
      to_js( '$stdin' ).must_equal 'process.stdin'
    end

    it 'should handle STDOUT' do
      to_js( 'STDOUT' ).must_equal 'process.stdout'
      to_js( '$stdout' ).must_equal 'process.stdout'
    end

    it 'should handle STDERR' do
      to_js( 'STDERR' ).must_equal 'process.stderr'
      to_js( '$stderr' ).must_equal 'process.stderr'
    end
  end

  describe 'ruby "builtin" requires' do
    it 'should eat fileutils requires' do
      to_js( 'require "fileutils"' ).must_equal ''
    end

    it 'should eat tmpdir requires' do
      to_js( 'require "tmpdir"' ).must_equal ''
    end
  end

  describe 'esm' do
    it 'should handle child process' do
      to_js_esm('system "echo hi"').
        must_equal 'import child_process from "child_process"; ' +
          'child_process.execSync("echo hi", {stdio: "inherit"})'
    end

    it 'should handle fs' do
      to_js_esm( 'IO.read("foo")' ).
        must_equal 'import fs from "fs"; fs.readFileSync("foo", "utf8")'
    end

    it 'should put imports first' do
      to_js_esm( 'ARGV[0] + `echo hi`' ).
        must_equal 'import child_process from "child_process"; ' + 
          'var ARGV = process.argv.slice(2); ' +
          'ARGV[0] + child_process.execSync("echo hi", {encoding: "utf8"})'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Node" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Node
    end
  end
end
