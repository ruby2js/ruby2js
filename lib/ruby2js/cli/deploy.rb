# frozen_string_literal: true

require 'optparse'
require 'fileutils'

module Ruby2JS
  module CLI
    module Deploy
      DIST_DIR = 'dist'

      # Valid deploy targets and their required databases
      TARGETS = {
        'vercel' => %w[turso neon planetscale dexie],
        'cloudflare' => %w[d1 turso dexie]
      }.freeze

      class << self
        def run(args)
          options = parse_options(args)

          validate_rails_app!
          check_installation!
          validate_target!(options)

          deploy(options)
        end

        private

        def parse_options(args)
          options = {
            target: ENV['JUNTOS_TARGET'],
            database: ENV['JUNTOS_DATABASE'],
            environment: ENV['RAILS_ENV'] || 'production',
            verbose: false,
            skip_build: false,
            force: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: juntos deploy [options]"
            opts.separator ""
            opts.separator "Build and deploy to a serverless platform."
            opts.separator ""
            opts.separator "Options:"

            opts.on("-t", "--target TARGET", TARGETS.keys, "Deploy target: #{TARGETS.keys.join(', ')}") do |target|
              options[:target] = target
            end

            opts.on("-d", "--database ADAPTER", "Database adapter for deployment") do |db|
              options[:database] = db
            end

            opts.on("-e", "--environment ENV", "Rails environment (default: production)") do |env|
              options[:environment] = env
            end

            opts.on("--skip-build", "Skip the build step (use existing dist/)") do
              options[:skip_build] = true
            end

            opts.on("-f", "--force", "Force deploy (clears remote build cache)") do
              options[:force] = true
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

        def check_installation!
          package_json = File.join(DIST_DIR, 'package.json')

          unless File.exist?(package_json)
            abort "Error: #{package_json} not found.\n" \
                  "Run 'juntos install' first to set up the project."
          end
        end

        def validate_target!(options)
          # Infer target from database if not specified
          unless options[:target]
            options[:target] = infer_target_from_database(options[:database])
          end

          unless options[:target]
            abort "Error: Deploy target required.\n" \
                  "Use -t/--target to specify: #{TARGETS.keys.join(', ')}\n\n" \
                  "Example: juntos deploy -t vercel -d turso"
          end

          unless TARGETS.key?(options[:target])
            abort "Error: Unknown target '#{options[:target]}'.\n" \
                  "Valid targets: #{TARGETS.keys.join(', ')}"
          end

          if options[:database]
            valid_dbs = TARGETS[options[:target]]
            unless valid_dbs.include?(options[:database])
              abort "Error: Database '#{options[:database]}' not supported for #{options[:target]}.\n" \
                    "Valid databases: #{valid_dbs.join(', ')}"
            end
          end
        end

        def infer_target_from_database(database)
          return nil unless database
          require 'ruby2js/rails/builder'
          target = SelfhostBuilder::DEFAULT_TARGETS[database]
          # Only return deploy-able targets (vercel, cloudflare)
          target if %w[vercel cloudflare].include?(target)
        end

        def deploy(options)
          target = options[:target]

          # Set RAILS_ENV for child processes
          ENV['RAILS_ENV'] = options[:environment]

          # Build first unless skipped
          unless options[:skip_build]
            puts "Building for #{target} (#{options[:environment]})..."
            require 'ruby2js/rails/builder'
            builder_opts = { target: target }
            builder_opts[:database] = options[:database] if options[:database]
            SelfhostBuilder.new(nil, **builder_opts).build
          end

          # Regenerate package.json with tarball URL for deploy
          regenerate_package_json_for_deploy(options)

          # Generate platform config
          generate_platform_config(target, options)

          # Verify deployment before proceeding
          verify_deployment(target, options)

          # Run platform deploy
          run_platform_deploy(target, options)
        end

        def regenerate_package_json_for_deploy(options)
          package_path = File.join(DIST_DIR, 'package.json')
          return unless File.exist?(package_path)

          require 'ruby2js/rails/builder'
          # Generate fresh package.json with tarball URL instead of local file path
          gen_options = {
            app_root: Dir.pwd,
            for_deploy: true
          }
          # Pass the database adapter so correct dependencies are included
          gen_options[:adapters] = [options[:database]] if options[:database]

          package = SelfhostBuilder.generate_package_json(gen_options)

          File.write(package_path, JSON.pretty_generate(package) + "\n")
          puts "  Updated package.json for deploy"

          # Remove package-lock.json so npm install creates a fresh one
          lock_path = File.join(DIST_DIR, 'package-lock.json')
          if File.exist?(lock_path)
            File.delete(lock_path)
            puts "  Removed stale package-lock.json"
          end
        end

        def generate_platform_config(target, options)
          case target
          when 'vercel'
            generate_vercel_config(options)
          when 'cloudflare'
            generate_cloudflare_config(options)
          end
        end

        def generate_vercel_config(options)
          # Vercel config for serverless deployment
          # App is pre-built locally, so skip Vercel's build step
          vercel_json = {
            "version" => 2,
            "buildCommand" => "",
            "routes" => [
              { "src" => "/assets/(.*)", "dest" => "/public/assets/$1" },
              { "src" => "/(.*)", "dest" => "/api/[[...path]]" }
            ]
          }
          # When forcing, clear npm cache before install
          if options[:force]
            vercel_json["installCommand"] = "npm cache clean --force && npm install"
          end

          File.write(File.join(DIST_DIR, 'vercel.json'), JSON.pretty_generate(vercel_json))
          puts "  Generated vercel.json"
          # Note: API handler is already generated by the builder with correct imports
        end

        def uses_turbo_broadcasting?
          # Check if app uses Turbo Streams broadcasting (broadcast_*_to in models or turbo_stream_from in views)
          models_dir = 'app/models'
          views_dir = 'app/views'

          # Check models for broadcast_*_to calls
          if Dir.exist?(models_dir)
            Dir.glob(File.join(models_dir, '**/*.rb')).each do |file|
              return true if File.read(file) =~ /broadcast_\w+_to/
            end
          end

          # Check views for turbo_stream_from helper
          if Dir.exist?(views_dir)
            Dir.glob(File.join(views_dir, '**/*.erb')).each do |file|
              return true if File.read(file) =~ /turbo_stream_from/
            end
          end

          false
        end

        def generate_cloudflare_config(options)
          app_name = File.basename(Dir.pwd).downcase.gsub(/[^a-z0-9-]/, '-')
          env = options[:environment] || 'production'

          # Read D1_DATABASE_ID from environment or .env.local
          # Check per-environment var first (D1_DATABASE_ID_PRODUCTION), then fallback to D1_DATABASE_ID
          env_var = env == 'development' ? 'D1_DATABASE_ID' : "D1_DATABASE_ID_#{env.upcase}"
          d1_database_id = ENV[env_var] || ENV['D1_DATABASE_ID']

          unless d1_database_id
            env_local = '.env.local'
            if File.exist?(env_local)
              File.readlines(env_local).each do |line|
                # Try per-environment var first
                if line =~ /^#{Regexp.escape(env_var)}=(.+)$/
                  d1_database_id = $1.strip
                  break
                # Fallback to D1_DATABASE_ID
                elsif line =~ /^D1_DATABASE_ID=(.+)$/ && !d1_database_id
                  d1_database_id = $1.strip
                end
              end
            end
          end

          unless d1_database_id
            abort "Error: #{env_var} not found.\n" \
                  "Set it in .env.local or as an environment variable.\n\n" \
                  "Create with: juntos db:create -d d1 -e #{env}"
          end

          uses_broadcasting = uses_turbo_broadcasting?

          wrangler_toml = <<~TOML
            name = "#{app_name}"
            main = "src/index.js"
            compatibility_date = "#{Date.today}"
            compatibility_flags = ["nodejs_compat"]
            workers_dev = true
            preview_urls = true

            # D1 database binding
            [[d1_databases]]
            binding = "DB"
            database_name = "#{app_name}"
            database_id = "#{d1_database_id}"

            # Static assets (Rails convention: public/)
            [assets]
            directory = "./public"
          TOML

          # Add Durable Objects only if app uses Turbo Streams broadcasting
          if uses_broadcasting
            wrangler_toml += <<~TOML

              # Durable Objects for Turbo Streams broadcasting
              [[durable_objects.bindings]]
              name = "TURBO_BROADCASTER"
              class_name = "TurboBroadcaster"

              [[migrations]]
              tag = "v1"
              new_sqlite_classes = ["TurboBroadcaster"]
            TOML
          end

          File.write(File.join(DIST_DIR, 'wrangler.toml'), wrangler_toml)
          puts "  Generated wrangler.toml"

          # Generate Worker entry point
          src_dir = File.join(DIST_DIR, 'src')
          FileUtils.mkdir_p(src_dir)

          imports = if uses_broadcasting
            "import { Application, Router, TurboBroadcaster } from '../lib/rails.js';"
          else
            "import { Application, Router } from '../lib/rails.js';"
          end

          exports = if uses_broadcasting
            "// Export Worker handler and Durable Object\nexport default Application.worker();\nexport { TurboBroadcaster };"
          else
            "// Export Worker handler\nexport default Application.worker();"
          end

          worker_js = <<~JS
            // Cloudflare Worker entry point
            // Generated by Juntos

            #{imports}
            import '../config/routes.js';
            import { migrations } from '../db/migrate/index.js';
            import { Seeds } from '../db/seeds.js';
            import { layout } from '../app/views/layouts/application.js';

            // Configure application
            Application.configure({
              migrations: migrations,
              seeds: Seeds,
              layout: layout
            });

            #{exports}
          JS

          File.write(File.join(src_dir, 'index.js'), worker_js)
          puts "  Generated src/index.js"
        end

        def verify_deployment(target, options)
          puts "\nVerifying deployment..."

          Dir.chdir(DIST_DIR) do
            # Clear caches when forcing
            if options[:force]
              puts "  Clearing npm cache..."
              system("npm cache clean --force --silent")
              FileUtils.rm_rf("node_modules")
              FileUtils.rm_f("package-lock.json")
            end

            # Install dependencies
            puts "  Installing dependencies..."
            unless system("npm install --silent")
              abort "Error: npm install failed. Check package.json for issues."
            end

            # Build Tailwind CSS if source exists
            tailwind_src = "app/assets/tailwind/application.css"
            if File.exist?(tailwind_src)
              puts "  Building Tailwind CSS..."
              FileUtils.mkdir_p("public/assets")
              system("npx", "tailwindcss",
                     "-i", tailwind_src,
                     "-o", "public/assets/tailwind.css",
                     "--minify")
            end

            # Determine entry point based on target
            entry_point = case target
            when 'vercel'
              "./api/[[...path]].js"
            when 'cloudflare'
              "./src/index.js"
            else
              "./config/routes.js"
            end

            # Verify the entry point module loads correctly
            puts "  Verifying module imports..."
            verify_script = <<~JS
              import('#{entry_point}')
                .then(() => process.exit(0))
                .catch(e => {
                  console.error('Module import failed:', e.message);
                  if (e.code === 'ERR_MODULE_NOT_FOUND') {
                    console.error('Missing dependency - check package.json');
                  }
                  process.exit(1);
                });
            JS

            unless system("node", "-e", verify_script)
              abort "\nError: Entry point failed to load.\n" \
                    "Fix the errors above before deploying."
            end

            # Remove package-lock.json so Vercel generates fresh one with correct hashes
            lock_path = "package-lock.json"
            File.delete(lock_path) if File.exist?(lock_path)

            puts "  ✓ Verification passed"
          end
        end

        def run_platform_deploy(target, options)
          puts "\nDeploying to #{target}..."

          case target
          when 'vercel'
            Dir.chdir(DIST_DIR) do
              if system("which vercel > /dev/null 2>&1")
                args = ["vercel", "--prod"]
                args << "--force" if options[:force]
                exec(*args)
              else
                force_flag = options[:force] ? " --force" : ""
                puts "\nTo deploy, install the Vercel CLI and run:"
                puts "  cd dist && vercel --prod#{force_flag}"
              end
            end
          when 'cloudflare'
            Dir.chdir(DIST_DIR) do
              if system("which wrangler > /dev/null 2>&1")
                exec("wrangler", "deploy")
              else
                puts "\nTo deploy, install Wrangler and run:"
                puts "  cd dist && wrangler deploy"
              end
            end
          end
        end
      end
    end
  end
end
