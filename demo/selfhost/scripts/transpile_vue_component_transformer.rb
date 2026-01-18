#!/usr/bin/env ruby
# Transpile VueComponentTransformer from Ruby to JavaScript for selfhost use

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

require 'ruby2js'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/camelCase'
require 'ruby2js/filter/selfhost'
require 'ruby2js/filter/pragma'

source_file = File.expand_path('../../../lib/ruby2js/vue_component_transformer.rb', __dir__)
source = File.read(source_file)

# Remove the module Ruby2JS wrapper - extract just the class
source = source.sub(/\A.*?^module Ruby2JS\n/m, '')
source = source.sub(/^end\s*\z/, '')
# Remove the leading indentation (2 spaces)
source = source.gsub(/^  /, '')

# Replace Struct.new with a simple class-based approach that transpiles cleanly
# Result = Struct.new(:sfc, :script, :template, :imports, :errors, keyword_init: true)
source = source.sub(
  /Result = Struct\.new\(:sfc, :script, :template, :imports, :errors, keyword_init: true\)/,
  <<~RUBY.strip
    def self.Result(sfc: nil, script: nil, template: nil, imports: nil, errors: nil)
      {sfc: sfc, script: script, template: template, imports: imports, errors: errors}
    end
  RUBY
)

# Replace Result.new(...) with just Result(...)
source = source.gsub(/Result\.new\(/, 'Result(')

# Remove require for vue_template_compiler - we'll import it instead
source = source.gsub(/require ['"]ruby2js\/vue_template_compiler['"]/, '')

js = Ruby2JS.convert(source,
  eslevel: 2022,
  autoexports: true,
  filters: [
    Ruby2JS::Filter::Selfhost::Core,
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM,
    Ruby2JS::Filter::CamelCase,
    Ruby2JS::Filter::Pragma
  ]
).to_s

# Add imports for dependencies
# Note: Filters must be imported to register with Ruby2JS.Filter
imports = <<~JS
import { convert, ast_node as astNode, parse } from '../ruby2js.js';
import { Ruby2JS } from '../ruby2js.js';
import { VueTemplateCompiler } from './vue_template_compiler.mjs';
import '../filters/sfc.js';
import '../filters/camelCase.js';

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

# Fix Result() calls - need class prefix in JS (VueComponentTransformer.Result)
# But don't modify the static method definition itself
js = js.gsub(/return Result\(/, 'return VueComponentTransformer.Result(')

# Fix Array.from().dup() - use spread instead
js = js.gsub(/Array\.from\(([^)]+)\)\.dup\(\)/, '[...\1]')
js = js.gsub(/Array\(([^)]+)\)\.dup\(\)/, '[...\1]')

# Fix Object iteration - Ruby's Hash#each becomes for..of which doesn't work on plain objects
# Convert: for (let [k, v] of ClassName.CONSTANT) → for (let [k, v] of Object.entries(ClassName.CONSTANT))
js = js.gsub(/for \(let \[(\w+), (\w+)\] of (VueComponentTransformer\.LIFECYCLE_HOOKS)\)/) do
  "for (let [#{$1}, #{$2}] of Object.entries(#{$3}))"
end

# Note: export is handled by autoexports: true option

puts js
