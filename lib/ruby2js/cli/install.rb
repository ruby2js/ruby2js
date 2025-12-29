# frozen_string_literal: true

require 'optparse'
require 'json'
require 'yaml'

module Ruby2JS
  module CLI
    module Install
      class << self
        def run(args)
          options = parse_options(args)

          validate_rails_app!
          ensure_package_json!
          install_dependencies!

          puts "Installation complete."
        end

        private

        def parse_options(args)
          options = {}

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: ruby2js install [options]"
            opts.separator ""
            opts.separator "Set up package.json and install npm dependencies."
            opts.separator ""
            opts.separator "Options:"

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

          unless File.exist?("config/database.yml")
            abort "Error: config/database.yml not found.\n" \
                  "This file is required to determine the database adapter."
          end
        end

        def ensure_package_json!
          if File.exist?("package.json")
            merge_package_json!
          else
            create_package_json!
          end
        end

        def create_package_json!
          puts "Creating package.json..."

          app_name = detect_app_name
          adapters = collect_adapters

          package = generate_package_json(app_name, adapters)
          File.write("package.json", JSON.pretty_generate(package) + "\n")

          puts "  Created package.json"
        end

        def merge_package_json!
          puts "Updating package.json..."

          existing = JSON.parse(File.read("package.json"))
          adapters = collect_adapters
          required = generate_package_json(existing["name"] || detect_app_name, adapters)

          # Merge dependencies (add missing, don't overwrite existing)
          existing["dependencies"] ||= {}
          required["dependencies"].each do |name, version|
            unless existing["dependencies"].key?(name)
              existing["dependencies"][name] = version
              puts "  Added dependency: #{name}"
            end
          end

          # Merge optional dependencies
          if required["optionalDependencies"]
            existing["optionalDependencies"] ||= {}
            required["optionalDependencies"].each do |name, version|
              unless existing["optionalDependencies"].key?(name)
                existing["optionalDependencies"][name] = version
                puts "  Added optional dependency: #{name}"
              end
            end
          end

          # Merge scripts (add missing, don't overwrite existing)
          existing["scripts"] ||= {}
          required["scripts"].each do |name, command|
            unless existing["scripts"].key?(name)
              existing["scripts"][name] = command
              puts "  Added script: #{name}"
            end
          end

          # Ensure type is module
          existing["type"] ||= "module"

          File.write("package.json", JSON.pretty_generate(existing) + "\n")
        end

        def install_dependencies!
          puts "Installing npm dependencies..."
          system("npm install") || abort("Error: npm install failed")
        end

        def detect_app_name
          if File.exist?("config/application.rb")
            content = File.read("config/application.rb")
            if content =~ /module\s+(\w+)/
              return $1.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
            end
          end
          File.basename(Dir.pwd).gsub(/[^a-z0-9_-]/i, '_').downcase
        end

        def load_database_config
          YAML.load_file("config/database.yml", aliases: true) rescue YAML.load_file("config/database.yml")
        rescue => e
          warn "Warning: Could not parse config/database.yml: #{e.message}"
          { "development" => { "adapter" => "dexie" } }
        end

        def collect_adapters
          database_config = load_database_config
          database_config.values
            .select { |v| v.is_a?(Hash) }
            .map { |v| v["adapter"] }
            .compact
            .uniq
        end

        def generate_package_json(app_name, adapters)
          deps = {
            "ruby2js-rails" => "https://www.ruby2js.com/releases/ruby2js-rails-beta.tgz"
          }

          optional_deps = {}

          adapters.each do |adapter|
            case adapter.to_s
            when "dexie"
              deps["dexie"] = "^4.0.10"
            when "sqljs"
              deps["sql.js"] = "^1.11.0"
            when "pglite"
              deps["@electric-sql/pglite"] = "^0.2.0"
            when "sqlite3", "better_sqlite3"
              optional_deps["better-sqlite3"] = "^11.0.0"
            when "pg"
              optional_deps["pg"] = "^8.13.0"
            when "mysql", "mysql2"
              optional_deps["mysql2"] = "^3.11.0"
            end
          end

          server_adapters = %w[sqlite3 better_sqlite3 pg mysql mysql2]

          scripts = {
            "dev" => "ruby2js-rails-dev",
            "dev:ruby" => "ruby2js-rails-dev --ruby",
            "build" => "ruby2js-rails-build",
            "start" => "npx serve -s dist -p 3000"
          }

          if adapters.any? { |a| server_adapters.include?(a.to_s) }
            scripts["start:node"] = "ruby2js-rails-server"
            scripts["start:bun"] = "bun node_modules/ruby2js-rails/server.mjs"
            scripts["start:deno"] = "deno run --allow-all node_modules/ruby2js-rails/server.mjs"
          end

          package = {
            "name" => app_name.to_s.gsub("_", "-"),
            "version" => "0.1.0",
            "type" => "module",
            "description" => "Rails-like app powered by Ruby2JS",
            "scripts" => scripts,
            "dependencies" => deps
          }

          package["optionalDependencies"] = optional_deps unless optional_deps.empty?

          package
        end
      end
    end
  end
end
