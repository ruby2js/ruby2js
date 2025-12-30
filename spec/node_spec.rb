require 'minitest/autorun'
require 'ruby2js/filter/node'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::Node do

  def to_js(string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Node],
    module: :cjs).to_s)
  end

  def to_js_esm(string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Node]).to_s)
  end

  def to_js_async(string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Node],
    async: true).to_s)
  end

  describe 'ARGV' do
    it 'should map ARGV to process.argv' do
      to_js( 'ARGV' ).must_equal 'let ARGV = process.argv.slice(2); ARGV'
    end
  end

  describe 'child_process' do
    it 'should handle backtics' do
      to_js('`echo hi`').
        must_equal 'const child_process = require("node:child_process"); ' +
          'child_process.execSync("echo hi", {encoding: "utf8"})'
      to_js('`echo #{hi}`').
        must_equal 'const child_process = require("node:child_process"); ' +
          'child_process.execSync("echo " + hi, {encoding: "utf8"})'
    end

    it 'should handle system with single argument' do
      to_js('system "echo hi"').
        must_equal 'const child_process = require("node:child_process"); ' +
          'child_process.execSync("echo hi", {stdio: "inherit"})'
    end

    it 'should handle system with multiple arguments' do
      to_js('system "echo", "hi"').
        must_equal 'const child_process = require("node:child_process"); ' +
          'child_process.execFileSync("echo", ["hi"], {stdio: "inherit"})'
    end
  end

  describe 'fs' do
    it 'should handle IO.read' do
      to_js( 'IO.read("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.readFileSync("foo", "utf8")'
    end

    it 'should handle File.read' do
      to_js( 'File.read("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.readFileSync("foo", "utf8")'
    end

    it 'should handle IO.write' do
      to_js( 'IO.write("foo", "bar")' ).
        must_equal 'const fs = require("node:fs"); fs.writeFileSync("foo", "bar")'
    end

    it 'should handle File.chmod' do
      to_js( 'File.chmod(0755, "foo", "bar")' ).
        must_equal 'const fs = require("node:fs"); fs.chmodSync("foo", 0755); ' +
          'fs.chmodSync("bar", 0755)'
    end

    it 'should handle File.lchmod' do
      to_js( 'File.lchmod(0755, "foo", "bar")' ).
        must_equal 'const fs = require("node:fs"); fs.lchmodSync("foo", 0755); ' +
          'fs.lchmodSync("bar", 0755)'
    end

    it 'should handle File.chown' do
      to_js( 'File.chown(0, 0, "foo", "bar")' ).
        must_equal 'const fs = require("node:fs"); fs.chownSync("foo", 0, 0); ' +
          'fs.chownSync("bar", 0, 0)'
    end

    it 'should handle File.lchown' do
      to_js( 'File.lchown(0, 0, "foo", "bar")' ).
        must_equal 'const fs = require("node:fs"); fs.lchownSync("foo", 0, 0); ' +
          'fs.lchownSync("bar", 0, 0)'
    end

    it 'should handle File.exist' do
      to_js( 'File.exist?("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.existsSync("foo")'
    end

    it 'should handle File.directory?' do
      to_js( 'File.directory?("foo")' ).
        must_equal 'const fs = require("node:fs"); ' +
          'fs.existsSync("foo") && fs.statSync("foo").isDirectory()'
    end

    it 'should handle File.file?' do
      to_js( 'File.file?("bar")' ).
        must_equal 'const fs = require("node:fs"); ' +
          'fs.existsSync("bar") && fs.statSync("bar").isFile()'
    end

    it 'should handle File.readlink' do
      to_js( 'File.readlink("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.readlinkSync("foo")'
    end

    it 'should handle File.realpath' do
      to_js( 'File.realpath("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.realpathSync("foo")'
    end

    it 'should handle File.rename' do
      to_js( 'FileUtils.mv("foo", "bar")' ).
        must_equal 'const fs = require("node:fs"); fs.renameSync("foo", "bar")'
      to_js( 'File.rename("foo", "bar")' ).
        must_equal 'const fs = require("node:fs"); fs.renameSync("foo", "bar")'
    end

    it 'should handle File.link' do
      to_js( 'File.link("foo", "bar")' ).
        must_equal 'const fs = require("node:fs"); fs.linkSync("foo", "bar")'
      to_js( 'FileUtils.ln("foo", "bar")' ).
        must_equal 'const fs = require("node:fs"); fs.linkSync("foo", "bar")'
    end

    it 'should handle File.symlink' do
      to_js( 'File.symlink("foo", "bar")' ).
        must_equal 'const fs = require("node:fs"); fs.symlinkSync("foo", "bar")'
      to_js( 'FileUtils.ln_s("foo", "bar")' ).
        must_equal 'const fs = require("node:fs"); fs.symlinkSync("foo", "bar")'
    end

    it 'should handle File.truncate' do
      to_js( 'File.truncate("foo", 0)' ).
        must_equal 'const fs = require("node:fs"); fs.truncateSync("foo", 0)'
    end

    it 'should handle File.stat' do
      to_js( 'File.stat("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.statSync("foo")'
    end

    it 'should handle File.lstat' do
      to_js( 'File.lstat("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.lstatSync("foo")'
    end

    it 'should handle File.unlink' do
      to_js( 'File.unlink("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.unlinkSync("foo")'
      to_js( 'FileUtils.rm("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.unlinkSync("foo")'
    end

    it 'should handle FileUtils.cp' do
      to_js( 'FileUtils.cp("foo", "bar")' ).
        must_equal 'const fs = require("node:fs"); fs.copyFileSync("foo", "bar")'

      to_js( 'FileUtils.copy("foo", "bar")' ).
        must_equal 'const fs = require("node:fs"); fs.copyFileSync("foo", "bar")'
    end

    it 'should handle Dir.mkdir' do
      to_js( 'Dir.mkdir("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.mkdirSync("foo")'
      to_js( 'FileUtils.mkdir("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.mkdirSync("foo")'
    end

    it 'should handle FileUtils.mkdir_p' do
      to_js( 'FileUtils.mkdir_p("foo/bar")' ).
        must_equal 'const fs = require("node:fs"); fs.mkdirSync("foo/bar", {recursive: true})'
    end

    it 'should handle FileUtils.rm_rf' do
      to_js( 'FileUtils.rm_rf("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.rmSync("foo", {recursive: true, force: true})'
    end

    it 'should handle Dir.rmdir' do
      to_js( 'Dir.rmdir("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.rmdirSync("foo")'
      to_js( 'FileUtils.rmdir("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.rmdirSync("foo")'
    end

    it 'should handle Dir.entries' do
      to_js( 'Dir.entries("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.readdirSync("foo")'
    end

    it 'should handle Dir.mktmpdir' do
      to_js( 'Dir.mktmpdir' ).
        must_equal 'const fs = require("node:fs"); fs.mkdtempSync("d")'
      to_js( 'Dir.mktmpdir("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.mkdtempSync("foo")'
    end

    it 'should handle Dir.exist?' do
      to_js( 'Dir.exist?("foo")' ).
        must_equal 'const fs = require("node:fs"); fs.existsSync("foo")'
    end

    it 'should handle Dir.glob' do
      to_js( 'Dir.glob("**/*.rb")' ).
        must_equal 'const fs = require("node:fs"); fs.globSync("**/*.rb")'
    end
  end

  describe 'path' do
    it 'should handle File.absolute_path' do
      to_js( 'File.absolute_path("foo")' ).
        must_equal 'const path = require("node:path"); path.resolve("foo")'
    end

    it 'should handle File.expand_path' do
      to_js( 'File.expand_path("foo")' ).
        must_equal 'const path = require("node:path"); path.resolve("foo")'
    end

    it 'should handle File.absolute_path?' do
      to_js( 'File.absolute_path?("foo")' ).
        must_equal 'const path = require("node:path"); path.isAbsolute("foo")'
    end

    it 'should handle File.basename' do
      to_js( 'File.basename("foo")' ).
        must_equal 'const path = require("node:path"); path.basename("foo")'
    end

    it 'should handle File.dirname' do
      to_js( 'File.dirname("foo")' ).
        must_equal 'const path = require("node:path"); path.dirname("foo")'
    end

    it 'should handle File.extname' do
      to_js( 'File.extname("foo")' ).
        must_equal 'const path = require("node:path"); path.extname("foo")'
    end

    it 'should handle File.join' do
      to_js( 'File.join("foo", "bar")' ).
        must_equal 'const path = require("node:path"); path.join("foo", "bar")'
    end

    it 'should handle Pathname#relative_path_from' do
      to_js( 'Pathname.new(a).relative_path_from(Pathname.new(b))' ).
        must_equal 'const path = require("node:path"); path.relative(b, a)'
    end

    it 'should handle File::PATH_SEPARATOR' do
      to_js( 'File::PATH_SEPARATOR' ).
        must_equal 'const path = require("node:path"); path.delimiter'
    end

    it 'should handle File::SEPARATOR' do
      to_js( 'File::SEPARATOR' ).
        must_equal 'const path = require("node:path"); path.sep'
    end
  end

  describe 'os' do
    it 'should handle Dir.home' do
      to_js( 'Dir.home' ).must_equal 'const os = require("node:os"); os.homedir()'
    end

    it 'should handle Dir.tmpdir' do
      to_js( 'Dir.tmpdir' ).must_equal 'const os = require("node:os"); os.tmpdir()'
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
        must_equal 'import child_process from "node:child_process"; ' +
          'child_process.execSync("echo hi", {stdio: "inherit"})'
    end

    it 'should handle fs' do
      to_js_esm( 'IO.read("foo")' ).
        must_equal 'import fs from "node:fs"; fs.readFileSync("foo", "utf8")'
    end

    it 'should put imports first' do
      to_js_esm( 'ARGV[0] + `echo hi`' ).
        must_equal 'import child_process from "node:child_process"; ' +
          'let ARGV = process.argv.slice(2); ' +
          'ARGV[0] + child_process.execSync("echo hi", {encoding: "utf8"})'
    end
  end

  describe 'async mode' do
    it 'should use fs/promises for File.read' do
      to_js_async( 'File.read("foo")' ).
        must_equal 'import fs from "node:fs/promises"; await fs.readFile("foo", "utf8")'
    end

    it 'should use fs/promises for File.write' do
      to_js_async( 'IO.write("foo", "bar")' ).
        must_equal 'import fs from "node:fs/promises"; await fs.writeFile("foo", "bar")'
    end

    it 'should use fs/promises for FileUtils.mkdir_p' do
      to_js_async( 'FileUtils.mkdir_p("foo/bar")' ).
        must_equal 'import fs from "node:fs/promises"; await fs.mkdir("foo/bar", {recursive: true})'
    end

    it 'should use fs/promises for FileUtils.rm_rf' do
      to_js_async( 'FileUtils.rm_rf("foo")' ).
        must_equal 'import fs from "node:fs/promises"; await fs.rm("foo", {recursive: true, force: true})'
    end

    it 'should use fs/promises for FileUtils.cp' do
      to_js_async( 'FileUtils.cp("foo", "bar")' ).
        must_equal 'import fs from "node:fs/promises"; await fs.copyFile("foo", "bar")'
    end

    it 'should use fs/promises for Dir.entries' do
      to_js_async( 'Dir.entries("foo")' ).
        must_equal 'import fs from "node:fs/promises"; await fs.readdir("foo")'
    end

    it 'should keep existsSync even in async mode' do
      to_js_async( 'File.exist?("foo")' ).
        must_equal 'import fsSync from "node:fs"; fsSync.existsSync("foo")'
    end

    it 'should keep existsSync for Dir.exist? in async mode' do
      to_js_async( 'Dir.exist?("foo")' ).
        must_equal 'import fsSync from "node:fs"; fsSync.existsSync("foo")'
    end

    it 'should use Array.fromAsync for Dir.glob in async mode' do
      to_js_async( 'Dir.glob("**/*.rb")' ).
        must_equal 'import fs from "node:fs/promises"; await Array.fromAsync(fs.glob("**/*.rb"))'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Node" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Node
    end
  end
end
