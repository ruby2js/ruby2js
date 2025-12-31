# frozen_string_literal: true

require 'rails/generators'
require 'json'
require 'fileutils'

# Use Ruby2js (lowercase 'js') so Rails finds this as 'ruby2js:install'
# rather than 'ruby2_j_s:install'
module Ruby2js
  class InstallGenerator < Rails::Generators::Base
    desc "Set up Ruby2JS/Juntos for transpiling Rails to JavaScript"

    DIST_DIR = 'dist'

    def setup_dist_directory
      empty_directory DIST_DIR
      say_status :create, "#{DIST_DIR}/ directory"
    end

    def create_package_json
      require 'ruby2js/rails/builder'

      package_path = File.join(DIST_DIR, 'package.json')

      if File.exist?(package_path)
        merge_package_json(package_path)
      else
        write_package_json(package_path)
      end
    end

    def install_dependencies
      say_status :run, "npm install in #{DIST_DIR}/"
      inside DIST_DIR do
        run "npm install", verbose: false
      end
    end

    def create_binstub
      binstub_path = "bin/juntos"

      if File.exist?(binstub_path)
        say_status :skip, "bin/juntos already exists"
        return
      end

      binstub_content = <<~RUBY
        #!/usr/bin/env ruby
        # frozen_string_literal: true

        # Juntos - Rails patterns, JavaScript runtimes
        # This binstub delegates to the ruby2js gem's Juntos CLI

        require "bundler/setup"
        require "ruby2js/cli/juntos"

        Ruby2JS::CLI::Juntos.run(ARGV)
      RUBY

      create_file binstub_path, binstub_content
      chmod binstub_path, 0755
    end

    def show_instructions
      say ""
      say "Ruby2JS/Juntos installed!", :green
      say ""
      say "Next steps:"
      say "  bin/juntos build              - Transpile your app"
      say "  bin/juntos dev -d dexie       - Development server (browser)"
      say "  bin/juntos server -d sqlite   - Production server (Node.js)"
      say ""
    end

    private

    def write_package_json(package_path)
      say_status :create, package_path

      app_name = detect_app_name
      package = SelfhostBuilder.generate_package_json(
        app_name: app_name,
        app_root: destination_root
      )
      create_file package_path, JSON.pretty_generate(package) + "\n"
    end

    def merge_package_json(package_path)
      say_status :update, package_path

      existing = JSON.parse(File.read(package_path))
      required = SelfhostBuilder.generate_package_json(
        app_name: existing["name"] || detect_app_name,
        app_root: destination_root
      )

      # Merge dependencies (add missing, don't overwrite existing)
      existing["dependencies"] ||= {}
      required["dependencies"].each do |name, version|
        unless existing["dependencies"].key?(name)
          existing["dependencies"][name] = version
          say_status :add, "dependency: #{name}"
        end
      end

      # Merge optional dependencies
      if required["optionalDependencies"]
        existing["optionalDependencies"] ||= {}
        required["optionalDependencies"].each do |name, version|
          unless existing["optionalDependencies"].key?(name)
            existing["optionalDependencies"][name] = version
            say_status :add, "optional dependency: #{name}"
          end
        end
      end

      # Merge scripts (add missing, don't overwrite existing)
      existing["scripts"] ||= {}
      required["scripts"].each do |name, command|
        unless existing["scripts"].key?(name)
          existing["scripts"][name] = command
          say_status :add, "script: #{name}"
        end
      end

      # Ensure type is module
      existing["type"] ||= "module"

      # Use gsub_file would require the file to exist with specific content
      # Instead, remove and recreate
      remove_file package_path
      create_file package_path, JSON.pretty_generate(existing) + "\n"
    end

    def detect_app_name
      if File.exist?("config/application.rb")
        content = File.read("config/application.rb")
        if content =~ /module\s+(\w+)/
          return $1.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
        end
      end
      File.basename(destination_root).gsub(/[^a-z0-9_-]/i, '_').downcase
    end
  end
end
