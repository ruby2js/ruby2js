# frozen_string_literal: true

require 'optparse'

module Ruby2JS
  module CLI
    module Build
      class << self
        def run(args)
          options = parse_options(args)

          validate_rails_app!
          ensure_dependencies!

          build(options)
        end

        private

        def parse_options(args)
          options = {
            verbose: false
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

          unless File.exist?("package.json")
            abort "Error: package.json not found.\n" \
                  "Run 'ruby2js dev' first to set up the project."
          end
        end

        def ensure_dependencies!
          unless File.directory?("node_modules")
            puts "Installing npm dependencies..."
            system("npm install") || abort("Error: npm install failed")
          end
        end

        def build(options)
          puts "Building application..."

          success = if options[:verbose]
            system("npm run build")
          else
            system("npm run build > /dev/null 2>&1")
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
