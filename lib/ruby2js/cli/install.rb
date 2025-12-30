# frozen_string_literal: true

require 'optparse'
require 'json'

module Ruby2JS
  module CLI
    module Install
      class << self
        def run(args)
          options = parse_options(args)

          validate_rails_app!

          # Load shared builder for package.json generation
          require 'ruby2js/rails/builder'

          ensure_package_json!
          setup_tailwind! if tailwind_rails_detected?
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
          package = SelfhostBuilder.generate_package_json(
            app_name: app_name,
            app_root: Dir.pwd
          )
          File.write("package.json", JSON.pretty_generate(package) + "\n")

          puts "  Created package.json"
        end

        def merge_package_json!
          puts "Updating package.json..."

          existing = JSON.parse(File.read("package.json"))
          required = SelfhostBuilder.generate_package_json(
            app_name: existing["name"] || detect_app_name,
            app_root: Dir.pwd
          )

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

        def tailwind_rails_detected?
          File.exist?("app/assets/tailwind/application.css")
        end

        def setup_tailwind!
          puts "Setting up Tailwind CSS for npm..."

          # Patch CSS to use standard directives (Rails gem uses @import "tailwindcss")
          css_file = "app/assets/tailwind/application.css"
          File.write(css_file, <<~CSS)
            @tailwind base;
            @tailwind components;
            @tailwind utilities;
          CSS
          puts "  Patched #{css_file}"

          # Create tailwind.config.js if it doesn't exist
          unless File.exist?("tailwind.config.js")
            File.write("tailwind.config.js", <<~JS)
              /** @type {import('tailwindcss').Config} */
              module.exports = {
                content: [
                  './app/views/**/*.{erb,html}',
                  './dist/views/**/*.html'
                ],
                theme: {
                  extend: {},
                },
                plugins: [],
              }
            JS
            puts "  Created tailwind.config.js"
          end
        end
      end
    end
  end
end
