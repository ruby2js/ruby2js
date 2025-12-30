# frozen_string_literal: true

require 'optparse'

module Ruby2JS
  module CLI
    module Build
      DIST_DIR = 'dist'

      class << self
        def run(args)
          options = parse_options(args)

          validate_rails_app!
          check_installation!

          build(options)
        end

        private

        def parse_options(args)
          options = {
            verbose: false,
            selfhost: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: ruby2js build [options]"
            opts.separator ""
            opts.separator "Build a Rails-like app for deployment."
            opts.separator ""
            opts.separator "Options:"

            opts.on("-v", "--verbose", "Show detailed build output") do
              options[:verbose] = true
            end

            opts.on("--selfhost", "Use JavaScript transpiler instead of Ruby") do
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

          success = if options[:selfhost]
            # Use JavaScript transpiler via npm (run from dist/)
            Dir.chdir(DIST_DIR) do
              if options[:verbose]
                system("npm run build")
              else
                system("npm run build > /dev/null 2>&1")
              end
            end
          else
            # Use Ruby transpiler directly
            require 'ruby2js/rails/builder'
            SelfhostBuilder.new.build
            true
          end

          if success
            puts "Build complete. Output in dist/"
          else
            abort "Error: Build failed. Run with --verbose for details."
          end
        end
      end
    end
  end
end
