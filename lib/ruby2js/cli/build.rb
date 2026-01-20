# frozen_string_literal: true

require 'optparse'
require_relative 'build_helper'

module Ruby2JS
  module CLI
    module Build
      DIST_DIR = 'dist'

      class << self
        def run(args)
          options = parse_options(args)

          validate_rails_app!

          # Non-Rails frameworks generate their own project structure
          unless options[:framework] && options[:framework] != 'rails'
            check_installation!
          end

          build(options)
        end

        private

        def parse_options(args)
          options = {
            verbose: false,
            selfhost: false,
            sourcemap: false,
            base: nil,
            target: ENV['JUNTOS_TARGET'],
            database: ENV['JUNTOS_DATABASE'],
            framework: ENV['JUNTOS_FRAMEWORK']
          }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: ruby2js build [options]"
            opts.separator ""
            opts.separator "Build a Rails-like app for deployment."
            opts.separator ""
            opts.separator "Options:"

            opts.on("-f", "--framework FRAMEWORK", "Output framework: rails (default), astro, vue, svelte") do |framework|
              options[:framework] = framework
            end

            opts.on("-t", "--target TARGET", "Build target: browser, node, vercel, cloudflare") do |target|
              options[:target] = target
            end

            opts.on("-d", "--database ADAPTER", "Database adapter (overrides database.yml)") do |db|
              options[:database] = db
            end

            opts.on("-e", "--environment ENV", "Rails environment (default: development)") do |env|
              ENV['RAILS_ENV'] = env
            end

            opts.on("-v", "--verbose", "Show detailed build output") do
              options[:verbose] = true
            end

            opts.on("--sourcemap", "Generate source maps (useful for debugging production builds)") do
              options[:sourcemap] = true
            end

            opts.on("--base PATH", "Base public path for assets (e.g., /demos/blog/)") do |path|
              options[:base] = path
            end

            opts.on("--selfhost", "Use JavaScript transpiler instead of Ruby (legacy mode)") do
              options[:selfhost] = true
            end

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
        end

        def check_installation!
          package_json = File.join(DIST_DIR, 'package.json')
          node_modules = File.join(DIST_DIR, 'node_modules')

          unless File.exist?(package_json)
            abort "Error: #{package_json} not found.\n" \
                  "Run 'ruby2js install' first to set up the project."
          end

          unless File.directory?(node_modules)
            abort "Error: #{node_modules} not found.\n" \
                  "Run 'ruby2js install' first."
          end
        end

        def build(options)
          puts "Building application..."

          # Framework-specific builds
          if options[:framework] && options[:framework] != 'rails'
            success = build_for_framework(options)
          elsif options[:selfhost] && !BuildHelper.vite_configured?
            # Legacy: Use JavaScript transpiler via npm (run from dist/)
            Dir.chdir(DIST_DIR) do
              if options[:verbose]
                success = system("npm run build")
              else
                success = system("npm run build > /dev/null 2>&1")
              end
            end
          else
            # Use unified build (Vite if configured, else Ruby builder)
            success = BuildHelper.build(options)
          end

          if success
            puts "Build complete. Output in dist/"
          else
            abort "Error: Build failed. Run with --verbose for details."
          end
        end

        def build_for_framework(options)
          framework = options[:framework]

          case framework
          when 'astro'
            require 'ruby2js/rails/astro_builder'
            Ruby2JS::Rails::AstroBuilder.new(options).build
          when 'vue', 'svelte'
            abort "Error: #{framework} framework not yet implemented."
          else
            abort "Error: Unknown framework '#{framework}'. Valid options: rails, astro, vue, svelte"
          end
        end
      end
    end
  end
end
