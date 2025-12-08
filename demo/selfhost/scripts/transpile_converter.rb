#!/usr/bin/env ruby
# Transpile the Ruby2JS converter to JavaScript

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

require 'ruby2js'
require 'ruby2js/filter/combiner'
require 'ruby2js/filter/pragma'
require 'ruby2js/filter/require'
require 'ruby2js/filter/selfhost'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'

# For now, just try transpiling the main converter.rb
converter_file = File.expand_path('../../../lib/ruby2js/converter.rb', __dir__)
source = File.read(converter_file)

# Workaround: Remove non-pragma comments that cause issues with extended regex handling
# The transpiler sometimes confuses Ruby comments with extended regex comments
source = source.gsub(/^(\s*)#(?!\s*Pragma:)(.*)$/) do |match|
  indent = $1
  # Keep the line but make it empty (preserves line numbers)
  "#{indent}"
end

js = Ruby2JS.convert(source,
  eslevel: 2022,
  comparison: :identity,
  underscored_private: true,
  file: converter_file,
  filters: [
    Ruby2JS::Filter::Pragma,
    Ruby2JS::Filter::Combiner,
    Ruby2JS::Filter::Require,
    Ruby2JS::Filter::Selfhost::Core,
    Ruby2JS::Filter::Selfhost::Walker,
    Ruby2JS::Filter::Selfhost::Converter,
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM
  ]
).to_s

# Add preamble for ES module compatibility
preamble = <<~JS
// Preamble: Ruby built-ins needed by the transpiled converter
class NotImplementedError extends Error {
  constructor(message) {
    super(message);
    this.name = 'NotImplementedError';
  }
}

// Export the Ruby2JS module
export const
JS

puts preamble + js
