# frozen_string_literal: true

require 'optparse'

module Ruby2JS
  module CLI
    module Server
      class << self
        def run(args)
          options = parse_options(args)

          validate_rails_app!
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

          unless File.exist?("package.json")
            abort "Error: package.json not found.\n" \
                  "Run 'ruby2js dev' first to set up the project."
          end
        end

        def ensure_built!
          unless File.directory?("node_modules")
            puts "Installing npm dependencies..."
            system("npm install") || abort("Error: npm install failed")
          end

          unless File.directory?("dist")
            puts "Building application..."
            system("npm run build") || abort("Error: build failed")
          end
        end

        def start_server(options)
          ENV["PORT"] = options[:port].to_s

          if options[:runtime]
            script = "start:#{options[:runtime]}"
            exec("npm", "run", script)
          else
            exec("npm", "run", "start")
          end
        end
      end
    end
  end
end
