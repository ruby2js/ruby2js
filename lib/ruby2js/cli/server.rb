# frozen_string_literal: true

require 'optparse'

module Ruby2JS
  module CLI
    module Server
      DIST_DIR = 'dist'

      class << self
        def run(args)
          options = parse_options(args)

          validate_rails_app!
          check_installation!
          ensure_built!

          start_server(options)
        end

        private

        def parse_options(args)
          options = {
            port: 3000,
            runtime: nil
          }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: ruby2js server [options]"
            opts.separator ""
            opts.separator "Start a production server for Rails-like apps."
            opts.separator ""
            opts.separator "Options:"

            opts.on("-p", "--port PORT", Integer, "Port to run the server on (default: 3000)") do |port|
              options[:port] = port
            end

            opts.on("--runtime RUNTIME", %w[node bun deno], "Runtime for server adapters (node/bun/deno)") do |runtime|
              options[:runtime] = runtime
            end

            opts.on("-h", "--help", "Show this help message") do
              puts opts
              exit
            end
          end

          parser.parse!(args)
          options
        end

        def validate_rails_app!
          unless File.directory?("app") && File.directory?("config")
            abort "Error: Not a Rails-like application directory.\n" \
                  "Run this command from your Rails application root."
          end
        end

        def check_installation!
          package_json = File.join(DIST_DIR, 'package.json')
          node_modules = File.join(DIST_DIR, 'node_modules')

          unless File.exist?(package_json)
            abort "Error: #{package_json} not found.\n" \
                  "Run 'ruby2js install' first to set up the project."
          end

          unless File.directory?(node_modules)
            abort "Error: #{node_modules} not found.\n" \
                  "Run 'ruby2js install' first."
          end
        end

        def ensure_built!
          # Check if dist has transpiled output (config/routes.js is a good indicator)
          unless File.exist?(File.join(DIST_DIR, 'config/routes.js'))
            puts "Building application..."
            require 'ruby2js/rails/builder'
            SelfhostBuilder.new.build
          end
        end

        def start_server(options)
          ENV["PORT"] = options[:port].to_s

          # Auto-detect runtime from database.yml if not specified
          runtime = options[:runtime]
          unless runtime
            require 'ruby2js/rails/builder'
            config = SelfhostBuilder.detect_runtime
            if config[:target] == 'browser'
              # Browser databases use static file serving (run from dist/)
              Dir.chdir(DIST_DIR) do
                exec("npm", "run", "start")
              end
              return
            end
            runtime = config[:runtime]
          end

          script = "start:#{runtime}"
          Dir.chdir(DIST_DIR) do
            exec("npm", "run", script)
          end
        end
      end
    end
  end
end
