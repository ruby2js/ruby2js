#!/usr/bin/env ruby
# Transpile ErbToJsx converter from Ruby to JavaScript for selfhost use

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

require 'ruby2js'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/camelCase'

source_file = File.expand_path('../../../lib/ruby2js/erb_to_jsx.rb', __dir__)
source = File.read(source_file)

# Remove the module Ruby2JS wrapper - extract just the class
source = source.sub(/\A.*?^module Ruby2JS\n/m, '')
source = source.sub(/^end\s*\z/, '')
# Remove the leading indentation (2 spaces)
source = source.gsub(/^  /, '')

# Remove require statements - we'll handle imports explicitly
source = source.gsub(/require ['"][^'"]+['"]\n?/, '')

# Replace StringScanner.new with a function call
source = source.gsub(/StringScanner\.new\(([^)]+)\)/, 'createScanner(\1)')

# Replace self.convert with static method pattern
source = source.gsub(/def self\.convert/, 'def ErbToJsx.convert')

# Replace new(...) with createInstance(...) to avoid JS keyword
source = source.gsub(/\bnew\(([^)]*)\)/, 'createInstance(\1)')

js = Ruby2JS.convert(source,
  eslevel: 2022,
  autoexports: true,
  filters: [
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM,
    Ruby2JS::Filter::CamelCase
  ]
).to_s

# Add imports for dependencies
imports = <<~JS
import { convert } from '../ruby2js.js';
import '../filters/functions.js';
import '../filters/camelCase.js';
import '../filters/return.js';

JS

# Add StringScanner polyfill
scanner_polyfill = <<~JS

// Simple StringScanner implementation for ERB parsing
class StringScanner {
  constructor(source) {
    this.source = source;
    this.pos = 0;
  }

  get eos() {
    return this.pos >= this.source.length;
  }

  check(pattern) {
    const regex = new RegExp(pattern.source, pattern.flags.replace('g', ''));
    const match = this.source.slice(this.pos).match(regex);
    if (match && match.index === 0) {
      return match[0];
    }
    return null;
  }

  scan(pattern) {
    const regex = new RegExp(pattern.source, pattern.flags.replace('g', ''));
    const match = this.source.slice(this.pos).match(regex);
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

  get getch() {
    if (this.pos >= this.source.length) return null;
    return this.source[this.pos++];
  }
}

function createScanner(source) {
  return new StringScanner(source);
}

JS

js = imports + scanner_polyfill + js

# Fix Ruby2JS.convert references to use imported convert
js = js.gsub(/Ruby2JS\.convert/, 'convert')

# Fix Ruby2JS::Filter::* references
js = js.gsub(/Ruby2JS\.Filter\.(\w+)/, '"\\1"')

# Fix createInstance calls to use new ErbToJsx
js = js.gsub(/createInstance\(([^)]*)\)/, 'new ErbToJsx(\1)')

puts js
