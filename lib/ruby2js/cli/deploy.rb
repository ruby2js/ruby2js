# frozen_string_literal: true

require 'optparse'

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
            verbose: false,
            skip_build: false,
            skip_migrate: false,
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

            opts.on("--skip-build", "Skip the build step (use existing dist/)") do
              options[:skip_build] = true
            end

            opts.on("--skip-migrate", "Skip running migrations") do
              options[:skip_migrate] = true
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

        def deploy(options)
          target = options[:target]

          # Build first unless skipped
          unless options[:skip_build]
            puts "Building for #{target}..."
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

          # Run migrations locally (better error output, faster)
          unless options[:skip_migrate]
            run_migrations_locally(options)
          end

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
          # Migrations run locally before deploy, so no buildCommand needed
          vercel_json = {
            "version" => 2,
            "routes" => [
              { "src" => "/app/assets/(.*)", "dest" => "/app/assets/$1" },
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

        def generate_cloudflare_config(options)
          wrangler_toml = <<~TOML
            name = "#{File.basename(Dir.pwd)}"
            main = "worker.js"
            compatibility_date = "#{Date.today}"

            [site]
            bucket = "./public"
          TOML

          File.write(File.join(DIST_DIR, 'wrangler.toml'), wrangler_toml)
          puts "  Generated wrangler.toml"

          # Generate worker
          worker_js = <<~JS
            // Cloudflare Worker - auto-generated by Juntos
            import { Application } from './config/routes.js';

            export default {
              async fetch(request, env, ctx) {
                return Application.handleRequest(request, env);
              }
            };
          JS

          File.write(File.join(DIST_DIR, 'worker.js'), worker_js)
          puts "  Generated worker.js"
        end

        def verify_deployment(target, options)
          puts "\nVerifying deployment..."

          Dir.chdir(DIST_DIR) do
            # Install dependencies
            puts "  Installing dependencies..."
            unless system("npm install --silent")
              abort "Error: npm install failed. Check package.json for issues."
            end

            # Determine entry point based on target
            entry_point = case target
            when 'vercel'
              "./api/[[...path]].js"
            when 'cloudflare'
              "./worker.js"
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

        def run_migrations_locally(options)
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
              abort "\nError: Migration failed.\n" \
                    "Fix the errors above before deploying."
            end
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
