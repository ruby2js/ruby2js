#!/usr/bin/env ruby
# Transpile SvelteTemplateCompiler from Ruby to JavaScript for selfhost use

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

require 'ruby2js'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/camelCase'
require 'ruby2js/filter/selfhost'

source_file = File.expand_path('../../../lib/ruby2js/svelte_template_compiler.rb', __dir__)
source = File.read(source_file)

# Remove the module Ruby2JS wrapper - extract just the class
source = source.sub(/\A.*?^module Ruby2JS\n/m, '')
source = source.sub(/^end\s*\z/, '')
# Remove the leading indentation (2 spaces)
source = source.gsub(/^  /, '')

# Replace Struct.new with a simple class-based approach that transpiles cleanly
source = source.sub(
  /Result = Struct\.new\(:template, :errors, :warnings, keyword_init: true\)/,
  <<~RUBY.strip
    def self.Result(template: nil, errors: nil, warnings: nil)
      {template: template, errors: errors, warnings: warnings}
    end
  RUBY
)

# Replace Result.new(...) with just Result(...)
source = source.gsub(/Result\.new\(/, 'Result(')

js = Ruby2JS.convert(source,
  eslevel: 2022,
  autoexports: true,
  filters: [
    Ruby2JS::Filter::Selfhost::Core,
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM,
    Ruby2JS::Filter::CamelCase
  ]
).to_s

# Add imports
# Note: Filters must be imported to register with Ruby2JS.Filter
imports = <<~JS
import { convert } from '../ruby2js.js';
import { Ruby2JS } from '../ruby2js.js';
import '../filters/camelCase.js';
import '../filters/functions.js';

JS

js = imports + js

# Fix require statements - remove them as we handle imports explicitly
js = js.gsub(/require\([^)]+\);\n?/, '')

# Fix Ruby2JS.convert references to use imported convert
js = js.gsub(/Ruby2JS\.convert/, 'convert')

# Fix Hash#fetch calls - Ruby's fetch(key, default) becomes JS's ?? operator
js = js.gsub(/\.fetch\(["':](\w+)["']?,\s*(.+?)\)/) do
  ".#{$1} ?? #{$2}"
end

# Fix Result() calls - need class prefix in JS (SvelteTemplateCompiler.Result)
# But don't modify the static method definition itself
js = js.gsub(/return Result\(/, 'return SvelteTemplateCompiler.Result(')

# Fix Array.from().dup() - use spread instead
js = js.gsub(/Array\.from\(([^)]+)\)\.dup\(\)/, '[...\1]')
js = js.gsub(/Array\(([^)]+)\)\.dup\(\)/, '[...\1]')

# Note: export is handled by autoexports: true option

puts js
