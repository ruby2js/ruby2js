# Example usage:
#
#   Add:
#      gem 'ruby2js'
# to your gemfile and bundle
#  Add:
#  require "ruby2js/haml"
#   to any initializer ot config/application.rb
#
#  Use :ruby2js filter in your templates like
#
#  :ruby2js
#    alert "Hello"
#
# (Note missing brackets: ruby syntax, js sematics)
#
require "haml"

module Ruby2JS
  module Haml::Ruby2JS
    include Haml::Filters::Base
    def render(text)
      converted = Ruby2JS.convert(text).to_s
      "<script type='text/javascript'>\n#{converted}\n</script>"
    end
  end
end
