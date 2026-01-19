#!/usr/bin/env ruby
# Transpile ErbPnodeTransformer from Ruby to JavaScript for selfhost use

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

require 'ruby2js'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/camelCase'
require 'ruby2js/filter/selfhost'
require 'ruby2js/filter/pragma'

source_file = File.expand_path('../../../lib/ruby2js/erb_pnode_transformer.rb', __dir__)
source = File.read(source_file)

# Remove the module Ruby2JS wrapper - extract just the class
source = source.sub(/\A.*?^module Ruby2JS\n/m, '')
source = source.sub(/^end\s*\z/, '')
# Remove the leading indentation (2 spaces)
source = source.gsub(/^  /, '')

# Remove require statements - we'll handle imports explicitly
source = source.gsub(/require ['"][^'"]+['"]\n?/, '')

# Replace Struct.new with a simple class-based approach that transpiles cleanly
# Result = Struct.new(:component, :script, :template, :errors, keyword_init: true)
source = source.sub(
  /Result = Struct\.new\(:component, :script, :template, :errors, keyword_init: true\)/,
  <<~RUBY.strip
    def self.Result(component: nil, script: nil, template: nil, errors: nil)
      {component: component, script: script, template: template, errors: errors}
    end
  RUBY
)

# Replace Result.new(...) with just Result(...)
source = source.gsub(/Result\.new\(/, 'Result(')

# Replace StringScanner.new with a function call (will be handled by polyfill)
source = source.gsub(/StringScanner\.new\(([^)]+)\)/, 'createScanner(\1)')

# Replace self.new(args) with createInstance(args) - avoid JavaScript new keyword
source = source.gsub(/\bnew\(([^)]*)\)\.transform/, 'createInstance(\1).transform')

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
imports = <<~JS
import { convert } from '../ruby2js.js';
import '../filters/esm.js';
import '../filters/functions.js';
import '../filters/return.js';
import '../filters/camelCase.js';
import '../filters/react.js';
import '../filters/jsx.js';

JS

js = imports + js

# Fix require statements - remove them as we handle imports explicitly
js = js.gsub(/require\([^)]+\);\n?/, '')

# Fix Ruby2JS.convert references to use imported convert
js = js.gsub(/Ruby2JS\.convert/, 'convert')

# Fix Ruby2JS::Filter::* references - these are registered globally
js = js.gsub(/Ruby2JS\.Filter\.(\w+)/, '"\1"')

# Fix Hash#fetch calls - Ruby's fetch(key, default) becomes JS's ?? operator
js = js.gsub(/\.fetch\(["':](\w+)["']?,\s*(.+?)\)/) do
  ".#{$1} ?? #{$2}"
end

# Fix Result() calls - need class prefix in JS (ErbPnodeTransformer.Result)
js = js.gsub(/return Result\(/, 'return ErbPnodeTransformer.Result(')

# Fix StringScanner - use a simple implementation
# Add StringScanner polyfill at the top after imports
scanner_polyfill = <<~JS

// Simple StringScanner implementation for ERB parsing
class StringScanner {
  constructor(source) {
    this.source = source;
    this.pos = 0;
  }

  eos() {
    return this.pos >= this.source.length;
  }

  check(pattern) {
    const match = this.source.slice(this.pos).match(pattern);
    if (match && match.index === 0) {
      return match[0];
    }
    return null;
  }

  scan(pattern) {
    const match = this.source.slice(this.pos).match(pattern);
    if (match && match.index === 0) {
      this.pos += match[0].length;
      return match[0];
    }
    return null;
  }

  scanUntil(pattern) {
    const rest = this.source.slice(this.pos);
    const match = rest.match(pattern);
    if (match) {
      const end = match.index + match[0].length;
      const result = rest.slice(0, end);
      this.pos += end;
      return result;
    }
    return null;
  }

  getch() {
    if (this.pos >= this.source.length) return null;
    return this.source[this.pos++];
  }
}

function createScanner(source) {
  return new StringScanner(source);
}

JS

js = imports + scanner_polyfill + js.sub(imports, '')

# Fix createInstance calls to use new ErbPnodeTransformer
js = js.gsub(/createInstance\(([^)]*)\)/, 'new ErbPnodeTransformer(\1)')

puts js
