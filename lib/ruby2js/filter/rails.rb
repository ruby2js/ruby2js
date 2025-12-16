# Rails meta-filter - loads all Rails sub-filters
#
# The Rails filters transform idiomatic Rails code into JavaScript:
# - Model: has_many, belongs_to, validates, callbacks
# - Controller: before_action, params, render, redirect_to
# - Routes: Rails.application.routes.draw, resources
# - Schema: ActiveRecord::Schema.define, create_table
#
# Usage:
#   require 'ruby2js/filter/rails'
#
# Or load individual filters:
#   require 'ruby2js/filter/rails/model'
#   require 'ruby2js/filter/rails/controller'
#   require 'ruby2js/filter/rails/routes'
#   require 'ruby2js/filter/rails/schema'

require 'ruby2js/filter/rails/model'
require 'ruby2js/filter/rails/controller'
require 'ruby2js/filter/rails/routes'
require 'ruby2js/filter/rails/schema'
