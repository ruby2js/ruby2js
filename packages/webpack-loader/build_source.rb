#!/usr/bin/env ruby

require "fileutils"
require_relative "./rb2js.config"

source = "src"
dir = "_ruby2js_build"

if Dir.exist?(dir)
  FileUtils.rm_r dir
end

Dir.mkdir dir 

files = Dir["#{source}/**/*.js.rb"]

Dir.chdir(dir) do
  files.each do |ruby_file|
    FileUtils.mkdir_p(File.dirname(ruby_file))

    ruby_code = File.read(File.expand_path(ruby_file, "../"))
    js_code = Ruby2JS::Loader.process(ruby_code)

    File.write(ruby_file.chomp(".rb"), js_code)
  end
end
