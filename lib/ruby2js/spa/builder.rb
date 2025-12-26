# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'ruby2js/inflector'

module Ruby2JS
  module Spa
    # Orchestrates the SPA build process
    #
    # The builder generates a standalone SPA directory with:
    # - Ruby source files (models, controllers, views)
    # - package.json with ruby2js-rails dependency
    # - Config files (database.yml, ruby2js.yml, routes.rb)
    # - index.html entry point
    #
    # The user then runs `npm install && npm run build` to transpile.
    #
    class Builder
      attr_reader :manifest, :rails_root, :output_dir
      attr_reader :resolved_models, :copied_views, :copied_controllers

      def initialize(manifest, rails_root: nil)
        @manifest = manifest
        @rails_root = (rails_root || (defined?(Rails) ? Rails.root : Dir.pwd)).to_s
        @output_dir = File.join(@rails_root, 'public', 'spa', manifest.name.to_s)
        @resolved_models = {}
        @copied_views = []
        @copied_controllers = []
      end

      def build
        validate_manifest!
        prepare_output_directory

        # Resolve model dependencies
        resolve_model_dependencies

        # Copy Ruby source files
        copy_models
        copy_views
        copy_controllers

        # Generate config files
        generate_database_yml
        generate_ruby2js_yml
        generate_routes_rb
        generate_schema_rb
        copy_or_generate_seeds

        # Generate package.json
        generate_package_json

        # Generate index.html and styles
        generate_index_html
        copy_styles

        # Generate README
        generate_readme

        puts "SPA generated successfully: #{output_dir}"
        puts "  Runtime: #{manifest.runtime}"
        puts "  Database: #{manifest.database}"
        puts "  Models: #{@resolved_models.keys.join(', ')}"
        puts "  Views: #{@copied_views.join(', ')}" if @copied_views.any?
        puts "  Controllers: #{@copied_controllers.join(', ')}" if @copied_controllers.any?
        puts ""
        puts "Next steps:"
        puts "  cd #{output_dir}"
        puts "  npm install"
        puts "  npm run build"
        puts "  npm start"
      end

      private

      def validate_manifest!
        unless manifest.valid?
          raise ArgumentError, "Invalid manifest: #{manifest.errors.join(', ')}"
        end
      end

      def prepare_output_directory
        FileUtils.rm_rf(output_dir)
        FileUtils.mkdir_p(output_dir)
        FileUtils.mkdir_p(File.join(output_dir, 'app', 'models'))
        FileUtils.mkdir_p(File.join(output_dir, 'app', 'views'))
        FileUtils.mkdir_p(File.join(output_dir, 'app', 'controllers'))
        FileUtils.mkdir_p(File.join(output_dir, 'config'))
        FileUtils.mkdir_p(File.join(output_dir, 'db'))
        FileUtils.mkdir_p(File.join(output_dir, 'public'))
      end

      # Model handling

      def resolve_model_dependencies
        return if manifest.model_config.included_models.empty?

        resolver = ModelResolver.new(@rails_root)
        @resolved_models = resolver.resolve(manifest.model_config.included_models)

        # Warn about excluded models that were discovered as dependencies
        excluded = manifest.model_config.excluded_models
        @resolved_models.keys.each do |model_name|
          if excluded.include?(model_name)
            warn "Warning: #{model_name} is excluded but required by other models"
          end
        end
      end

      def copy_models
        return if @resolved_models.empty?

        models_dir = File.join(output_dir, 'app', 'models')

        @resolved_models.each do |model_name, model_info|
          src = model_info[:file]
          dst = File.join(models_dir, File.basename(src))
          FileUtils.cp(src, dst) if File.exist?(src)
        end

        # Copy or generate ApplicationRecord
        app_record_src = File.join(@rails_root, 'app', 'models', 'application_record.rb')
        app_record_dst = File.join(models_dir, 'application_record.rb')

        if File.exist?(app_record_src)
          FileUtils.cp(app_record_src, app_record_dst)
        else
          # Generate a minimal ApplicationRecord
          File.write(app_record_dst, <<~RUBY)
            class ApplicationRecord < ActiveRecord::Base
              self.abstract_class = true
            end
          RUBY
        end
      end

      # View handling

      def copy_views
        return if manifest.view_config.included_views.empty?

        views_src_dir = File.join(@rails_root, 'app', 'views')
        views_dst_dir = File.join(output_dir, 'app', 'views')

        manifest.view_config.included_views.each do |view_pattern|
          if view_pattern.include?('*')
            # Glob pattern
            glob_pattern = File.join(views_src_dir, view_pattern)
            Dir.glob(glob_pattern).each do |src_path|
              copy_view_file(src_path, views_src_dir, views_dst_dir)
            end
          else
            # Direct path
            src_path = File.join(views_src_dir, view_pattern)
            src_path += '.html.erb' unless src_path.end_with?('.erb')
            copy_view_file(src_path, views_src_dir, views_dst_dir) if File.exist?(src_path)
          end
        end

        # Copy layout if it exists
        layout_src = File.join(views_src_dir, 'layouts', 'application.html.erb')
        if File.exist?(layout_src)
          layout_dst_dir = File.join(views_dst_dir, 'layouts')
          FileUtils.mkdir_p(layout_dst_dir)
          FileUtils.cp(layout_src, File.join(layout_dst_dir, 'application.html.erb'))
        end
      end

      def copy_view_file(src_path, views_src_dir, views_dst_dir)
        return unless File.exist?(src_path)

        relative = src_path.sub(views_src_dir + '/', '')
        dst_path = File.join(views_dst_dir, relative)

        FileUtils.mkdir_p(File.dirname(dst_path))
        FileUtils.cp(src_path, dst_path)

        @copied_views << relative.sub('.html.erb', '')
      end

      # Controller handling

      def copy_controllers
        return if manifest.controller_config.included_controllers.empty?

        controllers_src_dir = File.join(@rails_root, 'app', 'controllers')
        controllers_dst_dir = File.join(output_dir, 'app', 'controllers')

        manifest.controller_config.included_controllers.each_key do |controller_name|
          src = File.join(controllers_src_dir, "#{controller_name}_controller.rb")
          dst = File.join(controllers_dst_dir, "#{controller_name}_controller.rb")

          if File.exist?(src)
            FileUtils.cp(src, dst)
            @copied_controllers << controller_name.to_s
          end
        end

        # Copy ApplicationController
        app_controller_src = File.join(controllers_src_dir, 'application_controller.rb')
        app_controller_dst = File.join(controllers_dst_dir, 'application_controller.rb')

        if File.exist?(app_controller_src)
          FileUtils.cp(app_controller_src, app_controller_dst)
        else
          File.write(app_controller_dst, <<~RUBY)
            class ApplicationController < ActionController::Base
            end
          RUBY
        end
      end

      # Config generation

      # Database adapter descriptions for comments
      DATABASE_DESCRIPTIONS = {
        dexie: 'Dexie (IndexedDB) for browser-based offline storage',
        sqljs: 'sql.js (SQLite compiled to WebAssembly) for browser',
        pglite: 'PGLite (PostgreSQL in WebAssembly) for browser',
        better_sqlite3: 'better-sqlite3 for Node.js server',
        pg: 'PostgreSQL via node-postgres',
        mysql: 'MySQL via mysql2'
      }.freeze

      def generate_database_yml
        adapter = manifest.database
        description = DATABASE_DESCRIPTIONS[adapter] || adapter.to_s

        config = <<~YAML
          # Database configuration for SPA
          # Uses #{description}

          development:
            adapter: #{adapter}
            database: #{manifest.name}_dev

          production:
            adapter: #{adapter}
            database: #{manifest.name}_prod
        YAML

        File.write(File.join(output_dir, 'config', 'database.yml'), config)
      end

      def generate_ruby2js_yml
        config = <<~YAML
          # Ruby2JS Transpilation Configuration

          default: &default
            eslevel: 2022
            include:
              - class
              - call
            autoexports: true
            comparison: identity

          development:
            <<: *default

          production:
            <<: *default
            strict: true
        YAML

        File.write(File.join(output_dir, 'config', 'ruby2js.yml'), config)
      end

      def generate_routes_rb
        # Generate routes based on manifest controller config
        routes = []
        routes << "Rails.application.routes.draw do"

        # Add root route if specified
        if manifest.root_route
          routes << "  root \"#{manifest.root_route}\""
          routes << ""
        end

        # Generate resource routes for each controller
        manifest.controller_config.included_controllers.each do |controller_name, config|
          if config[:only]
            actions = config[:only].map { |a| ":#{a}" }.join(', ')
            routes << "  resources :#{controller_name}, only: [#{actions}]"
          else
            routes << "  resources :#{controller_name}"
          end
        end

        routes << "end"

        File.write(File.join(output_dir, 'config', 'routes.rb'), routes.join("\n") + "\n")
      end

      def generate_schema_rb
        # Copy schema from source Rails app if it exists
        schema_src = File.join(@rails_root, 'db', 'schema.rb')
        schema_dst = File.join(output_dir, 'config', 'schema.rb')

        if File.exist?(schema_src)
          # Filter schema to only include tables for resolved models
          schema_content = File.read(schema_src)
          # For now, copy the full schema - filtering can be added later
          File.write(schema_dst, schema_content)
        else
          # Generate minimal schema
          tables = @resolved_models.keys.map do |model_name|
            table_name = Inflector.pluralize(snake_case(model_name.to_s))
            <<~RUBY
              create_table "#{table_name}", force: :cascade do |t|
                t.timestamps
              end
            RUBY
          end

          schema = <<~RUBY
            ActiveRecord::Schema[7.0].define(version: 0) do
              #{tables.join("\n")}
            end
          RUBY

          File.write(schema_dst, schema)
        end
      end

      def copy_or_generate_seeds
        seeds_src = File.join(@rails_root, 'db', 'seeds.rb')
        seeds_dst = File.join(output_dir, 'db', 'seeds.rb')

        # Check if seeds.rb has actual Ruby code (not just comments/whitespace)
        has_code = File.exist?(seeds_src) &&
                   File.read(seeds_src).lines.any? { |line| line.strip !~ /\A(#.*|\s*)\z/ }

        if has_code
          # Copy existing seeds file - the rails/seeds filter will wrap bare code
          # in module Seeds if needed during transpilation
          FileUtils.cp(seeds_src, seeds_dst)
        else
          # Generate empty Seeds module (rails/seeds filter needs code to process)
          File.write(seeds_dst, <<~RUBY)
            # Seeds for #{manifest.name}
            module Seeds
              def self.run
                # Add your seed data here
              end
            end
          RUBY
        end
      end

      # Database npm package names
      DATABASE_PACKAGES = {
        dexie: { 'dexie' => '^4.0.10' },
        sqljs: { 'sql.js' => '^1.11.0' },
        pglite: { '@electric-sql/pglite' => '^0.2.0' },
        better_sqlite3: { 'better-sqlite3' => '^11.0.0' },
        pg: { 'pg' => '^8.13.0' },
        mysql: { 'mysql2' => '^3.11.0' }
      }.freeze

      def generate_package_json
        runtime = manifest.runtime
        database = manifest.database

        # Base scripts - focused on the target runtime
        scripts = {
          dev: dev_script_for(runtime),
          build: "ruby2js-rails-build",
          start: start_script_for(runtime)
        }

        # Base dependencies
        dependencies = {
          "ruby2js-rails" => "https://www.ruby2js.com/releases/ruby2js-rails-beta.tgz"
        }

        # Add database-specific dependency
        db_deps = DATABASE_PACKAGES[database] || {}
        dependencies.merge!(db_deps)

        package = {
          name: manifest.name.to_s.gsub('_', '-'),
          version: "0.1.0",
          type: "module",
          description: description_for(runtime, database),
          scripts: scripts,
          dependencies: dependencies,
          engines: engines_for(runtime)
        }

        File.write(File.join(output_dir, 'package.json'), JSON.pretty_generate(package) + "\n")
      end

      def dev_script_for(runtime)
        case runtime
        when :browser then "ruby2js-rails-dev"
        when :node then "ruby2js-rails-dev --ruby"
        when :bun then "ruby2js-rails-dev --ruby"
        when :deno then "ruby2js-rails-dev --ruby"
        else "ruby2js-rails-dev"
        end
      end

      def start_script_for(runtime)
        case runtime
        when :browser then "npx serve -s -p 3000"
        when :node then "ruby2js-rails-server"
        when :bun then "bun node_modules/ruby2js-rails/server.mjs"
        when :deno then "deno run --allow-all node_modules/ruby2js-rails/server.mjs"
        else "npx serve -s -p 3000"
        end
      end

      def description_for(runtime, database)
        case runtime
        when :browser then "Browser SPA with #{database} storage - generated by Ruby2JS"
        else "#{runtime.to_s.capitalize} server with #{database} database - generated by Ruby2JS"
        end
      end

      def engines_for(runtime)
        case runtime
        when :browser, :node then { node: ">=22.0.0" }
        when :bun then { bun: ">=1.0.0" }
        when :deno then { deno: ">=1.40.0" }
        else { node: ">=22.0.0" }
        end
      end

      # Importmap entries for browser databases
      BROWSER_IMPORTMAPS = {
        dexie: { 'dexie' => '/node_modules/dexie/dist/dexie.mjs' },
        sqljs: { 'sql.js' => '/node_modules/sql.js/dist/sql-wasm.js' },
        pglite: { '@electric-sql/pglite' => '/node_modules/@electric-sql/pglite/dist/index.js' }
      }.freeze

      def generate_index_html
        # Only generate index.html for browser runtime
        return unless manifest.browser?

        # Determine which controllers to set up navigation for
        nav_links = manifest.controller_config.included_controllers.keys.map do |controller|
          "<a onclick=\"navigate('/#{controller}')\">#{controller.to_s.capitalize}</a>"
        end.join("\n      ")

        # Build importmap for the chosen database
        importmap_entries = BROWSER_IMPORTMAPS[manifest.database] || {}
        importmap_json = JSON.pretty_generate({ imports: importmap_entries })

        html = <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>#{manifest.name.to_s.gsub('_', ' ').capitalize}</title>
            <link rel="stylesheet" href="/public/styles.css">
            <script type="importmap">
            #{importmap_json}
            </script>
          </head>
          <body>
            <div id="loading">Loading...</div>
            <div id="app" style="display: none;">
              <nav>
                #{nav_links}
              </nav>
              <main id="content"></main>
            </div>

            <script type="module">
              import { Application } from '/dist/config/routes.js';
              Application.start();
            </script>
          </body>
          </html>
        HTML

        File.write(File.join(output_dir, 'index.html'), html)
      end

      def generate_readme
        runtime_desc = case manifest.runtime
        when :browser then "runs in the browser"
        when :node then "runs on Node.js"
        when :bun then "runs on Bun"
        when :deno then "runs on Deno"
        else "runs on #{manifest.runtime}"
        end

        db_desc = DATABASE_DESCRIPTIONS[manifest.database] || manifest.database.to_s

        readme = <<~MD
          # #{manifest.name.to_s.gsub('_', ' ').capitalize}

          Application generated by Ruby2JS (#{runtime_desc} with #{manifest.database}).

          ## Quick Start

          ```bash
          npm install
          npm run build
          npm start
          ```

          Then open http://localhost:3000

          ## Development

          ```bash
          npm run dev
          ```

          This starts a development server with hot reload.

          ## Configuration

          - **Runtime:** #{manifest.runtime}
          - **Database:** #{db_desc}

          To change the target, edit `config/ruby2js_spa.rb` in your Rails app
          and regenerate with `rails ruby2js:spa:build`.

          ## Structure

          ```
          app/
            models/       # Ruby model classes
            controllers/  # Ruby controller classes
            views/        # ERB templates
          config/
            database.yml  # Database adapter configuration
            routes.rb     # URL routing
            ruby2js.yml   # Transpilation options
          dist/           # Generated JavaScript (after build)
          ```

          ## How It Works

          Ruby source files are transpiled to JavaScript using ruby2js-rails.
          The application #{runtime_desc} using #{db_desc}.
        MD

        File.write(File.join(output_dir, 'README.md'), readme)
      end

      # Copy styles if they exist
      def copy_styles
        styles_src = File.join(@rails_root, 'public', 'styles.css')
        styles_dst = File.join(output_dir, 'public', 'styles.css')

        if File.exist?(styles_src)
          FileUtils.cp(styles_src, styles_dst)
        else
          # Generate minimal styles
          File.write(styles_dst, <<~CSS)
            body { font-family: system-ui, sans-serif; margin: 2rem; }
            nav { margin-bottom: 1rem; }
            nav a { margin-right: 1rem; cursor: pointer; color: blue; }
            #loading { text-align: center; padding: 2rem; }
          CSS
        end
      end

      # Helpers

      def snake_case(str)
        str.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
      end
    end
  end
end
