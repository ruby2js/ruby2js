# frozen_string_literal: true

require 'ruby2js'

module Ruby2JS
  module Rails
    # Rack middleware that serves Ruby Stimulus controllers as JavaScript.
    #
    # This middleware intercepts requests for Stimulus controller JS files and:
    # 1. Transpiles corresponding .rb files to JavaScript on-the-fly
    # 2. Generates a controllers/index.js manifest that registers all controllers
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
    class StimulusMiddleware
      def initialize(app, options = {})
        @app = app
        @controllers_path = options[:controllers_path]
        @filters = options[:filters] || [:stimulus]
      end

      def call(env)
        path = env['PATH_INFO']

        # Match controllers/index.js - generate manifest
        if path =~ %r{/controllers/index\.js$}
          if controllers_path.exist?
            return [200, js_headers, [generate_manifest]]
          end
        end

        # Match *_controller.js - transpile from .rb if exists
        if path =~ %r{/controllers/(.+_controller)\.js$}
          controller_name = $1
          rb_path = controllers_path.join("#{controller_name}.rb")

          if rb_path.exist?
            begin
              js = Ruby2JS.convert(rb_path.read, filters: @filters)
              return [200, js_headers, [js.to_s]]
            rescue => e
              error_js = "console.error(#{e.message.to_json});"
              return [500, js_headers, [error_js]]
            end
          end
        end

        @app.call(env)
      end

      private

      def controllers_path
        @controllers_path ||= ::Rails.root.join("app/javascript/controllers")
      end

      def js_headers
        { 'Content-Type' => 'application/javascript; charset=utf-8' }
      end

      def generate_manifest
        controllers = discover_controllers

        imports = controllers.map do |identifier, filename, class_name|
          "import #{class_name} from \"./#{filename}.js\""
        end

        registrations = controllers.map do |identifier, filename, class_name|
          "application.register(\"#{identifier}\", #{class_name})"
        end

        <<~JS
          import { application } from "./application"

          #{imports.join("\n")}

          #{registrations.join("\n")}
        JS
      end

      def discover_controllers
        controllers = []

        # Find all .rb controller files
        Dir[controllers_path.join("*_controller.rb")].each do |path|
          filename = File.basename(path, ".rb")           # chat_controller
          identifier = filename.sub(/_controller$/, "")   # chat
          class_name = filename.split('_').map(&:capitalize).join + ""  # ChatController
          controllers << [identifier, filename, class_name]
        end

        # Also include .js controllers (that don't have .rb equivalents)
        Dir[controllers_path.join("*_controller.js")].each do |path|
          filename = File.basename(path, ".js")
          # Skip if we already have a .rb version
          next if controllers_path.join("#{filename}.rb").exist?

          identifier = filename.sub(/_controller$/, "")
          class_name = filename.split('_').map(&:capitalize).join
          controllers << [identifier, filename, class_name]
        end

        controllers.sort_by(&:first)
      end
    end
  end
end
