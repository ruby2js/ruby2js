# frozen_string_literal: true

module Ruby2JS
  module CLI
    # Shared build logic for CLI commands.
    #
    # Provides a unified interface for building applications that:
    # - Uses Vite when vite.config.js exists (Vite's buildStart runs SelfhostBuilder)
    # - Falls back to Ruby SelfhostBuilder when no Vite config
    #
    # This eliminates redundant builds where SelfhostBuilder was run twice
    # (once directly, once via Vite's buildStart hook).
    module BuildHelper
      DIST_DIR = 'dist'

      class << self
        # Build the application using the appropriate method.
        #
        # @param options [Hash] Build options
        # @option options [String] :target Build target (browser, node, cloudflare, etc.)
        # @option options [String] :database Database adapter (dexie, sqlite, pg, etc.)
        # @option options [String] :environment Rails environment (development, production)
        # @option options [Boolean] :sourcemap Generate source maps
        # @option options [Boolean] :verbose Show detailed output
        # @option options [String] :base Base public path for assets (e.g., /demos/blog/)
        # @return [Boolean] true if build succeeded
        def build(options = {})
          vite_config = File.join(DIST_DIR, 'vite.config.js')

          if File.exist?(vite_config)
            # Vite handles everything - its buildStart hook runs SelfhostBuilder
            run_vite_build(options)
          else
            # No Vite config - use Ruby builder directly
            run_ruby_build(options)
          end
        end

        # Run Vite build.
        #
        # Sets environment variables for the Vite plugin and runs vite build.
        # Vite's buildStart hook will run SelfhostBuilder for structural transforms.
        #
        # @param options [Hash] Build options
        # @return [Boolean] true if build succeeded
        def run_vite_build(options = {})
          # Set environment variables for Vite plugin
          ENV['JUNTOS_DATABASE'] = options[:database] if options[:database]
          ENV['JUNTOS_TARGET'] = options[:target] if options[:target]
          ENV['JUNTOS_BASE'] = options[:base] if options[:base]

          # Derive Vite mode from RAILS_ENV or NODE_ENV (RAILS_ENV takes precedence)
          # Default varies by context: deploy defaults to production, others to development
          default_mode = options[:default_mode] || 'development'
          mode = options[:environment] || ENV['RAILS_ENV'] || ENV['NODE_ENV'] || default_mode

          # Build command
          cmd = "npx vite build --mode #{mode}"
          cmd += " --sourcemap" if options[:sourcemap]
          cmd += " --base #{options[:base]}" if options[:base]

          puts "Bundling with Vite (mode: #{mode})..."

          Dir.chdir(DIST_DIR) do
            if options[:verbose]
              success = system(cmd)
            else
              success = system("#{cmd} 2>&1")
            end

            unless success
              abort "Error: Vite build failed."
            end

            true
          end
        end

        # Run Ruby SelfhostBuilder directly.
        #
        # Used when no vite.config.js exists (legacy mode).
        #
        # @param options [Hash] Build options
        # @return [Boolean] true if build succeeded
        def run_ruby_build(options = {})
          require 'ruby2js/rails/builder'

          builder_opts = {}
          builder_opts[:target] = options[:target] if options[:target]
          builder_opts[:database] = options[:database] if options[:database]

          SelfhostBuilder.new(nil, **builder_opts).build
          true
        end

        # Check if Vite is configured for this project.
        #
        # @return [Boolean] true if vite.config.js exists in dist/
        def vite_configured?
          File.exist?(File.join(DIST_DIR, 'vite.config.js'))
        end
      end
    end
  end
end
