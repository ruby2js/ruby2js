# frozen_string_literal: true

require 'optparse'

module Ruby2JS
  module CLI
    module Dev
      DIST_DIR = 'dist'

      class << self
        def run(args)
          options = parse_options(args)

          validate_rails_app!
          check_installation!

          start_dev_server(options)
        end

        private

        def parse_options(args)
          options = {
            port: 3000,
            open: false,
            selfhost: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: ruby2js dev [options]"
            opts.separator ""
            opts.separator "Start a development server with hot reload for Rails-like apps."
            opts.separator ""
            opts.separator "Options:"

            opts.on("-p", "--port PORT", Integer, "Port to run the dev server on (default: 3000)") do |port|
              options[:port] = port
            end

            opts.on("-e", "--environment ENV", "Rails environment (default: development)") do |env|
              ENV['RAILS_ENV'] = env
            end

            opts.on("-o", "--open", "Open browser automatically") do
              options[:open] = true
            end

            opts.on("--selfhost", "Use JavaScript transpiler instead of Ruby") do
              options[:selfhost] = true
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
                  "Expected to find 'app/' and 'config/' directories.\n\n" \
                  "Run this command from your Rails application root."
          end

          unless File.exist?("config/database.yml")
            abort "Error: config/database.yml not found.\n" \
                  "This file is required to determine the database adapter."
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

        def start_dev_server(options)
          cmd = ["npm", "run", "dev"]
          extra_args = []

          # Default to Ruby transpilation unless --selfhost is specified
          extra_args << "--ruby" unless options[:selfhost]

          # Pass app root so dev server knows where sources are
          extra_args << "--app-root=#{Dir.pwd}"

          # Pass port option through to the dev server
          extra_args << "--port=#{options[:port]}" if options[:port] != 3000

          unless extra_args.empty?
            cmd << "--"
            cmd.concat(extra_args)
          end

          # Open browser if requested
          if options[:open]
            Thread.new do
              sleep 2
              open_browser("http://localhost:#{options[:port]}")
            end
          end

          # Run npm from the dist directory
          Dir.chdir(DIST_DIR) do
            exec(*cmd)
          end
        end

        def open_browser(url)
          case RUBY_PLATFORM
          when /darwin/
            system("open", url)
          when /linux/
            system("xdg-open", url)
          when /mswin|mingw|cygwin/
            system("start", url)
          end
        end
      end
    end
  end
end
