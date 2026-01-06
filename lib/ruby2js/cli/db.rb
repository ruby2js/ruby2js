# frozen_string_literal: true

require 'optparse'
require 'fileutils'
require 'json'
require 'yaml'

module Ruby2JS
  module CLI
    module Db
      DIST_DIR = 'dist'
      SUBCOMMANDS = %w[create migrate seed prepare drop reset].freeze

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

          # Load database config from database.yml (CLI options override)
          load_database_config!(options)

          send("run_#{subcommand}", options)
        end

        private

        def parse_options(args)
          options = {
            database: ENV['JUNTOS_DATABASE'],
            target: ENV['JUNTOS_TARGET'],
            environment: ENV['RAILS_ENV'] || ENV['NODE_ENV'],
            verbose: false,
            yes: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: juntos db <command> [options]"

            opts.on("-d", "--database ADAPTER", "Database adapter (overrides database.yml)") do |db|
              options[:database] = db
            end

            opts.on("-t", "--target TARGET", "Target runtime") do |target|
              options[:target] = target
            end

            opts.on("-e", "--environment ENV", "Rails environment (default: development)") do |env|
              options[:environment] = env
            end

            opts.on("-y", "--yes", "Skip confirmation prompts (migrate, seed)") do
              options[:yes] = true
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

        # Load database configuration from config/database.yml
        # Priority: CLI options > environment variables > database.yml > defaults
        def load_database_config!(options)
          env = options[:environment] || 'development'
          ENV['RAILS_ENV'] = env  # Set for child processes

          # If CLI provided database, use it (already set in options)
          if options[:database]
            # Derive database name from environment if not in config
            options[:db_name] ||= "#{File.basename(Dir.pwd)}_#{env}".downcase.gsub(/[^a-z0-9_]/, '_')
            return
          end

          # Try to load from config/database.yml
          config_path = 'config/database.yml'
          if File.exist?(config_path)
            begin
              config = YAML.load_file(config_path, aliases: true)
              if config && config[env]
                env_config = config[env]
                options[:database] ||= env_config['adapter']
                options[:db_name] ||= env_config['database']
                options[:target] ||= env_config['target']
              end
            rescue => e
              warn "Warning: Could not parse #{config_path}: #{e.message}"
            end
          end

          # Defaults
          options[:database] ||= 'sqlite'
          options[:db_name] ||= "#{File.basename(Dir.pwd)}_#{env}".downcase.gsub(/[^a-z0-9_]/, '_')
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
              reset     Drop, create, migrate, and seed
              create    Create database (D1, Turso)
              drop      Delete database (D1, Turso, SQLite)

            Options:
              -d, --database ADAPTER   Database adapter (d1, sqlite, neon, turso, etc.)
              -e, --environment ENV    Rails environment (development, production, etc.)
              -t, --target TARGET      Target runtime (cloudflare, vercel, node, etc.)
              -y, --yes                Skip confirmation prompts (migrate, seed)
              -v, --verbose            Show detailed output
              -h, --help               Show this help message

            Examples:
              juntos db:migrate                    # Run migrations (uses database.yml)
              juntos db:seed                       # Run seeds
              juntos db:prepare                    # Migrate + seed if fresh
              juntos db:prepare -e production      # Prepare production database
              juntos db:create                     # Create database (D1, Turso)
              juntos db:drop                       # Delete database

            Configuration:
              Database settings are read from config/database.yml based on RAILS_ENV.
              Use -d to override the adapter, -e to set the environment.

            Note: Browser databases (dexie) auto-migrate at runtime.
          HELP
        end

        # ============================================
        # db create - Create database
        # ============================================
        def run_create(options)
          db = options[:database]

          case db
          when 'd1'
            run_d1_create(options)
          when 'turso'
            run_turso_create(options)
          when 'better_sqlite3', 'sqlite', 'sql.js'
            puts "SQLite databases are created automatically by db:migrate."
            puts "Run 'juntos db:migrate' to create and initialize the database."
          when 'dexie'
            puts "Dexie (IndexedDB) databases are created automatically in the browser."
            puts "No CLI action needed."
          when 'neon'
            puts "Neon databases are managed via the Neon console or CLI."
            puts "Visit: https://console.neon.tech/"
            puts "Or install the Neon CLI: npm install -g neonctl"
          when 'planetscale'
            puts "PlanetScale databases are managed via the PlanetScale console or CLI."
            puts "Visit: https://app.planetscale.com/"
            puts "Or use: pscale database create <name>"
          else
            puts "Database creation for '#{db || 'unknown'}' is not supported via CLI."
            puts "Please create your database using your database provider's tools."
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

          env = options[:environment] || 'development'

          # D1: also handles create if needed
          if d1?(options)
            database_id = get_database_id(env)
            unless database_id
              puts "No #{d1_env_var(env)} found. Creating database..."
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
        # db drop - Delete database
        # ============================================
        def run_drop(options)
          db = options[:database]

          case db
          when 'd1'
            run_d1_drop(options)
          when 'turso'
            run_turso_drop(options)
          when 'better_sqlite3', 'sqlite'
            run_sqlite_drop(options)
          when 'sql.js'
            puts "sql.js uses in-memory databases that don't persist."
            puts "No action needed."
          when 'dexie'
            puts "Dexie (IndexedDB) databases are managed by the browser."
            puts "Use browser DevTools > Application > IndexedDB to delete."
          when 'neon'
            puts "Neon databases are managed via the Neon console or CLI."
            puts "Visit: https://console.neon.tech/"
            puts "Or use: neonctl databases delete <name>"
          when 'planetscale'
            puts "PlanetScale databases are managed via the PlanetScale console or CLI."
            puts "Visit: https://app.planetscale.com/"
            puts "Or use: pscale database delete <name>"
          else
            puts "Database deletion for '#{db || 'unknown'}' is not supported via CLI."
            puts "Please delete your database using your database provider's tools."
          end
        end

        # ============================================
        # db reset - Drop, create, migrate, seed
        # ============================================
        def run_reset(options)
          validate_not_browser!(options, 'reset')

          db = options[:database]
          env = options[:environment] || 'development'

          puts "Resetting #{db} database for #{env}..."
          puts

          # Step 1: Drop (may prompt for confirmation)
          puts "Step 1/4: Dropping database..."
          run_drop(options)
          puts

          # Step 2: Create (for databases that need explicit creation)
          if %w[d1 turso].include?(db)
            puts "Step 2/4: Creating database..."
            run_create(options)
            puts
          else
            puts "Step 2/4: Skipping create (#{db} creates automatically)"
            puts
          end

          # Step 3: Migrate
          puts "Step 3/4: Running migrations..."
          build_app(options)
          if d1?(options)
            run_d1_migrate(options)
          else
            run_node_migrate(options)
          end
          puts

          # Step 4: Seed
          puts "Step 4/4: Running seeds..."
          if d1?(options)
            run_d1_seed(options)
          else
            run_node_seed(options)
          end

          puts
          puts "Database reset complete."
        end

        # ============================================
        # D1-specific implementations
        # ============================================

        def run_d1_create(options)
          db_name = options[:db_name]
          env = options[:environment] || 'development'
          puts "Creating D1 database '#{db_name}' for #{env}..."

          check_wrangler!

          output = `npx wrangler d1 create #{db_name} 2>&1`
          puts output if options[:verbose]

          # Match JSON format: "database_id": "xxx" or TOML format: database_id = "xxx"
          if output =~ /"?database_id"?\s*[=:]\s*"?([a-f0-9-]+)"?/i
            database_id = $1
            save_database_id(database_id, env)
            puts "Created D1 database: #{db_name}"
            puts "Database ID: #{database_id}"
            puts "Saved to .env.local (#{d1_env_var(env)})"
          elsif output.include?('already exists')
            puts "Database '#{db_name}' already exists."
            puts "Use 'juntos db:drop' first if you want to recreate it."
          else
            abort "Error: Failed to create database.\n#{output}"
          end
        end

        def run_d1_drop(options)
          db_name = options[:db_name]
          env = options[:environment] || 'development'
          database_id = get_database_id(env)

          unless database_id
            abort "Error: No #{d1_env_var(env)} found in .env.local"
          end

          check_wrangler!

          puts "Deleting D1 database '#{db_name}' (#{database_id})..."

          # Let wrangler prompt for confirmation - this is destructive
          unless system('npx', 'wrangler', 'd1', 'delete', db_name)
            abort "\nError: Failed to delete database."
          end

          remove_database_id(env)
          puts "Database deleted and removed from .env.local"
        end

        def run_d1_migrate(options)
          db_name = options[:db_name]
          env = options[:environment] || 'development'

          Dir.chdir(DIST_DIR) do
            load_env_local
            setup_wrangler_toml(env)

            check_wrangler!

            cmd = ['npx', 'wrangler', 'd1', 'execute', db_name, '--remote', '--file', 'db/migrations.sql']
            cmd << '--yes' if options[:yes]

            puts "Running D1 migrations on '#{db_name}'..."
            unless system(*cmd)
              abort "\nError: Migration failed."
            end
          end
        end

        def run_d1_seed(options)
          db_name = options[:db_name]
          env = options[:environment] || 'development'

          Dir.chdir(DIST_DIR) do
            load_env_local
            setup_wrangler_toml(env)

            unless File.exist?('db/seeds.sql')
              puts "No seeds.sql found - nothing to seed."
              return
            end

            check_wrangler!

            cmd = ['npx', 'wrangler', 'd1', 'execute', db_name, '--remote', '--file', 'db/seeds.sql']
            cmd << '--yes' if options[:yes]

            puts "Running D1 seeds on '#{db_name}'..."
            unless system(*cmd)
              abort "\nError: Seeding failed."
            end
          end
        end

        def run_d1_prepare(options)
          db_name = options[:db_name]
          env = options[:environment] || 'development'

          Dir.chdir(DIST_DIR) do
            load_env_local
            setup_wrangler_toml(env)

            check_wrangler!

            is_fresh = database_fresh?(db_name)

            # Always skip prompts for prepare - database unavailability is expected
            puts "Running D1 migrations..."
            unless system('npx', 'wrangler', 'd1', 'execute', db_name, '--remote',
                          '--file', 'db/migrations.sql', '--yes')
              abort "\nError: Migration failed."
            end

            if is_fresh && File.exist?('db/seeds.sql')
              puts "Running D1 seeds (fresh database)..."
              unless system('npx', 'wrangler', 'd1', 'execute', db_name, '--remote',
                            '--file', 'db/seeds.sql', '--yes')
                abort "\nError: Seeding failed."
              end
            elsif !is_fresh
              puts "Skipping seeds (existing database)"
            end
          end
        end

        # ============================================
        # Turso implementations
        # ============================================

        def run_turso_create(options)
          db_name = options[:db_name]
          env = options[:environment] || 'development'

          unless turso_cli_available?
            puts "Turso CLI not found. Install it first:"
            puts "  curl -sSfL https://get.tur.so/install.sh | bash"
            puts "\nOr create the database at: https://turso.tech/app"
            return
          end

          puts "Creating Turso database '#{db_name}' for #{env}..."

          output = `turso db create #{db_name} 2>&1`
          if $?.success?
            puts "Created Turso database: #{db_name}"
            puts "\nTo get your connection URL, run:"
            puts "  turso db show #{db_name} --url"
            puts "  turso db tokens create #{db_name}"
            puts "\nAdd these to .env.local:"
            puts "  TURSO_DATABASE_URL=libsql://#{db_name}-<org>.turso.io"
            puts "  TURSO_AUTH_TOKEN=<token>"
          else
            abort "Error: Failed to create database.\n#{output}"
          end
        end

        def run_turso_drop(options)
          db_name = options[:db_name]
          env = options[:environment] || 'development'

          unless turso_cli_available?
            puts "Turso CLI not found. Delete the database at:"
            puts "  https://turso.tech/app"
            return
          end

          puts "Deleting Turso database '#{db_name}' (#{env})..."

          # Let turso prompt for confirmation - this is destructive
          unless system('turso', 'db', 'destroy', db_name)
            abort "\nError: Failed to delete database."
          end

          puts "Database deleted."
        end

        def turso_cli_available?
          system('turso', '--version', out: File::NULL, err: File::NULL)
        end

        # ============================================
        # SQLite implementations
        # ============================================

        def run_sqlite_drop(options)
          # Find the database file
          db_file = find_sqlite_database

          unless db_file
            puts "No SQLite database file found."
            puts "Looked for: db/*.sqlite3, db/*.db, *.sqlite3, *.db"
            return
          end

          puts "Deleting SQLite database: #{db_file}"
          File.delete(db_file)
          puts "Database deleted."
        end

        def find_sqlite_database
          # Common SQLite database locations
          patterns = [
            'db/development.sqlite3',
            'db/production.sqlite3',
            'db/*.sqlite3',
            'db/*.db',
            '*.sqlite3',
            '*.db'
          ]

          patterns.each do |pattern|
            matches = Dir.glob(pattern)
            return matches.first if matches.any?
          end

          nil
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

        # Environment variable name for D1 database ID
        # development uses D1_DATABASE_ID, others use D1_DATABASE_ID_PRODUCTION, etc.
        def d1_env_var(env = 'development')
          env == 'development' ? 'D1_DATABASE_ID' : "D1_DATABASE_ID_#{env.upcase}"
        end

        def get_database_id(env = 'development')
          env_file = '.env.local'
          return nil unless File.exist?(env_file)

          var_name = d1_env_var(env)
          fallback_id = nil

          File.readlines(env_file).each do |line|
            # Try per-environment var first
            if line =~ /^#{Regexp.escape(var_name)}=(.+)$/
              return $1.strip.gsub(/["']/, '')
            # Track D1_DATABASE_ID as fallback for backwards compatibility
            elsif line =~ /^D1_DATABASE_ID=(.+)$/
              fallback_id = $1.strip.gsub(/["']/, '')
            end
          end

          # Fall back to D1_DATABASE_ID if per-environment var not found
          fallback_id
        end

        def save_database_id(database_id, env = 'development')
          env_file = '.env.local'
          lines = File.exist?(env_file) ? File.readlines(env_file) : []

          var_name = d1_env_var(env)
          lines.reject! { |line| line.start_with?("#{var_name}=") }
          lines << "#{var_name}=#{database_id}\n"

          File.write(env_file, lines.join)
        end

        def remove_database_id(env = 'development')
          env_file = '.env.local'
          return unless File.exist?(env_file)

          var_name = d1_env_var(env)
          lines = File.readlines(env_file)
          lines.reject! { |line| line.start_with?("#{var_name}=") }
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

        def setup_wrangler_toml(env = 'development')
          return unless File.exist?('wrangler.toml')

          content = File.read('wrangler.toml')
          return unless content.include?('${D1_DATABASE_ID}')

          var_name = d1_env_var(env)
          # Try per-environment var first, fall back to D1_DATABASE_ID for backwards compatibility
          d1_id = ENV[var_name] || ENV['D1_DATABASE_ID']
          unless d1_id
            abort "Error: #{var_name} not set.\n" \
                  "Run 'juntos db:create -e #{env}' first or set it in .env.local"
          end

          updated = content.gsub('${D1_DATABASE_ID}', d1_id)
          File.write('wrangler.toml', updated)
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
