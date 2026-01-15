# frozen_string_literal: true

require 'rails/generators'
require 'json'
require 'ruby2js/installer'

# Use Ruby2js (lowercase 'js') so Rails finds this as 'ruby2js:install'
# rather than 'ruby2_j_s:install'
module Ruby2js
  class InstallGenerator < Rails::Generators::Base
    desc "Set up Ruby2JS/Juntos for transpiling Rails to JavaScript"

    DIST_DIR = Ruby2JS::Installer::DIST_DIR

    def setup_dist_directory
      empty_directory DIST_DIR
      say_status :create, "#{DIST_DIR}/ directory"
    end

    def create_package_json
      package_path = File.join(DIST_DIR, 'package.json')

      if File.exist?(package_path)
        merge_package_json(package_path)
      else
        write_package_json(package_path)
      end
    end

    def create_vite_config
      config_path = File.join(DIST_DIR, 'vite.config.js')

      if File.exist?(config_path)
        say_status :skip, "vite.config.js already exists"
        return
      end

      database = Ruby2JS::Installer.detect_database(destination_root)
      config_content = Ruby2JS::Installer.generate_vite_config(database: database)

      create_file config_path, config_content
    end

    def install_dependencies
      say_status :run, "npm install in #{DIST_DIR}/"
      inside DIST_DIR do
        # Use verbose: true so npm errors are visible
        run "npm install", verbose: true
      end

      # Verify critical package was installed
      vite_path = File.join(DIST_DIR, 'node_modules', 'vite')
      unless File.directory?(vite_path)
        say_status :error, "npm install may have failed - vite not found", :red
        say "Try running: cd #{DIST_DIR} && npm install"
      end
    end

    def create_binstub
      binstub_path = "bin/juntos"

      if File.exist?(binstub_path)
        say_status :skip, "bin/juntos already exists"
        return
      end

      create_file binstub_path, Ruby2JS::Installer.generate_binstub
      chmod binstub_path, 0755
    end

    def show_instructions
      say ""
      say "Ruby2JS/Juntos installed!", :green
      say ""
      say "Next steps:"
      say "  bin/juntos dev                - Start Vite dev server"
      say "  bin/juntos build              - Build with Vite"
      say "  bin/juntos server             - Production server (Node.js)"
      say ""
    end

    private

    def write_package_json(package_path)
      say_status :create, package_path

      app_name = Ruby2JS::Installer.detect_app_name(destination_root)
      package = Ruby2JS::Installer.generate_package_json(
        app_name: app_name,
        app_root: destination_root
      )

      create_file package_path, JSON.pretty_generate(package) + "\n"
    end

    def merge_package_json(package_path)
      say_status :update, package_path

      existing = JSON.parse(File.read(package_path))
      app_name = Ruby2JS::Installer.detect_app_name(destination_root)
      required = Ruby2JS::Installer.generate_package_json(
        app_name: existing["name"] || app_name,
        app_root: destination_root
      )

      added = Ruby2JS::Installer.merge_package_dependencies(existing, required)

      added.each do |type, name|
        say_status :add, "#{type}: #{name}"
      end

      remove_file package_path
      create_file package_path, JSON.pretty_generate(existing) + "\n"
    end
  end
end
