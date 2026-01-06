# frozen_string_literal: true

require 'optparse'
require 'fileutils'
require 'json'

module Ruby2JS
  module CLI
    module Db
      DIST_DIR = 'dist'
      SUBCOMMANDS = %w[create migrate seed prepare drop].freeze

      # Databases that run in the browser (no CLI migration possible)
      BROWSER_DATABASES = %w[dexie].freeze

      # Databases that require wrangler CLI
      WRANGLER_DATABASES = %w[d1].freeze

      class << self
        def run(args)
          subcommand = args.shift

          unless subcommand
            show_help
            exit 1
          end

          unless SUBCOMMANDS.include?(subcommand)
            if subcommand == '-h' || subcommand == '--help'
              show_help
              exit 0
            end
            abort "Unknown db command: #{subcommand}\nRun 'juntos db --help' for usage."
          end

          options = parse_options(args)
          validate_rails_app!

          send("run_#{subcommand}", options)
        end

        private

        def parse_options(args)
          options = {
            database: ENV['JUNTOS_DATABASE'],
            target: ENV['JUNTOS_TARGET'],
            verbose: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: juntos db <command> [options]"

            opts.on("-d", "--database ADAPTER", "Database adapter") do |db|
              options[:database] = db
            end

            opts.on("-t", "--target TARGET", "Target runtime") do |target|
              options[:target] = target
            end

            opts.on("-v", "--verbose", "Show detailed output") do
              options[:verbose] = true
            end

            opts.on("-h", "--help", "Show this help message") do
              show_help
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

        def show_help
          puts <<~HELP
            Juntos Database Commands

            Usage: juntos db <command> [options]
                   juntos db:command [options]

            Commands:
              migrate   Run database migrations
              seed      Run database seeds
              prepare   Migrate, and seed if fresh database
              create    Create database (D1 only)
              drop      Delete database (D1 only)

            Options:
              -d, --database ADAPTER   Database adapter (d1, sqlite, neon, turso, etc.)
              -t, --target TARGET      Target runtime (cloudflare, vercel, node, etc.)
              -v, --verbose            Show detailed output
              -h, --help               Show this help message

            Examples:
              juntos db:migrate                    # Run migrations
              juntos db:seed                       # Run seeds
              juntos db:prepare                    # Migrate + seed if fresh
              juntos db:prepare -d d1              # D1: create + migrate + seed
              juntos db:create -d d1               # Create D1 database
              juntos db:drop -d d1                 # Delete D1 database

            Note: Browser databases (dexie) auto-migrate at runtime.
          HELP
        end

        # ============================================
        # db create - Create database (D1 only)
        # ============================================
        def run_create(options)
          validate_d1!(options, 'create')

          app_name = get_app_name
          puts "Creating D1 database '#{app_name}'..."

          check_wrangler!

          output = `npx wrangler d1 create #{app_name} 2>&1`
          puts output if options[:verbose]

          if output =~ /database_id\s*[=:]\s*["']?([a-f0-9-]+)["']?/i
            database_id = $1
            save_database_id(database_id)
            puts "Created D1 database: #{app_name}"
            puts "Database ID: #{database_id}"
            puts "Saved to .env.local"
          elsif output.include?('already exists')
            puts "Database '#{app_name}' already exists."
            puts "Use 'juntos db:drop' first if you want to recreate it."
          else
            abort "Error: Failed to create database.\n#{output}"
          end
        end

        # ============================================
        # db migrate - Run migrations
        # ============================================
        def run_migrate(options)
          validate_not_browser!(options, 'migrate')
          build_app(options)

          if d1?(options)
            run_d1_migrate(options)
          else
            run_node_migrate(options)
          end

          puts "Migrations completed."
        end

        # ============================================
        # db seed - Run seeds
        # ============================================
        def run_seed(options)
          validate_not_browser!(options, 'seed')
          build_app(options)

          if d1?(options)
            run_d1_seed(options)
          else
            run_node_seed(options)
          end

          puts "Seeds completed."
        end

        # ============================================
        # db prepare - Migrate + seed if fresh
        # ============================================
        def run_prepare(options)
          validate_not_browser!(options, 'prepare')

          # D1: also handles create if needed
          if d1?(options)
            database_id = get_database_id
            unless database_id
              puts "No D1_DATABASE_ID found. Creating database..."
              run_create(options)
            end
          end

          build_app(options)

          if d1?(options)
            run_d1_prepare(options)
          else
            run_node_prepare(options)
          end

          puts "Database prepared."
        end

        # ============================================
        # db drop - Delete database (D1 only)
        # ============================================
        def run_drop(options)
          validate_d1!(options, 'drop')

          database_id = get_database_id
          unless database_id
            abort "Error: No D1_DATABASE_ID found in .env.local"
          end

          app_name = get_app_name
          check_wrangler!

          puts "Deleting D1 database '#{app_name}' (#{database_id})..."

          unless system('npx', 'wrangler', 'd1', 'delete', database_id, '--yes')
            abort "\nError: Failed to delete database."
          end

          remove_database_id
          puts "Database deleted and removed from .env.local"
        end

        # ============================================
        # D1-specific implementations
        # ============================================

        def run_d1_migrate(options)
          Dir.chdir(DIST_DIR) do
            load_env_local
            setup_wrangler_toml

            db_name = get_db_name_from_wrangler
            check_wrangler!

            puts "Running D1 migrations..."
            unless system('npx', 'wrangler', 'd1', 'execute', db_name, '--remote',
                          '--file', 'db/migrations.sql')
              abort "\nError: Migration failed."
            end
          end
        end

        def run_d1_seed(options)
          Dir.chdir(DIST_DIR) do
            load_env_local
            setup_wrangler_toml

            unless File.exist?('db/seeds.sql')
              puts "No seeds.sql found - nothing to seed."
              return
            end

            db_name = get_db_name_from_wrangler
            check_wrangler!

            puts "Running D1 seeds..."
            unless system('npx', 'wrangler', 'd1', 'execute', db_name, '--remote',
                          '--file', 'db/seeds.sql')
              abort "\nError: Seeding failed."
            end
          end
        end

        def run_d1_prepare(options)
          Dir.chdir(DIST_DIR) do
            load_env_local
            setup_wrangler_toml

            db_name = get_db_name_from_wrangler
            check_wrangler!

            is_fresh = database_fresh?(db_name)

            puts "Running D1 migrations..."
            unless system('npx', 'wrangler', 'd1', 'execute', db_name, '--remote',
                          '--file', 'db/migrations.sql')
              abort "\nError: Migration failed."
            end

            if is_fresh && File.exist?('db/seeds.sql')
              puts "Running D1 seeds (fresh database)..."
              unless system('npx', 'wrangler', 'd1', 'execute', db_name, '--remote',
                            '--file', 'db/seeds.sql')
                abort "\nError: Seeding failed."
              end
            elsif !is_fresh
              puts "Skipping seeds (existing database)"
            end
          end
        end

        # ============================================
        # Node.js implementations (SQLite, Postgres, etc.)
        # ============================================

        def run_node_migrate(options)
          Dir.chdir(DIST_DIR) do
            load_env_local

            puts "Running migrations..."
            unless system('node', 'node_modules/ruby2js-rails/migrate.mjs', '--migrate-only')
              abort "\nError: Migration failed."
            end
          end
        end

        def run_node_seed(options)
          Dir.chdir(DIST_DIR) do
            load_env_local

            puts "Running seeds..."
            unless system('node', 'node_modules/ruby2js-rails/migrate.mjs', '--seed-only')
              abort "\nError: Seeding failed."
            end
          end
        end

        def run_node_prepare(options)
          Dir.chdir(DIST_DIR) do
            load_env_local

            puts "Running migrations and seeds..."
            unless system('node', 'node_modules/ruby2js-rails/migrate.mjs')
              abort "\nError: Database preparation failed."
            end
          end
        end

        # ============================================
        # Validation helpers
        # ============================================

        def d1?(options)
          options[:database] == 'd1'
        end

        def browser_database?(options)
          BROWSER_DATABASES.include?(options[:database])
        end

        def validate_d1!(options, command)
          unless d1?(options)
            abort "Error: 'db:#{command}' only works with D1 databases.\n" \
                  "Use: juntos db:#{command} -d d1"
          end
        end

        def validate_not_browser!(options, command)
          if browser_database?(options)
            abort "Error: Browser databases (#{options[:database]}) auto-migrate at runtime.\n" \
                  "No CLI command needed - migrations run when the app loads in the browser."
          end
        end

        # ============================================
        # D1 helper methods
        # ============================================

        def check_wrangler!
          unless system('npx', 'wrangler', '--version', out: File::NULL, err: File::NULL)
            abort "Error: wrangler not found. Install with: npm install -D wrangler"
          end
        end

        def get_app_name
          File.basename(Dir.pwd).downcase.gsub(/[^a-z0-9-]/, '-')
        end

        def get_database_id
          env_file = '.env.local'
          return nil unless File.exist?(env_file)

          File.readlines(env_file).each do |line|
            if line =~ /^D1_DATABASE_ID=(.+)$/
              return $1.strip.gsub(/["']/, '')
            end
          end

          nil
        end

        def save_database_id(database_id)
          env_file = '.env.local'
          lines = File.exist?(env_file) ? File.readlines(env_file) : []

          lines.reject! { |line| line.start_with?('D1_DATABASE_ID=') }
          lines << "D1_DATABASE_ID=#{database_id}\n"

          File.write(env_file, lines.join)
        end

        def remove_database_id
          env_file = '.env.local'
          return unless File.exist?(env_file)

          lines = File.readlines(env_file)
          lines.reject! { |line| line.start_with?('D1_DATABASE_ID=') }
          File.write(env_file, lines.join)
        end

        def load_env_local
          env_file = ".env.local"
          return unless File.exist?(env_file)

          File.readlines(env_file).each do |line|
            next if line.start_with?('#') || line.strip.empty?
            if line =~ /^([^=]+)=["']?([^"'\n]*)["']?$/
              ENV[$1] = $2
            end
          end
        end

        def setup_wrangler_toml
          return unless File.exist?('wrangler.toml')

          content = File.read('wrangler.toml')
          return unless content.include?('${D1_DATABASE_ID}')

          d1_id = ENV['D1_DATABASE_ID']
          unless d1_id
            abort "Error: D1_DATABASE_ID not set.\n" \
                  "Run 'juntos db:create' first or set it in .env.local"
          end

          updated = content.gsub('${D1_DATABASE_ID}', d1_id)
          File.write('wrangler.toml', updated)
        end

        def get_db_name_from_wrangler
          return get_app_name unless File.exist?('wrangler.toml')

          File.read('wrangler.toml').each_line do |line|
            if line =~ /database_name\s*=\s*"([^"]+)"/
              return $1
            end
          end

          get_app_name
        end

        def database_fresh?(db_name)
          output = `npx wrangler d1 execute #{db_name} --remote --command="SELECT name FROM sqlite_master WHERE type='table' AND name='schema_migrations';" 2>&1`
          !output.include?('schema_migrations')
        end

        def build_app(options)
          puts "Building application..."

          require 'ruby2js/rails/builder'

          builder_opts = {}
          builder_opts[:target] = options[:target] if options[:target]
          builder_opts[:database] = options[:database] if options[:database]

          # Default target based on database
          if d1?(options) && !builder_opts[:target]
            builder_opts[:target] = 'cloudflare'
          end

          SelfhostBuilder.new(nil, **builder_opts).build
        end
      end
    end
  end
end
