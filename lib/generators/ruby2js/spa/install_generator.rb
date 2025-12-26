# frozen_string_literal: true

require 'rails/generators'

# Use Ruby2js (lowercase 'js') so Rails finds this as 'ruby2js:spa:install'
# rather than 'ruby2_j_s:spa:install'
module Ruby2js
  module Spa
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc "Creates a Ruby2JS SPA configuration file and sets up the build infrastructure"

      class_option :name, type: :string,
        desc: "Name of the SPA (defaults to Rails app name)"

      def set_default_name
        return if options[:name]
        # Derive from Rails app name (e.g., Blog::Application -> blog)
        app_name = Rails.application.class.module_parent_name.underscore rescue 'app'
        @options = options.merge(name: app_name)
      end

      class_option :mount_path, type: :string, default: '/offline',
        desc: "URL path where the SPA will be mounted"

      class_option :runtime, type: :string, default: 'browser',
        desc: "Target runtime: browser, node, bun, or deno"

      class_option :database, type: :string, default: 'dexie',
        desc: "Database adapter: dexie, sqljs, pglite, better_sqlite3, pg, or mysql"

      # Valid runtime/database combinations
      VALID_COMBINATIONS = {
        'browser' => %w[dexie sqljs pglite],
        'node' => %w[better_sqlite3 pg mysql],
        'bun' => %w[better_sqlite3 pg mysql],
        'deno' => %w[pg mysql]
      }.freeze

      def validate_options
        runtime = options[:runtime]
        database = options[:database]

        unless VALID_COMBINATIONS.key?(runtime)
          say_status :error, "Invalid runtime '#{runtime}'. Valid options: #{VALID_COMBINATIONS.keys.join(', ')}", :red
          raise ArgumentError, "Invalid runtime"
        end

        valid_dbs = VALID_COMBINATIONS[runtime]
        unless valid_dbs.include?(database)
          say_status :error, "Invalid database '#{database}' for runtime '#{runtime}'. Valid options: #{valid_dbs.join(', ')}", :red
          raise ArgumentError, "Invalid database for runtime"
        end
      end

      def create_initializer
        create_file 'config/initializers/ruby2js_spa.rb', <<~RUBY
          # Load Ruby2JS SPA engine (provides rake tasks and middleware)
          require 'ruby2js/spa'
        RUBY
      end

      def create_manifest
        template 'ruby2js_spa.rb.tt', 'config/ruby2js_spa.rb'
      end

      def add_to_gitignore
        gitignore = Rails.root.join('.gitignore')
        if File.exist?(gitignore)
          content = File.read(gitignore)
          entry = "/public/spa/"
          unless content.include?(entry)
            append_to_file '.gitignore', "\n# Ruby2JS SPA generated files\n#{entry}\n"
          end
        end
      end

      def show_instructions
        say ""
        say "Ruby2JS SPA installed!", :green
        say ""
        say "Next steps:"
        say "  1. Edit config/ruby2js_spa.rb to configure your SPA"
        say "  2. Run: rails ruby2js:spa:build"
        say "  3. Visit: #{options[:mount_path]}/"
        say ""
        say "Useful commands:"
        say "  rails ruby2js:spa:build  - Build the SPA"
        say "  rails ruby2js:spa:clean  - Remove generated files"
        say "  rails ruby2js:spa:info   - Show configuration"
        say ""
      end
    end
  end
end
