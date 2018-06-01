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
#
# Asset Pipeline:
#
#  Ruby2JS registers ".rbs" (RuBy Script) extension.
#  You can add "ruby_thing.js.rbs" to your javascript folder
#  and '= require ruby_thing' from other js sources.
#
#  (options are not yet supported, but by requiring the appropriate files
#   as shown above, you can configure proejct wide.)
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

    class SprocketProcessor
      def initialize( file)
        @file = file
      end
      def render(context , _)
        context = context.instance_eval { binding } unless context.is_a? Binding
        Ruby2JS.convert(File.read(@file), binding: context).to_s
      end
    end

    class Engine < ::Rails::Engine
      engine_name "ruby2js"

      config.assets.configure do |env|
        env.register_engine '.rbs', SprocketProcessor, mime_type: 'text/javascript', silence_deprecation: true
      end

    end

  end

end
