# Rails meta-filter - loads all Rails sub-filters
#
# The Rails filters transform idiomatic Rails code into JavaScript:
# - Model: has_many, belongs_to, validates, callbacks
# - Controller: before_action, params, render, redirect_to
# - Routes: Rails.application.routes.draw, resources
# - Migration: ActiveRecord::Migration, create_table, add_column, etc.
# - Seeds: module Seeds with def self.run, auto-imports models
# - Test: describe/it blocks with async AR operations for dual-target tests
# - Logger: Rails.logger.debug/info/warn/error -> console.debug/info/warn/error
# - Helpers: form_for, form_tag, link_to, truncate (for ERB templates)
#
# Usage:
#   require 'ruby2js/filter/rails'
#
# Or load individual filters:
#   require 'ruby2js/filter/rails/model'
#   require 'ruby2js/filter/rails/controller'
#   require 'ruby2js/filter/rails/routes'
#   require 'ruby2js/filter/rails/migration'
#   require 'ruby2js/filter/rails/seeds'
#   require 'ruby2js/filter/rails/test'
#   require 'ruby2js/filter/rails/logger'
#   require 'ruby2js/filter/rails/helpers'

require 'ruby2js/filter/rails/active_record'
require 'ruby2js/filter/rails/model'
require 'ruby2js/filter/rails/controller'
require 'ruby2js/filter/rails/routes'
require 'ruby2js/filter/rails/migration'
require 'ruby2js/filter/rails/seeds'
require 'ruby2js/filter/rails/test'
require 'ruby2js/filter/rails/logger'
require 'ruby2js/filter/rails/helpers'
