# frozen_string_literal: true

require 'fileutils'
require 'ruby2js/inflector'

module Ruby2JS
  module Spa
    # Orchestrates the SPA build process
    #
    # The builder:
    # 1. Parses routes.rb and filters by manifest criteria
    # 2. Parses model files and resolves dependencies
    # 3. Transpiles filtered routes, models, controllers, and views
    # 4. Copies Stimulus controllers
    # 5. Generates runtime files (Turbo interceptor, sync, Dexie adapter)
    # 6. Writes output to public/spa/{name}/
    #
    class Builder
      attr_reader :manifest, :rails_root, :output_dir
      attr_reader :resolved_models, :schema, :built_views, :built_controllers

      def initialize(manifest, rails_root: nil)
        @manifest = manifest
        @rails_root = (rails_root || (defined?(Rails) ? Rails.root : Dir.pwd)).to_s
        @output_dir = File.join(@rails_root, 'public', 'spa', manifest.name.to_s)
        @resolved_models = {}
        @schema = {}
        @built_views = []
        @built_controllers = []
      end

      def build
        validate_manifest!
        prepare_output_directory

        # Stage 2: Models
        resolve_model_dependencies
        parse_schema
        build_models

        # Stage 3: Views
        build_views

        # Stage 4: Controllers
        build_controllers

        # Routes (placeholder)
        # build_routes

        # Stage 5: Copy Stimulus controllers
        copy_stimulus_controllers

        # Generate Dexie database schema
        generate_dexie_schema

        # Generate runtime files
        # generate_runtime

        # Generate index.html
        generate_index_html

        puts "SPA built successfully: #{output_dir}"
        puts "  Models: #{@resolved_models.keys.join(', ')}"
        puts "  Tables: #{@schema.keys.join(', ')}"
        puts "  Views: #{@built_views.join(', ')}" if @built_views&.any?
        puts "  Controllers: #{@built_controllers.join(', ')}" if @built_controllers&.any?
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
        FileUtils.mkdir_p(File.join(output_dir, 'models'))
        FileUtils.mkdir_p(File.join(output_dir, 'views'))
        FileUtils.mkdir_p(File.join(output_dir, 'controllers'))
        FileUtils.mkdir_p(File.join(output_dir, 'stimulus'))
        FileUtils.mkdir_p(File.join(output_dir, 'lib'))
      end

      # Stage 2: Model handling

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

      def parse_schema
        parser = SchemaParser.new(@rails_root)
        parser.parse
        @schema = parser.tables
      end

      def build_models
        return if @resolved_models.empty?

        transpiler = ModelTranspiler.new(@rails_root)
        models_dir = File.join(output_dir, 'models')

        @resolved_models.each_key do |model_name|
          js = transpiler.transpile(model_name)
          next unless js

          file_name = "#{snake_case(model_name.to_s)}.js"
          File.write(File.join(models_dir, file_name), js)
        end

        # Generate ApplicationRecord base class
        generate_application_record
      end

      def generate_application_record
        # Generate a Dexie-backed ApplicationRecord base class
        app_record = <<~JS
          import { db } from '../lib/database.js';

          export class ApplicationRecord {
            static table_name = null;

            constructor(attributes = {}) {
              this._attributes = attributes;
              this.id = attributes.id;

              // Copy attributes to instance properties
              for (let key in attributes) {
                if (key !== 'id') {
                  this[key] = attributes[key];
                }
              }
            }

            // Class methods
            static async all() {
              const records = await db[this.table_name].toArray();
              return records.map(r => new this(r));
            }

            static async find(id) {
              const record = await db[this.table_name].get(id);
              return record ? new this(record) : null;
            }

            static async find_by(conditions) {
              const record = await db[this.table_name].where(conditions).first();
              return record ? new this(record) : null;
            }

            static async where(conditions) {
              const records = await db[this.table_name].where(conditions).toArray();
              return records.map(r => new this(r));
            }

            static async create(attributes) {
              const now = new Date().toISOString();
              attributes.created_at = attributes.created_at || now;
              attributes.updated_at = attributes.updated_at || now;

              const id = await db[this.table_name].add(attributes);
              attributes.id = id;
              return new this(attributes);
            }

            // Instance methods
            async save() {
              this._attributes.updated_at = new Date().toISOString();

              if (this.id) {
                await db[this.constructor.table_name].put(this._attributes);
              } else {
                this._attributes.created_at = new Date().toISOString();
                this.id = await db[this.constructor.table_name].add(this._attributes);
                this._attributes.id = this.id;
              }

              return this;
            }

            async update(attributes) {
              Object.assign(this._attributes, attributes);
              Object.assign(this, attributes);
              return this.save();
            }

            async destroy() {
              if (this.id) {
                await db[this.constructor.table_name].delete(this.id);
              }
            }

            // Validation helpers (called by generated validate() methods)
            validates_presence_of(attr) {
              if (!this._attributes[attr] || this._attributes[attr] === '') {
                this.errors = this.errors || {};
                this.errors[attr] = this.errors[attr] || [];
                this.errors[attr].push("can't be blank");
              }
            }

            validates_length_of(attr, options) {
              const value = this._attributes[attr] || '';
              if (options.minimum && value.length < options.minimum) {
                this.errors = this.errors || {};
                this.errors[attr] = this.errors[attr] || [];
                this.errors[attr].push(`is too short (minimum is ${options.minimum} characters)`);
              }
              if (options.maximum && value.length > options.maximum) {
                this.errors = this.errors || {};
                this.errors[attr] = this.errors[attr] || [];
                this.errors[attr].push(`is too long (maximum is ${options.maximum} characters)`);
              }
            }

            get valid() {
              this.errors = {};
              if (typeof this.validate === 'function') {
                this.validate();
              }
              return Object.keys(this.errors).length === 0;
            }
          }
        JS

        File.write(File.join(output_dir, 'models', 'application_record.js'), app_record)
      end

      def generate_dexie_schema
        parser = SchemaParser.new(@rails_root)
        parser.parse

        # Only include tables for resolved models (table names are pluralized snake_case)
        table_names = @resolved_models.keys.map do |m|
          Inflector.pluralize(snake_case(m.to_s))
        end

        db_js = parser.to_dexie_js(
          only_tables: table_names,
          db_name: "#{manifest.name}_db"
        )

        File.write(File.join(output_dir, 'lib', 'database.js'), db_js)
      end

      # Stage 5: Stimulus controllers

      def copy_stimulus_controllers
        manifest.stimulus_config.included_controllers.each do |controller|
          src = File.join(rails_root, 'app', 'javascript', 'controllers', controller)
          dst = File.join(output_dir, 'stimulus', controller)

          if File.exist?(src)
            FileUtils.cp(src, dst)
          else
            warn "Stimulus controller not found: #{src}"
          end
        end
      end

      # Index HTML

      def generate_index_html
        html = <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>#{manifest.name} - Offline SPA</title>
            <script type="module" src="./app.js"></script>
          </head>
          <body>
            <div id="loading">Loading...</div>
            <main id="main"></main>
          </body>
          </html>
        HTML

        File.write(File.join(output_dir, 'index.html'), html)
      end

      # Placeholder methods for subsequent stages

      def build_views
        return if manifest.view_config.included_views.empty?

        transpiler = ViewTranspiler.new(@rails_root, database: 'dexie')
        views_dir = File.join(output_dir, 'views')

        # Group views by controller for generating combined modules
        views_by_controller = {}

        manifest.view_config.included_views.each do |view_pattern|
          # Handle glob patterns (e.g., 'articles/*.html.erb')
          if view_pattern.include?('*')
            glob_pattern = File.join(@rails_root, 'app', 'views', view_pattern)
            Dir.glob(glob_pattern).each do |file_path|
              transpile_view_file(transpiler, file_path, views_dir, views_by_controller)
            end
          else
            # Direct view path (e.g., 'articles/show.html.erb' or 'articles/show')
            view_path = view_pattern.sub(/\.html\.erb$/, '')
            parts = view_path.split('/')
            controller = parts[-2] || 'application'
            action = parts[-1]

            js = transpiler.transpile(controller, action)
            if js
              write_view_file(controller, action, js, views_dir, views_by_controller)
            end
          end
        end

        # Generate combined modules for each controller
        # Write to views/{controller}.js (not inside controller subdirectory to avoid conflict with index view)
        views_by_controller.each do |controller, actions|
          module_js = transpiler.generate_views_module(controller, actions)
          module_path = File.join(views_dir, "#{controller}.js")
          File.write(module_path, module_js)
        end
      end

      def transpile_view_file(transpiler, file_path, views_dir, views_by_controller)
        relative = file_path.sub(File.join(@rails_root, 'app', 'views') + '/', '')
        parts = relative.split('/')
        controller = parts[-2] || 'application'
        action = File.basename(parts[-1], '.html.erb')

        # Skip partials for now (they start with _)
        return if action.start_with?('_')

        template = File.read(file_path)
        js = transpiler.send(:transpile_erb, template)

        write_view_file(controller, action, js, views_dir, views_by_controller)
      end

      def write_view_file(controller, action, js, views_dir, views_by_controller)
        controller_dir = File.join(views_dir, controller)
        FileUtils.mkdir_p(controller_dir)

        file_path = File.join(controller_dir, "#{action}.js")
        File.write(file_path, js)

        views_by_controller[controller] ||= {}
        views_by_controller[controller][action] = js

        @built_views << "#{controller}/#{action}"
      end

      def build_controllers
        return if manifest.controller_config.included_controllers.empty?

        transpiler = ControllerTranspiler.new(@rails_root)
        controllers_dir = File.join(output_dir, 'controllers')

        manifest.controller_config.included_controllers.each do |name, config|
          actions = config[:only]
          js = transpiler.transpile(name, actions: actions)

          if js
            FileUtils.mkdir_p(controllers_dir)
            file_path = File.join(controllers_dir, "#{name}_controller.js")
            File.write(file_path, js)
            @built_controllers << name.to_s
          end
        end
      end

      def build_routes
        # Stage 4: Filter and transpile routes
        raise NotImplementedError, "Route transpilation not yet implemented"
      end

      def generate_runtime
        # Stage 5-6: Generate Turbo interceptor, sync layer
        raise NotImplementedError, "Runtime generation not yet implemented"
      end

      # Helpers

      def snake_case(str)
        str.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
      end
    end
  end
end
