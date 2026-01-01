# frozen_string_literal: true

require 'optparse'

module Ruby2JS
  module CLI
    module Migrate
      DIST_DIR = 'dist'

      class << self
        def run(args)
          options = parse_options(args)

          validate_rails_app!

          # Build first (fast, transparent)
          build_app(options)

          # Then run migrations
          run_migrations(options)
        end

        private

        def parse_options(args)
          options = {
            target: ENV['JUNTOS_TARGET'],
            database: ENV['JUNTOS_DATABASE'],
            verbose: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: juntos migrate [options]"
            opts.separator ""
            opts.separator "Build and run database migrations."
            opts.separator ""
            opts.separator "Options:"

            opts.on("-t", "--target TARGET", "Target runtime (node, vercel, cloudflare, etc.)") do |target|
              options[:target] = target
            end

            opts.on("-d", "--database ADAPTER", "Database adapter (better_sqlite3, neon, etc.)") do |db|
              options[:database] = db
            end

            opts.on("-e", "--environment ENV", "Rails environment (default: development)") do |env|
              ENV['RAILS_ENV'] = env
            end

            opts.on("-v", "--verbose", "Show detailed output") do
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
        end

        def build_app(options)
          puts "Building application..."

          require 'ruby2js/rails/builder'

          builder_opts = {}
          builder_opts[:target] = options[:target] if options[:target]
          builder_opts[:database] = options[:database] if options[:database]

          SelfhostBuilder.new(nil, **builder_opts).build
        end

        def run_migrations(options)
          puts "\nRunning migrations..."

          Dir.chdir(DIST_DIR) do
            # Load environment variables from .env.local if present
            env_file = ".env.local"
            if File.exist?(env_file)
              File.readlines(env_file).each do |line|
                next if line.start_with?('#') || line.strip.empty?
                if line =~ /^([^=]+)=["']?([^"'\n]*)["']?$/
                  ENV[$1] = $2
                end
              end
            end

            # Run the migrate script
            unless system("node", "node_modules/ruby2js-rails/migrate.mjs")
              abort "\nError: Migration failed."
            end
          end

          puts "Migrations completed."
        end
      end
    end
  end
end
