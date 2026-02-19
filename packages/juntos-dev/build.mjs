#!/usr/bin/env node
let dist_dir;
import path from "node:path";
import fs from "node:fs";
import yaml from "js-yaml";
import child_process from "node:child_process";
let ARGV = process.argv.slice(2);
import * as Ruby2JS from "../../demo/selfhost/ruby2js.js";
await Ruby2JS.initPrism();
import { Rails_Model } from "../../demo/selfhost/filters/rails/model.js";
import { Rails_Controller } from "../../demo/selfhost/filters/rails/controller.js";
import { Rails_Routes } from "../../demo/selfhost/filters/rails/routes.js";
import { Rails_Seeds } from "../../demo/selfhost/filters/rails/seeds.js";
import { Rails_Migration } from "../../demo/selfhost/filters/rails/migration.js";
import { Functions } from "../../demo/selfhost/filters/functions.js";
import { ESM } from "../../demo/selfhost/filters/esm.js";
import { Return } from "../../demo/selfhost/filters/return.js";
import { Erb } from "../../demo/selfhost/filters/erb.js";
import { Pragma } from "../../demo/selfhost/filters/pragma.js";
import { Rails_Helpers } from "../../demo/selfhost/filters/rails/helpers.js";
import { Phlex } from "../../demo/selfhost/filters/phlex.js";
import { Stimulus } from "../../demo/selfhost/filters/stimulus.js";
import { CamelCase } from "../../demo/selfhost/filters/camelCase.js";
import { CJS } from "../../demo/selfhost/filters/cjs.js";
import { ActiveSupport } from "../../demo/selfhost/filters/active_support.js";
import { SecureRandom } from "../../demo/selfhost/filters/securerandom.js";
import { Jest } from "../../demo/selfhost/filters/jest.js";
import { TaggedTemplates } from "../../demo/selfhost/filters/tagged_templates.js";
import { Nokogiri } from "../../demo/selfhost/filters/nokogiri.js";
import { Haml } from "../../demo/selfhost/filters/haml.js";
import { React } from "../../demo/selfhost/filters/react.js";
import { Astro } from "../../demo/selfhost/filters/astro.js";
import { Vue } from "../../demo/selfhost/filters/vue.js";
import { ErbCompiler } from "../../demo/selfhost/lib/erb_compiler.js";
import { MigrationSQL } from "../../demo/selfhost/lib/migration_sql.js";
import { SeedSQL } from "../../demo/selfhost/lib/seed_sql.js";

export class SelfhostBuilder {
  // ============================================================
  // Class methods for shared functionality
  // These can be called by SPA builder, CLI commands, etc.
  // ============================================================
  // Load database configuration from environment or config/database.yml
  // Returns: { 'adapter' => 'dexie', 'database' => 'myapp_dev', ... }
  static load_database_config(app_root=null, { quiet=false } = {}) {
    app_root = app_root ?? SelfhostBuilder.DEMO_ROOT;
    let env = process.env.RAILS_ENV || process.env.NODE_ENV || "development";

    // Load config from database.yml first
    let config_path = path.join(app_root, "config/database.yml");

    let db_config = fs.existsSync(config_path) ? (() => {
      // Ruby 3.4+/4.0+ requires aliases: true for YAML anchors used by Rails
      let config = yaml.load(fs.readFileSync(config_path, "utf8"));

      if (config && config[env]) {
        if (!quiet) console.log(`  Using config/database.yml [${env}]`);
        return config[env]
      }
    })() : null;

    // Default config if database.yml not found or empty
    db_config = db_config ?? {
      adapter: "sqljs",
      database: "ruby2js_rails"
    };

    // JUNTOS_DATABASE or DATABASE env var overrides adapter only
    let db_env = process.env.JUNTOS_DATABASE ?? process.env.DATABASE;

    if (db_env) {
      if (!quiet) {
        console.log(`  Adapter override: ${process.env.JUNTOS_DATABASE ? "JUNTOS_DATABASE" : "DATABASE"}=${db_env}`)
      };

      db_config.adapter = db_env.toLowerCase()
    };

    return db_config
  };

  // Detect runtime/target from database configuration
  // Returns: { target: 'browser'|'server', runtime: nil|'node'|'bun'|'deno', database: 'adapter_name' }
  // Priority: JUNTOS_* env vars > database.yml target > inferred from adapter
  static detect_runtime(app_root=null) {
    let db_config;

    // Check for CLI overrides first
    let database = process.env.JUNTOS_DATABASE;
    let target = process.env.JUNTOS_TARGET;

    // Fall back to database.yml
    if (!database) {
      db_config = this.load_database_config(app_root, {quiet: true});
      database = db_config.adapter || db_config.adapter || "sqljs";
      target = target || db_config.target || db_config.target
    };

    // Infer target from database if not specified
    target = target || SelfhostBuilder.DEFAULT_TARGETS[database] || "node";
    let runtime = null;

    if (target != "browser") {
      let required = SelfhostBuilder.RUNTIME_REQUIRED[database];
      runtime = required ?? target
    };

    return {target, runtime, database}
  };

  // Generate package.json content for a Ruby2JS app
  // Options:
  //   app_name: Application name (used for package name)
  //   app_root: Application root directory
  // Returns: Hash suitable for JSON.generate
  // Note: Database and target-specific dependencies are added at build time
  static generate_package_json(options={}) {
    let app_name = options.app_name ?? "ruby2js-app";
    let app_root = options.app_root;
    let root_install = options.root_install // If true, package.json is at project root;

    // Check for local packages directory (when running from ruby2js repo)
    // For deploy targets, always use tarball URL since deployed code can't access local files
    let gem_root = path.resolve(import.meta.dirname, "../../..");
    let local_package = path.join(gem_root, "packages/juntos");

    // Path is relative to where package.json lives (root or dist/)
    let package_dir = root_install ? (() => {
      return app_root ?? process.cwd()
    })() : path.join(app_root ?? process.cwd(), "dist");

    // Only use local package if running from development checkout
    // (gem_root is a parent of the app, not installed in bundle/gems)
    let use_local = false;

    if (fs.existsSync(local_package) && fs.statSync(local_package).isDirectory() && !options.for_deploy) {
      // Check if app_root is within the gem source tree (development scenario)
      let app_path = new Pathname(app_root ?? process.cwd()).expand_path;
      let gem_path = new Pathname(gem_root).expand_path;
      use_local = app_path.toString().startsWith(gem_path.toString())
    };

    let deps = use_local ? (() => {
      let relative_path = path.relative(package_dir, local_package);

      // Also add ruby2js directly - Node's module resolution doesn't follow symlinks
      // in file: dependencies, so the peerDep in juntos isn't found
      let selfhost_path = path.relative(
        package_dir,
        path.join(gem_root, "demo/selfhost")
      );

      return {
        "juntos": `file:${relative_path}`,
        ruby2js: `file:${selfhost_path}`
      }
    })() : {
      ruby2js: "https://ruby2js.github.io/ruby2js/releases/ruby2js-beta.tgz",
      "juntos": "https://ruby2js.github.io/ruby2js/releases/juntos-beta.tgz"
    };

    let dev_deps = {};

    // Hotwire Turbo and Stimulus - used by all targets
    // Include both base Turbo (for browser-only) and turbo-rails (for server targets with WebSockets)
    deps["@hotwired/turbo"] = "^8.0.0";
    deps["@hotwired/turbo-rails"] = "^8.0.0";
    deps["@hotwired/stimulus"] = "^3.2.0";

    // React - used by rails.js for rendering React elements
    // Apps can override versions in config/ruby2js.yml
    deps.react = "^18.2.0";
    deps["react-dom"] = "^18.2.0";

    // Add tailwindcss if tailwindcss-rails gem is detected
    let tailwind_css = app_root ? path.join(
      app_root,
      "app/assets/tailwind/application.css"
    ) : "app/assets/tailwind/application.css";

    if (fs.existsSync(tailwind_css)) {
      deps.tailwindcss = "^4.0.0";
      dev_deps["@tailwindcss/cli"] = "^4.0.0"
    };

    // Add user dependencies from ruby2js.yml
    let config_path = app_root ? path.join(
      app_root,
      "config/ruby2js.yml"
    ) : "config/ruby2js.yml";

    if (fs.existsSync(config_path)) {
      try {
        let config = yaml.load(fs.readFileSync(config_path, "utf8")) ?? {};
        let user_deps = config.dependencies ?? {};
        Object.assign(deps, user_deps)
      } catch ($EXCEPTION) {
        if ($EXCEPTION instanceof Error) {

        } else {
          throw $EXCEPTION
        }
      }
    };

    // Skip if config is invalid
    // Base scripts - server scripts added at build time based on target
    let scripts = {
      dev: "juntos-dev",
      "dev:ruby": "juntos-dev --ruby",
      build: "juntos-build",
      migrate: "juntos-migrate",
      start: "npx serve -s -p 3000",

      // Server scripts included by default - they just won't work without deps
      "start:node": "juntos-server",
      "start:bun": "bun node_modules/juntos/server.mjs",
      "start:deno": "deno run --allow-all node_modules/juntos/server.mjs"
    };

    let result = {
      name: app_name.toString().replace(/_/g, "-"),
      version: "0.1.0",
      type: "module",
      description: "Rails-like app powered by Ruby2JS",
      scripts: scripts,
      dependencies: deps
    };

    if (Object.keys(dev_deps).length !== 0) result.devDependencies = dev_deps;
    return result
  };

  // Ensure package.json has required dependencies for the selected adapter and target
  // Updates the file if dependencies are missing and returns true if npm install is needed
  ensure_adapter_dependencies() {
    let package_path = path.join(this._dist_dir, "package.json");
    if (!fs.existsSync(package_path)) return false;
    let $package = JSON.parse(fs.readFileSync(package_path, "utf8"));
    let deps = $package.dependencies ?? {};
    let optional_deps = $package.optionalDependencies ?? {};
    let updated = false;

    // Add adapter-specific dependencies
    let required = SelfhostBuilder.ADAPTER_DEPENDENCIES[this._database];

    if (required) {
      // Native adapters go to optionalDependencies (may fail to compile on some platforms)
      let is_native = SelfhostBuilder.NATIVE_ADAPTERS.includes(this._database);
      let target_deps = is_native ? optional_deps : deps;
      let dep_type = is_native ? "optional dependency" : "dependency";

      Object.entries(required).forEach(([name, version]) => {
        if (name in target_deps || name in deps) return;
        target_deps[name] = version;
        console.log(`  Adding ${dep_type}: ${name}@${version}`);
        updated = true
      })
    };

    // Add broadcast adapter dependencies (Supabase Realtime, Pusher, etc.)
    // Note: @broadcast may not be set yet during initial build, so we auto-detect
    let broadcast = this._broadcast;

    if (!broadcast) {
      if (this._database == "supabase") {
        broadcast = "supabase"
      } else if (SelfhostBuilder.VERCEL_RUNTIMES.includes(this._target.toString())) {
        broadcast = "pusher"
      }
    };

    let broadcast_deps = SelfhostBuilder.BROADCAST_ADAPTER_DEPENDENCIES[broadcast];

    if (broadcast_deps) {
      Object.entries(broadcast_deps).forEach(([name, version]) => {
        if (name in deps) return;
        deps[name] = version;
        console.log(`  Adding broadcast dependency: ${name}@${version}`);
        updated = true
      })
    };

    // Add ws for Node/Bun/Deno targets (WebSocket support for real-time features)
    // Skip if using external broadcast adapter (Supabase, Pusher handle their own connections)
    let node_targets = ["node", "bun", "deno"];

    if (node_targets.includes(this._target.toString()) && !broadcast && !("ws" in optional_deps)) {
      optional_deps.ws = "^8.18.0";
      console.log("  Adding optional dependency: ws@^8.18.0");
      updated = true
    };

    // Add user-specified dependencies from ruby2js.yml
    let user_deps = this.load_ruby2js_config("dependencies");

    if (typeof user_deps === "object" && user_deps !== null && !Array.isArray(user_deps)) {
      Object.entries(user_deps).forEach(([name, version]) => {
        if (!(name in deps)) {
          deps[name] = version;
          console.log(`  Adding dependency: ${name}@${version}`);
          updated = true
        }
      })
    };

    if (!updated) return false;
    $package.dependencies = deps;
    if (optional_deps.length != 0) $package.optionalDependencies = optional_deps;

    // Use atomic write (temp file + rename) to avoid race conditions
    // where other processes might read a partially written file
    let temp_path = `${package_path}.tmp`;
    fs.writeFileSync(temp_path, JSON.stringify($package, null, 2) + "\n");
    fs.renameSync(temp_path, package_path);
    console.log("  Updated package.json");
    return true
  };

  // Generate index.html for browser builds
  // Options:
  //   app_name: Application name (for title)
  //   database: Database adapter (for importmap)
  //   target: Target runtime ('browser' uses base Turbo, server targets use turbo-rails)
  //   css: CSS framework ('none', 'tailwind', 'pico', 'bootstrap', 'bulma')
  //   output_path: Where to write the file (if nil, returns string)
  //   importmap: Hash of additional import map entries (e.g., {'react' => 'https://esm.sh/react'})
  // Returns: HTML string (also writes to output_path if specified)
  static generate_index_html(options={}) {
    let html, turbo_import;
    let app_name = options.app_name ?? "Ruby2JS App";
    let database = options.database ?? "dexie";
    let target = options.target ?? "browser";
    let css = options.css ?? "none";
    let output_path = options.output_path;

    // Base path for assets - '/dist' when serving from app root, '' when serving from dist/
    let base_path = options.base_path ?? "/dist";
    let user_importmap = options.importmap ?? {};
    let dependencies = options.dependencies ?? {};
    let stylesheets = options.stylesheets ?? [];
    let dist_dir = options.dist_dir;

    // bundled: true generates index.html for Vite bundling (no importmap)
    let bundled = options.bundled || false;

    // Use base Turbo for browser and edge targets, turbo-rails for server targets
    // Browser uses BroadcastChannel API, Cloudflare uses simple WebSocket (hibernation-friendly)
    // Server targets (Node/Bun/Deno) use turbo-rails for Action Cable WebSocket support
    let use_turbo_rails = !["browser", "cloudflare"].includes(target);

    // CSS link based on framework
    // This method is only used for browser targets, which serve from dist/ root
    let css_link = (() => {
      switch (css.toString()) {
      case "tailwind":
        return "<link href=\"/public/assets/tailwind.css\" rel=\"stylesheet\">";

      case "pico":
        return "<link rel=\"stylesheet\" href=\"/node_modules/@picocss/pico/css/pico.min.css\">";

      case "bootstrap":
        return "<link href=\"https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css\" rel=\"stylesheet\">";

      case "bulma":
        return "<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/bulma@0.9.4/css/bulma.min.css\">";

      default:
        return ""
      }
    })();

    // Main container class based on CSS framework
    let main_class = (() => {
      switch (css.toString()) {
      case "pico":
        return "container";

      case "bootstrap":
        return "container mt-4";

      case "bulma":
        return "container mt-4";

      case "tailwind":
        return "container mx-auto mt-28 px-5";

      default:
        return ""
      }
    })();

    if (bundled) {
      // For Vite bundling: no importmap, reference main.js entry point
      // Vite will bundle all imports including npm dependencies
      // CSS is handled via main.js imports, but keep framework CSS link
      html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${app_name}</title>
  ${css_link}
</head>
<body>
  <div id="loading">Loading...</div>
  <div id="app" style="display:none">
    <main class="${main_class}" id="content"></main>
  </div>
  <script type="module" src="./main.js"></script>
</body>
</html>
`;

      // Also generate main.js entry point for Vite to bundle
      if (dist_dir) {
        // Browser-only targets use base Turbo (no Action Cable needed, uses BroadcastChannel)
        // Cloudflare uses base Turbo + simple cable client (hibernation-friendly)
        // Server targets use turbo-rails for WebSocket support via Action Cable
        turbo_import = use_turbo_rails ? "@hotwired/turbo-rails" : "@hotwired/turbo";

        // Cloudflare needs the simple cable client for WebSocket subscriptions
        let cable_import = target == "cloudflare" ? "import './lib/turbo_cable_simple.js';\n" : "";
        let main_js = `// Main entry point for Vite bundling
import * as Turbo from '${turbo_import}';
${cable_import}import { Application } from './config/routes.js';
import './app/javascript/controllers/index.js';
window.Turbo = Turbo;
Application.start();
`;
        fs.writeFileSync(path.join(dist_dir, "main.js"), main_js)
      }
    } else {
      // For importmap mode: include importmap for unbundled development
      // Build importmap - merge common entries with database-specific and user entries
      let db_entries = SelfhostBuilder.IMPORTMAP_ENTRIES[database] ?? SelfhostBuilder.IMPORTMAP_ENTRIES.dexie;

      let importmap_entries = {
        ...SelfhostBuilder.COMMON_IMPORTMAP_ENTRIES,
        ...db_entries,
        ...user_importmap
      };

      // Add turbo import based on target - browser-only uses base Turbo, server targets use turbo-rails
      turbo_import = use_turbo_rails ? "@hotwired/turbo-rails" : "@hotwired/turbo";
      let turbo_path = use_turbo_rails ? "/node_modules/@hotwired/turbo-rails/app/assets/javascripts/turbo.js" : "/node_modules/@hotwired/turbo/dist/turbo.es2017-esm.js";
      importmap_entries[turbo_import] = turbo_path;

      Object.entries(dependencies).forEach(([pkg_name, _version]) => {
        if (pkg_name in importmap_entries) return // Don't override existing entries;

        let pkg_json_path = dist_dir ? path.join(
          dist_dir,
          "node_modules",
          pkg_name,
          "package.json"
        ) : null;

        if (pkg_json_path && fs.existsSync(pkg_json_path)) {
          try {
            let pkg_json = JSON.parse(fs.readFileSync(pkg_json_path, "utf8"));

            // Prefer "module" (ESM), fall back to "main"
            let entry_point = pkg_json.module || pkg_json.main || "index.js";
            importmap_entries[pkg_name] = `/node_modules/${pkg_name}/${entry_point}`
          } catch ($EXCEPTION) {
            if ($EXCEPTION instanceof SyntaxError) {

            } else {
              throw $EXCEPTION
            }
          }
        }
      });

      // Skip if package.json is invalid
      let importmap = {imports: importmap_entries};

      // Add additional stylesheets from ruby2js.yml (only needed in unbundled mode)
      // These are CSS files from npm packages (e.g., 'reactflow/dist/style.css')
      let stylesheet_links = stylesheets.map(path => (
        `<link rel="stylesheet" href="/node_modules/${path}">`
      )).join("\n    ");

      // Combine framework CSS with additional stylesheets
      let all_css_links = [css_link, stylesheet_links].filter(s => (
        !(s.toString().length == 0)
      )).join("\n    ");

      html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${app_name}</title>
  ${all_css_links}
  <script type="importmap">
  ${JSON.stringify(
        importmap,
        null,
        2
      )}
  </script>
</head>
<body>
  <div id="loading">Loading...</div>
  <div id="app" style="display:none">
    <main class="${main_class}" id="content"></main>
  </div>
  <script type="module">
    import * as Turbo from '${turbo_import}';
    import { Application } from '${base_path}/config/routes.js';
    import '${base_path}/app/javascript/controllers/index.js';
    window.Turbo = Turbo;
    Application.start();
  </script>
</body>
</html>
`
    };

    if (output_path) {
      fs.mkdirSync(path.dirname(output_path), {recursive: true});
      fs.writeFileSync(output_path, html)
    };

    return html
  };

  // ============================================================
  // Instance methods
  // ============================================================
  constructor(dist_dir=null, { target=null, database=null, broadcast=null, base=null, vite=null, sourcemap=true } = {}) {
    this._dist_dir = dist_dir ?? path.join(
      SelfhostBuilder.DEMO_ROOT,
      "dist"
    );

    this._database_override = database // CLI override for database adapter;
    this._database = null // Set during build from config or override;
    this._target = target // Can be set explicitly or derived from database;
    this._runtime = null // For server targets: 'node', 'bun', or 'deno';
    this._broadcast = broadcast // Broadcast adapter: 'supabase', 'pusher', or nil (use native WebSocket);
    this._base = base // Base path for routes (e.g., '/blog' when serving from subdirectory);
    this._model_associations = {} // model_name -> [association_names];
    this._vite = vite // nil = auto (true for browser), false = force compiled imports;
    this._sourcemap = sourcemap // Generate sourcemaps for transpiled files
  };

  // Note: Using explicit () on all method calls for JS transpilation compatibility
  build() {
    // Clean dist directory but preserve files managed by ruby2js install
    // These shouldn't be removed during builds
    // Also preserve database files (SQLite, etc.)
    if (fs.existsSync(this._dist_dir) && fs.statSync(this._dist_dir).isDirectory()) {
      for (let basename of fs.readdirSync(this._dist_dir)) {
        if ([
          "package.json",
          "package-lock.json",
          "node_modules",
          "vite.config.js",
          "storage"
        ].includes(basename)) continue;

        // Preserve SQLite database files (including WAL mode files)
        if ([".sqlite3", ".db", "-shm", "-wal"].some(_p => basename.endsWith(_p))) {
          continue
        };

        fs.rmSync(
          path.join(this._dist_dir, basename),
          {recursive: true, force: true}
        )
      }
    } else {
      fs.mkdirSync(this._dist_dir, {recursive: true})
    };

    console.log("=== Building Ruby2JS-on-Rails Demo ===");
    console.log("");

    // Load database config and derive target (unless explicitly set)
    // Priority: CLI option > database.yml target > inferred from adapter
    console.log("Database Adapter:");

    if (this._database_override) {
      console.log(`  CLI override: ${this._database_override}`);
      this._database = this._database_override
    } else {
      let db_config = this.load_database_config();
      this._database = db_config.adapter || db_config.adapter || "sqljs"
    };

    this._target = this._target || process.env.JUNTOS_TARGET || SelfhostBuilder.DEFAULT_TARGETS[this._database] || "node";

    // Set runtime based on target
    if (this._target == "browser" || this._target == "capacitor") {
      this._runtime = null // Browser/Capacitor targets don't use a server runtime
    } else if (this._target == "electron") {
      this._runtime = "electron" // Electron has its own runtime
    } else {
      // Check if database requires a specific runtime
      let required_runtime = SelfhostBuilder.RUNTIME_REQUIRED[this._database];

      if (required_runtime) {
        this._runtime = required_runtime
      } else if (this._target == "vercel" || this._target == "vercel-edge") {
        this._runtime = "vercel-edge";
        this._target = "vercel" // Normalize target name
      } else if (this._target == "vercel-node") {
        this._runtime = "vercel-node";
        this._target = "vercel" // Normalize target name
      } else if (this._target == "deno-deploy") {
        this._runtime = "deno-deploy";
        this._target = "deno-deploy"
      } else if (this._target == "cloudflare") {
        this._runtime = "cloudflare"
      } else {
        this._runtime = this._target // node, bun, deno
      };

      if (!SelfhostBuilder.SERVER_RUNTIMES.includes(this._runtime) && this._runtime != "electron") {
        throw `Unknown runtime: ${this._runtime}. Valid options: ${SelfhostBuilder.SERVER_RUNTIMES.join(", ")}, electron`
      }
    };

    // Validate database/target combination
    this.validate_target();

    // Ensure package.json has required dependencies for this adapter
    this._needs_npm_install = this.ensure_adapter_dependencies();
    this.copy_database_adapter();
    this.setup_broadcast_adapter();
    console.log(`  Target: ${this._target}`);
    if (this._runtime) console.log(`  Runtime: ${this._runtime}`);

    if (this._broadcast || SelfhostBuilder.VERCEL_RUNTIMES.includes(this._runtime) || SelfhostBuilder.DENO_DEPLOY_RUNTIMES.includes(this._runtime)) {
      console.log(`  Broadcast: ${this._broadcast ?? "native WebSocket"}`)
    };

    console.log("");

    // Copy target-specific lib files (rails.js framework)
    console.log("Library:");
    this.copy_lib_files();
    console.log("");

    // Generate ApplicationRecord wrapper and transpile models
    console.log("Models:");
    this.generate_application_record();

    this.transpile_directory(
      path.join(SelfhostBuilder.DEMO_ROOT, "app/models"),
      path.join(this._dist_dir, "app/models"),
      "**/*.rb",
      {skip: ["application_record.rb"]}
    );

    this.generate_models_index();
    console.log("");

    // Parse model associations for controller preloading
    this.parse_model_associations();

    // Transpile controllers (use 'controllers' section from ruby2js.yml if present)
    // Skip application_controller.rb - it extends ActionController::Base which has no JS equivalent
    // The transpiled controllers are modules, not classes, so they don't need a base class
    console.log("Controllers:");

    this.transpile_directory(
      path.join(SelfhostBuilder.DEMO_ROOT, "app/controllers"),
      path.join(this._dist_dir, "app/controllers"),
      "**/*.rb",
      {skip: ["application_controller.rb"], section: "controllers"}
    );

    console.log("");

    // Build component map for import resolution before transpiling
    // Maps component names to their paths (e.g., 'Button' => 'app/components/Button.js')
    let components_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "app/components"
    );

    this._component_map = this.build_component_map(components_dir);

    // Transpile components (Phlex views, JSX.rb, and JSX React components)
    // - .rb files use 'components' section from ruby2js.yml
    // - .jsx.rb files use 'rbx' section (React filter with rbx2_js)
    // - .jsx/.tsx files use esbuild for JSX transformation
    if (fs.existsSync(components_dir)) {
      console.log("Components:");
      this.copy_phlex_runtime();
      this.copy_json_stream_provider();

      this.transpile_directory(
        components_dir,
        path.join(this._dist_dir, "app/components"),
        "**/*.{rb,jsx.rb,jsx,tsx}",
        {section: "components"}
      );

      console.log("")
    };

    // Handle Stimulus controllers (app/javascript/controllers/)
    // - Copy .js files directly (no transpilation)
    // - Transpile .rb files with stimulus filter
    // - Generate controllers/index.js to register all controllers
    let stimulus_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "app/javascript/controllers"
    );

    if (fs.existsSync(stimulus_dir)) {
      console.log("Stimulus Controllers:");

      let controllers_dest = path.join(
        this._dist_dir,
        "app/javascript/controllers"
      );

      this.process_stimulus_controllers(stimulus_dir, controllers_dest);

      // Copy generated index.js back to source for Vite compatibility
      // (Rails generates importmap-style imports that don't work with Vite bundling)
      let generated_index = path.join(controllers_dest, "index.js");

      if (fs.existsSync(generated_index)) {
        fs.copyFileSync(generated_index, path.join(stimulus_dir, "index.js"))
      };

      // For edge targets (Cloudflare, Vercel), also copy to public/ for static serving
      let edge_targets = ["cloudflare", "vercel-edge", "vercel-node"];
      let target_str = this._target ? this._target.toString() : null;
      let runtime_str = this._runtime ? this._runtime.toString() : null;

      if (edge_targets.includes(target_str) || edge_targets.includes(runtime_str)) {
        let public_controllers = path.join(
          this._dist_dir,
          "public/app/javascript/controllers"
        );

        fs.mkdirSync(public_controllers, {recursive: true});

        FileUtils.cp_r(
          fs.globSync(`${controllers_dest}/*.js`),
          public_controllers
        );

        console.log("  -> public/app/javascript/controllers/ (for static serving)")
      };

      console.log("")
    };

    // Transpile config - only routes.rb is relevant for Juntos
    // Skip all Rails-specific config files (boot, application, environment, puma, etc.)
    // Skip subdirectories (environments/, initializers/) which are Rails-only
    console.log("Config:");
    this.transpile_routes_files();
    console.log("");

    // Transpile views (ERB templates and layout)
    console.log("Views:");
    this.transpile_erb_directory();
    if (this._target != "browser") this.transpile_layout();
    console.log("");

    // Note: Rails view helpers (app/helpers/) are not transpiled
    // They don't have Juntos equivalents - use JS helper functions instead
    // Transpile db (migrations and seeds)
    console.log("Database:");
    let db_src = path.join(SelfhostBuilder.DEMO_ROOT, "db");
    let db_dest = path.join(this._dist_dir, "db");

    // Transpile migrations (skip schema.rb and seeds.rb)
    this.transpile_migrations(db_src, db_dest);

    // Handle seeds.rb specially - generate stub if empty/comments-only
    this.transpile_seeds(db_src, db_dest);
    console.log("");

    // Generate index.html for browser targets
    if (this._target == "browser") {
      console.log("Static Files:");
      this.generate_browser_index();
      console.log("")
    };

    // Generate Vercel deployment files
    if (SelfhostBuilder.VERCEL_RUNTIMES.includes(this._runtime)) {
      console.log("Vercel:");
      this.generate_vercel_config();
      this.generate_vercel_entry_point();
      console.log("")
    };

    // Generate Cloudflare deployment files
    if (this._runtime == "cloudflare") {
      console.log("Cloudflare:");
      this.generate_cloudflare_config();
      this.generate_cloudflare_entry_point();
      console.log("")
    };

    // Generate Deno Deploy deployment files
    if (SelfhostBuilder.DENO_DEPLOY_RUNTIMES.includes(this._runtime)) {
      console.log("Deno Deploy:");
      this.generate_deno_deploy_entry_point();
      console.log("")
    };

    // Generate Fly.io deployment files
    if (SelfhostBuilder.FLY_RUNTIMES.includes(this._runtime)) {
      console.log("Fly.io:");
      this.generate_fly_config();
      console.log("")
    };

    // Generate Capacitor deployment files
    if (SelfhostBuilder.CAPACITOR_RUNTIMES.includes(this._target)) {
      console.log("Capacitor:");
      this.generate_capacitor_config();
      console.log("")
    };

    // Generate Electron deployment files
    if (SelfhostBuilder.ELECTRON_RUNTIMES.includes(this._target)) {
      console.log("Electron:");
      this.generate_electron_main();
      this.generate_electron_preload();
      console.log("")
    };

    // Generate Tauri deployment files
    if (SelfhostBuilder.TAURI_RUNTIMES.includes(this._target)) {
      console.log("Tauri:");
      this.generate_tauri_config();
      console.log("")
    };

    // Handle Tailwind CSS if present
    this.setup_tailwind();

    // Run npm install if dependencies were added to package.json
    if (this._needs_npm_install) {
      console.log("Installing dependencies...");
      let $oldwd = process.cwd();

      try {
        process.chdir(this._dist_dir);

        child_process.execFileSync(
          "npm",
          ["install", "--silent"],
          {stdio: "inherit"}
        )
      } finally {
        process.chdir($oldwd)
      };

      console.log("")
    };

    // Copy .env.local if present (for database credentials, API keys, etc.)
    let env_local = path.join(SelfhostBuilder.DEMO_ROOT, ".env.local");

    if (fs.existsSync(env_local)) {
      fs.copyFileSync(env_local, path.join(this._dist_dir, ".env.local"))
    };

    return console.log("=== Build Complete ===")
  };

  validate_target() {
    // Determine the effective target for validation
    // For browser/capacitor/electron targets, use the target name directly
    // For server targets, use the runtime
    let effective_target = (() => {
      switch (this._target) {
      case "browser":
      case "capacitor":
      case "electron":
        return this._target;

      default:
        return this._runtime
      }
    })();

    let valid_targets = SelfhostBuilder.VALID_TARGETS[this._database];
    if (!valid_targets) return // Unknown database, skip validation;

    if (!valid_targets.includes(effective_target)) {
      return (() => { throw `${`Database '${this._database}' does not support target '${effective_target}'.\n`}${`Valid targets for ${this._database}: ${valid_targets.join(", ")}`}` })()
    }
  };

  load_ruby2js_config(section=null) {
    let env = process.env.RAILS_ENV || process.env.NODE_ENV || "development";

    let config_path = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "config/ruby2js.yml"
    );

    if (!fs.existsSync(config_path)) return {};

    // Ruby 3.4+ requires aliases: true for YAML anchors
    let config = yaml.load(fs.readFileSync(config_path, "utf8"));

    // If a specific section is requested (e.g., 'controllers', 'components', 'dependencies')
    // Return the section if it exists, otherwise empty hash
    if (section) return config[section] ?? {};

    if (env in config) {
      return config[env]
    } else if ("default" in config) {
      return config.default
    } else {
      return config
    }
  };

  build_options(section=null) {
    // Load section-specific config if section is specified, otherwise default
    let base = this.load_ruby2js_config(section);

    // Check if preset mode is enabled
    let use_preset = base.preset ?? base.preset;

    // Use section-specific options as base, or preset if enabled
    let base_options = use_preset ? PRESET_OPTIONS : (() => {
      switch (section) {
      case "stimulus":
        return SelfhostBuilder.STIMULUS_OPTIONS;

      case "rbx":
        return SelfhostBuilder.RBX_OPTIONS;

      case "astro":
        return SelfhostBuilder.ASTRO_OPTIONS;

      case "vue":
        return SelfhostBuilder.VUE_OPTIONS;

      default:
        return SelfhostBuilder.OPTIONS
      }
    })();

    // Start with hardcoded options as base (using spread for JS compatibility)
    let options = {...base_options};

    // Track filters to disable (processed after all options are merged)
    let disable_filters = null;

    Object.entries(base).forEach(([key, value]) => {
      let sym_key = key.toString();

      // Skip preset key (already handled above)
      if (sym_key == "preset") return;

      // Handle disable_filters separately (applied after filters are set)
      if (sym_key == "disable_filters" && Array.isArray(value)) {
        disable_filters = this.resolve_filters(value);
        return
      };

      // Convert filter names to module references
      if (sym_key == "filters" && Array.isArray(value)) {
        options[sym_key] = this.resolve_filters(value)
      } else {
        options[sym_key] = value
      }
    });

    // Apply disable_filters: remove specified filters from the list
    if (disable_filters && options.filters) {
      options.filters = options.filters.filter(f => !(disable_filters.includes(f)))
    };

    // Pass model associations to controller filter for preloading
    if (section == "controllers" && this._model_associations && Object.keys(this._model_associations).length > 0) {
      options.model_associations = this._model_associations
    };

    // Pass target for target-specific pragmas (browser, node, server, etc.)
    if (this._target) options.target = this._target;
    return options
  };

  resolve_filters(filter_names) {
    return filter_names.map((name) => {
      let valid_filters;

      // Already a filter (not a string)? Pass through
      // In Ruby, filters are Modules; in JS, they're prototype objects
      if (typeof name !== "string") return name;

      // Normalize: strip for lookup (preserve case for camelCase)
      let normalized = name.toString().trim();
      let lookup_key = normalized in SelfhostBuilder.FILTER_MAP ? normalized : normalized.toLowerCase();
      let filter = SelfhostBuilder.FILTER_MAP[lookup_key];

      if (!filter) {
        valid_filters = [...new Set(SelfhostBuilder.FILTER_MAP.keys)].sort().join(", ");
        throw `Unknown filter: '${name}'. Valid filters: ${valid_filters}`
      };

      return filter
    })
  };

  load_database_config() {
    return SelfhostBuilder.load_database_config(SelfhostBuilder.DEMO_ROOT)
  };

  copy_database_adapter() {
    let valid, rpc_adapter_src, rpc_adapter_dest;
    let adapter_file = SelfhostBuilder.ADAPTER_FILES[this._database];

    if (!adapter_file) {
      valid = Object.keys(SelfhostBuilder.ADAPTER_FILES).join(", ");
      throw `Unknown DATABASE adapter: ${this._database}. Valid options: ${valid}`
    };

    // Check for local packages first (development), then npm-installed, finally vendor (legacy)
    // Prefer local source over npm when available so local changes are immediately reflected
    let npm_adapter_dir = path.join(
      this._dist_dir,
      "node_modules/juntos/adapters"
    );

    let npm_dist_dir = path.join(
      this._dist_dir,
      "node_modules/juntos/dist/lib"
    );

    let pkg_adapter_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "../../packages/juntos/adapters"
    );

    let vendor_adapter_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "vendor/ruby2js/adapters"
    );

    let adapter_dir = fs.existsSync(pkg_adapter_dir) ? pkg_adapter_dir : fs.existsSync(npm_adapter_dir) ? npm_adapter_dir : fs.existsSync(npm_dist_dir) ? npm_dist_dir : fs.existsSync(vendor_adapter_dir) ? vendor_adapter_dir : (() => { throw `Could not find juntos adapters directory.
Looked in:
  - ${npm_adapter_dir}
  - ${npm_dist_dir}
  - ${pkg_adapter_dir}
  - ${vendor_adapter_dir}

Try running: npm install juntos
Or ensure the juntos package is properly installed.
` })();
    let lib_dest = path.join(this._dist_dir, "lib");
    fs.mkdirSync(lib_dest, {recursive: true});

    // Shared modules (active_record_base, active_record_sql, relation, inflector, sql_parser)
    // are now imported from juntos npm package, not copied to dist.
    // This keeps dist smaller and provides a single source of truth.
    // Copy dialect files (SQLite, PostgreSQL, or MySQL)
    let dialects_src = path.join(adapter_dir, "dialects");

    if (fs.existsSync(dialects_src) && fs.statSync(dialects_src).isDirectory()) {
      let dialects_dest = path.join(lib_dest, "dialects");
      fs.mkdirSync(dialects_dest, {recursive: true});

      // Determine which dialect to copy based on adapter
      // Note: dexie and supabase are intentionally standalone (non-SQL)
      let sqlite_adapters = [
        "sqljs",
        "sql.js",
        "better_sqlite3",
        "sqlite3",
        "sqlite",
        "turso",
        "libsql",
        "d1"
      ];

      let postgres_adapters = [
        "pg",
        "postgres",
        "postgresql",
        "pglite",
        "neon",
        "mpg"
      ];

      let mysql_adapters = ["mysql", "mysql2", "planetscale"];

      if (sqlite_adapters.includes(this._database)) {
        let dialect_src = path.join(dialects_src, "sqlite.mjs");

        if (fs.existsSync(dialect_src)) {
          fs.copyFileSync(dialect_src, path.join(dialects_dest, "sqlite.mjs"));
          console.log("  Dialect: dialects/sqlite.mjs")
        }
      } else if (postgres_adapters.includes(this._database)) {
        let dialect_src = path.join(dialects_src, "postgres.mjs");

        if (fs.existsSync(dialect_src)) {
          fs.copyFileSync(
            dialect_src,
            path.join(dialects_dest, "postgres.mjs")
          );

          console.log("  Dialect: dialects/postgres.mjs")
        }
      } else if (mysql_adapters.includes(this._database)) {
        let dialect_src = path.join(dialects_src, "mysql.mjs");

        if (fs.existsSync(dialect_src)) {
          fs.copyFileSync(dialect_src, path.join(dialects_dest, "mysql.mjs"));
          console.log("  Dialect: dialects/mysql.mjs")
        }
      }
    };

    // Get database config for injection
    // Always load from database.yml, but CLI -d flag overrides the adapter
    let db_config = this.load_database_config();
    if (this._database_override) db_config.adapter = this._database;

    // Ensure SQLite databases have .sqlite3 extension for reliable preservation during rebuilds
    let db_name = db_config.database ?? db_config.database;

    if (db_name && ["sqlite", "sqlite3", "better_sqlite3"].includes(this._database)) {
      if (![".sqlite3", ".db"].some(_p => db_name.endsWith(_p)) && db_name != ":memory:") {
        db_config.database = `${db_name}.sqlite3`
      }
    };

    // Read adapter and inject config
    let adapter_src = path.join(adapter_dir, adapter_file);
    let adapter_dest = path.join(lib_dest, "active_record.mjs");
    let adapter_code = fs.readFileSync(adapter_src, "utf8");

    adapter_code = adapter_code.replace(
      "const DB_CONFIG = {};",
      `const DB_CONFIG = ${JSON.stringify(db_config)};`
    );

    fs.writeFileSync(adapter_dest, adapter_code);
    console.log(`  Adapter: ${this._database} -> lib/active_record.mjs`);

    if (db_config.database || db_config.database) {
      console.log(`  Database: ${db_config.database ?? db_config.database}`)
    };

    if (SelfhostBuilder.SERVER_RUNTIMES.includes(this._target)) {
      rpc_adapter_src = path.join(adapter_dir, "active_record_rpc.mjs");

      if (fs.existsSync(rpc_adapter_src)) {
        rpc_adapter_dest = path.join(lib_dest, "active_record_client.mjs");
        fs.copyFileSync(rpc_adapter_src, rpc_adapter_dest);
        return console.log("  RPC Adapter: lib/active_record_client.mjs (for browser)")
      }
    }
  };

  // Set up broadcast adapter for real-time Turbo Streams
  // Auto-detects based on database and target if not explicitly set
  setup_broadcast_adapter() {
    // Auto-detect broadcast adapter if not explicitly set
    if (!this._broadcast) {
      if (this._database == "supabase") {
        // Supabase Realtime for Supabase database users
        this._broadcast = "supabase"
      } else if (SelfhostBuilder.VERCEL_RUNTIMES.includes(this._runtime) || SelfhostBuilder.DENO_DEPLOY_RUNTIMES.includes(this._runtime)) {
        // Pusher for Vercel/Deno Deploy (no native WebSocket support)
        this._broadcast = "pusher"
      }
    };

    // Otherwise, use native WebSocket (built into rails.js targets)
    // Copy broadcast adapter if using an external service
    let adapter_file = SelfhostBuilder.BROADCAST_ADAPTER_FILES[this._broadcast];
    if (!adapter_file) return;
    let adapter_dir = this.find_adapter_dir();
    let lib_dest = path.join(this._dist_dir, "lib");
    fs.mkdirSync(lib_dest, {recursive: true});
    let adapter_src = path.join(adapter_dir, adapter_file);
    let adapter_dest = path.join(lib_dest, "broadcast.mjs");

    if (fs.existsSync(adapter_src)) {
      fs.copyFileSync(adapter_src, adapter_dest);
      return console.log(`  Broadcast: ${this._broadcast} -> lib/broadcast.mjs`)
    } else {
      return console.log(`  Warning: Broadcast adapter not found: ${adapter_src}`)
    }
  };

  // Find the adapters directory
  // Checks multiple locations:
  // 1. Local packages (development)
  // 2. App root node_modules (Vite-native architecture)
  // 3. dist/ node_modules (legacy .juntos architecture)
  // 4. Vendor directory
  find_adapter_dir() {
    let npm_adapter_dir = path.join(
      this._dist_dir,
      "node_modules/juntos/adapters"
    );

    let npm_dist_dir = path.join(
      this._dist_dir,
      "node_modules/juntos/dist/lib"
    );

    let pkg_adapter_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "../../packages/juntos/adapters"
    );

    let vendor_adapter_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "vendor/ruby2js/adapters"
    );

    // Vite-native: node_modules at app root
    let app_root_adapter_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "node_modules/juntos/adapters"
    );

    if (fs.existsSync(pkg_adapter_dir)) {
      return pkg_adapter_dir
    } else if (fs.existsSync(app_root_adapter_dir)) {
      return app_root_adapter_dir
    } else if (fs.existsSync(npm_adapter_dir)) {
      return npm_adapter_dir
    } else if (fs.existsSync(npm_dist_dir)) {
      return npm_dist_dir
    } else if (fs.existsSync(vendor_adapter_dir)) {
      return vendor_adapter_dir
    } else {
      return null
    }
  };

  // Find the juntos package directory, preferring local packages when in dev
  get find_package_dir() {
    let npm_package_dir = path.join(
      this._dist_dir,
      "node_modules/juntos"
    );

    let pkg_package_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "../../packages/juntos"
    );

    let vendor_package_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "vendor/ruby2js"
    );

    // When running from within ruby2js repo, remove stale npm module UNLESS it's
    // already a symlink (from file: dependency in package.json) pointing to local packages
    if (fs.existsSync(pkg_package_dir) && fs.existsSync(npm_package_dir) && !fs.lstatSync(npm_package_dir).isSymbolicLink()) {
      console.log("  Removing stale npm module (using local packages instead)");
      fs.rmSync(npm_package_dir, {recursive: true, force: true})
    };

    if (fs.existsSync(npm_package_dir)) {
      return npm_package_dir
    } else if (fs.existsSync(pkg_package_dir)) {
      return pkg_package_dir
    } else {
      return vendor_package_dir
    }
  };

  copy_lib_files() {
    let target_dir, cable_src;
    let lib_dest = path.join(this._dist_dir, "lib");
    fs.mkdirSync(lib_dest, {recursive: true});

    // Determine source directory: browser or runtime-specific server target
    if (this._target == "browser") {
      target_dir = "browser"
    } else if (this._target == "capacitor") {
      target_dir = "capacitor"
    } else if (this._target == "electron") {
      target_dir = "electron"
    } else if (this._target == "tauri") {
      target_dir = "tauri"
    } else if (this._target == "cloudflare") {
      target_dir = "cloudflare"
    } else if (SelfhostBuilder.FLY_RUNTIMES.includes(this._runtime)) {
      target_dir = "node" // Fly.io runs Node.js in containers
    } else {
      target_dir = this._runtime // node, bun, or deno
    };

    let package_dir = this.find_package_dir;

    // Copy base files (rails_base.js is needed by all targets)
    let base_src = path.join(package_dir, "rails_base.js");

    if (fs.existsSync(base_src)) {
      fs.copyFileSync(base_src, path.join(lib_dest, "rails_base.js"));
      console.log("  Copying: rails_base.js");
      console.log(`    -> ${lib_dest}/rails_base.js`)
    };

    // Copy server module (needed by server targets, not browser/capacitor/tauri)
    if (this._target != "browser" && this._target != "capacitor" && this._target != "tauri") {
      let server_src = path.join(package_dir, "rails_server.js");

      if (fs.existsSync(server_src)) {
        fs.copyFileSync(server_src, path.join(lib_dest, "rails_server.js"));
        console.log("  Copying: rails_server.js");
        console.log(`    -> ${lib_dest}/rails_server.js`)
      };

      // Copy RPC directory (server.mjs imported by rails_server.js)
      let rpc_src = path.join(package_dir, "rpc");

      if (fs.existsSync(rpc_src) && fs.statSync(rpc_src).isDirectory()) {
        let rpc_dest = path.join(lib_dest, "rpc");
        fs.mkdirSync(rpc_dest, {recursive: true});

        for (let src_path of fs.globSync(path.join(rpc_src, "*.mjs"))) {
          let dest_path = path.join(rpc_dest, path.basename(src_path));
          fs.copyFileSync(src_path, dest_path);
          console.log(`  Copying: rpc/${path.basename(src_path)}`);
          console.log(`    -> ${dest_path}`)
        }
      }
    };

    // Copy target-specific files (rails.js from targets/browser, node, bun, or deno)
    let target_src = path.join(package_dir, "targets", target_dir);

    for (let src_path of fs.globSync(path.join(target_src, "*.js"))) {
      let dest_path = path.join(lib_dest, path.basename(src_path));
      fs.copyFileSync(src_path, dest_path);
      console.log(`  Copying: targets/${target_dir}/${path.basename(src_path)}`);
      console.log(`    -> ${dest_path}`)
    };

    // Copy runtime lib files (erb_runtime.mjs only - build tools stay in vendor)
    let runtime_libs = ["erb_runtime.mjs"];

    for (let filename of runtime_libs) {
      let src_path = path.join(package_dir, filename);
      if (!fs.existsSync(src_path)) continue;
      let dest_path = path.join(lib_dest, filename);
      fs.copyFileSync(src_path, dest_path);
      console.log(`  Copying: ${filename}`);
      console.log(`    -> ${dest_path}`)
    };

    if (this._target == "cloudflare") {
      cable_src = path.join(package_dir, "turbo_cable_simple.js");

      if (fs.existsSync(cable_src)) {
        fs.copyFileSync(
          cable_src,
          path.join(lib_dest, "turbo_cable_simple.js")
        );

        console.log("  Copying: turbo_cable_simple.js");
        return console.log(`    -> ${lib_dest}/turbo_cable_simple.js`)
      }
    }
  };

  copy_phlex_runtime() {
    let lib_dest = path.join(this._dist_dir, "lib");
    fs.mkdirSync(lib_dest, {recursive: true});
    let package_dir = this.find_package_dir;
    let src_path = path.join(package_dir, "phlex_runtime.mjs");
    if (!fs.existsSync(src_path)) return;
    let dest_path = path.join(lib_dest, "phlex_runtime.mjs");
    fs.copyFileSync(src_path, dest_path);
    console.log("  Copying: phlex_runtime.mjs");
    return console.log(`    -> ${dest_path}`)
  };

  copy_json_stream_provider() {
    let lib_dest = path.join(this._dist_dir, "lib");
    fs.mkdirSync(lib_dest, {recursive: true});
    let package_dir = this.find_package_dir;

    let src_path = path.join(
      package_dir,
      "components/JsonStreamProvider.js"
    );

    if (!fs.existsSync(src_path)) return;
    let dest_path = path.join(lib_dest, "JsonStreamProvider.js");
    fs.copyFileSync(src_path, dest_path);
    console.log("  Copying: JsonStreamProvider.js");
    return console.log(`    -> ${dest_path}`)
  };

  // Build a map of component names to their output paths
  // Used for import resolution: 'components/Button' → relative path
  //
  // Returns a hash like:
  //   { 'Button' => 'app/components/Button.js',
  //     'users/UserCard' => 'app/components/users/UserCard.js' }
  build_component_map(components_dir) {
    if (!fs.existsSync(components_dir)) return {};
    let component_map = {};

    // Scan for all component files
    for (let src_path of fs.globSync(path.join(
      components_dir,
      "**/*.{rb,jsx.rb,jsx,tsx}"
    ))) {
      // Get path relative to components_dir
      let relative = src_path.replace(components_dir + "/", "");

      // Get the component name (without extension)
      // e.g., 'Button.rb' → 'Button', 'users/UserCard.jsx' → 'users/UserCard'
      let component_name = relative.replace(/\.(jsx\.rb|rb|jsx|tsx)$/m, "");

      // Output path (relative to dist root)
      let output_path = `app/components/${component_name}.js`;

      // Map both the full path and just the basename for convenience
      // 'components/Button' and 'components/users/UserCard'
      component_map[`components/${component_name}`] = output_path;

      // Also map just the basename if unique (for simpler imports)
      let basename = path.basename(component_name);

      if (!(`components/${basename}` in component_map) || basename == component_name) {
        component_map[`components/${basename}`] = output_path
      }
    };

    return component_map
  };

  transpile_file(src_path, dest_path, section=null) {
    console.log(`Transpiling: ${path.basename(src_path)}`);
    let source = fs.readFileSync(src_path, "utf8");

    // Use relative path for cleaner display in browser debugger
    let relative_src = src_path.replace(
      SelfhostBuilder.DEMO_ROOT + "/",
      ""
    );

    let options = {...this.build_options(section), file: relative_src};

    // Add component map for import resolution if available
    if (this._component_map && Object.keys(this._component_map).length > 0) {
      options.component_map = this._component_map;
      options.file_path = relative_src // Needed to compute relative imports
    };

    let result = Ruby2JS.convert(source, options);
    let js = result.toString();
    fs.mkdirSync(path.dirname(dest_path), {recursive: true});

    if (this._sourcemap) {
      // Copy source file alongside transpiled output for source maps
      let src_basename = path.basename(src_path);

      let copied_src_path = path.join(
        path.dirname(dest_path),
        src_basename
      );

      fs.writeFileSync(copied_src_path, source);

      // Generate sourcemap - source is in same directory
      let map_path = `${dest_path}.map`;
      let sourcemap = result.sourcemap;
      sourcemap.sourcesContent = [source];
      sourcemap.sources = [`./${src_basename}`];

      // Add sourcemap reference to JS file
      let js_with_map = `${js}\n//# sourceMappingURL=${path.basename(map_path)}\n`;
      fs.writeFileSync(dest_path, js_with_map);
      fs.writeFileSync(map_path, JSON.stringify(sourcemap))
    } else {
      fs.writeFileSync(dest_path, js)
    };

    return console.log(`  -> ${dest_path}`)
  };

  // Transform JSX/TSX files using esbuild
  // Converts JSX syntax to plain JavaScript while preserving ES modules
  transform_jsx_file(src_path, dest_path) {
    console.log(`Transforming JSX: ${path.basename(src_path)}`);
    fs.mkdirSync(path.dirname(dest_path), {recursive: true});

    // Copy source file alongside output for debugging
    let src_basename = path.basename(src_path);

    let copied_src_path = path.join(
      path.dirname(dest_path),
      src_basename
    );

    fs.copyFileSync(src_path, copied_src_path);

    // Determine loader based on extension
    let loader = src_path.endsWith(".tsx") ? "tsx" : "jsx";

    // Use esbuild to transform JSX (not bundle, just transform)
    // --loader: jsx or tsx
    // --jsx: transform (converts JSX to React.createElement)
    // --format: esm (keep ES modules)
    // --sourcemap: generate source map (optional)
    let esbuild_cmd = [
      "npx",
      "esbuild",
      src_path,
      `--loader=${loader}`,
      "--jsx=transform",
      "--format=esm",
      `--outfile=${dest_path}`
    ];

    if (this._sourcemap) esbuild_cmd.push("--sourcemap");
    let $oldwd = process.cwd();

    try {
      process.chdir(this._dist_dir);

      let success = child_process.execFileSync(
        ...esbuild_cmd,
        [{[["out", "err"]]: File.NULL}],
        {stdio: "inherit"}
      );

      if (!success) {
        // If esbuild fails, try without npx (maybe esbuild is in PATH)
        esbuild_cmd[0] = "esbuild";
        esbuild_cmd.delete_at(0) // remove 'npx';

        success = child_process.execFileSync(
          "esbuild",
          [...esbuild_cmd.slice(1), {[["out", "err"]]: File.NULL}],
          {stdio: "inherit"}
        );

        if (!success) {
          console.log("  WARNING: esbuild not available, copying file as-is");
          console.log("  Install esbuild: npm install esbuild");
          fs.copyFileSync(src_path, dest_path)
        }
      }
    } finally {
      process.chdir($oldwd)
    };

    return console.log(`  -> ${dest_path}`)
  };

  transpile_erb_file(src_path, dest_path) {
    console.log(`Transpiling ERB: ${path.basename(src_path)}`);
    let template = fs.readFileSync(src_path, "utf8");

    // Compile ERB to Ruby and get position mapping
    let compiler = new ErbCompiler(template);
    let ruby_src = compiler.src;

    // Use relative path for cleaner display in browser debugger
    let relative_src = src_path.replace(
      SelfhostBuilder.DEMO_ROOT + "/",
      ""
    );

    // Pass database and target options for target-aware link generation
    // Also pass ERB source and position map for source map generation
    let erb_options = {
      ...SelfhostBuilder.ERB_OPTIONS,
      database: this._database,
      target: this._target,
      file: relative_src
    };

    let result = Ruby2JS.convert(ruby_src, erb_options);

    // Set ERB source map data on the result (which is the Serializer/Converter)
    result.erb_source = template;
    result.erb_position_map = compiler.position_map;
    let js = result.toString();

    // Note: Function may not be at start if imports were added by rails/helpers filter
    // Handle both sync and async render functions
    js = js.replace(
      /(^|\n)(async )?function render/,
      "$1export $2function render"
    );

    fs.mkdirSync(path.dirname(dest_path), {recursive: true});

    if (this._sourcemap) {
      // Copy source file alongside transpiled output for source maps
      let src_basename = path.basename(src_path);

      let copied_src_path = path.join(
        path.dirname(dest_path),
        src_basename
      );

      fs.writeFileSync(copied_src_path, template);

      // Generate source map - source is in same directory
      let map_path = `${dest_path}.map`;
      let sourcemap = result.sourcemap;
      sourcemap.sourcesContent = [template] // Use original ERB, not Ruby;
      sourcemap.sources = [`./${src_basename}`];

      // Add sourcemap reference to JS file
      let js_with_map = `${js}\n//# sourceMappingURL=${path.basename(map_path)}\n`;
      fs.writeFileSync(dest_path, js_with_map);
      fs.writeFileSync(map_path, JSON.stringify(sourcemap))
    } else {
      fs.writeFileSync(dest_path, js)
    };

    console.log(`  -> ${dest_path}`);
    return js
  };

  transpile_erb_directory() {
    let views_root = path.join(SelfhostBuilder.DEMO_ROOT, "app/views");
    if (!fs.existsSync(views_root)) return;

    // Find all resource directories (exclude layouts, pwa, and partials)
    let excluded_dirs = ["layouts", "pwa"];

    let resource_dirs = fs.readdirSync(views_root).filter((name) => {
      let dir_path = path.join(views_root, name);
      return fs.existsSync(dir_path) && fs.statSync(dir_path).isDirectory() && !excluded_dirs.includes(name) && !name.startsWith("_")
    });

    if (resource_dirs.length == 0) return;
    let views_dist_dir = path.join(this._dist_dir, "app/views");
    fs.mkdirSync(views_dist_dir, {recursive: true});

    for (let resource of resource_dirs) {
      this.transpile_unified_views(resource, views_root, views_dist_dir);

      this.transpile_turbo_stream_views(
        resource,
        views_root,
        views_dist_dir
      )
    }
  };

  // Unified view transpilation - handles all view file types in a resource directory
  // Supports: .html.erb (ERB), .rb (Phlex), .jsx.rb (JSX.rb), .jsx/.tsx (JSX)
  // Generates a combined module exporting all render functions
  transpile_unified_views(resource, views_root, views_dist_dir) {
    let resource_dir = path.join(views_root, resource);

    // Create resource subdirectory in dist
    let resource_dist_dir = path.join(views_dist_dir, resource);

    // Transpile ERB partials (files starting with _) - they're imported by views but not exported
    let partials = fs.globSync(path.join(resource_dir, "_*.html.erb"));

    if (partials.length != 0) {
      fs.mkdirSync(resource_dist_dir, {recursive: true});

      for (let partial_path of partials) {
        let partial_name = path.basename(partial_path, ".html.erb");
        let dest_path = path.join(resource_dist_dir, `${partial_name}.js`);
        this.transpile_erb_file(partial_path, dest_path)
      }
    };

    // Collect all view files with their types (non-partials)
    let view_files = this.collect_view_files(resource_dir);
    if (view_files.length == 0) return;
    fs.mkdirSync(resource_dist_dir, {recursive: true});

    // Group files by view name and resolve conflicts
    let views_by_name = this.resolve_view_conflicts(view_files);

    // Track source format for each view (for module comments)
    let source_formats = [];

    // Use .keys().each for JS compatibility - parens trigger Object.keys() conversion
    for (let view_name of Object.keys(views_by_name)) {
      let file_info = views_by_name[view_name];
      let src_path = file_info.path;
      let ext = file_info.ext;
      let dest_path = path.join(resource_dist_dir, `${view_name}.js`);

      switch (ext) {
      case ".html.erb":
        this.transpile_erb_file(src_path, dest_path);
        source_formats.push(`${view_name}: ERB`);
        break;

      case ".rb":
        this.transpile_phlex_view_file(src_path, dest_path);
        source_formats.push(`${view_name}: Phlex`);
        break;

      case ".jsx.rb":
        this.transpile_file(src_path, dest_path, "rbx");
        source_formats.push(`${view_name}: JSX.rb`);
        break;

      case ".jsx":
      case ".tsx":
        this.transform_jsx_file(src_path, dest_path);
        source_formats.push(`${view_name}: JSX`)
      }
    };

    return this.generate_unified_views_module(
      resource,
      views_by_name,
      views_dist_dir,
      source_formats
    )
  };

  // Collect all view files from a resource directory
  // Returns array of { name: 'index', ext: '.html.erb', path: '/full/path', priority: 4 }
  collect_view_files(resource_dir) {
    let view_files = [];

    // Note: Use file_path instead of path to avoid JS scoping issues with hash key
    for (let file_path of fs.globSync(path.join(
      resource_dir,
      "*.html.erb"
    ))) {
      let name = path.basename(file_path, ".html.erb");
      if (name.startsWith("_")) continue // Skip partials;

      view_files.push({
        name,
        ext: ".html.erb",
        path: file_path,
        priority: SelfhostBuilder.VIEW_FILE_PRIORITIES[".html.erb"]
      })
    };

    // Phlex files (.rb) - exclude compound extensions like .jsx.rb, .vue.rb, etc.
    for (let file_path of fs.globSync(path.join(resource_dir, "*.rb"))) {
      let name = path.basename(file_path, ".rb");
      if (name.startsWith("_")) continue // Skip partials;

      if ([".jsx", ".vue", ".svelte", ".erb"].some(_p => name.endsWith(_p))) {
        continue
      } // Skip compound extensions;

      // Convert PascalCase to snake_case for view name (Index.rb -> index)
      let view_name = name.replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2").replace(
        /([a-z\d])([A-Z])/g,
        "$1_$2"
      ).toLowerCase();

      view_files.push({
        name: view_name,
        ext: ".rb",
        path: file_path,
        priority: SelfhostBuilder.VIEW_FILE_PRIORITIES[".rb"]
      })
    };

    // JSX.rb files (Ruby + JSX)
    for (let file_path of fs.globSync(path.join(resource_dir, "*.jsx.rb"))) {
      let name = path.basename(file_path, ".jsx.rb");
      if (name.startsWith("_")) continue;

      let view_name = name.replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2").replace(
        /([a-z\d])([A-Z])/g,
        "$1_$2"
      ).toLowerCase();

      view_files.push({
        name: view_name,
        ext: ".jsx.rb",
        path: file_path,
        priority: SelfhostBuilder.VIEW_FILE_PRIORITIES[".jsx.rb"]
      })
    };

    // JSX/TSX files
    for (let file_path of fs.globSync(path.join(
      resource_dir,
      "*.{jsx,tsx}"
    ))) {
      let ext = path.extname(file_path);
      let name = path.basename(file_path, ext);
      if (name.startsWith("_")) continue;

      let view_name = name.replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2").replace(
        /([a-z\d])([A-Z])/g,
        "$1_$2"
      ).toLowerCase();

      view_files.push({
        name: view_name,
        ext,
        path: file_path,
        priority: SelfhostBuilder.VIEW_FILE_PRIORITIES[ext]
      })
    };

    return view_files
  };

  // Resolve conflicts when multiple files have the same view name
  // Higher priority (lower number) wins
  resolve_view_conflicts(view_files) {
    let views_by_name = {};

    for (let file_info of view_files) {
      let name = file_info.name;

      if (views_by_name[name]) {
        let existing = views_by_name[name];

        if (file_info.priority < existing.priority) {
          // New file has higher priority, use it
          console.log(`  Note: ${path.basename(file_info.path)} takes precedence over ${path.basename(existing.path)}`);
          views_by_name[name] = file_info
        } else {
          // Existing file has higher or equal priority, keep it
          console.log(`  Note: ${path.basename(existing.path)} takes precedence over ${path.basename(file_info.path)}`)
        }
      } else {
        views_by_name[name] = file_info
      }
    };

    return views_by_name
  };

  // Transpile a Phlex view file (for views directory, not components)
  // Uses the components section options but outputs to views
  transpile_phlex_view_file(src_path, dest_path) {
    console.log(`Transpiling Phlex view: ${path.basename(src_path)}`);
    let source = fs.readFileSync(src_path, "utf8");

    let relative_src = src_path.replace(
      SelfhostBuilder.DEMO_ROOT + "/",
      ""
    );

    let options = {
      ...this.build_options("components"),
      file: relative_src
    };

    // Add component map for import resolution if available
    if (this._component_map && Object.keys(this._component_map).length > 0) {
      options.component_map = this._component_map;
      options.file_path = relative_src
    };

    let result = Ruby2JS.convert(source, options);
    let js = result.toString();
    fs.mkdirSync(path.dirname(dest_path), {recursive: true});

    if (this._sourcemap) {
      // Copy source file alongside transpiled output for source maps
      let src_basename = path.basename(src_path);

      let copied_src_path = path.join(
        path.dirname(dest_path),
        src_basename
      );

      fs.writeFileSync(copied_src_path, source);

      // Generate sourcemap
      let map_path = `${dest_path}.map`;
      let sourcemap = result.sourcemap;
      sourcemap.sourcesContent = [source];
      sourcemap.sources = [`./${src_basename}`];
      let js_with_map = `${js}\n//# sourceMappingURL=${path.basename(map_path)}\n`;
      fs.writeFileSync(dest_path, js_with_map);
      fs.writeFileSync(map_path, JSON.stringify(sourcemap))
    } else {
      fs.writeFileSync(dest_path, js)
    };

    return console.log(`  -> ${dest_path}`)
  };

  // Generate the combined views module that exports all render functions
  generate_unified_views_module(resource, views_by_name, views_dist_dir, source_formats) {
    // Convert resource name to class-like name (messages -> Message, articles -> Article)
    let class_name = resource.chomp("s").split("_").map(item => item.capitalize).join("");
    let views_class = `${class_name}Views`;

    // Determine what file types are present - collect unique extensions via hash keys
    let ext_set = {};

    for (let v of Object.values(views_by_name)) {
      ext_set[v.ext] = true
    };

    let file_types = Object.keys(ext_set).sort();
    let unified_js = `// ${class_name} views - auto-generated from mixed source files
// Sources: ${source_formats.sort().join(", ")}
// File types: ${file_types.join(", ")}

`;
    let render_exports = [];
    let has_new = false;

    // For browser target with Vite: import from source files for HMR
    // For node/server targets: import from compiled .js files (no Vite transform)
    // @vite can override: nil = auto, true = source imports, false = compiled imports
    let use_source_imports = this._vite == null ? this._target == "browser" || this._target == "capacitor" : this._vite;

    for (let view_name of Object.keys(views_by_name).sort()) {
      let file_info = views_by_name[view_name];
      if (view_name == "new") has_new = true;
      let source_filename = path.basename(file_info.path);
      let ext = file_info.ext;

      // Determine import file based on source imports setting
      // For Vite (browser): import from source files for HMR
      // For Node/other: import from compiled .js files
      if (ext == ".html.erb") {
        let target_file = use_source_imports ? source_filename : source_filename.replace(
          ".html.erb",
          ".js"
        );

        unified_js += `import { render as ${view_name}_render } from './${resource}/${target_file}';\n`;
        render_exports.push(`${view_name}: ${view_name}_render`)
      } else if (ext == ".rb") {
        let target_file = use_source_imports ? source_filename : `${view_name}.js`;
        unified_js += `import ${view_name}_module from './${resource}/${target_file}';\n`;
        render_exports.push(`${view_name}: ${view_name}_module.render || ${view_name}_module`)
      } else if (ext == ".jsx.rb" || ext == ".jsx" || ext == ".tsx") {
        // Use view_name (snake_case) for compiled output, source_filename for Vite HMR
        let target_file = use_source_imports ? source_filename : `${view_name}.js`;
        unified_js += `import ${view_name}_component from './${resource}/${target_file}';\n`;
        render_exports.push(`${view_name}: ${view_name}_component`)
      }
    };

    // Also import and export partials (files starting with _)
    // These are used by turbo stream templates: PhotoViews._photo({...})
    let resource_dist_dir = path.join(views_dist_dir, resource);

    for (let partial_path of fs.globSync(path.join(
      resource_dist_dir,
      "_*.html.erb"
    ))) {
      let partial_filename = path.basename(partial_path) // e.g., "_photo.html.erb";
      let partial_basename = path.basename(partial_path, ".html.erb") // e.g., "_photo";

      let partial_target = use_source_imports ? partial_filename : partial_filename.replace(
        ".html.erb",
        ".js"
      );

      unified_js += `import { render as ${partial_basename}_render } from './${resource}/${partial_target}';\n`;
      render_exports.push(`${partial_basename}: ${partial_basename}_render`)
    };

    unified_js += `
// Export ${views_class} - method names match controller action names
export const ${views_class} = {
  ${render_exports.join(",\n  ")}${has_new ? ",\n  // $new alias for 'new' (JS reserved word handling)\n  $new: new_render" : ""}
};
`;

    fs.writeFileSync(
      path.join(views_dist_dir, `${resource}.js`),
      unified_js
    );

    return console.log(`  -> app/views/${resource}.js (unified views module)`)
  };

  transpile_turbo_stream_views(resource, views_root, views_dist_dir) {
    let erb_dir = path.join(views_root, resource);
    let erb_files = fs.globSync(path.join(erb_dir, "*.turbo_stream.erb"));
    if (erb_files.length == 0) return;

    // Create resource subdirectory in dist for turbo stream templates
    let resource_dist_dir = path.join(views_dist_dir, resource);
    fs.mkdirSync(resource_dist_dir, {recursive: true});

    // Transpile each turbo stream ERB file
    for (let src_path of erb_files) {
      let basename = path.basename(src_path, ".turbo_stream.erb");

      this.transpile_erb_file(
        src_path,
        path.join(resource_dist_dir, `${basename}_turbo_stream.js`)
      )
    };

    // Create combined module that exports all turbo stream functions
    // Convert resource name to class-like name (messages -> Message, articles -> Article)
    let class_name = resource.chomp("s").split("_").map(item => item.capitalize).join("");
    let turbo_class = `${class_name}TurboStreams`;
    let turbo_js = `// ${class_name} turbo stream templates - auto-generated from .turbo_stream.erb templates\n// Each exported function returns Turbo Stream HTML for partial page updates\n\n`;
    let render_exports = [];

    for (let erb_path of erb_files.sort()) {
      let name = path.basename(erb_path, ".turbo_stream.erb");

      // Import from ./#{resource}/ subdirectory
      turbo_js += `import { render as ${name}_render } from './${resource}/${name}_turbo_stream.js';\n`;
      render_exports.push(`${name}: ${name}_render`)
    };

    turbo_js += `
// Export ${turbo_class} - method names match controller action names
export const ${turbo_class} = {
  ${render_exports.join(`,\n  `)}
};
`;

    fs.writeFileSync(
      path.join(views_dist_dir, `${resource}_turbo_streams.js`),
      turbo_js
    );

    return console.log(`  -> app/views/${resource}_turbo_streams.js (turbo stream templates)`)
  };

  transpile_layout() {
    let turbo_url, stimulus_url;

    let layout_path = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "app/views/layouts/application.html.erb"
    );

    if (!fs.existsSync(layout_path)) return;
    console.log("Transpiling layout: application.html.erb");

    // Read the original layout ERB
    let template = fs.readFileSync(layout_path, "utf8");

    // Pre-process the template to replace Rails asset helpers with our JS-friendly versions
    // These helpers are stubbed in helpers.rb but we need actual content
    // Detect CSS framework for correct stylesheet link
    let css_link = "";

    let tailwind_src = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "app/assets/tailwind/application.css"
    );

    if (fs.existsSync(tailwind_src)) {
      css_link = "<link href=\"/assets/tailwind.css\" rel=\"stylesheet\">"
    };

    // Use CDN URLs for edge targets (Cloudflare, Vercel) since they don't have node_modules
    // Local server targets (Node, Bun, Deno) can serve from node_modules directly
    let edge_targets = ["cloudflare", "vercel-edge", "vercel-node"];
    let target_str = this._target ? this._target.toString() : null;
    let runtime_str = this._runtime ? this._runtime.toString() : null;

    if (edge_targets.includes(target_str) || edge_targets.includes(runtime_str)) {
      turbo_url = "https://cdn.jsdelivr.net/npm/@hotwired/turbo-rails@8/app/assets/javascripts/turbo.js";
      stimulus_url = "https://cdn.jsdelivr.net/npm/@hotwired/stimulus@3/dist/stimulus.js"
    } else {
      turbo_url = "/node_modules/@hotwired/turbo-rails/app/assets/javascripts/turbo.js";
      stimulus_url = "/node_modules/@hotwired/stimulus/dist/stimulus.js"
    };

    // Build the import map and module script to replace javascript_importmap_tags
    let importmap_replacement = `${css_link}
  <script type="importmap">
  {
    "imports": {
      "@hotwired/turbo-rails": "${turbo_url}",
      "@hotwired/stimulus": "${stimulus_url}"
    }
  }
  </script>
  <script type="module">
    import * as Turbo from '@hotwired/turbo-rails';
    import '/app/javascript/controllers/index.js';
    window.Turbo = Turbo;
  </script>
`;

    // Replace Rails asset helpers with our versions
    // stylesheet_link_tag outputs nothing (CSS is in importmap replacement)
    template = template.replace(/<%=\s*stylesheet_link_tag[^%]*%>/g, "");

    // javascript_importmap_tags gets replaced with our import map
    template = template.replace(
      /<%=\s*javascript_importmap_tags\s*%>/g,
      importmap_replacement.trim()
    );

    // Replace yield with valid Ruby expressions (yield is not valid outside methods)
    // <%= yield %> -> <%= content %> (content is passed to layout function)
    // <%= yield :head %> -> <%= context.contentFor.head || '' %>
    template = template.replace(
      /<%=\s*yield\s+:(\w+)\s*%>/g,
      _ => `<%= context.contentFor.${RegExp.$1} || '' %>`
    );

    template = template.replace(/<%=\s*yield\s*%>/g, "<%= content %>");

    // Compile ERB to Ruby
    let compiler = new ErbCompiler(template);
    let ruby_src = compiler.src;

    // Use relative path for cleaner display
    let relative_src = layout_path.replace(
      SelfhostBuilder.DEMO_ROOT + "/",
      ""
    );

    // Transpile with layout mode enabled
    let layout_options = {
      ...SelfhostBuilder.LAYOUT_OPTIONS,
      database: this._database,
      target: this._target,
      file: relative_src
    };

    let result = Ruby2JS.convert(ruby_src, layout_options);
    let js = result.toString();

    // Add export to the layout function
    js = js.replace(/^function layout/m, "export function layout");
    let dest_dir = path.join(this._dist_dir, "app/views/layouts");
    fs.mkdirSync(dest_dir, {recursive: true});
    fs.writeFileSync(path.join(dest_dir, "application.js"), js);
    return console.log("  -> app/views/layouts/application.js")
  };

  transpile_directory(src_dir, dest_dir, pattern="**/*.rb", { skip=[], section=null } = {}) {
    for (let src_path of fs.globSync(path.join(src_dir, pattern))) {
      let basename = path.basename(src_path);
      if (skip.includes(basename)) continue;
      let relative = src_path.replace(src_dir + "/", "");

      // Determine section and output path based on file extension
      let file_section = section;

      if (src_path.endsWith(".jsx") || src_path.endsWith(".tsx")) {
        // JSX/TSX files: transform with esbuild
        let dest_path = path.join(
          dest_dir,
          relative.replace(/\.[jt]sx$/m, ".js")
        );

        this.transform_jsx_file(src_path, dest_path)
      } else if (src_path.endsWith(".jsx.rb")) {
        file_section = "rbx";

        let dest_path = path.join(
          dest_dir,
          relative.replace(/\.jsx\.rb$/m, ".js")
        );

        this.transpile_file(src_path, dest_path, file_section)
      } else if (section == "astro") {
        // Astro mode: output .astro files for Phlex components
        let dest_path = path.join(
          dest_dir,
          relative.replace(/\.rb$/m, ".astro")
        );

        this.transpile_astro_file(src_path, dest_path)
      } else if (section == "vue") {
        let dest_path = path.join(
          dest_dir,
          relative.replace(/\.rb$/m, ".vue")
        );

        this.transpile_vue_file(src_path, dest_path)
      } else {
        let dest_path = path.join(
          dest_dir,
          relative.replace(/\.rb$/m, ".js")
        );

        this.transpile_file(src_path, dest_path, file_section)
      }
    }
  };

  // Transpile a Phlex component to Astro format
  transpile_astro_file(src_path, dest_path) {
    console.log(`Transpiling to Astro: ${path.basename(src_path)}`);
    let source = fs.readFileSync(src_path, "utf8");

    // Use relative path for cleaner display
    let relative_src = src_path.replace(
      SelfhostBuilder.DEMO_ROOT + "/",
      ""
    );

    let options = {...this.build_options("astro"), file: relative_src};
    let result = Ruby2JS.convert(source, options);
    let astro_content = result.toString();
    fs.mkdirSync(path.dirname(dest_path), {recursive: true});
    fs.writeFileSync(dest_path, astro_content);
    return console.log(`  -> ${dest_path}`)
  };

  // Transpile a Phlex component to Vue SFC format
  transpile_vue_file(src_path, dest_path) {
    console.log(`Transpiling to Vue: ${path.basename(src_path)}`);
    let source = fs.readFileSync(src_path, "utf8");

    // Use relative path for cleaner display
    let relative_src = src_path.replace(
      SelfhostBuilder.DEMO_ROOT + "/",
      ""
    );

    let options = {...this.build_options("vue"), file: relative_src};
    let result = Ruby2JS.convert(source, options);
    let vue_content = result.toString();
    fs.mkdirSync(path.dirname(dest_path), {recursive: true});
    fs.writeFileSync(dest_path, vue_content);
    return console.log(`  -> ${dest_path}`)
  };

  // Process Stimulus controllers:
  // - Copy .js files directly (no transpilation needed)
  // - Transpile .rb files with stimulus filter
  // - Generate index.js that registers all controllers with Stimulus
  process_stimulus_controllers(src_dir, dest_dir) {
    fs.mkdirSync(dest_dir, {recursive: true});
    let controllers = [];

    for (let src_path of fs.globSync(path.join(
      src_dir,
      "**/*_controller.{js,rb}"
    ))) {
      let basename = path.basename(src_path);
      let relative = src_path.replace(src_dir + "/", "");

      // Skip index files and application_controller
      if (basename == "index.js" || basename == "application_controller.js") {
        continue
      };

      if (src_path.endsWith(".js")) {
        // Copy .js files directly
        let dest_path = path.join(dest_dir, relative);
        fs.mkdirSync(path.dirname(dest_path), {recursive: true});
        fs.copyFileSync(src_path, dest_path);
        console.log(`  ${relative} (copied)`);
        controllers.push(relative)
      } else if (src_path.endsWith(".rb")) {
        // Transpile .rb files
        let dest_relative = relative.replace(/\.rb$/m, ".js");
        let dest_path = path.join(dest_dir, dest_relative);
        this.transpile_file(src_path, dest_path, "stimulus");
        controllers.push(dest_relative)
      }
    };

    if (controllers.length > 0) {
      return this.generate_stimulus_index(
        dest_dir,
        [...new Set(controllers)]
      )
    }
  };

  // Generate controllers/index.js that imports and registers all Stimulus controllers
  generate_stimulus_index(dest_dir, controller_files) {
    let imports = [];
    let registrations = [];

    for (let file of controller_files.sort()) {
      // Extract controller name from filename
      // hello_controller.js -> HelloController, "hello"
      // live_scores_controller.js -> LiveScoresController, "live-scores"
      let basename = path.basename(file, ".js");
      let name_part = basename.replace(/_controller$/m, "");

      // Convert to class name (hello_world -> HelloWorld)
      let class_name = name_part.split("_").map(item => item.capitalize).join("") + "Controller";

      // Convert to Stimulus identifier (hello_world -> hello-world)
      let identifier = name_part.replace(/_/g, "-");
      imports.push(`import ${class_name} from "./${file}";`);
      registrations.push(`application.register("${identifier}", ${class_name});`)
    };

    let index_content = `import { Application } from "@hotwired/stimulus";

${imports.join(`\n`)}

const application = Application.start();

${registrations.join(`\n`)}

export { application };
`;
    fs.writeFileSync(path.join(dest_dir, "index.js"), index_content);
    return console.log(`  -> index.js (${controller_files.length} controllers)`)
  };

  // Handle seeds.rb specially - if it has only comments/whitespace, generate a stub
  // This is shared logic with SPA builder (lib/ruby2js/spa/builder.rb)
  transpile_seeds(src_dir, dest_dir) {
    let seeds_src = path.join(src_dir, "seeds.rb");
    let seeds_dest = path.join(dest_dir, "seeds.js");

    // Check if seeds.rb has actual Ruby code (not just comments/whitespace)
    // Use split("\n") instead of .lines for JS compatibility (strings don't have .lines in JS)
    let has_code = fs.existsSync(seeds_src) && fs.readFileSync(
      seeds_src,
      "utf8"
    ).split("\n").some(line => !/^(#.*|\s*)$/.test(line.trim()));

    if (has_code) {
      // Transpile existing seeds file normally
      this.transpile_file(seeds_src, seeds_dest);

      if (this._database == "d1") {
        return this.generate_seeds_sql(seeds_src, dest_dir)
      }
    } else {
      fs.mkdirSync(dest_dir, {recursive: true});

      fs.writeFileSync(
        seeds_dest,
        `// Seeds stub - original seeds.rb had no executable code
export const Seeds = {
  run() {
    // Add your seed data here
  }
};
`
      );

      return console.log("  -> db/seeds.js (stub)")
    }
  };

  // Generate SQL seeds file for D1/wrangler
  generate_seeds_sql(seeds_src, db_dest) {
    let sql_path;
    let result = Ruby2JS.Rails.SeedSQL.generate(seeds_src);

    if (result.sql && result.sql.length != 0) {
      fs.mkdirSync(db_dest, {recursive: true});
      sql_path = path.join(db_dest, "seeds.sql");
      fs.writeFileSync(sql_path, result.sql);
      return console.log(`  -> db/seeds.sql (${result.inserts} inserts)`)
    }
  };

  // Transpile database migrations to JavaScript
  // Each migration becomes a module with an async up() function
  // Also generates an index file that exports all migrations with their versions
  transpile_migrations(src_dir, dest_dir) {
    let migrate_src = path.join(src_dir, "migrate");
    let migrate_dest = path.join(dest_dir, "migrate");
    if (!fs.existsSync(migrate_src)) return;
    let migrations = [];

    for (let src_path of fs.globSync(path.join(migrate_src, "*.rb")).sort()) {
      let basename = path.basename(src_path, ".rb");
      let dest_path = path.join(migrate_dest, `${basename}.js`);

      // Extract version from filename (e.g., 20241231120000_create_articles.rb)
      let version = basename.split("_")[0];
      this.transpile_migration_file(src_path, dest_path);
      migrations.push({version, filename: basename})
    };

    // Generate migrations index file
    if (migrations.length > 0) {
      this.generate_migrations_index(migrate_dest, migrations)
    };

    if (this._database == "d1") {
      return this.generate_migrations_sql(migrate_src, dest_dir)
    }
  };

  // Generate SQL migrations file for D1/wrangler
  generate_migrations_sql(migrate_src, db_dest) {
    let sql_path;
    let result = Ruby2JS.Rails.MigrationSQL.generate_all(migrate_src);

    if (result.sql && result.sql.length != 0) {
      fs.mkdirSync(db_dest, {recursive: true});
      sql_path = path.join(db_dest, "migrations.sql");
      fs.writeFileSync(sql_path, result.sql);
      return console.log(`  -> db/migrations.sql (${result.migrations.length} migrations)`)
    }
  };

  transpile_migration_file(src_path, dest_path) {
    console.log(`Transpiling migration: ${path.basename(src_path)}`);
    let source = fs.readFileSync(src_path, "utf8");

    let relative_src = src_path.replace(
      SelfhostBuilder.DEMO_ROOT + "/",
      ""
    );

    let options = {
      ...SelfhostBuilder.MIGRATION_OPTIONS,
      file: relative_src
    };

    let result = Ruby2JS.convert(source, options);
    let js = result.toString();
    fs.mkdirSync(path.dirname(dest_path), {recursive: true});

    if (this._sourcemap) {
      // Copy source file alongside transpiled output for source maps
      let src_basename = path.basename(src_path);

      let copied_src_path = path.join(
        path.dirname(dest_path),
        src_basename
      );

      fs.writeFileSync(copied_src_path, source);

      // Generate sourcemap
      let map_path = `${dest_path}.map`;
      let sourcemap = result.sourcemap;
      sourcemap.sourcesContent = [source];
      sourcemap.sources = [`./${src_basename}`];

      // Add sourcemap reference to JS file
      let js_with_map = `${js}\n//# sourceMappingURL=${path.basename(map_path)}\n`;
      fs.writeFileSync(dest_path, js_with_map);
      fs.writeFileSync(map_path, JSON.stringify(sourcemap))
    } else {
      fs.writeFileSync(dest_path, js)
    };

    return console.log(`  -> ${dest_path}`)
  };

  generate_migrations_index(migrate_dest, migrations) {
    let index_js = `// Database migrations index - auto-generated\n// Each migration exports { migration: { up: async () => {...} } }\n\n`;

    // Import each migration
    for (let m of migrations) {
      index_js += `import { migration as m${m.version} } from './${m.filename}.js';\n`
    };

    index_js += `\n// All migrations in order\nexport const migrations = [\n`;

    for (let m of migrations) {
      index_js += `  { version: '${m.version}', ...m${m.version} },\n`
    };

    index_js += `];\n`;
    fs.writeFileSync(path.join(migrate_dest, "index.js"), index_js);
    return console.log(`  -> db/migrate/index.js (${migrations.length} migrations)`)
  };

  generate_application_record() {
    let wrapper = `// ApplicationRecord - wraps ActiveRecord from adapter
// This file is generated by the build script
import { ActiveRecord, CollectionProxy } from '../../lib/active_record.mjs';

export { CollectionProxy };

export class ApplicationRecord extends ActiveRecord {
  // Subclasses (Article, Comment) extend this and add their own validations
}
`;
    let dest_dir = path.join(this._dist_dir, "app/models");
    fs.mkdirSync(dest_dir, {recursive: true});

    fs.writeFileSync(
      path.join(dest_dir, "application_record.js"),
      wrapper
    );

    return console.log("  -> app/models/application_record.js (wrapper for ActiveRecord)")
  };

  generate_browser_index() {
    let content;

    // Detect app name from config/application.rb
    let app_name = "Ruby2JS App";

    let app_config = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "config/application.rb"
    );

    if (fs.existsSync(app_config)) {
      content = fs.readFileSync(app_config, "utf8");
      if (/module\s+(\w+)/.test(content)) app_name = RegExp.$1
    };

    // Detect CSS framework from Gemfile or package.json
    let css = "none";
    let gemfile = path.join(SelfhostBuilder.DEMO_ROOT, "Gemfile");

    if (fs.existsSync(gemfile)) {
      content = fs.readFileSync(gemfile, "utf8");

      if (content.includes("tailwindcss")) {
        css = "tailwind"
      } else if (content.includes("bootstrap")) {
        css = "bootstrap"
      }
    };

    // Write index.html to dist/ - self-contained, served from dist root
    let output_path = path.join(this._dist_dir, "index.html");
    let user_deps = this.load_ruby2js_config("dependencies") ?? {};
    let user_stylesheets = this.load_ruby2js_config("stylesheets");
    if (!Array.isArray(user_stylesheets)) user_stylesheets = [];

    SelfhostBuilder.generate_index_html({
      app_name,
      database: this._database,
      target: this._target,
      css,
      output_path,
      base_path: "",
      dependencies: user_deps,
      stylesheets: user_stylesheets,
      dist_dir: this._dist_dir,
      bundled: true
    });

    console.log("  -> dist/index.html");
    console.log("  -> dist/main.js");
    fs.copyFileSync(output_path, path.join(this._dist_dir, "404.html"));
    return console.log("  -> dist/404.html")
  };

  generate_vercel_config() {
    // Determine runtime type for Vercel
    let runtime_type = this._runtime == "vercel-edge" ? "edge" : "nodejs";

    let config = {
      version: 2,
      buildCommand: "npm run build",
      outputDirectory: "dist",

      routes: [
        {src: "/assets/(.*)", dest: "/public/assets/$1"},
        {src: "/(.*)", dest: "/api/[[...path]]"}
      ]
    };

    // Add runtime configuration for edge functions
    if (this._runtime == "vercel-edge") {
      config.functions = {"api/[[...path]].js": {runtime: "edge"}}
    };

    let config_path = path.join(this._dist_dir, "vercel.json");
    fs.writeFileSync(config_path, JSON.stringify(config, null, 2));
    return console.log("  -> vercel.json")
  };

  generate_vercel_entry_point() {
    // Determine runtime type for export config
    let runtime_type = this._runtime == "vercel-edge" ? "edge" : "nodejs";

    // Detect app name from config/application.rb
    let app_name = "Ruby2JS App";

    let app_config = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "config/application.rb"
    );

    if (fs.existsSync(app_config)) {
      let content = fs.readFileSync(app_config, "utf8");
      if (/module\s+(\w+)/.test(content)) app_name = RegExp.$1
    };

    let entry = `// Vercel catch-all route handler
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
  runtime: '${runtime_type}'
};
`;

    // Create api directory and write entry point
    let api_dir = path.join(this._dist_dir, "api");
    fs.mkdirSync(api_dir, {recursive: true});
    fs.writeFileSync(path.join(api_dir, "[[...path]].js"), entry);
    return console.log("  -> api/[[...path]].js")
  };

  generate_deno_deploy_entry_point() {
    let entry = `// Deno Deploy entry point
// Generated by Ruby2JS on Rails

import { Application, Router } from './lib/rails.js';
import './config/routes.js';
import { migrations } from './db/migrate/index.js';
import { Seeds } from './db/seeds.js';
import { layout } from './app/views/layouts/application.js';

// Configure application
Application.configure({
  migrations: migrations,
  seeds: Seeds,
  layout: layout
});

// Start Deno server
Deno.serve(Application.handler());
`;
    fs.writeFileSync(path.join(this._dist_dir, "main.ts"), entry);
    return console.log("  -> main.ts")
  };

  generate_fly_config() {
    let app_name = path.basename(SelfhostBuilder.DEMO_ROOT).toLowerCase().replace(
      /[^a-z0-9-]/g,
      "-"
    );

    // Generate fly.toml
    let fly_toml = `app = '${app_name}'
primary_region = 'ord'

[build]

[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = 'stop'
  auto_start_machines = true
  min_machines_running = 0
  processes = ['app']

[[vm]]
  memory = '1gb'
  cpu_kind = 'shared'
  cpus = 1
`;
    fs.writeFileSync(path.join(this._dist_dir, "fly.toml"), fly_toml);
    console.log("  -> fly.toml");

    // Generate Dockerfile for Node.js
    let dockerfile = `# syntax = docker/dockerfile:1

# Adjust NODE_VERSION as desired
ARG NODE_VERSION=22
FROM node:$\{NODE_VERSION}-slim AS base

LABEL fly_launch_runtime="Node.js"

# Node.js app lives here
WORKDIR /app

# Set production environment
ENV NODE_ENV="production"

# Install packages needed to build node modules
RUN apt-get update -qq && \\
    apt-get install --no-install-recommends -y build-essential pkg-config python-is-python3

# Install node modules
COPY package*.json ./
RUN npm ci --include=dev

# Copy application code
COPY . .

# Start the server
EXPOSE 3000
CMD [ "npm", "run", "start:node" ]
`;
    fs.writeFileSync(path.join(this._dist_dir, "Dockerfile"), dockerfile);
    console.log("  -> Dockerfile");

    // Generate .dockerignore
    let dockerignore = `node_modules\n.git\n.env\n.env.local\n*.log\n`;

    fs.writeFileSync(
      path.join(this._dist_dir, ".dockerignore"),
      dockerignore
    );

    return console.log("  -> .dockerignore")
  };

  uses_turbo_broadcasting() {
    // Check if app uses Turbo Streams broadcasting (broadcast_*_to in models or turbo_stream_from in views)
    let models_dir = path.join(SelfhostBuilder.DEMO_ROOT, "app/models");
    let views_dir = path.join(SelfhostBuilder.DEMO_ROOT, "app/views");

    // Check models for broadcast_*_to calls
    if (fs.existsSync(models_dir)) {
      for (let file of fs.globSync(path.join(models_dir, "**/*.rb"))) {
        if (/broadcast_\w+_to/.test(fs.readFileSync(file, "utf8"))) return true
      }
    };

    // Check views for turbo_stream_from helper
    if (fs.existsSync(views_dir)) {
      for (let file of fs.globSync(path.join(views_dir, "**/*.erb"))) {
        if (/turbo_stream_from/.test(fs.readFileSync(file, "utf8"))) return true
      }
    };

    return false
  };

  generate_cloudflare_config() {
    // Generate wrangler.toml for Cloudflare Workers deployment
    let app_name = path.basename(SelfhostBuilder.DEMO_ROOT).toLowerCase().replace(
      /[^a-z0-9-]/g,
      "-"
    );

    let rails_env = process.env.RAILS_ENV ?? "production";

    let db_name = `${app_name}_${rails_env}`.toLowerCase().replace(
      /[^a-z0-9_]/g,
      "_"
    );

    let wrangler_toml = `name = "${app_name}"
main = "src/index.js"
compatibility_date = "${Date.today}"
compatibility_flags = ["nodejs_compat"]

# D1 database binding
[[d1_databases]]
binding = "DB"
database_name = "${db_name}"
database_id = "$\{D1_DATABASE_ID}"

# Static assets (Rails convention: public/)
[assets]
directory = "./public"
`;

    // Add Durable Objects only if app uses Turbo Streams broadcasting
    if (this.uses_turbo_broadcasting.bind(this)) {
      wrangler_toml += `
# Durable Objects for Turbo Streams broadcasting
[[durable_objects.bindings]]
name = "TURBO_BROADCASTER"
class_name = "TurboBroadcaster"

[[migrations]]
tag = "v1"
new_sqlite_classes = ["TurboBroadcaster"]
`
    };

    let config_path = path.join(this._dist_dir, "wrangler.toml");
    fs.writeFileSync(config_path, wrangler_toml);
    return console.log("  -> wrangler.toml")
  };

  generate_cloudflare_entry_point() {
    // Generate Cloudflare Worker entry point
    let uses_broadcasting = this.uses_turbo_broadcasting.bind(this);
    let imports = uses_broadcasting ? "import { Application, Router, TurboBroadcaster } from '../lib/rails.js';" : "import { Application, Router } from '../lib/rails.js';";
    let exports = uses_broadcasting ? `// Export Worker handler and Durable Object\nexport default Application.worker();\nexport { TurboBroadcaster };` : `// Export Worker handler\nexport default Application.worker();`;
    let entry = `// Cloudflare Worker entry point
// Generated by Ruby2JS on Rails

${imports}
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

${exports}
`;

    // Create src directory and write entry point
    let src_dir = path.join(this._dist_dir, "src");
    fs.mkdirSync(src_dir, {recursive: true});
    fs.writeFileSync(path.join(src_dir, "index.js"), entry);
    return console.log("  -> src/index.js")
  };

  generate_capacitor_config() {
    // Generate capacitor.config.ts for Capacitor mobile deployment
    let app_name = path.basename(SelfhostBuilder.DEMO_ROOT);

    let app_id = `com.example.${app_name.toLowerCase().replace(
      /[^a-z0-9]/g,
      ""
    )}`;

    let config = `import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: '${app_id}',
  appName: '${app_name}',
  webDir: 'dist',
  server: {
    // For development, use live reload from dev server
    // url: 'http://localhost:3000',
    // cleartext: true
  },
  plugins: {
    Camera: {
      // iOS camera permissions
      presentationStyle: 'fullScreen'
    }
  }
};

export default config;
`;

    let config_path = path.join(
      this._dist_dir,
      "..",
      "capacitor.config.ts"
    );

    fs.writeFileSync(config_path, config);
    console.log("  -> capacitor.config.ts");

    // Generate package.json scripts for Capacitor
    console.log("  Add to package.json scripts:");
    console.log("    \"cap:init\": \"npx cap init\"");
    console.log("    \"cap:add:ios\": \"npx cap add ios\"");
    console.log("    \"cap:add:android\": \"npx cap add android\"");
    console.log("    \"cap:sync\": \"npx cap sync\"");
    console.log("    \"cap:open:ios\": \"npx cap open ios\"");
    return console.log("    \"cap:open:android\": \"npx cap open android\"")
  };

  generate_electron_main() {
    // Generate Electron main process (main.js)
    let app_name = path.basename(SelfhostBuilder.DEMO_ROOT);
    let main_js = `// Electron Main Process
// Generated by Ruby2JS on Rails

const { app, BrowserWindow, Tray, Menu, globalShortcut, ipcMain, nativeImage } = require('electron');
const path = require('path');

let mainWindow = null;
let tray = null;

// Hide dock icon on macOS (menu bar app style)
if (process.platform === 'darwin') {
  app.dock.hide();
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 400,
    height: 500,
    show: false,
    frame: false,
    resizable: false,
    skipTaskbar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  // Load the app
  mainWindow.loadFile(path.join(__dirname, 'dist', 'index.html'));

  // Hide instead of close
  mainWindow.on('close', (event) => {
    if (!app.isQuitting) {
      event.preventDefault();
      mainWindow.hide();
    }
  });

  mainWindow.on('blur', () => {
    mainWindow.hide();
  });
}

function createTray() {
  const iconPath = path.join(__dirname, 'assets', 'tray-icon.png');
  const icon = nativeImage.createFromPath(iconPath);
  tray = new Tray(icon.resize({ width: 16, height: 16 }));

  const contextMenu = Menu.buildFromTemplate([
    { label: 'Take Photo', click: () => showAndCapture() },
    { label: 'Open Gallery', click: () => showWindow() },
    { type: 'separator' },
    { label: 'Quit', click: () => {
      app.isQuitting = true;
      app.quit();
    }}
  ]);

  tray.setToolTip('${app_name}');
  tray.setContextMenu(contextMenu);

  tray.on('click', () => {
    toggleWindow();
  });
}

function toggleWindow() {
  if (mainWindow.isVisible()) {
    mainWindow.hide();
  } else {
    showWindow();
  }
}

function showWindow() {
  const trayBounds = tray.getBounds();
  const windowBounds = mainWindow.getBounds();

  // Position window below tray icon
  const x = Math.round(trayBounds.x + (trayBounds.width / 2) - (windowBounds.width / 2));
  const y = Math.round(trayBounds.y + trayBounds.height + 4);

  mainWindow.setPosition(x, y, false);
  mainWindow.show();
  mainWindow.focus();
}

function showAndCapture() {
  showWindow();
  // Send quick-capture event to renderer
  mainWindow.webContents.send('quick-capture');
}

app.whenReady().then(() => {
  createWindow();
  createTray();

  // Register global shortcut (Cmd+Shift+P on Mac, Ctrl+Shift+P on Windows/Linux)
  const shortcut = process.platform === 'darwin' ? 'CommandOrControl+Shift+P' : 'Ctrl+Shift+P';
  globalShortcut.register(shortcut, () => {
    showAndCapture();
  });
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

// IPC handlers
ipcMain.on('hide-window', () => {
  mainWindow.hide();
});
`;
    let main_path = path.join(this._dist_dir, "..", "main.js");
    fs.writeFileSync(main_path, main_js);
    return console.log("  -> main.js")
  };

  generate_electron_preload() {
    // Generate Electron preload script (preload.js)
    let preload_js = `// Electron Preload Script
// Exposes safe IPC methods to renderer via contextBridge

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  // Send message to main process
  send: (channel, ...args) => {
    const validChannels = ['hide-window', 'photo-saved'];
    if (validChannels.includes(channel)) {
      ipcRenderer.send(channel, ...args);
    }
  },

  // Invoke main process and get response
  invoke: (channel, ...args) => {
    const validChannels = ['get-photos', 'save-photo'];
    if (validChannels.includes(channel)) {
      return ipcRenderer.invoke(channel, ...args);
    }
  },

  // Listen for quick-capture event from main
  onQuickCapture: (callback) => {
    ipcRenderer.on('quick-capture', () => callback());
  },

  // Listen for window show event
  onWindowShow: (callback) => {
    ipcRenderer.on('window-show', () => callback());
  },

  // Listen for window hide event
  onWindowHide: (callback) => {
    ipcRenderer.on('window-hide', () => callback());
  }
});
`;
    let preload_path = path.join(this._dist_dir, "..", "preload.js");
    fs.writeFileSync(preload_path, preload_js);
    console.log("  -> preload.js");

    // Create assets directory for tray icon
    let assets_dir = path.join(this._dist_dir, "..", "assets");
    fs.mkdirSync(assets_dir, {recursive: true});
    return console.log("  -> assets/ (add tray-icon.png)")
  };

  generate_tauri_config() {
    // Generate Tauri configuration (src-tauri/tauri.conf.json)
    let app_name = path.basename(SelfhostBuilder.DEMO_ROOT);

    let identifier = `com.example.${app_name.toLowerCase().replace(
      /[^a-z0-9]/g,
      ""
    )}`;

    let tauri_config = {
      productName: app_name,
      version: "0.1.0",
      identifier: identifier,
      build: {frontendDist: "../dist", devUrl: "http://localhost:5173"},

      app: {
        windows: [{
          title: app_name.split(/[-_]/).map(item => item.capitalize).join(" "),
          width: 1200,
          height: 800,
          resizable: true
        }],

        security: {csp: null}
      },

      bundle: {active: true, icon: [
        "icons/32x32.png",
        "icons/128x128.png",
        "icons/icon.icns",
        "icons/icon.ico"
      ]}
    };

    // Create src-tauri directory
    let tauri_dir = path.join(this._dist_dir, "..", "src-tauri");
    fs.mkdirSync(tauri_dir, {recursive: true});

    // Write tauri.conf.json
    let config_path = path.join(tauri_dir, "tauri.conf.json");
    fs.writeFileSync(config_path, JSON.stringify(tauri_config, null, 2));
    console.log("  -> src-tauri/tauri.conf.json");

    // Create icons directory
    let icons_dir = path.join(tauri_dir, "icons");
    fs.mkdirSync(icons_dir, {recursive: true});
    console.log("  -> src-tauri/icons/ (add app icons)");

    // Write README with setup instructions
    let readme = `# Tauri Setup

This directory contains the Tauri configuration for your app.
The \`tauri.conf.json\` file has been generated with your app settings.

## Prerequisites

Install Rust and Tauri CLI:

\`\`\`bash
# Install Rust (if not already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install Tauri CLI
cargo install tauri-cli
\`\`\`

Platform-specific requirements:
- **macOS:** Xcode Command Line Tools (\`xcode-select --install\`)
- **Windows:** Visual Studio Build Tools with C++ workload
- **Linux:** \`sudo apt install libwebkit2gtk-4.1-dev build-essential curl wget file libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev\`

## Initialize Rust Project

Run from the parent directory (not src-tauri):

\`\`\`bash
cargo tauri init
\`\`\`

This will create the Rust source files (\`src/main.rs\`, \`Cargo.toml\`, etc.)
while preserving your existing \`tauri.conf.json\`.

## Development

\`\`\`bash
cargo tauri dev
\`\`\`

## Build for Distribution

\`\`\`bash
cargo tauri build
\`\`\`

## Adding App Icons

Place your app icons in the \`icons/\` directory:
- \`32x32.png\` - Small icon
- \`128x128.png\` - Medium icon
- \`icon.icns\` - macOS icon
- \`icon.ico\` - Windows icon

You can generate these from a single source image using:
\`\`\`bash
cargo tauri icon path/to/app-icon.png
\`\`\`

## Documentation

- [Tauri v2 Documentation](https://v2.tauri.app/)
- [Configuration Reference](https://v2.tauri.app/reference/config/)
`;
    let readme_path = path.join(tauri_dir, "README.md");
    fs.writeFileSync(readme_path, readme);
    return console.log("  -> src-tauri/README.md")
  };

  setup_tailwind() {
    let npm_css, $oldwd;

    // Check for tailwindcss-rails gem source file
    let tailwind_src = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "app/assets/tailwind/application.css"
    );

    if (!fs.existsSync(tailwind_src)) return;
    console.log("Tailwind CSS:");

    // Create source directory (for Tailwind input)
    let tailwind_dest_dir = path.join(
      this._dist_dir,
      "app/assets/tailwind"
    );

    fs.mkdirSync(tailwind_dest_dir, {recursive: true});

    // Read the tailwindcss-rails source
    let source = fs.readFileSync(tailwind_src, "utf8");

    // Tailwind v4 uses CSS-first configuration with @import "tailwindcss"
    // Add @source directive to specify content paths for class scanning
    if (source.includes("@import \"tailwindcss\"") || source.includes("@import 'tailwindcss'")) {
      // Tailwind v4: keep @import as-is, add @source for content scanning
      npm_css = `@import "tailwindcss";\n@source "./app/**/*.{js,html,erb}";\n@source "./index.html";\n`
    } else {
      // Legacy format: use as-is
      npm_css = source
    };

    // Write the CSS to dist (source for Tailwind build)
    let dest_path = path.join(tailwind_dest_dir, "application.css");
    fs.writeFileSync(dest_path, npm_css);
    console.log("  -> app/assets/tailwind/application.css");

    // Tailwind v4 uses CSS-first config, no JS config needed
    // Remove old config if present to avoid conflicts
    let config_path = path.join(this._dist_dir, "tailwind.config.js");

    if (fs.existsSync(config_path)) {
      fs.unlinkSync(config_path);
      console.log("  -> removed tailwind.config.js (v4 uses CSS config)")
    };

    // Create output directory for built CSS (Rails convention: public/assets/)
    let assets_dir = path.join(this._dist_dir, "public/assets");
    fs.mkdirSync(assets_dir, {recursive: true});

    // Run Tailwind CSS build (only if tailwindcss is installed)
    let tailwind_bin = path.join(
      this._dist_dir,
      "node_modules/.bin/tailwindcss"
    );

    if (fs.existsSync(tailwind_bin)) {
      console.log("  Building CSS...");
      $oldwd = process.cwd();

      try {
        process.chdir(this._dist_dir);

        child_process.execFileSync(
          "npx",

          [
            "tailwindcss",
            "-i",
            "app/assets/tailwind/application.css",
            "-o",
            "public/assets/tailwind.css",
            "--minify"
          ],

          {stdio: "inherit"}
        )
      } finally {
        process.chdir($oldwd)
      };

      return console.log("  -> public/assets/tailwind.css")
    } else {
      return console.log("  (Run 'npm install' in dist/, then 'npx tailwindcss -i app/assets/tailwind/application.css -o public/assets/tailwind.css')")
    }
  };

  transpile_routes_files() {
    let map_path, sourcemap;

    let src_path = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "config/routes.rb"
    );

    let dest_dir = path.join(this._dist_dir, "config");
    let source = fs.readFileSync(src_path, "utf8");

    let relative_src = src_path.replace(
      SelfhostBuilder.DEMO_ROOT + "/",
      ""
    );

    let base_options = this.build_options();

    // Generate paths.js first (with only path helpers)
    console.log("Transpiling: routes.rb -> paths.js");

    let paths_options = {
      ...base_options,
      file: relative_src,
      paths_only: true,
      base: this._base
    };

    let result = Ruby2JS.convert(source, paths_options);
    let paths_js = result.toString();
    let paths_path = path.join(dest_dir, "paths.js");
    fs.mkdirSync(dest_dir, {recursive: true});
    fs.writeFileSync(paths_path, paths_js);
    console.log(`  -> ${paths_path}`);

    if (this._sourcemap) {
      // Generate sourcemap for paths.js
      map_path = `${paths_path}.map`;
      sourcemap = result.sourcemap;
      sourcemap.sourcesContent = [source];
      fs.writeFileSync(map_path, JSON.stringify(sourcemap));
      console.log(`  -> ${map_path}`)
    };

    // Generate routes.js (imports path helpers from paths.js)
    console.log("Transpiling: routes.rb -> routes.js");

    let routes_options = {
      ...base_options,
      file: relative_src,
      paths_file: "./paths.js",
      database: this._database,
      target: this._target,
      base: this._base
    };

    result = Ruby2JS.convert(source, routes_options);
    let routes_js = result.toString();
    let routes_path = path.join(dest_dir, "routes.js");
    fs.writeFileSync(routes_path, routes_js);
    console.log(`  -> ${routes_path}`);

    if (this._sourcemap) {
      // Generate sourcemap for routes.js
      map_path = `${routes_path}.map`;
      sourcemap = result.sourcemap;
      sourcemap.sourcesContent = [source];
      fs.writeFileSync(map_path, JSON.stringify(sourcemap));
      return console.log(`  -> ${map_path}`)
    }
  };

  generate_models_index() {
    let models_dir = path.join(this._dist_dir, "app/models");

    let model_files = fs.globSync(path.join(models_dir, "*.js")).map(f => (
      path.basename(f, ".js")
    )).filter(name => !(name == "application_record" || name == "index")).sort();

    if (model_files.length <= 0) return;

    // Build imports, exports, and model registry
    let imports = [];
    let exports = [];
    let class_names = [];

    for (let name of model_files) {
      // Use explicit capitalization for JS compatibility
      let class_name = name.split("_").map(s => s[0].toUpperCase() + s.slice(1)).join("");
      imports.push(`import { ${class_name} } from './${name}.js';`);
      exports.push(`export { ${class_name} };`);
      class_names.push(class_name)
    };

    // Generate index.js with imports, exports, and model registration
    let index_js = `${imports.join(`\n`)}
import { Application } from '../../lib/rails.js';

// Register models for association resolution (avoids circular dependency issues)
Application.registerModels({ ${class_names.join(", ")} });

${exports.join(`\n`)}
`;
    fs.writeFileSync(path.join(models_dir, "index.js"), index_js);
    return console.log("  -> app/models/index.js (re-exports)")
  };

  // Parse model files to extract has_many associations for controller preloading
  // This allows show/edit actions to await associations before rendering views
  parse_model_associations() {
    let models_dir = path.join(SelfhostBuilder.DEMO_ROOT, "app/models");
    if (!fs.existsSync(models_dir)) return;

    for (let model_path of fs.globSync(path.join(models_dir, "*.rb"))) {
      let basename = path.basename(model_path, ".rb");
      if (basename == "application_record") continue;
      let source = fs.readFileSync(model_path, "utf8");
      let associations = [];

      for (let $_ of source.matchAll(/has_many\s+:(\w+)/g)) {
        let match = $_.slice(1);
        associations.push(match[0])
      };

      if (associations.length > 0) {
        // Store associations keyed by singular model name (article -> [:comments])
        this._model_associations[basename] = associations
      }
    }
  }
};

// JS (Node.js): use process.cwd() since bin commands run from app root
// Ruby: use current working directory (assumes run from app root)
SelfhostBuilder.DEMO_ROOT = typeof process !== 'undefined' ? process.cwd() : process.cwd();

// Server-side JavaScript runtimes
SelfhostBuilder.SERVER_RUNTIMES = Object.freeze([
  "node",
  "bun",
  "deno",
  "cloudflare",
  "vercel-edge",
  "vercel-node",
  "deno-deploy",
  "fly"
]);

// Desktop/mobile targets (hybrid browser/node)
SelfhostBuilder.CAPACITOR_RUNTIMES = Object.freeze(["capacitor"]);
SelfhostBuilder.ELECTRON_RUNTIMES = Object.freeze(["electron"]);

// Vercel deployment targets
SelfhostBuilder.VERCEL_RUNTIMES = Object.freeze([
  "vercel-edge",
  "vercel-node"
]);

// Deno Deploy target
SelfhostBuilder.DENO_DEPLOY_RUNTIMES = Object.freeze(["deno-deploy"]);

// Fly.io target
SelfhostBuilder.FLY_RUNTIMES = Object.freeze(["fly"]);

// Tauri target (Rust backend, system webview)
SelfhostBuilder.TAURI_RUNTIMES = Object.freeze(["tauri"]);

// Databases that require a specific runtime
SelfhostBuilder.RUNTIME_REQUIRED = Object.freeze({
  d1: "cloudflare",
  mpg: "fly"
});

// Valid target environments for each database adapter
SelfhostBuilder.VALID_TARGETS = Object.freeze({
  // Browser-only databases (also work in Capacitor which uses WebView)
  dexie: ["browser", "capacitor"],
  indexeddb: ["browser", "capacitor"],
  sqljs: ["browser", "capacitor", "electron", "tauri"],
  "sql.js": ["browser", "capacitor", "electron", "tauri"],
  pglite: ["browser", "node", "capacitor", "electron", "tauri"],

  // Node.js databases (also work in Electron main process)
  better_sqlite3: ["node", "bun", "electron"],
  sqlite3: ["node", "bun", "electron"],
  pg: ["node", "bun", "deno", "electron"],
  postgres: ["node", "bun", "deno", "electron"],
  postgresql: ["node", "bun", "deno", "electron"],
  mysql2: ["node", "bun", "electron"],
  mysql: ["node", "bun", "electron"],

  // Platform-specific databases
  d1: ["cloudflare"],
  mpg: ["fly"],

  // HTTP-based databases (work everywhere including Capacitor/Electron/Tauri)
  neon: [
    "browser",
    "node",
    "bun",
    "deno",
    "cloudflare",
    "vercel-edge",
    "vercel-node",
    "deno-deploy",
    "capacitor",
    "electron",
    "tauri"
  ],

  turso: [
    "browser",
    "node",
    "bun",
    "deno",
    "cloudflare",
    "vercel-edge",
    "vercel-node",
    "deno-deploy",
    "capacitor",
    "electron",
    "tauri"
  ],

  libsql: [
    "browser",
    "node",
    "bun",
    "deno",
    "cloudflare",
    "vercel-edge",
    "vercel-node",
    "deno-deploy",
    "capacitor",
    "electron",
    "tauri"
  ],

  planetscale: [
    "browser",
    "node",
    "bun",
    "deno",
    "cloudflare",
    "vercel-edge",
    "vercel-node",
    "deno-deploy",
    "capacitor",
    "electron",
    "tauri"
  ],

  supabase: [
    "browser",
    "node",
    "bun",
    "deno",
    "cloudflare",
    "vercel-edge",
    "vercel-node",
    "deno-deploy",
    "capacitor",
    "electron",
    "tauri"
  ]
});

// Default target for each database adapter (used when target not specified)
SelfhostBuilder.DEFAULT_TARGETS = Object.freeze({
  // Browser-only databases
  dexie: "browser",
  indexeddb: "browser",
  sqljs: "browser",
  "sql.js": "browser",
  pglite: "browser",

  // TCP-based server databases
  better_sqlite3: "node",
  sqlite3: "node",
  sqlite: "node",
  pg: "node",
  postgres: "node",
  postgresql: "node",
  mysql2: "node",
  mysql: "node",

  // Platform-specific databases
  d1: "cloudflare",
  mpg: "fly",

  // HTTP-based edge databases
  neon: "vercel",
  turso: "vercel",
  libsql: "vercel",
  planetscale: "vercel",
  supabase: "vercel"
});

// Map DATABASE env var to adapter source file
SelfhostBuilder.ADAPTER_FILES = Object.freeze({
  // Browser adapters
  sqljs: "active_record_sqljs.mjs",
  "sql.js": "active_record_sqljs.mjs",
  dexie: "active_record_dexie.mjs",
  indexeddb: "active_record_dexie.mjs",
  pglite: "active_record_pglite.mjs",
  sqlite_wasm: "active_record_sqlite_wasm.mjs",
  "sqlite-wasm": "active_record_sqlite_wasm.mjs",
  wa_sqlite: "active_record_wa_sqlite.mjs",
  "wa-sqlite": "active_record_wa_sqlite.mjs",

  // Node.js adapters
  better_sqlite3: "active_record_better_sqlite3.mjs",
  sqlite3: "active_record_better_sqlite3.mjs",
  sqlite: "active_record_better_sqlite3.mjs",
  pg: "active_record_pg.mjs",
  postgres: "active_record_pg.mjs",
  postgresql: "active_record_pg.mjs",
  mysql2: "active_record_mysql2.mjs",
  mysql: "active_record_mysql2.mjs",

  // Cloudflare adapters
  d1: "active_record_d1.mjs",

  // Fly.io adapters
  mpg: "active_record_pg.mjs",

  // Universal adapters (HTTP-based, work on browser/node/edge)
  neon: "active_record_neon.mjs",
  turso: "active_record_turso.mjs",
  libsql: "active_record_turso.mjs",
  planetscale: "active_record_planetscale.mjs",
  supabase: "active_record_supabase.mjs",

  // RPC adapter (proxies to server, used with server targets)
  rpc: "active_record_rpc.mjs"
});

// Map broadcast adapter to source file
// Used for real-time Turbo Streams when native WebSockets aren't available
SelfhostBuilder.BROADCAST_ADAPTER_FILES = Object.freeze({
  supabase: "broadcast_supabase.mjs",
  pusher: "broadcast_pusher.mjs"
});

// 'websocket' is the default (built into rails.js targets), no separate file needed
// Map broadcast adapters to their required npm dependencies
SelfhostBuilder.BROADCAST_ADAPTER_DEPENDENCIES = Object.freeze({
  supabase: {"@supabase/supabase-js": "^2.47.0"},
  pusher: {pusher: "^5.2.0", "pusher-js": "^8.4.0"}
});

// Common transpilation options for Ruby files
SelfhostBuilder.OPTIONS = Object.freeze({
  eslevel: 2022,
  include: ["class", "call"],
  autoexports: true,

  filters: [
    Rails_Model.prototype,
    Rails_Controller.prototype,
    Rails_Routes.prototype,
    Rails_Seeds.prototype,
    Functions.prototype,
    ESM.prototype,
    Return.prototype
  ]
});

// Options for Stimulus controllers
// Uses Stimulus filter instead of Rails::Controller for proper ES class output
// autoexports: :default produces 'export default class' (Rails convention)
SelfhostBuilder.STIMULUS_OPTIONS = Object.freeze({
  eslevel: 2022,
  include: ["class", "call"],
  autoexports: "default",

  filters: [
    Stimulus.prototype,
    Functions.prototype,
    ESM.prototype,
    Return.prototype
  ]
});

// Options for ERB templates
// Note: Rails::Helpers must come BEFORE Erb for method overrides to work
SelfhostBuilder.ERB_OPTIONS = Object.freeze({
  eslevel: 2022,
  include: ["class", "call"],

  filters: [
    Rails_Helpers.prototype,
    Erb.prototype,
    Functions.prototype,
    Return.prototype
  ]
});

// Options for layout templates (ERB with layout: true)
// Layouts have different function signature: layout(context, content)
// and yield becomes content interpolation
SelfhostBuilder.LAYOUT_OPTIONS = Object.freeze({
  eslevel: 2022,
  include: ["class", "call"],
  layout: true,

  filters: [
    Rails_Helpers.prototype,
    Erb.prototype,
    Functions.prototype,
    Return.prototype
  ]
});

// Options for RBX files (Ruby with JSX syntax via %x{})
// RBX files compile to React components with React.createElement output
// Note: JSX filter is for Wunderbar syntax (_div {}), not %x{} syntax
SelfhostBuilder.RBX_OPTIONS = Object.freeze({
  eslevel: 2022,
  include: ["class", "call"],
  autoexports: "default",

  filters: [
    React.prototype,
    Functions.prototype,
    ESM.prototype,
    Return.prototype,
    Pragma.prototype
  ]
});

// Astro files compile Phlex components to .astro format
// Produces frontmatter + JSX-style template
SelfhostBuilder.ASTRO_OPTIONS = Object.freeze({
  eslevel: 2022,
  include: ["class", "call"],
  filters: [Phlex.prototype, Astro.prototype, Functions.prototype]
});

// Vue files compile Phlex components to .vue SFC format
// Produces <template> + <script setup> sections
SelfhostBuilder.VUE_OPTIONS = Object.freeze({
  eslevel: 2022,
  include: ["class", "call"],
  filters: [Phlex.prototype, Vue.prototype, Functions.prototype]
});

// Options for database migrations
SelfhostBuilder.MIGRATION_OPTIONS = Object.freeze({
  eslevel: 2022,
  include: ["class", "call"],

  filters: [
    Rails_Migration.prototype,
    Functions.prototype,
    ESM.prototype,
    Return.prototype
  ]
});

// Map database adapters to their required npm dependencies
// Each entry specifies: { package_name => version }
SelfhostBuilder.ADAPTER_DEPENDENCIES = Object.freeze({
  // Browser-only adapters
  dexie: {dexie: "^4.0.10"},
  indexeddb: {dexie: "^4.0.10"},
  sqljs: {"sql.js": "^1.11.0"},
  "sql.js": {"sql.js": "^1.11.0"},
  pglite: {"@electric-sql/pglite": "^0.2.0"},

  // Node-only adapters (native modules - use optionalDependencies)
  sqlite: {"better-sqlite3": "^11.0.0"},
  sqlite3: {"better-sqlite3": "^11.0.0"},
  better_sqlite3: {"better-sqlite3": "^11.0.0"},
  pg: {pg: "^8.13.0"},
  postgres: {pg: "^8.13.0"},
  postgresql: {pg: "^8.13.0"},
  mysql: {mysql2: "^3.11.0"},
  mysql2: {mysql2: "^3.11.0"},

  // Fly.io adapters
  mpg: {pg: "^8.13.0"},

  // Universal adapters (work on browser, node, and edge)
  neon: {"@neondatabase/serverless": "^0.10.0"},
  turso: {"@libsql/client": "^0.14.0"},
  libsql: {"@libsql/client": "^0.14.0"},
  planetscale: {"@planetscale/database": "^1.19.0"},
  supabase: {"@supabase/supabase-js": "^2.47.0", pg: "^8.13.0"}
});

// Adapters that require native compilation (should be optionalDependencies)
SelfhostBuilder.NATIVE_ADAPTERS = Object.freeze([
  "sqlite",
  "sqlite3",
  "better_sqlite3",
  "pg",
  "postgres",
  "postgresql",
  "mysql",
  "mysql2",
  "mpg"
]);

// Common importmap entries for all browser builds (turbo added dynamically based on target)
SelfhostBuilder.COMMON_IMPORTMAP_ENTRIES = Object.freeze({
  "@hotwired/stimulus": "/node_modules/@hotwired/stimulus/dist/stimulus.js",

  // Shared juntos modules (imported by adapters, not copied to dist)
  "juntos/adapters/active_record_base.mjs": "/node_modules/juntos/adapters/active_record_base.mjs",
  "juntos/adapters/active_record_sql.mjs": "/node_modules/juntos/adapters/active_record_sql.mjs",
  "juntos/adapters/relation.mjs": "/node_modules/juntos/adapters/relation.mjs",
  "juntos/adapters/collection_proxy.mjs": "/node_modules/juntos/adapters/collection_proxy.mjs",
  "juntos/adapters/inflector.mjs": "/node_modules/juntos/adapters/inflector.mjs",
  "juntos/adapters/sql_parser.mjs": "/node_modules/juntos/adapters/sql_parser.mjs"
});

// Database-specific importmap entries for browser builds
SelfhostBuilder.IMPORTMAP_ENTRIES = Object.freeze({
  dexie: {dexie: "/node_modules/dexie/dist/dexie.mjs"},
  indexeddb: {dexie: "/node_modules/dexie/dist/dexie.mjs"},
  sqljs: {"sql.js": "/node_modules/sql.js/dist/sql-wasm.js"},
  "sql.js": {"sql.js": "/node_modules/sql.js/dist/sql-wasm.js"},
  pglite: {"@electric-sql/pglite": "/node_modules/@electric-sql/pglite/dist/index.js"}
});

// Map filter names (strings) to Ruby2JS filter modules
// Only includes filters required above (selfhost-ready filters)
// Users needing other filters should require them before using builder
SelfhostBuilder.FILTER_MAP = Object.freeze({
  // Core filters
  functions: Functions.prototype,
  esm: ESM.prototype,
  cjs: CJS.prototype,
  return: Return.prototype,
  erb: Erb.prototype,
  pragma: Pragma.prototype,
  camelcase: CamelCase.prototype,
  camelCase: CamelCase.prototype,
  tagged_templates: TaggedTemplates.prototype,

  // Framework filters
  phlex: Phlex.prototype,
  stimulus: Stimulus.prototype,
  react: React.prototype,
  astro: Astro.prototype,
  vue: Vue.prototype,

  // Ruby stdlib filters (selfhost-ready)
  active_support: ActiveSupport.prototype,
  securerandom: SecureRandom.prototype,
  nokogiri: Nokogiri.prototype,
  haml: Haml.prototype,

  // Utility filters
  jest: Jest.prototype,

  // Rails sub-filters
  "rails/model": Rails_Model.prototype,
  "rails/controller": Rails_Controller.prototype,
  "rails/routes": Rails_Routes.prototype,
  "rails/seeds": Rails_Seeds.prototype,
  "rails/helpers": Rails_Helpers.prototype,
  "rails/migration": Rails_Migration.prototype
});

// Preset configuration: standard set of filters and options for typical apps
// Enable with `preset: true` in config/ruby2js.yml
SelfhostBuilder.PRESET_FILTERS = Object.freeze([
  Functions.prototype,
  ESM.prototype,
  Pragma.prototype,
  Return.prototype
]);

SelfhostBuilder.PRESET_OPTIONS = Object.freeze({
  eslevel: 2022,
  comparison: "identity",
  filters: SelfhostBuilder.PRESET_FILTERS
});

// File type priorities for conflict resolution
// Higher priority formats take precedence when same view name exists in multiple formats
SelfhostBuilder.VIEW_FILE_PRIORITIES = Object.freeze({
  ".rb": 1,
  ".jsx.rb": 2,
  ".jsx": 3,

  // JSX
  ".tsx": 3,
  ".html.erb": 4
});

// CLI entry point - only run if this file is executed directly
// Guard: defined? check ensures process.argv[1] exists in transpiled JS
if (typeof process.argv[1] !== 'undefined' && import.meta.url == `file://${fs.realpathSync(process.argv[1])}`) {
  dist_dir = ARGV[0] ? path.resolve(ARGV[0]) : null;
  let builder = new SelfhostBuilder(dist_dir);
  builder.build()
}
