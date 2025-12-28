#!/usr/bin/env node
let dist_dir;
import path from "node:path";
import fs from "node:fs";
import yaml from "js-yaml";
let ARGV = process.argv.slice(2);
import * as Ruby2JS from "ruby2js";
await Ruby2JS.initPrism();
import { Rails_Model } from "ruby2js/filters/rails/model.js";
import { Rails_Controller } from "ruby2js/filters/rails/controller.js";
import { Rails_Routes } from "ruby2js/filters/rails/routes.js";
import { Rails_Schema } from "ruby2js/filters/rails/schema.js";
import { Rails_Seeds } from "ruby2js/filters/rails/seeds.js";
import { Functions } from "ruby2js/filters/functions.js";
import { ESM } from "ruby2js/filters/esm.js";
import { Return } from "ruby2js/filters/return.js";
import { Erb } from "ruby2js/filters/erb.js";
import { Rails_Helpers } from "ruby2js/filters/rails/helpers.js";
import { Phlex } from "ruby2js/filters/phlex.js";
import { Stimulus } from "ruby2js/filters/stimulus.js";
import { CamelCase } from "ruby2js/filters/camelCase.js";
import { ErbCompiler } from "ruby2js/lib/erb_compiler.js";

export class SelfhostBuilder {
  constructor(dist_dir=null) {
    this._dist_dir = dist_dir ?? path.join(
      SelfhostBuilder.DEMO_ROOT,
      "dist"
    );

    this._database = null // Set during build from config;
    this._target = null // Derived from database: 'browser' or 'server';
    this._runtime = null // For server targets: 'node', 'bun', or 'deno'
  };

  // Note: Using explicit () on all method calls for JS transpilation compatibility
  build() {
    fs.rmSync(this._dist_dir, {recursive: true, force: true});
    fs.mkdirSync(this._dist_dir, {recursive: true});
    console.log("=== Building Ruby2JS-on-Rails Demo ===");
    console.log("");

    // Load database config and derive target
    console.log("Database Adapter:");
    let db_config = this.load_database_config();
    this._database = db_config.adapter || db_config.adapter || "sqljs";
    this._target = SelfhostBuilder.BROWSER_DATABASES.includes(this._database) ? "browser" : "server";

    // Validate and set runtime based on database type
    let requested_runtime = process.env.RUNTIME;
    if (requested_runtime) requested_runtime = requested_runtime.toLowerCase();

    if (this._target == "browser") {
      // Browser databases only work with browser target
      if (requested_runtime && requested_runtime != "browser") {
        throw `${`Database '${this._database}' is browser-only. Cannot use RUNTIME=${requested_runtime}.\n`}${`Browser databases: ${SelfhostBuilder.BROWSER_DATABASES.join(", ")}`}`
      };

      this._runtime = null // Browser target doesn't use a JS runtime
    } else {
      // Check if database requires a specific runtime
      let required_runtime = SelfhostBuilder.RUNTIME_REQUIRED[this._database];

      if (required_runtime) {
        if (requested_runtime && requested_runtime != required_runtime) {
          throw `Database '${this._database}' requires RUNTIME=${required_runtime}. Cannot use RUNTIME=${requested_runtime}.`
        };

        this._runtime = required_runtime
      } else {
        // Server databases work with node, bun, or deno (default: node)
        this._runtime = requested_runtime ?? "node"
      };

      if (!SelfhostBuilder.SERVER_RUNTIMES.includes(this._runtime)) {
        throw `Unknown runtime: ${this._runtime}. Valid options for server databases: ${SelfhostBuilder.SERVER_RUNTIMES.join(", ")}`
      }
    };

    this.copy_database_adapter(db_config);
    console.log(`  Target: ${this._target}`);
    if (this._runtime) console.log(`  Runtime: ${this._runtime}`);
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
      path.join(this._dist_dir, "models"),
      "**/*.rb",
      {skip: ["application_record.rb"]}
    );

    this.generate_models_index();
    console.log("");

    // Transpile controllers (use 'controllers' section from ruby2js.yml if present)
    console.log("Controllers:");

    this.transpile_directory(
      path.join(SelfhostBuilder.DEMO_ROOT, "app/controllers"),
      path.join(this._dist_dir, "controllers"),
      "**/*.rb",
      {section: "controllers"}
    );

    console.log("");

    // Transpile components (Phlex views, use 'components' section from ruby2js.yml)
    let components_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "app/components"
    );

    if (fs.existsSync(components_dir)) {
      console.log("Components:");
      this.copy_phlex_runtime();

      this.transpile_directory(
        components_dir,
        path.join(this._dist_dir, "components"),
        "**/*.rb",
        {section: "components"}
      );

      console.log("")
    };

    // Transpile Stimulus controllers (app/javascript/controllers/)
    let stimulus_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "app/javascript/controllers"
    );

    if (fs.existsSync(stimulus_dir)) {
      console.log("Stimulus Controllers:");

      this.transpile_directory(
        stimulus_dir,
        path.join(this._dist_dir, "javascript/controllers"),
        "**/*.rb",
        {section: "stimulus"}
      );

      console.log("")
    };

    // Transpile config (skip routes.rb, handled separately)
    console.log("Config:");

    this.transpile_directory(
      path.join(SelfhostBuilder.DEMO_ROOT, "config"),
      path.join(this._dist_dir, "config"),
      "**/*.rb",
      {skip: ["routes.rb"]}
    );

    this.transpile_routes_files();
    console.log("");

    // Transpile views (ERB templates and layout)
    console.log("Views:");
    this.transpile_erb_directory();
    if (this._target == "server") this.transpile_layout();
    console.log("");

    // Transpile helpers
    console.log("Helpers:");

    this.transpile_directory(
      path.join(SelfhostBuilder.DEMO_ROOT, "app/helpers"),
      path.join(this._dist_dir, "helpers")
    );

    console.log("");

    // Transpile db (seeds)
    console.log("Database:");

    this.transpile_directory(
      path.join(SelfhostBuilder.DEMO_ROOT, "db"),
      path.join(this._dist_dir, "db")
    );

    console.log("");
    return console.log("=== Build Complete ===")
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

    // If a specific section is requested (e.g., 'controllers', 'components')
    if (section && section in config) return config[section];

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

    // Start with hardcoded OPTIONS as base (using spread for JS compatibility)
    let options = {...SelfhostBuilder.OPTIONS};

    Object.entries(base).forEach(([key, value]) => {
      let sym_key = key.toString();

      // Convert filter names to module references
      if (sym_key == "filters" && Array.isArray(value)) {
        options[sym_key] = this.resolve_filters(value)
      } else {
        options[sym_key] = value
      }
    });

    return options
  };

  resolve_filters(filter_names) {
    return filter_names.map((name) => {
      let valid_filters;

      if (typeof name !== "string") {
        // Already a filter (not a string)? Pass through
        // In Ruby, filters are Modules; in JS, they're prototype objects
        return name
      };

      // Normalize: strip, downcase for lookup (but preserve camelCase key)
      let normalized = name.toString().trim();
      let lookup_key = normalized in SelfhostBuilder.FILTER_MAP ? normalized : normalized.toLowerCase();
      let filter = SelfhostBuilder.FILTER_MAP[lookup_key];

      if (!filter) {
        valid_filters = SelfhostBuilder.FILTER_MAP.keys.uniq.sort().join(", ");
        throw `Unknown filter: '${name}'. Valid filters: ${valid_filters}`
      };

      return filter
    })
  };

  load_runtime_config() {
    // Priority 1: RUNTIME environment variable
    if (process.env.RUNTIME) return process.env.RUNTIME.toLowerCase();

    // Priority 2: database.yml runtime key
    let db_config = this.load_database_config();
    if (db_config.runtime) return db_config.runtime.toLowerCase();

    // Priority 3: ruby2js.yml runtime key
    let r2js_config = this.load_ruby2js_config();
    if (r2js_config.runtime) return r2js_config.runtime.toLowerCase();
    return "node"
  };

  load_database_config() {
    // Use || instead of fetch for JS compatibility
    let env = process.env.RAILS_ENV || process.env.NODE_ENV || "development";

    // Priority 1: DATABASE environment variable
    if (process.env.DATABASE) {
      console.log(`  Using DATABASE=${process.env.DATABASE} from environment`);
      return {adapter: process.env.DATABASE.toLowerCase()}
    };

    // Priority 2: config/database.yml
    let config_path = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "config/database.yml"
    );

    if (fs.existsSync(config_path)) {
      let config = yaml.load(fs.readFileSync(config_path, "utf8"));

      if (config && config[env] && config[env].adapter) {
        console.log(`  Using config/database.yml [${env}]`);
        return config[env]
      }
    };

    // Default: sqljs
    console.log("  Using default adapter: sqljs");
    return {adapter: "sqljs", database: "ruby2js_rails"}
  };

  copy_database_adapter(db_config) {
    let valid;
    let adapter = db_config.adapter || db_config.adapter || "sqljs";
    let adapter_file = SelfhostBuilder.ADAPTER_FILES[adapter];

    if (!adapter_file) {
      valid = SelfhostBuilder.ADAPTER_FILES.keys.join(", ");
      throw `Unknown DATABASE adapter: ${adapter}. Valid options: ${valid}`
    };

    // Check for npm-installed package first, fall back to development vendor directory
    let npm_adapter_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "node_modules/ruby2js-rails/adapters"
    );

    let vendor_adapter_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "vendor/ruby2js/adapters"
    );

    let adapter_dir = fs.existsSync(npm_adapter_dir) ? npm_adapter_dir : vendor_adapter_dir;
    let lib_dest = path.join(this._dist_dir, "lib");
    fs.mkdirSync(lib_dest, {recursive: true});

    // Copy base class first (all adapters depend on it)
    let base_src = path.join(adapter_dir, "active_record_base.mjs");
    let base_dest = path.join(lib_dest, "active_record_base.mjs");
    fs.copyFileSync(base_src, base_dest);
    console.log("  Base class: active_record_base.mjs");

    // Read adapter and inject config
    let adapter_src = path.join(adapter_dir, adapter_file);
    let adapter_dest = path.join(lib_dest, "active_record.mjs");
    let adapter_code = fs.readFileSync(adapter_src, "utf8");

    adapter_code = adapter_code.replace(
      "const DB_CONFIG = {};",
      `const DB_CONFIG = ${JSON.stringify(db_config)};`
    );

    fs.writeFileSync(adapter_dest, adapter_code);
    console.log(`  Adapter: ${adapter} -> lib/active_record.mjs`);

    if (db_config.database || db_config.database) {
      return console.log(`  Database: ${db_config.database ?? db_config.database}`)
    }
  };

  copy_lib_files() {
    let target_dir;
    let lib_dest = path.join(this._dist_dir, "lib");
    fs.mkdirSync(lib_dest, {recursive: true});

    // Determine source directory: browser or runtime-specific server target
    if (this._target == "browser") {
      target_dir = "browser"
    } else {
      target_dir = this._runtime // node, bun, or deno
    };

    // Check for npm-installed package first, fall back to development vendor directory
    let npm_package_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "node_modules/ruby2js-rails"
    );

    let vendor_package_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "vendor/ruby2js"
    );

    let package_dir = fs.existsSync(npm_package_dir) ? npm_package_dir : vendor_package_dir;

    // Copy base files (rails_base.js is needed by all targets)
    let base_src = path.join(package_dir, "rails_base.js");
    if (fs.existsSync(base_src)) {
      fs.copyFileSync(base_src, path.join(lib_dest, "rails_base.js"));
      console.log("  Copying: rails_base.js");
      console.log(`    -> ${lib_dest}/rails_base.js`);
    }

    // Copy server module (needed by node, bun, deno, cloudflare targets)
    if (this._target == "server") {
      let server_src = path.join(package_dir, "rails_server.js");
      if (fs.existsSync(server_src)) {
        fs.copyFileSync(server_src, path.join(lib_dest, "rails_server.js"));
        console.log("  Copying: rails_server.js");
        console.log(`    -> ${lib_dest}/rails_server.js`);
      }
    }

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
    }
  };

  copy_phlex_runtime() {
    let lib_dest = path.join(this._dist_dir, "lib");
    fs.mkdirSync(lib_dest, {recursive: true});

    // Check for npm-installed package first, fall back to development vendor directory
    let npm_package_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "node_modules/ruby2js-rails"
    );

    let vendor_package_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "vendor/ruby2js"
    );

    let package_dir = fs.existsSync(npm_package_dir) ? npm_package_dir : vendor_package_dir;
    let src_path = path.join(package_dir, "phlex_runtime.mjs");
    if (!fs.existsSync(src_path)) return;
    let dest_path = path.join(lib_dest, "phlex_runtime.mjs");
    fs.copyFileSync(src_path, dest_path);
    console.log("  Copying: phlex_runtime.mjs");
    return console.log(`    -> ${dest_path}`)
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
    let result = Ruby2JS.convert(source, options);
    let js = result.toString();
    fs.mkdirSync(path.dirname(dest_path), {recursive: true});

    // Generate sourcemap
    let map_path = `${dest_path}.map`;
    let sourcemap = result.sourcemap;
    sourcemap.sourcesContent = [source];

    // Compute relative path from sourcemap location back to source file
    let map_dir = path.dirname(dest_path).replace(
      SelfhostBuilder.DEMO_ROOT + "/",
      ""
    );

    let depth = map_dir.split("/").length;
    let source_from_map = ("../".repeat(depth)) + relative_src;
    sourcemap.sources = [source_from_map];

    // Add sourcemap reference to JS file
    let js_with_map = `${js}\n//# sourceMappingURL=${path.basename(map_path)}\n`;
    fs.writeFileSync(dest_path, js_with_map);
    fs.writeFileSync(map_path, JSON.stringify(sourcemap));
    console.log(`  -> ${dest_path}`);
    return console.log(`  -> ${map_path}`)
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

    // Pass database option for target-aware link generation
    // Also pass ERB source and position map for source map generation
    let erb_options = {
      ...SelfhostBuilder.ERB_OPTIONS,
      database: this._database,
      file: relative_src
    };

    let result = Ruby2JS.convert(ruby_src, erb_options);

    // Set ERB source map data on the result (which is the Serializer/Converter)
    result.erb_source = template;
    result.erb_position_map = compiler.position_map;
    let js = result.toString();
    js = js.replace(/^function render/m, "export function render");
    fs.mkdirSync(path.dirname(dest_path), {recursive: true});

    // Generate source map
    let map_path = `${dest_path}.map`;
    let sourcemap = result.sourcemap;
    sourcemap.sourcesContent = [template] // Use original ERB, not Ruby;

    // Compute relative path from sourcemap location back to source file
    let map_dir = path.dirname(dest_path).replace(
      SelfhostBuilder.DEMO_ROOT + "/",
      ""
    );

    let depth = map_dir.split("/").length;
    let source_from_map = ("../".repeat(depth)) + relative_src;
    sourcemap.sources = [source_from_map];

    // Add sourcemap reference to JS file
    let js_with_map = `${js}\n//# sourceMappingURL=${path.basename(map_path)}\n`;
    fs.writeFileSync(dest_path, js_with_map);
    fs.writeFileSync(map_path, JSON.stringify(sourcemap));
    console.log(`  -> ${dest_path}`);
    console.log(`  -> ${map_path}`);
    return js
  };

  transpile_erb_directory() {
    let erb_dir = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "app/views/articles"
    );

    if (!fs.existsSync(erb_dir)) return;
    let renders = {};

    for (let src_path of fs.globSync(path.join(erb_dir, "**/*.html.erb"))) {
      let basename = path.basename(src_path, ".html.erb");

      let js = this.transpile_erb_file(
        src_path,
        path.join(this._dist_dir, "views/erb", `${basename}.js`)
      );

      renders[basename] = js
    };

    // Create a combined module that exports all render functions
    let erb_views_js = `// Article views - auto-generated from .html.erb templates\n// Each exported function is a render function that takes { article } or { articles }\n\n`;
    let render_exports = [];

    for (let erb_path of fs.globSync(path.join(erb_dir, "*.html.erb")).sort()) {
      let name = path.basename(erb_path, ".html.erb");
      erb_views_js += `import { render as ${name}_render } from './erb/${name}.js';\n`;
      render_exports.push(`${name}: ${name}_render`)
    };

    erb_views_js += `
// Export ArticleViews - method names match controller action names
export const ArticleViews = {
  ${render_exports.join(",\n  ")},
  // $new alias for 'new' (JS reserved word handling)
  $new: new_render
};
`;

    fs.writeFileSync(
      path.join(this._dist_dir, "views/articles.js"),
      erb_views_js
    );

    return console.log("  -> dist/views/articles.js (combined ERB module)")
  };

  transpile_layout() {
    let layout_path = path.join(
      SelfhostBuilder.DEMO_ROOT,
      "app/views/layouts/application.html.erb"
    );

    if (!fs.existsSync(layout_path)) return;
    console.log("Transpiling layout: application.html.erb");
    let template = fs.readFileSync(layout_path, "utf8");

    // Simple transformation: replace <%= yield %> with ${content}
    let js_template = template.replace(/<%=/g, "${").replace(/%>/g, "}");

    js_template = js_template.replace(/\$\{yield\}/g, "${content}").replace(
      /\$\{\ yield\ \}/g,
      "${content}"
    );

    // Wrap in a template literal function
    let js = `// Application layout - wraps view content
// Generated from app/views/layouts/application.html.erb
export function layout(content) {
  return \`${js_template}\`;
}
`;
    let dest_dir = path.join(this._dist_dir, "views/layouts");
    fs.mkdirSync(dest_dir, {recursive: true});
    fs.writeFileSync(path.join(dest_dir, "application.js"), js);
    return console.log("  -> dist/views/layouts/application.js")
  };

  transpile_directory(src_dir, dest_dir, pattern="**/*.rb", { skip=[], section=null } = {}) {
    for (let src_path of fs.globSync(path.join(src_dir, pattern))) {
      let basename = path.basename(src_path);
      if (skip.includes(basename)) continue;
      let relative = src_path.replace(src_dir + "/", "");

      let dest_path = path.join(
        dest_dir,
        relative.replace(/\.rb$/m, ".js")
      );

      this.transpile_file(src_path, dest_path, section)
    }
  };

  generate_application_record() {
    let wrapper = `// ApplicationRecord - wraps ActiveRecord from adapter
// This file is generated by the build script
import { ActiveRecord } from '../lib/active_record.mjs';

export class ApplicationRecord extends ActiveRecord {
  // Subclasses (Article, Comment) extend this and add their own validations
}
`;
    let dest_dir = path.join(this._dist_dir, "models");
    fs.mkdirSync(dest_dir, {recursive: true});

    fs.writeFileSync(
      path.join(dest_dir, "application_record.js"),
      wrapper
    );

    return console.log("  -> models/application_record.js (wrapper for ActiveRecord)")
  };

  transpile_routes_files() {
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
      paths_only: true
    };

    let result = Ruby2JS.convert(source, paths_options);
    let paths_js = result.toString();
    let paths_path = path.join(dest_dir, "paths.js");
    fs.mkdirSync(dest_dir, {recursive: true});
    fs.writeFileSync(paths_path, paths_js);
    console.log(`  -> ${paths_path}`);

    // Generate sourcemap for paths.js
    let map_path = `${paths_path}.map`;
    let sourcemap = result.sourcemap;
    sourcemap.sourcesContent = [source];
    fs.writeFileSync(map_path, JSON.stringify(sourcemap));
    console.log(`  -> ${map_path}`);

    // Generate routes.js (imports path helpers from paths.js)
    console.log("Transpiling: routes.rb -> routes.js");

    let routes_options = {
      ...base_options,
      file: relative_src,
      paths_file: "./paths.js",
      database: this._database
    };

    result = Ruby2JS.convert(source, routes_options);
    let routes_js = result.toString();
    let routes_path = path.join(dest_dir, "routes.js");
    fs.writeFileSync(routes_path, routes_js);
    console.log(`  -> ${routes_path}`);

    // Generate sourcemap for routes.js
    map_path = `${routes_path}.map`;
    sourcemap = result.sourcemap;
    sourcemap.sourcesContent = [source];
    fs.writeFileSync(map_path, JSON.stringify(sourcemap));
    return console.log(`  -> ${map_path}`)
  };

  generate_models_index() {
    let models_dir = path.join(this._dist_dir, "models");

    let model_files = fs.globSync(path.join(models_dir, "*.js")).map(f => (
      path.basename(f, ".js")
    )).filter(name => !(name == "application_record" || name == "index")).sort();

    if (!model_files.some(Boolean)) return;

    let index_js = model_files.map((name) => {
      // Use explicit capitalization for JS compatibility
      let class_name = name.split("_").map(s => s[0].toUpperCase() + s.slice(1)).join("");
      return `export { ${class_name} } from './${name}.js';`
    }).join("\n") + "\n";

    fs.writeFileSync(path.join(models_dir, "index.js"), index_js);
    return console.log(`  -> ${path.join(models_dir, "index.js")} (re-exports)`)
  }
};

// JS (Node.js): use process.cwd() since bin commands run from app root
// Ruby: resolve from scripts/ up one level to app root
SelfhostBuilder.DEMO_ROOT = typeof process !== 'undefined' ? process.cwd() : path.resolve(
  import.meta.dirname,
  ".."
);

// Browser databases - these run in the browser with IndexedDB or WASM
SelfhostBuilder.BROWSER_DATABASES = Object.freeze([
  "dexie",
  "indexeddb",
  "sqljs",
  "sql.js",
  "pglite"
]);

// Server-side JavaScript runtimes
SelfhostBuilder.SERVER_RUNTIMES = Object.freeze([
  "node",
  "bun",
  "deno",
  "cloudflare"
]);

// Databases that require a specific runtime
SelfhostBuilder.RUNTIME_REQUIRED = Object.freeze({d1: "cloudflare"});

// Map DATABASE env var to adapter source file
SelfhostBuilder.ADAPTER_FILES = Object.freeze({
  // Browser adapters
  sqljs: "active_record_sqljs.mjs",
  "sql.js": "active_record_sqljs.mjs",
  dexie: "active_record_dexie.mjs",
  indexeddb: "active_record_dexie.mjs",
  pglite: "active_record_pglite.mjs",

  // Node.js adapters
  better_sqlite3: "active_record_better_sqlite3.mjs",
  sqlite3: "active_record_better_sqlite3.mjs",
  pg: "active_record_pg.mjs",
  postgres: "active_record_pg.mjs",
  postgresql: "active_record_pg.mjs",
  mysql2: "active_record_mysql2.mjs",
  mysql: "active_record_mysql2.mjs",

  // Cloudflare adapters
  d1: "active_record_d1.mjs"
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
    Rails_Schema.prototype,
    Rails_Seeds.prototype,
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

// Map filter names (strings) to Ruby2JS filter modules
// Supports both short names ('phlex') and full paths ('rails/helpers')
SelfhostBuilder.FILTER_MAP = Object.freeze({
  // Core filters
  functions: Functions.prototype,
  esm: ESM.prototype,
  return: Return.prototype,
  erb: Erb.prototype,
  camelcase: CamelCase.prototype,
  camelCase: CamelCase.prototype,

  // Framework filters
  phlex: Phlex.prototype,
  stimulus: Stimulus.prototype,
  "rails/model": Rails_Model.prototype,
  "rails/controller": Rails_Controller.prototype,
  "rails/routes": Rails_Routes.prototype,
  "rails/schema": Rails_Schema.prototype,
  "rails/seeds": Rails_Seeds.prototype,
  "rails/helpers": Rails_Helpers.prototype
});

// CLI entry point - only run if this file is executed directly
if (import.meta.url == `file://${fs.realpathSync(process.argv[1])}`) {
  dist_dir = ARGV[0] ? path.resolve(ARGV[0]) : null;
  let builder = new SelfhostBuilder(dist_dir);
  builder.build()
}
