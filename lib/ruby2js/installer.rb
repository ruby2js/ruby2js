# frozen_string_literal: true

require 'json'
require 'yaml'
require 'fileutils'
require 'pathname'

module Ruby2JS
  # Shared installer logic for both Rails generator and CLI install command.
  # Provides methods for generating package.json, vite.config.js, and binstubs.
  module Installer
    DIST_DIR = 'dist'

    module_function

    # Generate package.json content with Vite dependencies
    def generate_package_json(app_name:, app_root:)
      require 'ruby2js/rails/builder'

      package = SelfhostBuilder.generate_package_json(
        app_name: app_name,
        app_root: app_root
      )

      add_vite_dependencies(package, app_root: app_root)
      package
    end

    # Add Vite dependencies and scripts to a package hash
    # Uses local file path when running from ruby2js repo, tarball URL otherwise
    def add_vite_dependencies(package, app_root: nil)
      package["devDependencies"] ||= {}
      package["devDependencies"]["vite"] = "^6.0.0"

      # Check for local vite-plugin-ruby2js (when running from ruby2js repo)
      gem_root = File.expand_path("../..", __dir__)
      local_plugin = File.join(gem_root, "packages/vite-plugin-ruby2js")
      dist_dir = File.join(app_root || Dir.pwd, 'dist')

      # Only use local plugin if running from development checkout
      # (gem_root is a parent of the app, not installed in bundle/gems)
      use_local = false
      if File.directory?(local_plugin)
        app_path = Pathname.new(app_root || Dir.pwd).expand_path
        gem_path = Pathname.new(gem_root).expand_path
        use_local = app_path.to_s.start_with?(gem_path.to_s)
      end

      if use_local
        relative_path = Pathname.new(local_plugin).relative_path_from(Pathname.new(dist_dir))
        package["devDependencies"]["vite-plugin-ruby2js"] = "file:#{relative_path}"
      else
        package["devDependencies"]["vite-plugin-ruby2js"] = "https://www.ruby2js.com/releases/vite-plugin-ruby2js-beta.tgz"
      end

      package["scripts"] ||= {}
      package["scripts"]["vite"] = "vite"
      package["scripts"]["vite:build"] = "vite build"
      package["scripts"]["vite:preview"] = "vite preview"
    end

    # Generate vite.config.js content
    # Database and target are controlled via JUNTOS_DATABASE/JUNTOS_TARGET env vars
    # or auto-detected from database.yml
    def generate_vite_config(database: nil, target: nil)
      <<~JS
        import { defineConfig } from 'vite';
        import { juntos } from 'ruby2js-rails/vite';

        export default defineConfig({
          plugins: juntos({
            appRoot: '..'  // Source files are in parent directory
          })
        });
      JS
    end

    # Generate bin/juntos binstub content
    def generate_binstub
      <<~RUBY
        #!/usr/bin/env ruby
        # frozen_string_literal: true

        # Juntos - Rails patterns, JavaScript runtimes
        # This binstub delegates to the ruby2js gem's Juntos CLI

        require "bundler/setup"
        require "ruby2js/cli/juntos"

        Ruby2JS::CLI::Juntos.run(ARGV)
      RUBY
    end

    # Detect database adapter from database.yml
    def detect_database(app_root)
      db_config_path = File.join(app_root, "config/database.yml")
      return 'dexie' unless File.exist?(db_config_path)

      # Rails database.yml often uses YAML aliases, so enable them
      db_config = YAML.load_file(db_config_path, aliases: true)
      adapter = db_config.dig('development', 'adapter') ||
                db_config.dig('default', 'adapter')

      case adapter
      when 'postgresql', 'pg' then 'pg'
      when 'mysql2' then 'mysql'
      when 'sqlite3' then 'sqlite'
      else 'dexie'
      end
    end

    # Detect app name from config/application.rb or directory name
    def detect_app_name(app_root)
      app_rb = File.join(app_root, "config/application.rb")
      if File.exist?(app_rb)
        content = File.read(app_rb)
        if content =~ /module\s+(\w+)/
          return $1.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
        end
      end
      File.basename(app_root).gsub(/[^a-z0-9_-]/i, '_').downcase
    end

    # Merge required dependencies into existing package.json
    def merge_package_dependencies(existing, required)
      # Merge dependencies
      existing["dependencies"] ||= {}
      added = []
      required["dependencies"]&.each do |name, version|
        unless existing["dependencies"].key?(name)
          existing["dependencies"][name] = version
          added << [:dependency, name]
        end
      end

      # Merge devDependencies
      existing["devDependencies"] ||= {}
      required["devDependencies"]&.each do |name, version|
        unless existing["devDependencies"].key?(name)
          existing["devDependencies"][name] = version
          added << [:devDependency, name]
        end
      end

      # Merge optional dependencies
      if required["optionalDependencies"]
        existing["optionalDependencies"] ||= {}
        required["optionalDependencies"].each do |name, version|
          unless existing["optionalDependencies"].key?(name)
            existing["optionalDependencies"][name] = version
            added << [:optionalDependency, name]
          end
        end
      end

      # Merge scripts
      existing["scripts"] ||= {}
      required["scripts"]&.each do |name, command|
        unless existing["scripts"].key?(name)
          existing["scripts"][name] = command
          added << [:script, name]
        end
      end

      # Ensure type is module
      existing["type"] ||= "module"

      added
    end
  end
end
