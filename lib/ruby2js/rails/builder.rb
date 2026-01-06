#!/usr/bin/env ruby
# Build script for Ruby2JS-on-Rails apps
# Transpiles Ruby models and controllers to JavaScript
#
# Can be required: require 'ruby2js/rails/builder'
# Or transpiled to JS: import { SelfhostBuilder } from 'ruby2js-rails/build.mjs'

require 'fileutils'
require 'json'
require 'pathname'
require 'yaml'

# Ensure we're using the local ruby2js
$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)
require 'ruby2js'
# Explicitly require each Rails sub-filter for JS transpilation compatibility
require 'ruby2js/filter/rails/model'
require 'ruby2js/filter/rails/controller'
require 'ruby2js/filter/rails/routes'
require 'ruby2js/filter/rails/seeds'
require 'ruby2js/filter/rails/migration'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/return'
require 'ruby2js/filter/erb'
require 'ruby2js/filter/rails/helpers'
require 'ruby2js/filter/phlex'
require 'ruby2js/filter/stimulus'
require 'ruby2js/filter/camelCase'
require_relative 'erb_compiler'
require_relative 'migration_sql'
require_relative 'seed_sql'

class SelfhostBuilder
  # JS (Node.js): use process.cwd() since bin commands run from app root
  # Ruby: use current working directory (assumes run from app root)
  DEMO_ROOT = if defined?(process)
    process.cwd()
  else
    Dir.pwd
  end

  # Server-side JavaScript runtimes
  SERVER_RUNTIMES = ['node', 'bun', 'deno', 'cloudflare', 'vercel-edge', 'vercel-node'].freeze

  # Vercel deployment targets
  VERCEL_RUNTIMES = ['vercel-edge', 'vercel-node'].freeze

  # Databases that require a specific runtime
  RUNTIME_REQUIRED = {
    'd1' => 'cloudflare'
  }.freeze

  # Valid target environments for each database adapter
  VALID_TARGETS = {
    'dexie' => ['browser'],
    'indexeddb' => ['browser'],
    'sqljs' => ['browser'],
    'sql.js' => ['browser'],
    'pglite' => ['browser', 'node'],
    'better_sqlite3' => ['node', 'bun'],
    'sqlite3' => ['node', 'bun'],
    'pg' => ['node', 'bun', 'deno'],
    'postgres' => ['node', 'bun', 'deno'],
    'postgresql' => ['node', 'bun', 'deno'],
    'mysql2' => ['node', 'bun'],
    'mysql' => ['node', 'bun'],
    'd1' => ['cloudflare'],
    'neon' => ['browser', 'node', 'bun', 'deno', 'cloudflare', 'vercel-edge', 'vercel-node'],
    'turso' => ['browser', 'node', 'bun', 'deno', 'cloudflare', 'vercel-edge', 'vercel-node'],
    'libsql' => ['browser', 'node', 'bun', 'deno', 'cloudflare', 'vercel-edge', 'vercel-node'],
    'planetscale' => ['browser', 'node', 'bun', 'deno', 'cloudflare', 'vercel-edge', 'vercel-node']
  }.freeze

  # Default target for each database adapter (used when target not specified)
  DEFAULT_TARGETS = {
    # Browser-only databases
    'dexie' => 'browser',
    'indexeddb' => 'browser',
    'sqljs' => 'browser',
    'sql.js' => 'browser',
    'pglite' => 'browser',
    # TCP-based server databases
    'better_sqlite3' => 'node',
    'sqlite3' => 'node',
    'sqlite' => 'node',
    'pg' => 'node',
    'postgres' => 'node',
    'postgresql' => 'node',
    'mysql2' => 'node',
    'mysql' => 'node',
    # Platform-specific databases
    'd1' => 'cloudflare',
    # HTTP-based edge databases
    'neon' => 'vercel',
    'turso' => 'vercel',
    'libsql' => 'vercel',
    'planetscale' => 'vercel'
  }.freeze

  # Map DATABASE env var to adapter source file
  ADAPTER_FILES = {
    # Browser adapters
    'sqljs' => 'active_record_sqljs.mjs',
    'sql.js' => 'active_record_sqljs.mjs',
    'dexie' => 'active_record_dexie.mjs',
    'indexeddb' => 'active_record_dexie.mjs',
    'pglite' => 'active_record_pglite.mjs',
    # Node.js adapters
    'better_sqlite3' => 'active_record_better_sqlite3.mjs',
    'sqlite3' => 'active_record_better_sqlite3.mjs',  # Alias
    'sqlite' => 'active_record_better_sqlite3.mjs',   # Alias
    'pg' => 'active_record_pg.mjs',
    'postgres' => 'active_record_pg.mjs',
    'postgresql' => 'active_record_pg.mjs',
    'mysql2' => 'active_record_mysql2.mjs',
    'mysql' => 'active_record_mysql2.mjs',
    # Cloudflare adapters
    'd1' => 'active_record_d1.mjs',
    # Universal adapters (HTTP-based, work on browser/node/edge)
    'neon' => 'active_record_neon.mjs',
    'turso' => 'active_record_turso.mjs',
    'libsql' => 'active_record_turso.mjs',
    'planetscale' => 'active_record_planetscale.mjs'
  }.freeze

  # Common transpilation options for Ruby files
  OPTIONS = {
    eslevel: 2022,
    include: [:class, :call],
    autoexports: true,
    filters: [
      Ruby2JS::Filter::Rails::Model,
      Ruby2JS::Filter::Rails::Controller,
      Ruby2JS::Filter::Rails::Routes,
      Ruby2JS::Filter::Rails::Seeds,
      Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::ESM,
      Ruby2JS::Filter::Return
    ]
  }.freeze

  # Options for Stimulus controllers
  # Uses Stimulus filter instead of Rails::Controller for proper ES class output
  # autoexports: :default produces 'export default class' (Rails convention)
  STIMULUS_OPTIONS = {
    eslevel: 2022,
    include: [:class, :call],
    autoexports: :default,
    filters: [
      Ruby2JS::Filter::Stimulus,
      Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::ESM,
      Ruby2JS::Filter::Return
    ]
  }.freeze

  # Options for ERB templates
  # Note: Rails::Helpers must come BEFORE Erb for method overrides to work
  ERB_OPTIONS = {
    eslevel: 2022,
    include: [:class, :call],
    filters: [
      Ruby2JS::Filter::Rails::Helpers,
      Ruby2JS::Filter::Erb,
      Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::Return
    ]
  }.freeze

  # Options for database migrations
  MIGRATION_OPTIONS = {
    eslevel: 2022,
    include: [:class, :call],
    filters: [
      Ruby2JS::Filter::Rails::Migration,
      Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::ESM,
      Ruby2JS::Filter::Return
    ]
  }.freeze

  # ============================================================
  # Class methods for shared functionality
  # These can be called by SPA builder, CLI commands, etc.
  # ============================================================

  # Load database configuration from environment or config/database.yml
  # Returns: { 'adapter' => 'dexie', 'database' => 'myapp_dev', ... }
  def self.load_database_config(app_root = nil, quiet: false)
    app_root ||= DEMO_ROOT
    env = ENV['RAILS_ENV'] || ENV['NODE_ENV'] || 'development'

    # Priority 1: JUNTOS_DATABASE or DATABASE environment variable
    db_env = ENV['JUNTOS_DATABASE'] || ENV['DATABASE']
    if db_env
      puts("  Using #{ENV['JUNTOS_DATABASE'] ? 'JUNTOS_DATABASE' : 'DATABASE'}=#{db_env} from environment") unless quiet
      return { 'adapter' => db_env.downcase }
    end

    # Priority 2: config/database.yml
    config_path = File.join(app_root, 'config/database.yml')
    if File.exist?(config_path)
      # Ruby 3.4+/4.0+ requires aliases: true for YAML anchors used by Rails
      config = YAML.load_file(config_path, aliases: true)
      if config && config[env] && config[env]['adapter']
        puts("  Using config/database.yml [#{env}]") unless quiet
        return config[env]
      end
    end

    # Default: sqljs
    puts("  Using default adapter: sqljs") unless quiet
    { 'adapter' => 'sqljs', 'database' => 'ruby2js_rails' }
  end

  # Detect runtime/target from database configuration
  # Returns: { target: 'browser'|'server', runtime: nil|'node'|'bun'|'deno', database: 'adapter_name' }
  # Priority: JUNTOS_* env vars > database.yml target > inferred from adapter
  def self.detect_runtime(app_root = nil)
    # Check for CLI overrides first
    database = ENV['JUNTOS_DATABASE']
    target = ENV['JUNTOS_TARGET']

    # Fall back to database.yml
    unless database
      db_config = self.load_database_config(app_root, quiet: true)
      database = db_config['adapter'] || db_config[:adapter] || 'sqljs'
      target ||= db_config['target'] || db_config[:target]
    end

    # Infer target from database if not specified
    target ||= DEFAULT_TARGETS[database] || 'node'

    runtime = nil
    if target != 'browser'
      required = RUNTIME_REQUIRED[database]
      runtime = required || target
    end

    { target: target, runtime: runtime, database: database }
  end

  # Generate package.json content for a Ruby2JS app
  # Options:
  #   app_name: Application name (used for package name)
  #   app_root: Application root directory
  # Returns: Hash suitable for JSON.generate
  # Note: Database and target-specific dependencies are added at build time
  def self.generate_package_json(options = {})
    app_name = options[:app_name] || 'ruby2js-app'
    app_root = options[:app_root]

    # Check for local packages directory (when running from ruby2js repo)
    # For deploy targets, always use tarball URL since deployed code can't access local files
    gem_root = File.expand_path("../../..", __dir__)
    local_package = File.join(gem_root, "packages/ruby2js-rails")
    # Path is relative to dist/ directory where package.json lives
    dist_dir = File.join(app_root || Dir.pwd, 'dist')

    use_local = File.directory?(local_package) && !options[:for_deploy]
    deps = if use_local
      relative_path = Pathname.new(local_package).relative_path_from(Pathname.new(dist_dir))
      { 'ruby2js-rails' => "file:#{relative_path}" }
    else
      { 'ruby2js-rails' => 'https://www.ruby2js.com/releases/ruby2js-rails-beta.tgz' }
    end

    # Hotwire Turbo and Stimulus - used by all targets
    deps['@hotwired/turbo'] = '^8.0.0'
    deps['@hotwired/stimulus'] = '^3.2.0'

    # Add tailwindcss if tailwindcss-rails gem is detected
    tailwind_css = app_root ? File.join(app_root, 'app/assets/tailwind/application.css') : 'app/assets/tailwind/application.css'
    if File.exist?(tailwind_css)
      deps['tailwindcss'] = '^3.4.0'
    end

    # Base scripts - server scripts added at build time based on target
    scripts = {
      'dev' => 'ruby2js-rails-dev',
      'dev:ruby' => 'ruby2js-rails-dev --ruby',
      'build' => 'ruby2js-rails-build',
      'migrate' => 'ruby2js-rails-migrate',
      'start' => 'npx serve -s -p 3000',
      # Server scripts included by default - they just won't work without deps
      'start:node' => 'ruby2js-rails-server',
      'start:bun' => 'bun node_modules/ruby2js-rails/server.mjs',
      'start:deno' => 'deno run --allow-all node_modules/ruby2js-rails/server.mjs'
    }

    {
      'name' => app_name.to_s.gsub('_', '-'),
      'version' => '0.1.0',
      'type' => 'module',
      'description' => 'Rails-like app powered by Ruby2JS',
      'scripts' => scripts,
      'dependencies' => deps
    }
  end

  # Map database adapters to their required npm dependencies
  # Each entry specifies: { package_name => version }
  ADAPTER_DEPENDENCIES = {
    # Browser-only adapters
    'dexie' => { 'dexie' => '^4.0.10' },
    'indexeddb' => { 'dexie' => '^4.0.10' },
    'sqljs' => { 'sql.js' => '^1.11.0' },
    'sql.js' => { 'sql.js' => '^1.11.0' },
    'pglite' => { '@electric-sql/pglite' => '^0.2.0' },
    # Node-only adapters (native modules - use optionalDependencies)
    'sqlite' => { 'better-sqlite3' => '^11.0.0' },
    'sqlite3' => { 'better-sqlite3' => '^11.0.0' },
    'better_sqlite3' => { 'better-sqlite3' => '^11.0.0' },
    'pg' => { 'pg' => '^8.13.0' },
    'postgres' => { 'pg' => '^8.13.0' },
    'postgresql' => { 'pg' => '^8.13.0' },
    'mysql' => { 'mysql2' => '^3.11.0' },
    'mysql2' => { 'mysql2' => '^3.11.0' },
    # Universal adapters (work on browser, node, and edge)
    'neon' => { '@neondatabase/serverless' => '^0.10.0' },
    'turso' => { '@libsql/client' => '^0.14.0' },
    'libsql' => { '@libsql/client' => '^0.14.0' },
    'planetscale' => { '@planetscale/database' => '^1.19.0' }
  }.freeze

  # Adapters that require native compilation (should be optionalDependencies)
  NATIVE_ADAPTERS = %w[sqlite sqlite3 better_sqlite3 pg postgres postgresql mysql mysql2].freeze

  # Ensure package.json has required dependencies for the selected adapter and target
  # Updates the file if dependencies are missing and returns true if npm install is needed
  def ensure_adapter_dependencies()
    package_path = File.join(@dist_dir, 'package.json')
    return false unless File.exist?(package_path)

    package = JSON.parse(File.read(package_path))
    deps = package['dependencies'] || {}
    optional_deps = package['optionalDependencies'] || {}
    updated = false

    # Add adapter-specific dependencies
    required = ADAPTER_DEPENDENCIES[@database]
    if required
      # Native adapters go to optionalDependencies (may fail to compile on some platforms)
      is_native = NATIVE_ADAPTERS.include?(@database)
      target_deps = is_native ? optional_deps : deps
      dep_type = is_native ? 'optional dependency' : 'dependency'

      missing = required.reject { |name, _version| target_deps.key?(name) || deps.key?(name) }
      missing.each do |name, version|
        target_deps[name] = version
        puts("  Adding #{dep_type}: #{name}@#{version}")
        updated = true
      end
    end

    # Add ws for Node/Bun/Deno targets (WebSocket support for real-time features)
    node_targets = %w[node bun deno]
    if node_targets.include?(@target.to_s) && !optional_deps.key?('ws')
      optional_deps['ws'] = '^8.18.0'
      puts("  Adding optional dependency: ws@^8.18.0")
      updated = true
    end

    return false unless updated

    package['dependencies'] = deps
    package['optionalDependencies'] = optional_deps unless optional_deps.empty?
    File.write(package_path, JSON.pretty_generate(package) + "\n")
    puts("  Updated package.json")

    true  # npm install needed
  end

  # Common importmap entries for all browser builds
  COMMON_IMPORTMAP_ENTRIES = {
    '@hotwired/turbo' => '/node_modules/@hotwired/turbo/dist/turbo.es2017-esm.js',
    '@hotwired/stimulus' => '/node_modules/@hotwired/stimulus/dist/stimulus.js'
  }.freeze

  # Database-specific importmap entries for browser builds
  IMPORTMAP_ENTRIES = {
    'dexie' => { 'dexie' => '/node_modules/dexie/dist/dexie.mjs' },
    'indexeddb' => { 'dexie' => '/node_modules/dexie/dist/dexie.mjs' },
    'sqljs' => { 'sql.js' => '/node_modules/sql.js/dist/sql-wasm.js' },
    'sql.js' => { 'sql.js' => '/node_modules/sql.js/dist/sql-wasm.js' },
    'pglite' => { '@electric-sql/pglite' => '/node_modules/@electric-sql/pglite/dist/index.js' }
  }.freeze

  # Generate index.html for browser builds
  # Options:
  #   app_name: Application name (for title)
  #   database: Database adapter (for importmap)
  #   css: CSS framework ('none', 'tailwind', 'pico', 'bootstrap', 'bulma')
  #   output_path: Where to write the file (if nil, returns string)
  # Returns: HTML string (also writes to output_path if specified)
  def self.generate_index_html(options = {})
    app_name = options[:app_name] || 'Ruby2JS App'
    database = options[:database] || 'dexie'
    css = options[:css] || 'none'
    output_path = options[:output_path]
    # Base path for assets - '/dist' when serving from app root, '' when serving from dist/
    base_path = options[:base_path] || '/dist'

    # Build importmap - merge common entries with database-specific entries
    db_entries = IMPORTMAP_ENTRIES[database] || IMPORTMAP_ENTRIES['dexie']
    importmap_entries = COMMON_IMPORTMAP_ENTRIES.merge(db_entries)
    importmap = {
      'imports' => importmap_entries
    }

    # CSS link based on framework
    # This method is only used for browser targets, which serve from dist/ root
    css_link = case css.to_s
    when 'tailwind'
      '<link href="/public/assets/tailwind.css" rel="stylesheet">'
    when 'pico'
      '<link rel="stylesheet" href="/node_modules/@picocss/pico/css/pico.min.css">'
    when 'bootstrap'
      '<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">'
    when 'bulma'
      '<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bulma@0.9.4/css/bulma.min.css">'
    else
      '' # No default CSS - apps without a framework don't need a stylesheet link
    end

    # Main container class based on CSS framework
    main_class = case css.to_s
    when 'pico' then 'container'
    when 'bootstrap' then 'container mt-4'
    when 'bulma' then 'container mt-4'
    when 'tailwind' then 'container mx-auto mt-28 px-5'
    else '' # No classes without a CSS framework
    end

    html = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{app_name}</title>
        #{css_link}
        <script type="importmap">
        #{JSON.pretty_generate(importmap)}
        </script>
      </head>
      <body>
        <div id="loading">Loading...</div>
        <div id="app" style="display:none">
          <main class="#{main_class}" id="content"></main>
        </div>
        <script type="module">
          import * as Turbo from '@hotwired/turbo';
          import { Application } from '#{base_path}/config/routes.js';
          import '#{base_path}/app/javascript/controllers/index.js';
          window.Turbo = Turbo;
          Application.start();
        </script>
      </body>
      </html>
    HTML

    if output_path
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, html)
    end

    html
  end

  # ============================================================
  # Instance methods
  # ============================================================

  def initialize(dist_dir = nil, target: nil, database: nil)
    @dist_dir = dist_dir || File.join(DEMO_ROOT, 'dist')
    @database_override = database  # CLI override for database adapter
    @database = nil  # Set during build from config or override
    @target = target # Can be set explicitly or derived from database
    @runtime = nil   # For server targets: 'node', 'bun', or 'deno'
    @model_associations = {}  # model_name -> [association_names]
  end

  # Note: Using explicit () on all method calls for JS transpilation compatibility
  def build()
    # Clean dist directory but preserve package.json, package-lock.json, and node_modules
    # These are managed by ruby2js install and shouldn't be removed during builds
    # Also preserve database files (SQLite, etc.)
    if File.directory?(@dist_dir)
      Dir.glob(File.join(@dist_dir, '*')).each do |path|
        basename = File.basename(path)
        next if ['package.json', 'package-lock.json', 'node_modules'].include?(basename)
        # Preserve SQLite database files (including WAL mode files)
        next if basename.end_with?('.sqlite3', '.db', '-shm', '-wal')
        FileUtils.rm_rf(path)
      end
    else
      FileUtils.mkdir_p(@dist_dir)
    end

    puts("=== Building Ruby2JS-on-Rails Demo ===")
    puts("")

    # Load database config and derive target (unless explicitly set)
    # Priority: CLI option > database.yml target > inferred from adapter
    puts("Database Adapter:")
    if @database_override
      puts("  CLI override: #{@database_override}")
      @database = @database_override
    else
      db_config = self.load_database_config()
      @database = db_config['adapter'] || db_config[:adapter] || 'sqljs'
    end
    @target ||= ENV['JUNTOS_TARGET'] || DEFAULT_TARGETS[@database] || 'node'

    # Set runtime based on target
    if @target == 'browser'
      @runtime = nil  # Browser target doesn't use a JS runtime
    else
      # Check if database requires a specific runtime
      required_runtime = RUNTIME_REQUIRED[@database]
      if required_runtime
        @runtime = required_runtime
      elsif @target == 'vercel' || @target == 'vercel-edge'
        @runtime = 'vercel-edge'
        @target = 'vercel'  # Normalize target name
      elsif @target == 'vercel-node'
        @runtime = 'vercel-node'
        @target = 'vercel'  # Normalize target name
      elsif @target == 'cloudflare'
        @runtime = 'cloudflare'
      else
        @runtime = @target  # node, bun, deno
      end

      unless SERVER_RUNTIMES.include?(@runtime)
        raise "Unknown runtime: #{@runtime}. Valid options: #{SERVER_RUNTIMES.join(', ')}"
      end
    end

    # Validate database/target combination
    self.validate_target!()

    # Ensure package.json has required dependencies for this adapter
    @needs_npm_install = self.ensure_adapter_dependencies()

    self.copy_database_adapter()
    puts("  Target: #{@target}")
    puts("  Runtime: #{@runtime}") if @runtime
    puts("")

    # Copy target-specific lib files (rails.js framework)
    puts("Library:")
    self.copy_lib_files()
    puts("")

    # Generate ApplicationRecord wrapper and transpile models
    puts("Models:")
    self.generate_application_record()
    self.transpile_directory(
      File.join(DEMO_ROOT, 'app/models'),
      File.join(@dist_dir, 'app/models'),
      '**/*.rb',
      skip: ['application_record.rb']
    )
    self.generate_models_index()
    puts("")

    # Parse model associations for controller preloading
    self.parse_model_associations()

    # Transpile controllers (use 'controllers' section from ruby2js.yml if present)
    puts("Controllers:")
    self.transpile_directory(
      File.join(DEMO_ROOT, 'app/controllers'),
      File.join(@dist_dir, 'app/controllers'),
      '**/*.rb',
      section: 'controllers'
    )
    puts("")

    # Transpile components (Phlex views, use 'components' section from ruby2js.yml)
    components_dir = File.join(DEMO_ROOT, 'app/components')
    if File.exist?(components_dir)
      puts("Components:")
      self.copy_phlex_runtime()
      self.transpile_directory(
        components_dir,
        File.join(@dist_dir, 'app/components'),
        '**/*.rb',
        section: 'components'
      )
      puts("")
    end

    # Handle Stimulus controllers (app/javascript/controllers/)
    # - Copy .js files directly (no transpilation)
    # - Transpile .rb files with stimulus filter
    # - Generate controllers/index.js to register all controllers
    stimulus_dir = File.join(DEMO_ROOT, 'app/javascript/controllers')
    if File.exist?(stimulus_dir)
      puts("Stimulus Controllers:")
      controllers_dest = File.join(@dist_dir, 'app/javascript/controllers')
      self.process_stimulus_controllers(stimulus_dir, controllers_dest)

      # For edge targets (Cloudflare, Vercel), also copy to public/ for static serving
      edge_targets = %w[cloudflare vercel-edge vercel-node]
      if edge_targets.include?(@target.to_s) || edge_targets.include?(@runtime.to_s)
        public_controllers = File.join(@dist_dir, 'public/app/javascript/controllers')
        FileUtils.mkdir_p(public_controllers)
        FileUtils.cp_r(Dir.glob("#{controllers_dest}/*.js"), public_controllers)
        puts("  -> public/app/javascript/controllers/ (for static serving)")
      end
      puts("")
    end

    # Transpile config (skip routes.rb, handled separately)
    puts("Config:")
    self.transpile_directory(
      File.join(DEMO_ROOT, 'config'),
      File.join(@dist_dir, 'config'),
      '**/*.rb',
      skip: ['routes.rb']
    )
    self.transpile_routes_files()
    puts("")

    # Transpile views (ERB templates and layout)
    puts("Views:")
    self.transpile_erb_directory()
    self.transpile_layout() if @target != 'browser'
    puts("")

    # Transpile helpers
    puts("Helpers:")
    self.transpile_directory(
      File.join(DEMO_ROOT, 'app/helpers'),
      File.join(@dist_dir, 'app/helpers')
    )
    puts("")

    # Transpile db (migrations and seeds)
    puts("Database:")
    db_src = File.join(DEMO_ROOT, 'db')
    db_dest = File.join(@dist_dir, 'db')
    # Transpile migrations (skip schema.rb and seeds.rb)
    self.transpile_migrations(db_src, db_dest)
    # Handle seeds.rb specially - generate stub if empty/comments-only
    self.transpile_seeds(db_src, db_dest)
    puts("")

    # Generate index.html for browser targets
    if @target == 'browser'
      puts("Static Files:")
      self.generate_browser_index()
      puts("")
    end

    # Generate Vercel deployment files
    if VERCEL_RUNTIMES.include?(@runtime)
      puts("Vercel:")
      self.generate_vercel_config()
      self.generate_vercel_entry_point()
      puts("")
    end

    # Generate Cloudflare deployment files
    if @runtime == 'cloudflare'
      puts("Cloudflare:")
      self.generate_cloudflare_config()
      self.generate_cloudflare_entry_point()
      puts("")
    end

    # Handle Tailwind CSS if present
    self.setup_tailwind()

    if @needs_npm_install
      puts("Installing dependencies...")
      Dir.chdir(@dist_dir) do
        system('npm', 'install', '--silent')
      end
      puts("")
    end

    # Copy .env.local if present (for database credentials, API keys, etc.)
    env_local = File.join(DEMO_ROOT, '.env.local')
    if File.exist?(env_local)
      FileUtils.cp(env_local, File.join(@dist_dir, '.env.local'))
    end

    puts("=== Build Complete ===")
  end

  def validate_target!()
    # Determine the effective target for validation
    # For browser target, use 'browser'; for server targets, use the runtime
    effective_target = @target == 'browser' ? 'browser' : @runtime

    valid_targets = VALID_TARGETS[@database]
    return unless valid_targets  # Unknown database, skip validation

    unless valid_targets.include?(effective_target)
      raise "Database '#{@database}' does not support target '#{effective_target}'.\n" \
            "Valid targets for #{@database}: #{valid_targets.join(', ')}"
    end
  end

  def load_ruby2js_config(section = nil)
    env = ENV['RAILS_ENV'] || ENV['NODE_ENV'] || 'development'
    config_path = File.join(DEMO_ROOT, 'config/ruby2js.yml')

    return {} unless File.exist?(config_path)

    # Ruby 3.4+ requires aliases: true for YAML anchors
    config = YAML.load_file(config_path, aliases: true)

    # If a specific section is requested (e.g., 'controllers', 'components')
    if section && config.key?(section)
      return config[section]
    end

    # Support environment-specific or flat config
    if config.key?(env)
      config[env]
    elsif config.key?('default')
      config['default']
    else
      config
    end
  end

  def build_options(section = nil)
    # Load section-specific config if section is specified, otherwise default
    base = self.load_ruby2js_config(section)

    # Use section-specific options as base
    base_options = case section
    when 'stimulus'
      STIMULUS_OPTIONS
    else
      OPTIONS
    end

    # Start with hardcoded options as base (using spread for JS compatibility)
    options = { **base_options }

    # Merge YAML config values (string keys converted to symbols)
    base.each do |key, value| # Pragma: entries
      sym_key = key.to_s.to_sym
      # Convert filter names to module references
      if sym_key == :filters && value.is_a?(Array)
        options[sym_key] = self.resolve_filters(value)
      else
        options[sym_key] = value
      end
    end

    # Pass model associations to controller filter for preloading
    if section == 'controllers' && @model_associations && @model_associations.any?  # Pragma: hash
      options[:model_associations] = @model_associations
    end

    options
  end

  # Map filter names (strings) to Ruby2JS filter modules
  # Supports both short names ('phlex') and full paths ('rails/helpers')
  FILTER_MAP = {
    # Core filters
    'functions' => Ruby2JS::Filter::Functions,
    'esm' => Ruby2JS::Filter::ESM,
    'return' => Ruby2JS::Filter::Return,
    'erb' => Ruby2JS::Filter::Erb,
    'camelcase' => Ruby2JS::Filter::CamelCase,
    'camelCase' => Ruby2JS::Filter::CamelCase,

    # Framework filters
    'phlex' => Ruby2JS::Filter::Phlex,
    'stimulus' => Ruby2JS::Filter::Stimulus,

    # Rails sub-filters
    'rails/model' => Ruby2JS::Filter::Rails::Model,
    'rails/controller' => Ruby2JS::Filter::Rails::Controller,
    'rails/routes' => Ruby2JS::Filter::Rails::Routes,
    'rails/seeds' => Ruby2JS::Filter::Rails::Seeds,
    'rails/helpers' => Ruby2JS::Filter::Rails::Helpers,
    'rails/migration' => Ruby2JS::Filter::Rails::Migration
  }.freeze

  def resolve_filters(filter_names)
    filter_names.map do |name|
      # Already a filter (not a string)? Pass through
      # In Ruby, filters are Modules; in JS, they're prototype objects
      return name unless name.is_a?(String)

      # Normalize: strip, downcase for lookup (but preserve camelCase key)
      normalized = name.to_s.strip
      lookup_key = FILTER_MAP.key?(normalized) ? normalized : normalized.downcase

      filter = FILTER_MAP[lookup_key]
      unless filter
        valid_filters = FILTER_MAP.keys.uniq.sort.join(', ')
        raise "Unknown filter: '#{name}'. Valid filters: #{valid_filters}"
      end
      filter
    end
  end

  def load_database_config()
    # Delegate to class method
    SelfhostBuilder.load_database_config(DEMO_ROOT)
  end

  def copy_database_adapter()
    adapter_file = ADAPTER_FILES[@database]

    unless adapter_file
      valid = ADAPTER_FILES.keys.join(', ')
      raise "Unknown DATABASE adapter: #{@database}. Valid options: #{valid}"
    end

    # Check for local packages first (development), then npm-installed, finally vendor (legacy)
    # Prefer local source over npm when available so local changes are immediately reflected
    npm_adapter_dir = File.join(@dist_dir, 'node_modules/ruby2js-rails/adapters')
    npm_dist_dir = File.join(@dist_dir, 'node_modules/ruby2js-rails/dist/lib')
    pkg_adapter_dir = File.join(DEMO_ROOT, '../../packages/ruby2js-rails/adapters')
    vendor_adapter_dir = File.join(DEMO_ROOT, 'vendor/ruby2js/adapters')
    adapter_dir = if File.exist?(pkg_adapter_dir)
      pkg_adapter_dir
    elsif File.exist?(npm_adapter_dir)
      npm_adapter_dir
    elsif File.exist?(npm_dist_dir)
      npm_dist_dir
    elsif File.exist?(vendor_adapter_dir)
      vendor_adapter_dir
    else
      raise <<~ERROR
        Could not find ruby2js-rails adapters directory.
        Looked in:
          - #{npm_adapter_dir}
          - #{npm_dist_dir}
          - #{pkg_adapter_dir}
          - #{vendor_adapter_dir}

        Try running: npm install ruby2js-rails
        Or ensure the ruby2js-rails package is properly installed.
      ERROR
    end
    lib_dest = File.join(@dist_dir, 'lib')
    FileUtils.mkdir_p(lib_dest)

    # Copy base class first (all adapters depend on it)
    base_src = File.join(adapter_dir, 'active_record_base.mjs')
    base_dest = File.join(lib_dest, 'active_record_base.mjs')
    FileUtils.cp(base_src, base_dest)
    puts("  Base class: active_record_base.mjs")

    # Get database config for injection (load from file or use minimal config for override)
    db_config = if @database_override
      { 'adapter' => @database, 'database' => "#{File.basename(DEMO_ROOT)}_dev" }
    else
      self.load_database_config()
    end

    # Ensure SQLite databases have .sqlite3 extension for reliable preservation during rebuilds
    db_name = db_config['database'] || db_config[:database]
    if db_name && ['sqlite', 'better_sqlite3'].include?(@database)
      unless db_name.end_with?('.sqlite3', '.db') || db_name == ':memory:'
        db_config['database'] = "#{db_name}.sqlite3"
      end
    end

    # Read adapter and inject config
    adapter_src = File.join(adapter_dir, adapter_file)
    adapter_dest = File.join(lib_dest, 'active_record.mjs')
    adapter_code = File.read(adapter_src)
    adapter_code = adapter_code.sub('const DB_CONFIG = {};', "const DB_CONFIG = #{JSON.generate(db_config)};")
    File.write(adapter_dest, adapter_code)

    puts("  Adapter: #{@database} -> lib/active_record.mjs")
    if db_config['database'] || db_config[:database]
      puts("  Database: #{db_config['database'] || db_config[:database]}")
    end
  end

  # Find the ruby2js-rails package directory, preferring local packages when in dev
  def find_package_dir
    npm_package_dir = File.join(@dist_dir, 'node_modules/ruby2js-rails')
    pkg_package_dir = File.join(DEMO_ROOT, '../../packages/ruby2js-rails')
    vendor_package_dir = File.join(DEMO_ROOT, 'vendor/ruby2js')

    # When running from within ruby2js repo, prefer packages directory over stale npm module
    if File.exist?(pkg_package_dir) && File.exist?(npm_package_dir)
      puts "  Removing stale npm module (using local packages instead)"
      FileUtils.rm_rf(npm_package_dir)
    end

    if File.exist?(npm_package_dir)
      npm_package_dir
    elsif File.exist?(pkg_package_dir)
      pkg_package_dir
    else
      vendor_package_dir
    end
  end

  def copy_lib_files()
    lib_dest = File.join(@dist_dir, 'lib')
    FileUtils.mkdir_p(lib_dest)

    # Determine source directory: browser or runtime-specific server target
    if @target == 'browser'
      target_dir = 'browser'
    else
      target_dir = @runtime  # node, bun, or deno
    end

    package_dir = find_package_dir

    # Copy base files (rails_base.js is needed by all targets)
    base_src = File.join(package_dir, 'rails_base.js')
    if File.exist?(base_src)
      FileUtils.cp(base_src, File.join(lib_dest, 'rails_base.js'))
      puts("  Copying: rails_base.js")
      puts("    -> #{lib_dest}/rails_base.js")
    end

    # Copy server module (needed by node, bun, deno, cloudflare targets)
    if @target != 'browser'
      server_src = File.join(package_dir, 'rails_server.js')
      if File.exist?(server_src)
        FileUtils.cp(server_src, File.join(lib_dest, 'rails_server.js'))
        puts("  Copying: rails_server.js")
        puts("    -> #{lib_dest}/rails_server.js")
      end
    end

    # Copy target-specific files (rails.js from targets/browser, node, bun, or deno)
    target_src = File.join(package_dir, 'targets', target_dir)
    Dir.glob(File.join(target_src, '*.js')).each do |src_path|
      dest_path = File.join(lib_dest, File.basename(src_path))
      FileUtils.cp(src_path, dest_path)
      puts("  Copying: targets/#{target_dir}/#{File.basename(src_path)}")
      puts("    -> #{dest_path}")
    end

    # Copy runtime lib files (erb_runtime.mjs only - build tools stay in vendor)
    runtime_libs = ['erb_runtime.mjs']
    runtime_libs.each do |filename|
      src_path = File.join(package_dir, filename)
      next unless File.exist?(src_path)
      dest_path = File.join(lib_dest, filename)
      FileUtils.cp(src_path, dest_path)
      puts("  Copying: #{filename}")
      puts("    -> #{dest_path}")
    end
  end

  def copy_phlex_runtime()
    lib_dest = File.join(@dist_dir, 'lib')
    FileUtils.mkdir_p(lib_dest)

    package_dir = find_package_dir
    src_path = File.join(package_dir, 'phlex_runtime.mjs')
    return unless File.exist?(src_path)

    dest_path = File.join(lib_dest, 'phlex_runtime.mjs')
    FileUtils.cp(src_path, dest_path)
    puts("  Copying: phlex_runtime.mjs")
    puts("    -> #{dest_path}")
  end

  def transpile_file(src_path, dest_path, section = nil)
    puts("Transpiling: #{File.basename(src_path)}")
    source = File.read(src_path)

    # Use relative path for cleaner display in browser debugger
    relative_src = src_path.sub(DEMO_ROOT + '/', '')
    options = self.build_options(section).merge(file: relative_src)
    result = Ruby2JS.convert(source, options)
    js = result.to_s

    FileUtils.mkdir_p(File.dirname(dest_path))

    # Copy source file alongside transpiled output for source maps
    src_basename = File.basename(src_path)
    copied_src_path = File.join(File.dirname(dest_path), src_basename)
    File.write(copied_src_path, source)

    # Generate sourcemap - source is in same directory
    map_path = "#{dest_path}.map"
    sourcemap = result.sourcemap
    sourcemap[:sourcesContent] = [source]
    sourcemap[:sources] = ["./#{src_basename}"]

    # Add sourcemap reference to JS file
    js_with_map = "#{js}\n//# sourceMappingURL=#{File.basename(map_path)}\n"
    File.write(dest_path, js_with_map)
    File.write(map_path, JSON.generate(sourcemap))

    puts("  -> #{dest_path}")
  end

  def transpile_erb_file(src_path, dest_path)
    puts("Transpiling ERB: #{File.basename(src_path)}")
    template = File.read(src_path)

    # Compile ERB to Ruby and get position mapping
    compiler = ErbCompiler.new(template)
    ruby_src = compiler.src

    # Use relative path for cleaner display in browser debugger
    relative_src = src_path.sub(DEMO_ROOT + '/', '')

    # Pass database and target options for target-aware link generation
    # Also pass ERB source and position map for source map generation
    erb_options = ERB_OPTIONS.merge(
      database: @database,
      target: @target,
      file: relative_src
    )
    result = Ruby2JS.convert(ruby_src, erb_options)

    # Set ERB source map data on the result (which is the Serializer/Converter)
    result.erb_source = template
    result.erb_position_map = compiler.position_map

    js = result.to_s
    js = js.sub(/^function render/, 'export function render')

    FileUtils.mkdir_p(File.dirname(dest_path))

    # Copy source file alongside transpiled output for source maps
    src_basename = File.basename(src_path)
    copied_src_path = File.join(File.dirname(dest_path), src_basename)
    File.write(copied_src_path, template)

    # Generate source map - source is in same directory
    map_path = "#{dest_path}.map"
    sourcemap = result.sourcemap
    sourcemap[:sourcesContent] = [template]  # Use original ERB, not Ruby
    sourcemap[:sources] = ["./#{src_basename}"]

    # Add sourcemap reference to JS file
    js_with_map = "#{js}\n//# sourceMappingURL=#{File.basename(map_path)}\n"
    File.write(dest_path, js_with_map)
    File.write(map_path, JSON.generate(sourcemap))

    puts("  -> #{dest_path}")
    js
  end

  def transpile_erb_directory()
    views_root = File.join(DEMO_ROOT, 'app/views')
    return unless Dir.exist?(views_root)

    # Find all resource directories (exclude layouts, pwa, and partials)
    excluded_dirs = %w[layouts pwa]
    resource_dirs = Dir.children(views_root).select do |name|
      dir_path = File.join(views_root, name)
      File.directory?(dir_path) && !excluded_dirs.include?(name) && !name.start_with?('_')
    end

    return if resource_dirs.empty?

    views_dist_dir = File.join(@dist_dir, 'app/views')
    FileUtils.mkdir_p(views_dist_dir)

    resource_dirs.each do |resource|
      transpile_resource_views(resource, views_root, views_dist_dir)
      transpile_turbo_stream_views(resource, views_root, views_dist_dir)
    end
  end

  def transpile_resource_views(resource, views_root, views_dist_dir)
    erb_dir = File.join(views_root, resource)
    erb_files = Dir.glob(File.join(erb_dir, '*.html.erb'))
    return if erb_files.empty?

    # Create resource subdirectory in dist
    resource_dist_dir = File.join(views_dist_dir, resource)
    FileUtils.mkdir_p(resource_dist_dir)

    # Transpile each ERB file
    erb_files.each do |src_path|
      basename = File.basename(src_path, '.html.erb')
      self.transpile_erb_file(src_path, File.join(resource_dist_dir, "#{basename}.js"))
    end

    # Create combined module that exports all render functions
    # Convert resource name to class-like name (messages -> Message, articles -> Article)
    class_name = resource.chomp('s').split('_').map(&:capitalize).join
    views_class = "#{class_name}Views"

    erb_views_js = <<~JS
      // #{class_name} views - auto-generated from .html.erb templates
      // Each exported function is a render function that takes { #{resource.chomp('s')} } or { #{resource} }

    JS

    render_exports = []
    has_new = false
    erb_files.sort.each do |erb_path|
      name = File.basename(erb_path, '.html.erb')
      has_new = true if name == 'new'
      # Import from ./#{resource}/ subdirectory
      erb_views_js += "import { render as #{name}_render } from './#{resource}/#{name}.js';\n"
      render_exports << "#{name}: #{name}_render"
    end

    erb_views_js += <<~JS

      // Export #{views_class} - method names match controller action names
      export const #{views_class} = {
        #{render_exports.join(",\n  ")}#{has_new ? ",\n  // $new alias for 'new' (JS reserved word handling)\n  $new: new_render" : ''}
      };
    JS

    # Write combined module to app/views/#{resource}.js
    File.write(File.join(views_dist_dir, "#{resource}.js"), erb_views_js)
    puts("  -> app/views/#{resource}.js (combined ERB module)")
  end

  def transpile_turbo_stream_views(resource, views_root, views_dist_dir)
    erb_dir = File.join(views_root, resource)
    erb_files = Dir.glob(File.join(erb_dir, '*.turbo_stream.erb'))
    return if erb_files.empty?

    # Create resource subdirectory in dist for turbo stream templates
    resource_dist_dir = File.join(views_dist_dir, resource)
    FileUtils.mkdir_p(resource_dist_dir)

    # Transpile each turbo stream ERB file
    erb_files.each do |src_path|
      basename = File.basename(src_path, '.turbo_stream.erb')
      self.transpile_erb_file(src_path, File.join(resource_dist_dir, "#{basename}_turbo_stream.js"))
    end

    # Create combined module that exports all turbo stream functions
    # Convert resource name to class-like name (messages -> Message, articles -> Article)
    class_name = resource.chomp('s').split('_').map(&:capitalize).join
    turbo_class = "#{class_name}TurboStreams"

    turbo_js = <<~JS
      // #{class_name} turbo stream templates - auto-generated from .turbo_stream.erb templates
      // Each exported function returns Turbo Stream HTML for partial page updates

    JS

    render_exports = []
    erb_files.sort.each do |erb_path|
      name = File.basename(erb_path, '.turbo_stream.erb')
      # Import from ./#{resource}/ subdirectory
      turbo_js += "import { render as #{name}_render } from './#{resource}/#{name}_turbo_stream.js';\n"
      render_exports << "#{name}: #{name}_render"
    end

    turbo_js += <<~JS

      // Export #{turbo_class} - method names match controller action names
      export const #{turbo_class} = {
        #{render_exports.join(",\n  ")}
      };
    JS

    # Write combined module to app/views/#{resource}_turbo_streams.js
    File.write(File.join(views_dist_dir, "#{resource}_turbo_streams.js"), turbo_js)
    puts("  -> app/views/#{resource}_turbo_streams.js (turbo stream templates)")
  end

  def transpile_layout()
    layout_path = File.join(DEMO_ROOT, 'app/views/layouts/application.html.erb')
    return unless File.exist?(layout_path)

    puts("Transpiling layout: application.html.erb")

    # Detect app name from config/application.rb for title
    app_name = 'Ruby2JS App'
    app_config = File.join(DEMO_ROOT, 'config/application.rb')
    if File.exist?(app_config)
      content = File.read(app_config)
      if content =~ /module\s+(\w+)/
        app_name = $1
      end
    end

    # Detect CSS framework for correct stylesheet link
    css_link = ''
    tailwind_src = File.join(DEMO_ROOT, 'app/assets/tailwind/application.css')
    if File.exist?(tailwind_src)
      css_link = '<link href="/assets/tailwind.css" rel="stylesheet">'
    end

    # Use CDN URLs for edge targets (Cloudflare, Vercel) since they don't have node_modules
    # Local server targets (Node, Bun, Deno) can serve from node_modules directly
    edge_targets = %w[cloudflare vercel-edge vercel-node]
    if edge_targets.include?(@target.to_s) || edge_targets.include?(@runtime.to_s)
      turbo_url = 'https://cdn.jsdelivr.net/npm/@hotwired/turbo@8/dist/turbo.es2017-esm.js'
      stimulus_url = 'https://cdn.jsdelivr.net/npm/@hotwired/stimulus@3/dist/stimulus.js'
    else
      turbo_url = '/node_modules/@hotwired/turbo/dist/turbo.es2017-esm.js'
      stimulus_url = '/node_modules/@hotwired/stimulus/dist/stimulus.js'
    end

    # Generate a minimal layout for server-side rendering
    # Rails-specific helpers (csrf_meta_tags, etc.) don't make sense in JS context
    # Layout receives context for access to contentFor, flash, etc.
    js = <<~JS
      // Application layout - wraps view content
      // Generated from app/views/layouts/application.html.erb
      export function layout(context, content) {
        const title = context.contentFor.title || '#{app_name}';
        return `<!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\${title}</title>
        #{css_link}
        <script type="importmap">
        {
          "imports": {
            "@hotwired/turbo": "#{turbo_url}",
            "@hotwired/stimulus": "#{stimulus_url}"
          }
        }
        </script>
        <script type="module">
          import * as Turbo from '@hotwired/turbo';
          import '/app/javascript/controllers/index.js';
          window.Turbo = Turbo;
        </script>
      </head>
      <body>
        <main class="container mx-auto px-4 py-8">
          \${content}
        </main>
      </body>
      </html>`;
      }
    JS

    dest_dir = File.join(@dist_dir, 'app/views/layouts')
    FileUtils.mkdir_p(dest_dir)
    File.write(File.join(dest_dir, 'application.js'), js)
    puts("  -> app/views/layouts/application.js")
  end

  def transpile_directory(src_dir, dest_dir, pattern = '**/*.rb', skip: [], section: nil)
    Dir.glob(File.join(src_dir, pattern)).each do |src_path|
      basename = File.basename(src_path)
      next if skip.include?(basename)

      relative = src_path.sub(src_dir + '/', '')
      dest_path = File.join(dest_dir, relative.sub(/\.rb$/, '.js'))
      self.transpile_file(src_path, dest_path, section)
    end
  end

  # Process Stimulus controllers:
  # - Copy .js files directly (no transpilation needed)
  # - Transpile .rb files with stimulus filter
  # - Generate index.js that registers all controllers with Stimulus
  def process_stimulus_controllers(src_dir, dest_dir)
    FileUtils.mkdir_p(dest_dir)

    controllers = []

    # Process all controller files
    Dir.glob(File.join(src_dir, '**/*_controller.{js,rb}')).each do |src_path|
      basename = File.basename(src_path)
      relative = src_path.sub(src_dir + '/', '')

      # Skip index files and application_controller
      next if basename == 'index.js' || basename == 'application_controller.js'

      if src_path.end_with?('.js')
        # Copy .js files directly
        dest_path = File.join(dest_dir, relative)
        FileUtils.mkdir_p(File.dirname(dest_path))
        FileUtils.cp(src_path, dest_path)
        puts("  #{relative} (copied)")
        controllers << relative
      elsif src_path.end_with?('.rb')
        # Transpile .rb files
        dest_relative = relative.sub(/\.rb$/, '.js')
        dest_path = File.join(dest_dir, dest_relative)
        self.transpile_file(src_path, dest_path, 'stimulus')
        controllers << dest_relative
      end
    end

    # Generate index.js that registers all controllers
    # Use uniq because both .js and .rb versions may exist (e.g., chat_controller.js and chat_controller.rb)
    if controllers.any?
      self.generate_stimulus_index(dest_dir, controllers.uniq)
    end
  end

  # Generate controllers/index.js that imports and registers all Stimulus controllers
  def generate_stimulus_index(dest_dir, controller_files)
    imports = []
    registrations = []

    controller_files.sort.each do |file|
      # Extract controller name from filename
      # hello_controller.js -> HelloController, "hello"
      # live_scores_controller.js -> LiveScoresController, "live-scores"
      basename = File.basename(file, '.js')
      name_part = basename.sub(/_controller$/, '')

      # Convert to class name (hello_world -> HelloWorld)
      class_name = name_part.split('_').map(&:capitalize).join('') + 'Controller'

      # Convert to Stimulus identifier (hello_world -> hello-world)
      identifier = name_part.gsub('_', '-')

      imports << "import #{class_name} from \"./#{file}\";"
      registrations << "application.register(\"#{identifier}\", #{class_name});"
    end

    index_content = <<~JS
      import { Application } from "@hotwired/stimulus";

      #{imports.join("\n")}

      const application = Application.start();

      #{registrations.join("\n")}

      export { application };
    JS

    File.write(File.join(dest_dir, 'index.js'), index_content)
    puts("  -> index.js (#{controller_files.length} controllers)")
  end

  # Handle seeds.rb specially - if it has only comments/whitespace, generate a stub
  # This is shared logic with SPA builder (lib/ruby2js/spa/builder.rb)
  def transpile_seeds(src_dir, dest_dir)
    seeds_src = File.join(src_dir, 'seeds.rb')
    seeds_dest = File.join(dest_dir, 'seeds.js')

    # Check if seeds.rb has actual Ruby code (not just comments/whitespace)
    # Use split("\n") instead of .lines for JS compatibility (strings don't have .lines in JS)
    has_code = File.exist?(seeds_src) &&
               File.read(seeds_src).split("\n").any? { |line| line.strip !~ /\A(#.*|\s*)\z/ }

    if has_code
      # Transpile existing seeds file normally
      self.transpile_file(seeds_src, seeds_dest)

      # For D1, also generate a seeds.sql file that wrangler can execute
      if @database == 'd1'
        generate_seeds_sql(seeds_src, dest_dir)
      end
    else
      # Generate empty Seeds module directly as JS (rails/seeds filter needs code to process)
      FileUtils.mkdir_p(dest_dir)
      File.write(seeds_dest, <<~JS)
        // Seeds stub - original seeds.rb had no executable code
        export const Seeds = {
          run() {
            // Add your seed data here
          }
        };
      JS
      puts("  -> db/seeds.js (stub)")
    end
  end

  # Generate SQL seeds file for D1/wrangler
  def generate_seeds_sql(seeds_src, db_dest)
    result = Ruby2JS::Rails::SeedSQL.generate(seeds_src)

    if result[:sql] && !result[:sql].empty?
      FileUtils.mkdir_p(db_dest)
      sql_path = File.join(db_dest, 'seeds.sql')
      File.write(sql_path, result[:sql])
      puts("  -> db/seeds.sql (#{result[:inserts]} inserts)")
    end
  end

  # Transpile database migrations to JavaScript
  # Each migration becomes a module with an async up() function
  # Also generates an index file that exports all migrations with their versions
  def transpile_migrations(src_dir, dest_dir)
    migrate_src = File.join(src_dir, 'migrate')
    migrate_dest = File.join(dest_dir, 'migrate')

    return unless File.exist?(migrate_src)

    migrations = []

    Dir.glob(File.join(migrate_src, '*.rb')).sort.each do |src_path|
      basename = File.basename(src_path, '.rb')
      dest_path = File.join(migrate_dest, "#{basename}.js")

      # Extract version from filename (e.g., 20241231120000_create_articles.rb)
      version = basename.split('_').first

      self.transpile_migration_file(src_path, dest_path)

      migrations << { version: version, filename: basename }
    end

    # Generate migrations index file
    if migrations.any?
      self.generate_migrations_index(migrate_dest, migrations)
    end

    # For D1, also generate a migrations.sql file that wrangler can execute
    if @database == 'd1'
      self.generate_migrations_sql(migrate_src, dest_dir)
    end
  end

  # Generate SQL migrations file for D1/wrangler
  def generate_migrations_sql(migrate_src, db_dest)
    result = Ruby2JS::Rails::MigrationSQL.generate_all(migrate_src)

    if result[:sql] && !result[:sql].empty?
      FileUtils.mkdir_p(db_dest)
      sql_path = File.join(db_dest, 'migrations.sql')
      File.write(sql_path, result[:sql])
      puts("  -> db/migrations.sql (#{result[:migrations].length} migrations)")
    end
  end

  def transpile_migration_file(src_path, dest_path)
    puts("Transpiling migration: #{File.basename(src_path)}")
    source = File.read(src_path)

    relative_src = src_path.sub(DEMO_ROOT + '/', '')
    options = MIGRATION_OPTIONS.merge(file: relative_src)
    result = Ruby2JS.convert(source, options)
    js = result.to_s

    FileUtils.mkdir_p(File.dirname(dest_path))

    # Copy source file alongside transpiled output for source maps
    src_basename = File.basename(src_path)
    copied_src_path = File.join(File.dirname(dest_path), src_basename)
    File.write(copied_src_path, source)

    # Generate sourcemap
    map_path = "#{dest_path}.map"
    sourcemap = result.sourcemap
    sourcemap[:sourcesContent] = [source]
    sourcemap[:sources] = ["./#{src_basename}"]

    # Add sourcemap reference to JS file
    js_with_map = "#{js}\n//# sourceMappingURL=#{File.basename(map_path)}\n"
    File.write(dest_path, js_with_map)
    File.write(map_path, JSON.generate(sourcemap))

    puts("  -> #{dest_path}")
  end

  def generate_migrations_index(migrate_dest, migrations)
    index_js = <<~JS
      // Database migrations index - auto-generated
      // Each migration exports { migration: { up: async () => {...} } }

    JS

    # Import each migration
    migrations.each do |m|
      index_js += "import { migration as m#{m[:version]} } from './#{m[:filename]}.js';\n"
    end

    index_js += "\n// All migrations in order\nexport const migrations = [\n"
    migrations.each do |m|
      index_js += "  { version: '#{m[:version]}', ...m#{m[:version]} },\n"
    end
    index_js += "];\n"

    File.write(File.join(migrate_dest, 'index.js'), index_js)
    puts("  -> db/migrate/index.js (#{migrations.length} migrations)")
  end

  def generate_application_record()
    wrapper = <<~JS
      // ApplicationRecord - wraps ActiveRecord from adapter
      // This file is generated by the build script
      import { ActiveRecord } from '../../lib/active_record.mjs';

      export class ApplicationRecord extends ActiveRecord {
        // Subclasses (Article, Comment) extend this and add their own validations
      }
    JS
    dest_dir = File.join(@dist_dir, 'app/models')
    FileUtils.mkdir_p(dest_dir)
    File.write(File.join(dest_dir, 'application_record.js'), wrapper)
    puts("  -> app/models/application_record.js (wrapper for ActiveRecord)")
  end

  def generate_browser_index()
    # Detect app name from config/application.rb
    app_name = 'Ruby2JS App'
    app_config = File.join(DEMO_ROOT, 'config/application.rb')
    if File.exist?(app_config)
      content = File.read(app_config)
      if content =~ /module\s+(\w+)/
        app_name = $1
      end
    end

    # Detect CSS framework from Gemfile or package.json
    css = 'none'
    gemfile = File.join(DEMO_ROOT, 'Gemfile')
    if File.exist?(gemfile)
      content = File.read(gemfile)
      if content.include?('tailwindcss')
        css = 'tailwind'
      elsif content.include?('bootstrap')
        css = 'bootstrap'
      end
    end

    # Write index.html to dist/ - self-contained, served from dist root
    output_path = File.join(@dist_dir, 'index.html')
    SelfhostBuilder.generate_index_html(
      app_name: app_name,
      database: @database,
      css: css,
      output_path: output_path,
      base_path: ''  # Serving from dist/ root, not /dist
    )
    puts("  -> dist/index.html")
  end

  def generate_vercel_config()
    # Determine runtime type for Vercel
    runtime_type = @runtime == 'vercel-edge' ? 'edge' : 'nodejs'

    config = {
      'version' => 2,
      'buildCommand' => 'npm run build',
      'outputDirectory' => 'dist',
      'routes' => [
        # Serve static assets from public/ (Rails convention)
        { 'src' => '/assets/(.*)', 'dest' => '/public/assets/$1' },
        # All other routes go to the catch-all API handler
        { 'src' => '/(.*)', 'dest' => '/api/[[...path]]' }
      ]
    }

    # Add runtime configuration for edge functions
    if @runtime == 'vercel-edge'
      config['functions'] = {
        'api/[[...path]].js' => { 'runtime' => 'edge' }
      }
    end

    config_path = File.join(@dist_dir, 'vercel.json')
    File.write(config_path, JSON.pretty_generate(config))
    puts("  -> vercel.json")
  end

  def generate_vercel_entry_point()
    # Determine runtime type for export config
    runtime_type = @runtime == 'vercel-edge' ? 'edge' : 'nodejs'

    # Detect app name from config/application.rb
    app_name = 'Ruby2JS App'
    app_config = File.join(DEMO_ROOT, 'config/application.rb')
    if File.exist?(app_config)
      content = File.read(app_config)
      if content =~ /module\s+(\w+)/
        app_name = $1
      end
    end

    entry = <<~JS
      // Vercel catch-all route handler
      // Generated by Ruby2JS on Rails

      import { Application, Router } from '../lib/rails.js';
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

      // Export handler for Vercel
      export default Application.handler();

      // Runtime configuration
      export const config = {
        runtime: '#{runtime_type}'
      };
    JS

    # Create api directory and write entry point
    api_dir = File.join(@dist_dir, 'api')
    FileUtils.mkdir_p(api_dir)
    File.write(File.join(api_dir, '[[...path]].js'), entry)
    puts("  -> api/[[...path]].js")
  end

  def uses_turbo_broadcasting?
    # Check if app uses Turbo Streams broadcasting (broadcast_*_to in models or turbo_stream_from in views)
    models_dir = File.join(DEMO_ROOT, 'app/models')
    views_dir = File.join(DEMO_ROOT, 'app/views')

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

  def generate_cloudflare_config()
    # Generate wrangler.toml for Cloudflare Workers deployment
    app_name = File.basename(DEMO_ROOT).downcase.gsub(/[^a-z0-9-]/, '-')

    wrangler_toml = <<~TOML
      name = "#{app_name}"
      main = "src/index.js"
      compatibility_date = "#{Date.today}"
      compatibility_flags = ["nodejs_compat"]

      # D1 database binding
      [[d1_databases]]
      binding = "DB"
      database_name = "#{app_name}_production"
      database_id = "${D1_DATABASE_ID}"

      # Static assets (Rails convention: public/)
      [assets]
      directory = "./public"
    TOML

    # Add Durable Objects only if app uses Turbo Streams broadcasting
    if uses_turbo_broadcasting?
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

    config_path = File.join(@dist_dir, 'wrangler.toml')
    File.write(config_path, wrangler_toml)
    puts("  -> wrangler.toml")
  end

  def generate_cloudflare_entry_point()
    # Generate Cloudflare Worker entry point
    uses_broadcasting = uses_turbo_broadcasting?

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

    entry = <<~JS
      // Cloudflare Worker entry point
      // Generated by Ruby2JS on Rails

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

    # Create src directory and write entry point
    src_dir = File.join(@dist_dir, 'src')
    FileUtils.mkdir_p(src_dir)
    File.write(File.join(src_dir, 'index.js'), entry)
    puts("  -> src/index.js")
  end

  def setup_tailwind()
    # Check for tailwindcss-rails gem source file
    tailwind_src = File.join(DEMO_ROOT, 'app/assets/tailwind/application.css')
    return unless File.exist?(tailwind_src)

    puts("Tailwind CSS:")

    # Create source directory (for Tailwind input)
    tailwind_dest_dir = File.join(@dist_dir, 'app/assets/tailwind')
    FileUtils.mkdir_p(tailwind_dest_dir)

    # Read the tailwindcss-rails source and convert to npm-compatible format
    source = File.read(tailwind_src)

    # Convert @import "tailwindcss" to npm @tailwind directives
    npm_css = source.gsub(/@import\s+["']tailwindcss["'];?/, <<~CSS.strip)
      @tailwind base;
      @tailwind components;
      @tailwind utilities;
    CSS

    # Write the converted CSS to dist (source for Tailwind build)
    dest_path = File.join(tailwind_dest_dir, 'application.css')
    File.write(dest_path, npm_css)
    puts("  -> app/assets/tailwind/application.css")

    # Create tailwind.config.js if not present
    config_path = File.join(@dist_dir, 'tailwind.config.js')
    unless File.exist?(config_path)
      # Generate config that watches dist/ for class names
      config = <<~JS
        /** @type {import('tailwindcss').Config} */
        export default {
          content: [
            './app/**/*.{js,html,erb}',
            './index.html'
          ],
          theme: {
            extend: {},
          },
          plugins: [],
        }
      JS
      File.write(config_path, config)
      puts("  -> tailwind.config.js")
    end

    # Create output directory for built CSS (Rails convention: public/assets/)
    assets_dir = File.join(@dist_dir, 'public/assets')
    FileUtils.mkdir_p(assets_dir)

    # Run Tailwind CSS build (only if tailwindcss is installed)
    tailwind_bin = File.join(@dist_dir, 'node_modules/.bin/tailwindcss')
    if File.exist?(tailwind_bin)
      puts("  Building CSS...")
      Dir.chdir(@dist_dir) do
        system('npx', 'tailwindcss',
               '-i', 'app/assets/tailwind/application.css',
               '-o', 'public/assets/tailwind.css',
               '--minify')
      end
      puts("  -> public/assets/tailwind.css")
    else
      puts("  (Run 'npm install' in dist/, then 'npx tailwindcss -i app/assets/tailwind/application.css -o public/assets/tailwind.css')")
    end
  end

  def transpile_routes_files()
    src_path = File.join(DEMO_ROOT, 'config/routes.rb')
    dest_dir = File.join(@dist_dir, 'config')
    source = File.read(src_path)
    relative_src = src_path.sub(DEMO_ROOT + '/', '')
    base_options = self.build_options()

    # Generate paths.js first (with only path helpers)
    puts("Transpiling: routes.rb -> paths.js")
    paths_options = base_options.merge(file: relative_src, paths_only: true)
    result = Ruby2JS.convert(source, paths_options)
    paths_js = result.to_s

    paths_path = File.join(dest_dir, 'paths.js')
    FileUtils.mkdir_p(dest_dir)
    File.write(paths_path, paths_js)
    puts("  -> #{paths_path}")

    # Generate sourcemap for paths.js
    map_path = "#{paths_path}.map"
    sourcemap = result.sourcemap
    sourcemap[:sourcesContent] = [source]
    File.write(map_path, JSON.generate(sourcemap))
    puts("  -> #{map_path}")

    # Generate routes.js (imports path helpers from paths.js)
    puts("Transpiling: routes.rb -> routes.js")
    routes_options = base_options.merge(file: relative_src, paths_file: './paths.js', database: @database)
    result = Ruby2JS.convert(source, routes_options)
    routes_js = result.to_s

    routes_path = File.join(dest_dir, 'routes.js')
    File.write(routes_path, routes_js)
    puts("  -> #{routes_path}")

    # Generate sourcemap for routes.js
    map_path = "#{routes_path}.map"
    sourcemap = result.sourcemap
    sourcemap[:sourcesContent] = [source]
    File.write(map_path, JSON.generate(sourcemap))
    puts("  -> #{map_path}")
  end

  def generate_models_index()
    models_dir = File.join(@dist_dir, 'app/models')
    model_files = Dir.glob(File.join(models_dir, '*.js'))
      .map { |f| File.basename(f, '.js') }
      .reject { |name| name == 'application_record' || name == 'index' }
      .sort

    return unless model_files.any?

    index_js = model_files.map do |name|
      # Use explicit capitalization for JS compatibility
      class_name = name.split('_').map { |s| s[0].upcase + s[1..-1] }.join
      "export { #{class_name} } from './#{name}.js';"
    end.join("\n") + "\n"

    File.write(File.join(models_dir, 'index.js'), index_js)
    puts("  -> app/models/index.js (re-exports)")
  end

  # Parse model files to extract has_many associations for controller preloading
  # This allows show/edit actions to await associations before rendering views
  def parse_model_associations()
    models_dir = File.join(DEMO_ROOT, 'app/models')
    return unless File.exist?(models_dir)

    Dir.glob(File.join(models_dir, '*.rb')).each do |model_path|
      basename = File.basename(model_path, '.rb')
      next if basename == 'application_record'

      source = File.read(model_path)
      associations = []

      # Simple regex to find has_many declarations
      # Matches: has_many :comments or has_many :comments, dependent: :destroy
      source.scan(/has_many\s+:(\w+)/) do |match|
        associations << match[0].to_sym
      end

      if associations.any?
        # Store associations keyed by singular model name (article -> [:comments])
        @model_associations[basename.to_sym] = associations
      end
    end
  end
end

# CLI entry point - only run if this file is executed directly
if __FILE__ == $0
  dist_dir = ARGV[0] ? File.expand_path(ARGV[0]) : nil
  builder = SelfhostBuilder.new(dist_dir)
  builder.build()
end
