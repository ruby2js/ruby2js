# frozen_string_literal: true

require 'optparse'
require 'json'
require 'fileutils'

module Ruby2JS
  module CLI
    module Install
      DIST_DIR = 'dist'

      class << self
        def run(args)
          options = parse_options(args)

          validate_rails_app!

          # Load shared builder for package.json generation
          require 'ruby2js/rails/builder'

          setup_dist_directory!
          create_package_json!(options)
          create_vite_config!(options)
          install_dependencies!
          create_binstub!

          puts "Installation complete."
          puts "  Run 'bin/juntos dev' to start the Vite dev server"
          puts "  Run 'bin/juntos build' to build with Vite"
          puts ""
          puts "Note: You can also use 'rails generate ruby2js:install' for Rails integration."
        end

        private

        def parse_options(args)
          options = {
            database: ENV['JUNTOS_DATABASE'],
            target: ENV['JUNTOS_TARGET']
          }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: ruby2js install [options]"
            opts.separator ""
            opts.separator "Set up dist/ directory with Vite, package.json, and npm dependencies."
            opts.separator ""
            opts.separator "Options:"

            opts.on("-d", "--database ADAPTER", "Database adapter (default: auto-detected from database.yml)") do |db|
              options[:database] = db
            end

            opts.on("-t", "--target TARGET", "Build target: browser, node, electron (default: browser)") do |target|
              options[:target] = target
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

          unless File.exist?("config/database.yml")
            abort "Error: config/database.yml not found.\n" \
                  "This file is required to determine the database adapter."
          end
        end

        def setup_dist_directory!
          FileUtils.mkdir_p(DIST_DIR)
          puts "Created #{DIST_DIR}/ directory"
        end

        def create_package_json!(options)
          package_path = File.join(DIST_DIR, 'package.json')

          if File.exist?(package_path)
            merge_package_json!(package_path, options)
          else
            write_package_json!(package_path, options)
          end
        end

        def write_package_json!(package_path, options)
          puts "Creating #{package_path}..."

          app_name = detect_app_name
          package = SelfhostBuilder.generate_package_json(
            app_name: app_name,
            app_root: Dir.pwd
          )

          # Add Vite dependencies (always included now)
          add_vite_dependencies!(package)

          File.write(package_path, JSON.pretty_generate(package) + "\n")

          puts "  Created #{package_path}"
        end

        def merge_package_json!(package_path, options)
          puts "Updating #{package_path}..."

          existing = JSON.parse(File.read(package_path))
          required = SelfhostBuilder.generate_package_json(
            app_name: existing["name"] || detect_app_name,
            app_root: Dir.pwd
          )

          # Add Vite dependencies (always included now)
          add_vite_dependencies!(required)

          # Merge dependencies (add missing, don't overwrite existing)
          existing["dependencies"] ||= {}
          required["dependencies"].each do |name, version|
            unless existing["dependencies"].key?(name)
              existing["dependencies"][name] = version
              puts "  Added dependency: #{name}"
            end
          end

          # Merge devDependencies
          if required["devDependencies"]
            existing["devDependencies"] ||= {}
            required["devDependencies"].each do |name, version|
              unless existing["devDependencies"].key?(name)
                existing["devDependencies"][name] = version
                puts "  Added devDependency: #{name}"
              end
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

          File.write(package_path, JSON.pretty_generate(existing) + "\n")
        end

        def add_vite_dependencies!(package)
          package["devDependencies"] ||= {}
          package["devDependencies"]["vite"] = "^6.0.0"
          package["devDependencies"]["vite-plugin-ruby2js"] = "*"

          # Add Vite scripts
          package["scripts"] ||= {}
          package["scripts"]["vite"] = "vite"
          package["scripts"]["vite:build"] = "vite build"
          package["scripts"]["vite:preview"] = "vite preview"
        end

        def create_vite_config!(options)
          config_path = File.join(DIST_DIR, 'vite.config.js')

          if File.exist?(config_path)
            puts "  vite.config.js already exists, skipping"
            return
          end

          database = options[:database] || detect_database
          target = options[:target] || 'browser'

          config_content = <<~JS
            import { juntos } from 'ruby2js-rails/vite';

            export default juntos({
              database: '#{database}',
              target: '#{target}',
              appRoot: '..'  // Source files are in parent directory
            });
          JS

          File.write(config_path, config_content)
          puts "  Created vite.config.js"
        end

        def detect_database
          return 'dexie' unless File.exist?("config/database.yml")

          require 'yaml'
          db_config = YAML.load_file("config/database.yml")
          adapter = db_config.dig('development', 'adapter') ||
                    db_config.dig('default', 'adapter')

          case adapter
          when 'postgresql', 'pg' then 'pg'
          when 'mysql2' then 'mysql'
          when 'sqlite3' then 'sqlite'
          else 'dexie'
          end
        end

        def install_dependencies!
          puts "Installing npm dependencies in #{DIST_DIR}/..."
          Dir.chdir(DIST_DIR) do
            system("npm install") || abort("Error: npm install failed")
          end
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

        def create_binstub!
          binstub_path = "bin/juntos"

          # Don't overwrite existing binstub
          if File.exist?(binstub_path)
            puts "  bin/juntos already exists, skipping"
            return
          end

          FileUtils.mkdir_p("bin")

          binstub_content = <<~RUBY
            #!/usr/bin/env ruby
            # frozen_string_literal: true

            # Juntos - Rails patterns, JavaScript runtimes
            # This binstub delegates to the ruby2js gem's Juntos CLI

            require "bundler/setup"
            require "ruby2js/cli/juntos"

            Ruby2JS::CLI::Juntos.run(ARGV)
          RUBY

          File.write(binstub_path, binstub_content)
          File.chmod(0755, binstub_path)
          puts "  Created bin/juntos"
        end
      end
    end
  end
end
