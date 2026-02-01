# Shared filter configurations for spec and filter transpilation
# Used by both build_all.rb and transpile_spec.rb

require 'ruby2js'
require 'ruby2js/filter/combiner'
require 'ruby2js/filter/pragma'
require 'ruby2js/filter/selfhost'
require 'ruby2js/filter/selfhost/filter'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/return'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/node'

# Filters for transpiling spec files
SPEC_FILTERS = [
  Ruby2JS::Filter::Pragma,
  Ruby2JS::Filter::Node,
  Ruby2JS::Filter::Combiner,
  Ruby2JS::Filter::Selfhost::Core,
  Ruby2JS::Filter::Selfhost::Walker,
  Ruby2JS::Filter::Selfhost::Spec,
  Ruby2JS::Filter::Functions,
  Ruby2JS::Filter::Return,
  Ruby2JS::Filter::ESM
].freeze

# Filters for transpiling filter source files
FILTER_FILTERS = [
  Ruby2JS::Filter::Pragma,
  Ruby2JS::Filter::Combiner,
  Ruby2JS::Filter::Selfhost::Filter,
  Ruby2JS::Filter::Selfhost::Core,
  Ruby2JS::Filter::Selfhost::Converter,
  Ruby2JS::Filter::Functions,
  Ruby2JS::Filter::Node,
  Ruby2JS::Filter::Return,
  Ruby2JS::Filter::ESM
].freeze
