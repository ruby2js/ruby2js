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
          create_package_json!
          install_dependencies!
          create_binstub!

          puts "Installation complete."
          puts "  Run 'bin/juntos build' to transpile your app"
          puts "  Run 'bin/juntos dev' to start the development server"
        end

        private

        def parse_options(args)
          options = {}

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: ruby2js install [options]"
            opts.separator ""
            opts.separator "Set up dist/ directory with package.json and npm dependencies."
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

        def setup_dist_directory!
          FileUtils.mkdir_p(DIST_DIR)
          puts "Created #{DIST_DIR}/ directory"
        end

        def create_package_json!
          package_path = File.join(DIST_DIR, 'package.json')

          if File.exist?(package_path)
            merge_package_json!(package_path)
          else
            write_package_json!(package_path)
          end
        end

        def write_package_json!(package_path)
          puts "Creating #{package_path}..."

          app_name = detect_app_name
          package = SelfhostBuilder.generate_package_json(
            app_name: app_name,
            app_root: Dir.pwd
          )
          File.write(package_path, JSON.pretty_generate(package) + "\n")

          puts "  Created #{package_path}"
        end

        def merge_package_json!(package_path)
          puts "Updating #{package_path}..."

          existing = JSON.parse(File.read(package_path))
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

          File.write(package_path, JSON.pretty_generate(existing) + "\n")
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
