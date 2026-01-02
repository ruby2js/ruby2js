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
  filters: [
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM
  ]
).to_s

# Add export statement
js = js.sub(/^class MigrationSQL/, 'export class MigrationSQL')

puts js
