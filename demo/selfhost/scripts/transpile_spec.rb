#!/usr/bin/env ruby
# Transpile a Ruby spec file to JavaScript

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

# Shared filter configurations
require_relative 'filter_config'

spec_file = ARGV[0] || raise("Usage: transpile_spec.rb <spec_file>")
source = File.read(spec_file)

# Add skip pragmas to all requires (they're external dependencies)
source = source.gsub(/^(require\s+['"][^'"]*['"])/) do
  "#{$1} # Pragma: skip"
end

js = Ruby2JS.convert(source,
  eslevel: 2022,
  comparison: :identity,
  underscored_private: true,
  file: spec_file,
  filters: SPEC_FILTERS
).to_s

puts js
