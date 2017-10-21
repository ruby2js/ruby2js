# Example usage:
#
#   $ echo gem 'ruby2js', require: 'ruby2js/rails' > Gemfile
#   $ bundle update
#   $ rails generate controller Say hello
#   $ echo 'alert "Hello world!"' > app/views/say/hello.js.rb
#   $ rails server
#   $ curl http://localhost:3000/say/hello.js
#
# Using an optional filter:
#
#   $ echo 'require "ruby2js/filter/functions"' > config/initializers/ruby2js.rb

require 'ruby2js'

module Ruby2JS
  module Rails
    class Template
      cattr_accessor :default_format
      self.default_format = Mime[:js]
      def self.call(template)
        "Ruby2JS.convert(#{template.source.inspect}).to_s"
      end
    end

    ActionView::Template.register_template_handler :rb, Template
  end

end
