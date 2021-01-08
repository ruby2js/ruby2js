---
order: 19
title: Node
top_section: Filters
category: node
---

The **Node** filter provides a number of convenience methods and variables which make writing Node scripts feel more like traditional Ruby.

## List of Transformations

{% capture caret %}<sl-icon name="caret-right-fill"></sl-icon>{% endcapture %}

{:.functions-list}
* `` `command` `` {{ caret }} `child_process.execSync("command", {encoding: "utf8"})`
* `ARGV` {{ caret }} `process.argv.slice(2)`
* `__dir__` {{ caret }} `__dirname`
* `Dir.chdir` {{ caret }} `process.chdir`
* `Dir.entries` {{ caret }} `fs.readdirSync`
* `Dir.home` {{ caret }} `os.homedir()`
* `Dir.mkdir` {{ caret }} `fs.mkdirSync`
* `Dir.mktmpdir` {{ caret }} `fs.mkdtempSync`
* `Dir.pwd` {{ caret }} `process.cwd`
* `Dir.rmdir` {{ caret }} `fs.rmdirSync`
* `Dir.tmpdir` {{ caret }} `os.tmpdir()`
* `ENV` {{ caret }} `process.env`
* `__FILE__` {{ caret }} `__filename`
* `File.absolute_path` {{ caret }} `path.resolve`
* `File.absolute_path?` {{ caret }} `path.isAbsolute`
* `File.basename` {{ caret }} `path.basename`
* `File.chmod` {{ caret }} `fs.chmodSync`
* `File.chown` {{ caret }} `fs.chownSync`
* `File.cp` {{ caret }} `fs.copyFileSync`
* `File.dirname` {{ caret }} `path.dirname`
* `File.exist?` {{ caret }} `fs.existsSync`
* `File.extname` {{ caret }} `path.extname`
* `File.join` {{ caret }} `path.join`
* `File.lchmod` {{ caret }} `fs.lchmodSync`
* `File.link` {{ caret }} `fs.linkSync`
* `File.ln` {{ caret }} `fs.linkSync`
* `File.lstat` {{ caret }} `fs.lstatSync`
* `File::PATH_SEPARATOR` {{ caret }} `path.delimiter`
* `File.read` {{ caret }} `fs.readFileSync`
* `File.readlink` {{ caret }} `fs.readlinkSync`
* `File.realpath` {{ caret }} `fs.realpathSync`
* `File.rename` {{ caret }} `fs.renameSync`
* `File::SEPARATOR` {{ caret }} `path.sep`
* `File.stat` {{ caret }} `fs.statSync`
* `File.symlink` {{ caret }} `fs.symlinkSync`
* `File.truncate` {{ caret }} `fs.truncateSync`
* `File.unlink` {{ caret }} `fs.unlinkSync`
* `FileUtils.cd` {{ caret }} `process.chdir`
* `FileUtils.cp` {{ caret }} `fs.copyFileSync`
* `FileUtils.ln` {{ caret }} `fs.linkSync`
* `FileUtils.ln_s` {{ caret }} `fs.symlinkSync`
* `FileUtils.mkdir` {{ caret }} `fs.mkdirSync`
* `FileUtils.mv` {{ caret }} `fs.renameSync`
* `FileUtils.pwd` {{ caret }} `process.cwd`
* `FileUtils.rm` {{ caret }} `fs.unlinkSync`
* `IO.read` {{ caret }} `fs.readFileSync`
* `IO.write` {{ caret }} `fs.writeFileSync`
* `system` {{ caret }} `child_process.execSync(..., {stdio: "inherit"})`

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/node_spec.rb).
{% endrendercontent %}
