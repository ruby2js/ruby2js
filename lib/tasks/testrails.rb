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

test = File.basename(source, '.md').gsub('_', ':').gsub('-', '')

source = IO.read(source)

gen = %r{\./bin/rails generate .*}.match(source)
html = /.*`(.*?)`.*?```html\n(.*?)```/m.match(source)
ruby = /.*`(.*?)`.*?```ruby\n(.*?)```/m.match(source)
link = %r{<(http://localhost:3000/.*?)>}.match(source)

system 'rm -rf testrails'
system 'rails new testrails'
Dir.chdir 'testrails'
system './bin/spring stop'

add = ["gem 'ruby2js', path: #{home.inspect}, require: 'ruby2js/rails'"]
add << "gem 'stimulus-rails'" if test.include? 'stimulus'

IO.write 'Gemfile', "\n" + add.join("\n"), mode: 'a'
system './bin/bundle install'
system "./bin/rails ruby2js:install:#{test}"

ruby2js = "#{home}/packages/ruby2js/"
version = JSON.parse(IO.read "#{ruby2js}/package.json")['version']
mod = Dir["#{ruby2js}/ruby2js-ruby2js-*#{version}.tgz"].first
system "yarn add #{mod}" if mod

loader = "#{home}/packages/webpack-loader/"
version = JSON.parse(IO.read "#{loader}/package.json")['version']
mod = Dir["#{loader}/ruby2js-webpack-loader-*#{version}.tgz"].first
system "yarn add #{mod}" if mod

system gen[0]
IO.write html[1], html[2], mode: 'a+' if html
IO.write ruby[1], ruby[2], mode: 'w' if ruby
File.unlink ruby[1].chomp('.rb') if File.exist? ruby[1].chomp('.rb')

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

system './bin/rails server'
