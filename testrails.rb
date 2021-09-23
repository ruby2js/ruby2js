#!/usr/bin/env ruby
require 'json'

source = ARGV[0]
home = File.expand_path(__dir__)

if not source
  puts 'Usage: '
  Dir.chdir home
  Dir["docs/src/_examples/rails/*.md"].sort.each do |file|
    next if File.basename(file) == 'index.md'
    puts "  #{$PROGRAM_NAME} #{file}"
  end
  exit 1
end

# determine what to install based on the markdown source file name
install = File.basename(source, '.md').gsub('_', ':').gsub('-', '')

# extract instructions from markdown source
source = IO.read(source)
gen = %r{\./bin/rails generate .*}.match(source)
html = /.*`(.*?)`.*?```(?:html|erb)\n(.*?)```/m.match(source)
ruby = /.*`(.*?)`.*?```ruby\n(.*?)```/m.match(source)
link = %r{<(http://localhost:3000/.*?)>}.match(source)
rails = /Rails Version: (\d[.\w]*)/i.match(source)
opts = source[/rails new [-\w]+(.*)/, 1]
run = /## Try it out!\n.*?```\n(.*?)```/m.match(source)

# match the version of rails to the example
if rails
  installed = `gem list '^rails$'`.scan(/\d[.\w]+/)
  version = installed.find {|version| version.start_with? rails[1]}
  rails "Rails version #{version} is not installed" unless version
  rails = "rails _#{version}_"
else
  rails = 'rails'
end

# Create a rails app
system 'rm -rf testrails'
system "#{rails} new testrails#{opts}"
Dir.chdir 'testrails'
system './bin/spring stop'

# install ruby2js and dependencies
add = ["gem 'ruby2js', path: #{home.inspect}, require: 'ruby2js/rails'"]
add << "gem 'stimulus-rails'" if install.include? 'stimulus_webpacker'
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

if ARGV.include? '-w' or ARGV.include? '--watch'
  require 'listen'

  ruby2js = File.realpath(__dir__)

  # extract config
  if File.exist? "#{ruby2js}/testrails/rollup.config.js"
    config = IO.read("#{ruby2js}/testrails/rollup.config.js")
    config = config[/ruby2js\((\{.*?\})\)/m, 1]
  elsif File.exist? "#{ruby2js}/testrails/config/webpack/loaders/ruby2js.js"
    config = IO.read("#{ruby2js}/testrails/config/webpack/loaders/ruby2js.js")
    config = config[/@ruby2js.*?options:\s*(\{.*?\})\s*\}\s*\]/m, 1]
  else
    config = {}
  end

  # convert to Ruby2JS options
  config = eval config
  filters = config.delete(:filters)
  eslevel = config.delete(:eslevel)
  opts = config.map{|name, value| "--#{name}=#{value}"}.join(' ')
  opts += " --es#{eslevel}" if eslevel
  opts += " --filter=#{filters.join(',')}" if filters

  # watch for changes
  controllers = "#{ruby2js}/testrails/app/javascript/controllers"
  elements = "#{ruby2js}/testrails/app/javascript/elements"
  listener = Listen.to(*Dir[controllers, elements]) do |mod, add, rem|
    (mod + add).each do |file|
      source = File.basename(file)
      next unless source.end_with? '.js.rb'
      target = source.sub('.rb', '')

      cmd = "#{ruby2js}/demo/ruby2js.rb #{opts} <#{source} >#{target}"
      system "cd #{File.dirname(file)}; #{cmd}"

      # replace .rb reference in index with .js
      if File.exist? "#{controllers}/index.js"
        index = IO.read("#{controllers}/index.js")
        if index.include? source
          index.gsub! source, target
          IO.write("#{controllers}/index.js", index)
        end
      end
    end
  end

  # remove .rb from require.context call
  if File.exist? "#{elements}/index.js"
    index = IO.read("#{elements}/index.js")
    if index.include? '(\\.rb)?'
      index.gsub! '(\\.rb)?', ''
      IO.write("#{elements}/index.js", index)
    end
  end

  listener.start

  # update everything
  Dir["#{controllers}/*.rb", "#{elements}/*.rb"].each do |file|
    system "touch #{file}"
  end
end

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
(run ? run[1].split("\n") : ['./bin/rails server']).each do |cmd|
  system cmd
end
