#!/usr/bin/env ruby
# Test transpiling each converter handler file individually
# Also tests serializer.rb and converter.rb (without require filter)

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

require 'ruby2js'
require 'ruby2js/filter/pragma'
require 'ruby2js/filter/selfhost'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'

converter_dir = File.expand_path('../../../lib/ruby2js/converter', __dir__)
ruby2js_dir = File.expand_path('../../../lib/ruby2js', __dir__)

# Collect all files to test
handler_files = Dir.glob("#{converter_dir}/*.rb").sort
core_files = [
  "#{ruby2js_dir}/serializer.rb",
  "#{ruby2js_dir}/converter.rb"
]

results = { success: [], failure: [] }

def test_file(file, results, skip_requires: false)
  basename = File.basename(file)
  source = File.read(file)

  # Strip non-pragma comments (workaround for extended regex issue)
  source = source.gsub(/^(\s*)#(?!\s*Pragma:)(.*)$/) { $1 }

  # For core files, skip require_relative statements
  if skip_requires
    source = source.gsub(/^require_relative\s+['"].*['"]$/, '# skipped require')
  end

  begin
    js = Ruby2JS.convert(source,
      eslevel: 2022,
      comparison: :identity,
      underscored_private: true,
      file: file,
      filters: [
        Ruby2JS::Filter::Pragma,
        Ruby2JS::Filter::Selfhost::Core,
        Ruby2JS::Filter::Selfhost::Walker,
        Ruby2JS::Filter::Selfhost::Converter,
        Ruby2JS::Filter::Functions,
        Ruby2JS::Filter::Return,
        Ruby2JS::Filter::ESM
      ]
    ).to_s

    results[:success] << basename
    puts "✓ #{basename} (#{js.lines.count} lines)"
    true
  rescue => e
    results[:failure] << { file: basename, error: e.message.split("\n").first }
    puts "✗ #{basename}: #{e.message.split("\n").first}"
    false
  end
end

puts "Testing handler files..."
handler_files.each do |f|
  begin
    test_file(f, results)
  rescue => e
    results[:failure] << { file: File.basename(f), error: e.message.split("\n").first }
    puts "✗ #{File.basename(f)}: #{e.message.split("\n").first}"
  end
end

puts "\nTesting core files..."
core_files.each do |f|
  begin
    test_file(f, results, skip_requires: true)
  rescue Exception => e
    results[:failure] << { file: File.basename(f), error: e.message.split("\n").first }
    puts "✗ #{File.basename(f)}: #{e.message.split("\n").first}"
  end
end

puts "\n" + "="*60
puts "Summary: #{results[:success].length} success, #{results[:failure].length} failure"
puts "="*60

if results[:failure].any?
  puts "\nFailures:"
  results[:failure].each do |f|
    puts "  #{f[:file]}: #{f[:error]}"
  end
end
