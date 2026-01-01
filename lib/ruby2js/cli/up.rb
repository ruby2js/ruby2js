# frozen_string_literal: true

require 'optparse'

module Ruby2JS
  module CLI
    module Up
      DIST_DIR = 'dist'

      # Valid targets for local run (not serverless platforms)
      LOCAL_TARGETS = %w[node bun deno browser].freeze

      class << self
        def run(args)
          options = parse_options(args)

          validate_rails_app!

          # Build first
          build_app(options)

          # Then start server
          start_server(options)
        end

        private

        def parse_options(args)
          options = {
            port: 3000,
            target: ENV['JUNTOS_TARGET'],
            database: ENV['JUNTOS_DATABASE'],
            verbose: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: juntos up [options]"
            opts.separator ""
            opts.separator "Build (if needed) and run a Rails-like app locally."
            opts.separator ""
            opts.separator "Options:"

            opts.on("-t", "--target TARGET", LOCAL_TARGETS, "Target runtime: #{LOCAL_TARGETS.join(', ')}") do |target|
              options[:target] = target
            end

            opts.on("-d", "--database ADAPTER", "Database adapter (better_sqlite3, dexie, etc.)") do |db|
              options[:database] = db
            end

            opts.on("-p", "--port PORT", Integer, "Port to run the server on (default: 3000)") do |port|
              options[:port] = port
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

        def start_server(options)
          ENV["PORT"] = options[:port].to_s
          ENV["NODE_ENV"] = ENV["RAILS_ENV"] if ENV["RAILS_ENV"]

          # Detect runtime from what was built
          require 'ruby2js/rails/builder'
          config = SelfhostBuilder.detect_runtime

          if config[:target] == 'browser'
            # Browser databases use static file serving
            puts "\nStarting browser server on http://localhost:#{options[:port]}..."
            Dir.chdir(DIST_DIR) do
              exec("npm", "run", "start")
            end
          else
            runtime = config[:runtime] || 'node'
            script = "start:#{runtime}"
            puts "\nStarting #{runtime} server on http://localhost:#{options[:port]}..."
            Dir.chdir(DIST_DIR) do
              exec("npm", "run", script)
            end
          end
        end
      end
    end
  end
end
