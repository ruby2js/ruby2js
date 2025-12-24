# frozen_string_literal: true

require 'fileutils'

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

      def initialize(manifest, rails_root: nil)
        @manifest = manifest
        @rails_root = rails_root || (defined?(Rails) ? Rails.root : Dir.pwd)
        @output_dir = File.join(@rails_root, 'public', 'spa', manifest.name.to_s)
      end

      def build
        validate_manifest!
        prepare_output_directory

        # Stage 2-4: These will be implemented in subsequent stages
        # build_models
        # build_views
        # build_controllers
        # build_routes

        # Stage 5: Copy Stimulus controllers
        # copy_stimulus_controllers

        # Generate runtime files
        # generate_runtime

        # Generate index.html
        generate_index_html

        puts "SPA built successfully: #{output_dir}"
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

      def build_models
        # Stage 2: Parse models, resolve dependencies, transpile
        raise NotImplementedError, "Model transpilation not yet implemented"
      end

      def build_views
        # Stage 3: Transpile ERB templates
        raise NotImplementedError, "View transpilation not yet implemented"
      end

      def build_controllers
        # Stage 4: Filter and transpile controllers
        raise NotImplementedError, "Controller transpilation not yet implemented"
      end

      def build_routes
        # Stage 4: Filter and transpile routes
        raise NotImplementedError, "Route transpilation not yet implemented"
      end

      def copy_stimulus_controllers
        # Stage 5: Copy specified Stimulus controllers
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

      def generate_runtime
        # Stage 5-6: Generate Turbo interceptor, sync layer, Dexie adapter
        raise NotImplementedError, "Runtime generation not yet implemented"
      end
    end
  end
end
