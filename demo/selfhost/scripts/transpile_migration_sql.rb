#!/usr/bin/env ruby
# Transpile MigrationSQL from Ruby to JavaScript for selfhost use

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

require 'ruby2js'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'

migration_sql_file = File.expand_path('../../../lib/ruby2js/rails/migration_sql.rb', __dir__)
source = File.read(migration_sql_file)

js = Ruby2JS.convert(source,
  eslevel: 2022,
  autoexports: true,
  autoimports: {
    Inflector: '../ruby2js.js',
    Ruby2JS: '../ruby2js.js'
  },
  filters: [
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM
  ]
).to_s

# Remove incorrect require-based imports that ESM filter generates
js = js.gsub(/^import ["']ruby2js.*["'];\n/, '')

# Extract just the MigrationSQL class from the nested module structure
# Input:  export const Ruby2JS = {Rails: {MigrationSQL: class {...}}}
# Output: export class MigrationSQL {...}
js = js.sub(/^export const Ruby2JS = \{Rails: \{MigrationSQL: class \{/, 'export class MigrationSQL {')
js = js.sub(/\}\}\}\s*$/, '}')

puts js
