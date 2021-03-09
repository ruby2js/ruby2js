#!/bin/env ruby
require 'json'

source = ARGV[0]
home = File.expand_path('../..', __dir__)

if not source
  puts 'Usage: '
  Dir['../../docs/src/_examples/rails/*.md'].sort.each do |file|
    puts "  #{$PROGRAM_NAME} #{file}"
  end
  exit 1
end

# determine what to install based on the markdown source file name
install = File.basename(source, '.md').gsub('_', ':').gsub('-', '')

# extract instructions from markdown source
source = IO.read(source)
gen = %r{\./bin/rails generate .*}.match(source)
html = /.*`(.*?)`.*?```html\n(.*?)```/m.match(source)
ruby = /.*`(.*?)`.*?```ruby\n(.*?)```/m.match(source)
link = %r{<(http://localhost:3000/.*?)>}.match(source)

# Create a rails app
system 'rm -rf testrails'
system 'rails new testrails'
Dir.chdir 'testrails'
system './bin/spring stop'

# install ruby2js and dependencies
add = ["gem 'ruby2js', path: #{home.inspect}, require: 'ruby2js/rails'"]
add << "gem 'stimulus-rails'" if install.include? 'stimulus'
IO.write 'Gemfile', "\n" + add.join("\n"), mode: 'a'
system './bin/bundle install'
system "./bin/rails ruby2js:install:#{install}"

# install locally built ruby2js
ruby2js = "#{home}/packages/ruby2js"
version = JSON.parse(IO.read "#{ruby2js}/package.json")['version']
mod = Dir["#{ruby2js}/ruby2js-ruby2js-*#{version}.tgz"].first
system "yarn add #{mod}" if mod

# install locally built webpack-loader
loader = "#{home}/packages/webpack-loader"
version = JSON.parse(IO.read "#{loader}/package.json")['version']
mod = Dir["#{loader}/ruby2js-webpack-loader-*#{version}.tgz"].first
system "yarn add #{mod}" if mod

# create ruby and html sources per markdown
system gen[0]
IO.write html[1], html[2], mode: 'a+' if html
IO.write ruby[1], ruby[2], mode: 'w' if ruby
File.unlink ruby[1].chomp('.rb') if File.exist? ruby[1].chomp('.rb')

# launch browser once server is up and running
require 'net/http'
Thread.new do
  port = link[1][/:(\d+)/, 1].to_i

  # wait for server to start
  60.times do
    sleep 0.5
    begin
      status = Net::HTTP.get_response('0.0.0.0','/',port).code
      break if %(200 404 500).include? status
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT
    end
  end

  # launch browser
  if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
    system "start #{link[1]}"
  elsif RbConfig::CONFIG['host_os'] =~ /darwin/
    system "open #{link[1]}"
  elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
    if ENV['WSLENV'] and not `which wslview`.empty?
      system "wslview #{link[1]}"
    else
      system "xdg-open #{link[1]}"
    end
  end
end

# start server
system './bin/rails server'
