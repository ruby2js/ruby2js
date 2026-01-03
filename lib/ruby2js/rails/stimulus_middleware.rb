# frozen_string_literal: true

require 'ruby2js'

module Ruby2JS
  module Rails
    # Rack middleware that transpiles Ruby Stimulus controllers to JavaScript.
    #
    # This middleware runs early in the request cycle and ensures all Ruby
    # controller files are transpiled to JavaScript before Propshaft serves them.
    # The generated .js files are placed alongside the .rb files so Propshaft
    # discovers and serves them with proper fingerprinting.
    #
    # Usage in Rails:
    #   # config/application.rb or config/environments/development.rb
    #   config.middleware.use Ruby2JS::Rails::StimulusMiddleware
    #
    # Then place Ruby Stimulus controllers in app/javascript/controllers/:
    #   # app/javascript/controllers/chat_controller.rb
    #   class ChatController < Stimulus::Controller
    #     def connect()
    #       puts "Connected!"
    #     end
    #   end
    #
    # The middleware will generate chat_controller.js alongside the .rb file.
    # Add it to your controllers/index.js:
    #   import ChatController from "./chat_controller"
    #   application.register("chat", ChatController)
    #
    class StimulusMiddleware
      def initialize(app, options = {})
        @app = app
        @controllers_path = options[:controllers_path]
        # Use stimulus + esm filters with autoexports for Rails-compatible output
        @filters = options[:filters] || [:stimulus, :esm]
        @options = { autoexports: :default }.merge(options.except(:filters, :controllers_path))
        @checked = false
      end

      def call(env)
        # Ensure Ruby controllers are transpiled to JS files
        # In development, check on every request; in production, check once
        if !@checked || ::Rails.env.development?
          ensure_controllers_transpiled
          @checked = true
        end

        @app.call(env)
      end

      private

      def ensure_controllers_transpiled
        return unless controllers_path.exist?

        # Transpile any .rb controllers that are newer than their .js counterparts
        Dir[controllers_path.join("*_controller.rb")].each do |rb_path|
          js_path = rb_path.sub(/\.rb$/, '.js')

          if !File.exist?(js_path) || File.mtime(rb_path) > File.mtime(js_path)
            transpile_controller(rb_path, js_path)
          end
        end
      end

      def transpile_controller(rb_path, js_path)
        js = Ruby2JS.convert(File.read(rb_path), filters: @filters, **@options)
        File.write(js_path, js.to_s)
        log(:info, "Ruby2JS: Transpiled #{File.basename(rb_path)} -> #{File.basename(js_path)}")
      rescue => e
        log(:error, "Ruby2JS: Failed to transpile #{rb_path}: #{e.message}")
      end

      def log(level, message)
        if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
          ::Rails.logger.send(level, message)
        elsif level == :error
          warn message
        end
      end

      def controllers_path
        @controllers_path ||= ::Rails.root.join("app/javascript/controllers")
      end
    end
  end
end
