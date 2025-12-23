#!/usr/bin/env ruby
# Publish script for Ruby2JS-on-Rails demo
# Creates a tarball that depends on ruby2js-rails npm package
# Users run: curl ... | tar xz && cd ruby2js-on-rails && npm install && npm run dev

require 'fileutils'
require 'json'

SELFHOST_DIR = File.expand_path('..', __dir__)
DEMO_DIR = File.expand_path('../../ruby2js-on-rails', __dir__)
DIST_DIR = File.join(SELFHOST_DIR, 'dist')
OUTPUT_DIR = File.join(DIST_DIR, 'ruby2js-on-rails')

# Ensure clean output
FileUtils.rm_rf(OUTPUT_DIR)
FileUtils.mkdir_p(OUTPUT_DIR)

puts "=== Publishing Ruby2JS-on-Rails Demo ==="
puts ""
puts "Source: #{DEMO_DIR}"
puts "Output: #{OUTPUT_DIR}"
puts ""

# 1. Copy user app (Ruby source)
puts "Copying user app..."
%w[app config db].each do |dir|
  src = File.join(DEMO_DIR, dir)
  dest = File.join(OUTPUT_DIR, dir)
  if File.exist?(src)
    FileUtils.cp_r(src, dest)
    puts "  #{dir}/"
  end
end
puts ""

# 2. Copy static files
puts "Copying static files..."
%w[index.html README.md favicon.ico].each do |file|
  src = File.join(DEMO_DIR, file)
  if File.exist?(src)
    FileUtils.cp(src, File.join(OUTPUT_DIR, file))
    puts "  #{file}"
  end
end
puts ""

# 3. Copy public directory (CSS, static assets)
public_src = File.join(DEMO_DIR, 'public')
if File.exist?(public_src)
  puts "Copying public assets..."
  FileUtils.cp_r(public_src, File.join(OUTPUT_DIR, 'public'))
  puts "  public/"
  puts ""
end

# 4. Copy bin directory
puts "Copying bin scripts..."
bin_src = File.join(DEMO_DIR, 'bin')
bin_dest = File.join(OUTPUT_DIR, 'bin')
FileUtils.cp_r(bin_src, bin_dest)
# Ensure scripts are executable
Dir.glob(File.join(bin_dest, '*')).each do |script|
  FileUtils.chmod(0755, script)
end
puts "  bin/dev"
puts "  bin/rails"
puts ""

# 5. Generate package.json (depends on ruby2js-rails npm package)
# All build/dev/server scripts are provided by ruby2js-rails bin commands
puts "Generating package.json..."
package_json = {
  "name" => "ruby2js-on-rails",
  "version" => "0.1.0",
  "type" => "module",
  "description" => "Rails-like web app powered by Ruby2JS - write Ruby, run JavaScript",
  "scripts" => {
    "dev" => "ruby2js-rails-dev",
    "dev:node" => "DATABASE=better_sqlite3 npm run build && ruby2js-rails-server",
    "dev:bun" => "DATABASE=better_sqlite3 RUNTIME=bun npm run build && bun node_modules/ruby2js-rails/server.mjs",
    "dev:deno" => "DATABASE=better_sqlite3 RUNTIME=deno npm run build && deno run --allow-all node_modules/ruby2js-rails/server.mjs",
    "build" => "ruby2js-rails-build",
    "start" => "npx serve -p 3000",
    "start:node" => "ruby2js-rails-server",
    "start:bun" => "bun node_modules/ruby2js-rails/server.mjs",
    "start:deno" => "deno run --allow-all node_modules/ruby2js-rails/server.mjs"
  },
  "dependencies" => {
    "ruby2js-rails" => "https://www.ruby2js.com/releases/ruby2js-rails-beta.tgz",
    "dexie" => "^4.0.10",
    "better-sqlite3" => "^11.0.0"
  },
  "engines" => {
    "node" => ">=22.0.0"
  }
}
File.write(File.join(OUTPUT_DIR, 'package.json'), JSON.pretty_generate(package_json) + "\n")
puts "  package.json"
puts ""

# 6. Create tarball
puts "Creating tarball..."
tarball_path = File.join(DIST_DIR, 'ruby2js-on-rails.tar.gz')
Dir.chdir(DIST_DIR) do
  system('tar', '-czf', 'ruby2js-on-rails.tar.gz', 'ruby2js-on-rails')
end
puts "  #{tarball_path}"
puts ""

# Report file count and size
file_count = Dir.glob(File.join(OUTPUT_DIR, '**/*')).count { |f| File.file?(f) }
tarball_size = File.size(tarball_path)
puts "=== Publish Complete ==="
puts ""
puts "  Files: #{file_count}"
puts "  Tarball: #{(tarball_size / 1024.0).round(1)} KB"
puts ""
puts "To test the published demo:"
puts ""
puts "  cd #{DIST_DIR}"
puts "  tar -xzf ruby2js-on-rails.tar.gz"
puts "  cd ruby2js-on-rails"
puts "  npm install"
puts "  npm run dev"
puts ""
