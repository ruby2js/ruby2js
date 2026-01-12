# frozen_string_literal: true

require 'optparse'
require 'json'
require 'fileutils'
require 'ruby2js/installer'

module Ruby2JS
  module CLI
    module Install
      DIST_DIR = Ruby2JS::Installer::DIST_DIR

      class << self
        def run(args)
          options = parse_options(args)

          validate_rails_app!

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
            merge_package_json!(package_path)
          else
            write_package_json!(package_path)
          end
        end

        def write_package_json!(package_path)
          puts "Creating #{package_path}..."

          app_name = Installer.detect_app_name(Dir.pwd)
          package = Installer.generate_package_json(
            app_name: app_name,
            app_root: Dir.pwd
          )

          File.write(package_path, JSON.pretty_generate(package) + "\n")
          puts "  Created #{package_path}"
        end

        def merge_package_json!(package_path)
          puts "Updating #{package_path}..."

          existing = JSON.parse(File.read(package_path))
          app_name = Installer.detect_app_name(Dir.pwd)
          required = Installer.generate_package_json(
            app_name: existing["name"] || app_name,
            app_root: Dir.pwd
          )

          added = Installer.merge_package_dependencies(existing, required)

          added.each do |type, name|
            puts "  Added #{type}: #{name}"
          end

          File.write(package_path, JSON.pretty_generate(existing) + "\n")
        end

        def create_vite_config!(options)
          config_path = File.join(DIST_DIR, 'vite.config.js')

          if File.exist?(config_path)
            puts "  vite.config.js already exists, skipping"
            return
          end

          database = options[:database] || Installer.detect_database(Dir.pwd)
          target = options[:target] || 'browser'

          config_content = Installer.generate_vite_config(database: database, target: target)

          File.write(config_path, config_content)
          puts "  Created vite.config.js"
        end

        def install_dependencies!
          puts "Installing npm dependencies in #{DIST_DIR}/..."
          Dir.chdir(DIST_DIR) do
            system("npm install") || abort("Error: npm install failed")
          end
        end

        def create_binstub!
          binstub_path = "bin/juntos"

          if File.exist?(binstub_path)
            puts "  bin/juntos already exists, skipping"
            return
          end

          FileUtils.mkdir_p("bin")
          File.write(binstub_path, Installer.generate_binstub)
          File.chmod(0755, binstub_path)
          puts "  Created bin/juntos"
        end
      end
    end
  end
end
