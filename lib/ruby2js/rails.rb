# Example usage:
#
#   $ echo "gem 'ruby2js', require: 'ruby2js/rails'" >> Gemfile
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
#  Ruby2JS registers ".rb.js" extension.
#  You can add "ruby_thing.js.rb" to your app/javascript folder
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
      def self.call(template, source)
        "Ruby2JS.convert(#{template.source.inspect}, file: source).to_s"
      end
    end

    ActiveSupport.on_load(:action_view) do
      ActionView::Template.register_template_handler :rb, Template
    end

    class SprocketProcessor
      def initialize(file = nil)
        @file = file
      end
      def render(context , _)
        context = context.instance_eval { binding } unless context.is_a? Binding
        Ruby2JS.convert(File.read(@file), binding: context).to_s
      end
    end

    class Engine < ::Rails::Engine
      engine_name "ruby2js"

      config.app_generators.javascripts true
      config.app_generators.javascript_engine :rb

      config.assets.configure do |env|
        env.register_mime_type 'text/ruby', extensions: ['.js.rb', '.rb']
        env.register_transformer 'text/ruby', 'text/javascript', SprocketProcessor
        env.register_preprocessor 'text/javascript', SprocketProcessor
      end
    end

  end

end
