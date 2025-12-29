# frozen_string_literal: true

require 'optparse'
require 'json'
require 'yaml'
require 'fileutils'

module Ruby2JS
  module CLI
    module Dev
      class << self
        def run(args)
          options = parse_options(args)

          validate_rails_app!
          ensure_package_json!
          ensure_node_modules!

          start_dev_server(options)
        end

        private

        def parse_options(args)
          options = {
            port: 3000,
            open: false
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

            opts.on("-o", "--open", "Open browser automatically") do
              options[:open] = true
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

        def ensure_package_json!
          return if File.exist?("package.json")

          puts "Creating package.json..."

          app_name = detect_app_name
          database_config = load_database_config
          adapter = database_config.dig("development", "adapter") || "dexie"

          package = generate_package_json(app_name, adapter)
          File.write("package.json", JSON.pretty_generate(package) + "\n")

          puts "  Created package.json with #{adapter} adapter"
        end

        def ensure_node_modules!
          return if File.directory?("node_modules")

          puts "Installing npm dependencies..."
          system("npm install") || abort("Error: npm install failed")
          puts ""
        end

        def start_dev_server(options)
          cmd = ["npm", "run", "dev"]

          # Pass options through to the dev server
          if options[:port] != 3000
            cmd << "--"
            cmd << "--port=#{options[:port]}"
          end

          # Open browser if requested
          if options[:open]
            Thread.new do
              sleep 2
              open_browser("http://localhost:#{options[:port]}")
            end
          end

          exec(*cmd)
        end

        def detect_app_name
          # Try to get from Rails application name
          if File.exist?("config/application.rb")
            content = File.read("config/application.rb")
            if content =~ /module\s+(\w+)/
              return $1.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
            end
          end

          # Fall back to directory name
          File.basename(Dir.pwd).gsub(/[^a-z0-9_-]/i, '_').downcase
        end

        def load_database_config
          YAML.load_file("config/database.yml", aliases: true) rescue YAML.load_file("config/database.yml")
        rescue => e
          warn "Warning: Could not parse config/database.yml: #{e.message}"
          { "development" => { "adapter" => "dexie" } }
        end

        def generate_package_json(app_name, adapter)
          # Determine dependencies based on adapter
          deps = {
            "ruby2js-rails" => "https://www.ruby2js.com/releases/ruby2js-rails-beta.tgz"
          }

          case adapter.to_s
          when "dexie"
            deps["dexie"] = "^4.0.10"
          when "sqljs"
            deps["sql.js"] = "^1.11.0"
          when "pglite"
            deps["@electric-sql/pglite"] = "^0.2.0"
          end

          optional_deps = {}
          case adapter.to_s
          when "better_sqlite3"
            optional_deps["better-sqlite3"] = "^11.0.0"
          when "pg"
            optional_deps["pg"] = "^8.13.0"
          when "mysql", "mysql2"
            optional_deps["mysql2"] = "^3.11.0"
          end

          package = {
            "name" => app_name.gsub("_", "-"),
            "version" => "0.1.0",
            "type" => "module",
            "description" => "Rails-like app powered by Ruby2JS",
            "scripts" => {
              "dev" => "ruby2js-rails-dev",
              "dev:ruby" => "ruby2js-rails-dev --ruby",
              "build" => "ruby2js-rails-build",
              "start" => "npx serve -s -p 3000"
            },
            "dependencies" => deps
          }

          package["optionalDependencies"] = optional_deps unless optional_deps.empty?

          # Add server scripts for server-side adapters
          if %w[better_sqlite3 pg mysql mysql2].include?(adapter.to_s)
            package["scripts"]["start:node"] = "ruby2js-rails-server"
            package["scripts"]["start:bun"] = "bun node_modules/ruby2js-rails/server.mjs"
            package["scripts"]["start:deno"] = "deno run --allow-all node_modules/ruby2js-rails/server.mjs"
          end

          package
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
