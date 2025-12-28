# frozen_string_literal: true

require 'rails/generators'
require 'json'

# Use Ruby2js (lowercase 'js') so Rails finds this as 'ruby2js:spa:install'
# rather than 'ruby2_j_s:spa:install'
module Ruby2js
  module Spa
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc "Creates a Ruby2JS SPA configuration file and sets up the build infrastructure"

      class_option :name, type: :string,
        desc: "Name of the SPA (defaults to Rails app name)"

      class_option :mount_path, type: :string, default: '/offline',
        desc: "URL path where the SPA will be mounted"

      class_option :runtime, type: :string, default: 'browser',
        desc: "Target runtime: browser, node, bun, or deno"

      class_option :database, type: :string, default: 'dexie',
        desc: "Database adapter: dexie, sqljs, pglite, better_sqlite3, pg, or mysql"

      class_option :scaffold, type: :array, default: [],
        desc: "Scaffold(s) to include (default: auto-detect all)"

      class_option :root, type: :string,
        desc: "Root route (default: copy from Rails routes.rb)"

      class_option :css, type: :string,
        desc: "CSS framework: none, pico, or tailwind (default: auto-detect from Rails app)"

      def set_defaults
        # Derive name from Rails app name if not provided
        unless options[:name]
          app_name = Rails.application.class.module_parent_name.underscore rescue 'app'
          @options = options.merge(name: app_name)
        end

        # Auto-detect CSS framework if not provided
        unless options[:css]
          detected_css = detect_css_framework
          @options = (@options || options).merge(css: detected_css)
        end

        # Auto-detect scaffolds if none provided
        if options[:scaffold].empty?
          @detected_scaffolds = detect_scaffolds
        else
          @detected_scaffolds = options[:scaffold].map(&:capitalize)
        end

        # Detect root route if not provided
        @root_route = options[:root] || detect_root_route
      end

      # Valid runtime/database combinations
      VALID_COMBINATIONS = {
        'browser' => %w[dexie sqljs pglite],
        'node' => %w[better_sqlite3 pg mysql],
        'bun' => %w[better_sqlite3 pg mysql],
        'deno' => %w[pg mysql]
      }.freeze

      # Valid CSS framework options
      VALID_CSS_OPTIONS = %w[none pico tailwind].freeze

      def validate_options
        runtime = options[:runtime]
        database = options[:database]
        css = options[:css]

        unless VALID_COMBINATIONS.key?(runtime)
          say_status :error, "Invalid runtime '#{runtime}'. Valid options: #{VALID_COMBINATIONS.keys.join(', ')}", :red
          raise ArgumentError, "Invalid runtime"
        end

        valid_dbs = VALID_COMBINATIONS[runtime]
        unless valid_dbs.include?(database)
          say_status :error, "Invalid database '#{database}' for runtime '#{runtime}'. Valid options: #{valid_dbs.join(', ')}", :red
          raise ArgumentError, "Invalid database for runtime"
        end

        unless VALID_CSS_OPTIONS.include?(css)
          say_status :error, "Invalid CSS framework '#{css}'. Valid options: #{VALID_CSS_OPTIONS.join(', ')}", :red
          raise ArgumentError, "Invalid CSS framework"
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
        say "Configuration:"
        say "  Runtime:  #{options[:runtime]}"
        say "  Database: #{options[:database]}"
        say "  CSS:      #{options[:css]}"
        say "  Scaffolds: #{@detected_scaffolds.any? ? @detected_scaffolds.join(', ') : '(none detected)'}"
        say "  Root: #{@root_route || '(none)'}"
        say ""
        say "Next steps:"
        say "  1. Review config/ruby2js_spa.rb"
        say "  2. Run: rails ruby2js:spa:build"
        say "  3. Visit: #{options[:mount_path]}/"
        say ""
        say "Useful commands:"
        say "  rails ruby2js:spa:build  - Build the SPA"
        say "  rails ruby2js:spa:clean  - Remove generated files"
        say "  rails ruby2js:spa:info   - Show configuration"
        say ""
      end

      private

      # Detect CSS framework from Rails app configuration
      def detect_css_framework
        gemfile = Rails.root.join('Gemfile')
        return 'none' unless File.exist?(gemfile)

        gemfile_content = File.read(gemfile)

        # Check for tailwindcss-rails gem
        if gemfile_content =~ /gem\s+['"]tailwindcss-rails['"]/
          return 'tailwind'
        end

        # Check for cssbundling-rails with specific CSS frameworks
        if gemfile_content =~ /gem\s+['"]cssbundling-rails['"]/
          # Check package.json for the specific CSS framework
          package_json = Rails.root.join('package.json')
          if File.exist?(package_json)
            begin
              pkg = JSON.parse(File.read(package_json))
              deps = (pkg['dependencies'] || {}).merge(pkg['devDependencies'] || {})

              return 'tailwind' if deps['tailwindcss']
              # Bootstrap and Bulma not yet supported, fall through to none
            rescue JSON::ParserError
              # Ignore JSON parse errors
            end
          end
        end

        'none'
      end

      # Detect models that have corresponding controllers (scaffolds)
      def detect_scaffolds
        models_dir = Rails.root.join('app', 'models')
        controllers_dir = Rails.root.join('app', 'controllers')

        return [] unless Dir.exist?(models_dir) && Dir.exist?(controllers_dir)

        scaffolds = []
        Dir.glob(models_dir.join('*.rb')).each do |model_file|
          model_name = File.basename(model_file, '.rb')
          next if model_name == 'application_record'

          # Check if corresponding controller exists
          controller_file = controllers_dir.join("#{model_name.pluralize}_controller.rb")
          if File.exist?(controller_file)
            scaffolds << model_name.camelize
          end
        end

        scaffolds.sort
      end

      # Detect root route from config/routes.rb
      def detect_root_route
        routes_file = Rails.root.join('config', 'routes.rb')
        return nil unless File.exist?(routes_file)

        content = File.read(routes_file)
        # Match: root "controller#action" or root 'controller#action' or root to: "controller#action"
        # Anchor to start of line to avoid matching commented-out roots like "# root ..."
        if content =~ /^\s*root\s+["']([^"']+)["']/m ||
           content =~ /^\s*root\s+to:\s*["']([^"']+)["']/m
          $1
        end
      end
    end
  end
end
