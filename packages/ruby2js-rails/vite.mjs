/**
 * Juntos Vite Preset for Ruby2JS Rails Applications
 *
 * Provides full Rails app transformation including:
 * - Ruby file transformation (.rb → .js)
 * - JSX.rb file support (Ruby + JSX with React)
 * - Structural transforms (models, controllers, views, routes)
 * - Stimulus HMR
 * - Platform-specific configuration
 *
 * Usage:
 *   import { juntos } from 'ruby2js-rails/vite';
 *
 *   export default juntos({
 *     database: 'dexie',
 *     target: 'browser'
 *   });
 */

import path from 'node:path';
import fs from 'node:fs';
import yaml from 'js-yaml';

// Import React filter for .jsx.rb files
import 'ruby2js/filters/react.js';

// Import Stimulus filter for controller support
import 'ruby2js/filters/stimulus.js';

// Import Pragma filter for target-specific pragmas (browser, capacitor, etc.)
import 'ruby2js/filters/pragma.js';

// Import Functions filter for core method translations
import 'ruby2js/filters/functions.js';

// Import ESM filter for ES module imports/exports
import 'ruby2js/filters/esm.js';

// Import Return filter for implicit returns
import 'ruby2js/filters/return.js';

// ============================================================
// Configuration constants (previously from SelfhostBuilder)
// ============================================================

/**
 * Default target for each database adapter (used when target not specified).
 */
const DEFAULT_TARGETS = Object.freeze({
  // Browser-only databases
  dexie: 'browser',
  indexeddb: 'browser',
  sqljs: 'browser',
  'sql.js': 'browser',
  pglite: 'browser',

  // TCP-based server databases
  better_sqlite3: 'node',
  sqlite3: 'node',
  sqlite: 'node',
  pg: 'node',
  postgres: 'node',
  postgresql: 'node',
  mysql2: 'node',
  mysql: 'node',

  // Platform-specific databases
  d1: 'cloudflare',
  mpg: 'fly',

  // HTTP-based edge databases
  neon: 'vercel',
  turso: 'vercel',
  libsql: 'vercel',
  planetscale: 'vercel',
  supabase: 'vercel'
});

/**
 * Load database configuration from environment or config/database.yml.
 * Returns: { adapter: 'dexie', database: 'myapp_dev', ... }
 */
function loadDatabaseConfig(appRoot, { quiet = false } = {}) {
  const env = process.env.RAILS_ENV || process.env.NODE_ENV || 'development';
  const configPath = path.join(appRoot, 'config/database.yml');

  let dbConfig = null;
  if (fs.existsSync(configPath)) {
    try {
      const config = yaml.load(fs.readFileSync(configPath, 'utf8'));
      if (config && config[env]) {
        if (!quiet) console.log(`  Using config/database.yml [${env}]`);
        dbConfig = config[env];
      }
    } catch (e) {
      if (!quiet) console.warn(`  Warning: Failed to parse database.yml: ${e.message}`);
    }
  }

  // Default config if database.yml not found or empty
  dbConfig = dbConfig || { adapter: 'dexie', database: 'ruby2js_rails' };

  // JUNTOS_DATABASE or DATABASE env var overrides adapter only
  const dbEnv = process.env.JUNTOS_DATABASE || process.env.DATABASE;
  if (dbEnv) {
    if (!quiet) {
      console.log(`  Adapter override: ${process.env.JUNTOS_DATABASE ? 'JUNTOS_DATABASE' : 'DATABASE'}=${dbEnv}`);
    }
    dbConfig.adapter = dbEnv.toLowerCase();
  }

  return dbConfig;
}

/**
 * Get Ruby2JS transpilation options for a given section.
 * Uses filter names as strings (resolved by ruby2js).
 */
function getBuildOptions(section, target) {
  const baseOptions = {
    eslevel: 2022,
    include: ['class', 'call']
  };

  switch (section) {
    case 'stimulus':
      return {
        ...baseOptions,
        autoexports: 'default',
        filters: ['Pragma', 'Stimulus', 'Functions', 'ESM', 'Return'],
        target
      };

    case 'controllers':
      return {
        ...baseOptions,
        autoexports: true,
        filters: ['Rails_Controller', 'Functions', 'ESM', 'Return'],
        target
      };

    default:
      // Models, routes, seeds, migrations
      return {
        ...baseOptions,
        autoexports: true,
        filters: ['Rails_Model', 'Rails_Controller', 'Rails_Routes', 'Rails_Seeds', 'Rails_Migration', 'Functions', 'ESM', 'Return'],
        target
      };
  }
}

// Import ERB compiler for .erb files
import { ErbCompiler } from './lib/erb_compiler.js';

// Import inflector for singularization
import { singularize } from 'ruby2js-rails/adapters/inflector.mjs';

// Helper function for capitalizing resource names
function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

/**
 * @typedef {Object} JuntosOptions
 * @property {string} [database] - Database adapter (dexie, sqlite, pg, etc.)
 * @property {string} [target] - Build target (browser, electron, capacitor, node, etc.)
 * @property {string} [broadcast] - Broadcast adapter (supabase, pusher, or null)
 * @property {string} [appRoot] - Application root directory (default: process.cwd())
 * @property {boolean} [hmr] - Enable HMR for Stimulus controllers (default: true)
 * @property {number} [eslevel] - ES level to target (default: 2022)
 * @property {string[]} [external] - Modules to externalize (not bundled, resolved at runtime)
 *   Supports exact matches ('lodash') and prefix patterns ('@capacitor/*')
 */

/**
 * Load configuration from ruby2js.yml and database.yml
 *
 * @param {string} appRoot - Application root directory
 * @param {Object} overrides - Option overrides from juntos() call
 * @returns {Object} Merged configuration
 */
export function loadConfig(appRoot, overrides = {}) {
  const env = process.env.RAILS_ENV || process.env.NODE_ENV || 'development';

  // Load ruby2js.yml if it exists
  let ruby2jsConfig = {};
  let topLevelConfig = {};
  const ruby2jsPath = path.join(appRoot, 'config/ruby2js.yml');
  if (fs.existsSync(ruby2jsPath)) {
    try {
      const parsed = yaml.load(fs.readFileSync(ruby2jsPath, 'utf8'));
      // Environment-specific config (nested under development/production/etc)
      ruby2jsConfig = parsed?.[env] || parsed?.default || {};
      // Top-level config (not nested under environment) - for settings like 'external'
      // that don't vary by environment
      topLevelConfig = parsed || {};
    } catch (e) {
      console.warn(`[juntos] Warning: Failed to parse ruby2js.yml: ${e.message}`);
    }
  }

  // Get database from env, overrides, or database.yml
  // Priority: JUNTOS_DATABASE env > overrides > database.yml > default
  let database = process.env.JUNTOS_DATABASE || overrides.database;
  if (!database) {
    const dbConfig = loadDatabaseConfig(appRoot, { quiet: true });
    database = dbConfig?.adapter || 'dexie';
  }

  // Derive target from env, overrides, config, or database
  // Priority: JUNTOS_TARGET env > overrides > ruby2js.yml > default from database
  const target = process.env.JUNTOS_TARGET ||
                 overrides.target ||
                 ruby2jsConfig.target ||
                 DEFAULT_TARGETS[database] ||
                 'browser';

  // External modules: top-level config, then env-specific, then overrides
  const external = overrides.external ||
                   ruby2jsConfig.external ||
                   topLevelConfig.external ||
                   [];

  // Base path for subdirectory deployment (e.g., '/ruby2js/blog/')
  // Priority: JUNTOS_BASE env > overrides > ruby2js.yml > default
  const base = process.env.JUNTOS_BASE ||
               overrides.base ||
               ruby2jsConfig.base ||
               '/';

  // Spread configs first, then override with our calculated values
  // This ensures env vars take precedence over hardcoded vite.config.js values
  return {
    ...ruby2jsConfig,
    ...overrides,
    eslevel: ruby2jsConfig.eslevel || overrides.eslevel || 2022,
    database: database || 'dexie',
    target,
    broadcast: overrides.broadcast || ruby2jsConfig.broadcast,
    external,
    base
  };
}

/**
 * Create the Juntos Vite preset.
 *
 * @param {JuntosOptions} options
 * @returns {import('vite').Plugin[]}
 */
export function juntos(options = {}) {
  const {
    database,
    target,
    broadcast,
    appRoot: appRootOption = process.cwd(),
    hmr = true,
    eslevel = 2022,
    external,
    ...ruby2jsOptions
  } = options;

  // Resolve appRoot to absolute path to avoid path resolution issues
  const appRoot = path.resolve(appRootOption);

  // Load and merge configuration (external comes from ruby2js.yml or options)
  const config = loadConfig(appRoot, { database, target, broadcast, eslevel, external });

  return [
    // Generate .browser/index.html and main.js for browser targets
    createBrowserEntryPlugin(config, appRoot),

    // Virtual modules (juntos:rails, juntos:active-record)
    // Eliminates need for .juntos/lib/ directory
    createVirtualPlugin(config, appRoot),

    // JSX.rb file handling (Ruby + JSX)
    createJsxRbPlugin(config),

    // ERB file handling (server-rendered templates as JS modules)
    createErbPlugin(config),

    // On-the-fly Ruby transformation (models, controllers, routes, migrations, seeds)
    createRubyTransformPlugin(config, appRoot),

    // Structural transforms (routes, migrations, seeds)
    createStructurePlugin(config, appRoot),

    // Platform-specific Vite configuration (includes external from ruby2js.yml)
    createConfigPlugin(config, appRoot),

    // HMR support for Stimulus controllers
    ...(hmr ? [createHmrPlugin()] : [])
  ];
}

/**
 * JSX.rb plugin for Ruby + JSX files.
 */
function createJsxRbPlugin(config) {
  // Import convert function dynamically
  let convert, initPrism;
  let prismReady = false;

  return {
    name: 'juntos-jsx-rb',

    async buildStart() {
      // Lazy import ruby2js
      if (!convert) {
        const ruby2jsModule = await import('ruby2js');
        convert = ruby2jsModule.convert;
        initPrism = ruby2jsModule.initPrism;
      }
      if (!prismReady) {
        await initPrism();
        prismReady = true;
      }
    },

    async transform(code, id) {
      if (!id.endsWith('.jsx.rb')) return null;

      // Ensure Prism is ready
      if (!prismReady && initPrism) {
        await initPrism();
        prismReady = true;
      }

      try {
        const result = convert(code, {
          filters: ['React', 'Functions', 'ESM', 'Return'],
          eslevel: config.eslevel,
          autoexports: 'default',
          file: id
        });

        const js = result.toString();
        const map = result.sourcemap;

        if (map) {
          map.sources = [id];
          map.sourcesContent = [code];
        }

        return { code: js, map };
      } catch (error) {
        const enhancedError = new Error(
          `Juntos JSX.rb transform error in ${id}: ${error.message}`
        );
        enhancedError.id = id;
        enhancedError.plugin = 'juntos-jsx-rb';
        throw enhancedError;
      }
    }
  };
}

/**
 * ERB plugin for Rails ERB templates.
 * Compiles ERB → Ruby → JavaScript with HMR support.
 */
function createErbPlugin(config) {
  let convert, initPrism;
  let prismReady = false;

  async function ensureReady() {
    if (!convert) {
      const ruby2jsModule = await import('ruby2js');
      convert = ruby2jsModule.convert;
      initPrism = ruby2jsModule.initPrism;

      // Import ERB filters AFTER ruby2js module to ensure they register correctly
      await import('ruby2js/filters/erb.js');
      await import('ruby2js/filters/rails/helpers.js');
    }
    if (!prismReady && initPrism) {
      await initPrism();
      prismReady = true;
    }
  }

  async function transformErb(code, id, isLayout = false) {
    await ensureReady();

    console.log('[juntos-erb] Transforming:', id);

    let template = code;

    // For layouts, replace yield with content/contentFor
    // yield becomes content, yield :section becomes context.contentFor.section
    if (isLayout) {
      // <%= yield :head %> -> <%= context.contentFor.head || '' %>
      template = template.replace(/<%=\s*yield\s+:(\w+)\s*%>/g, (_, section) =>
        `<%= context.contentFor.${section} || '' %>`
      );
      // <%= yield %> -> <%= content %>
      template = template.replace(/<%=\s*yield\s*%>/g, '<%= content %>');
    }

    // Step 1: Compile ERB to Ruby
    const compiler = new ErbCompiler(template);
    const rubySrc = compiler.src;

    // Step 2: Convert Ruby to JavaScript with ERB filters
    // Note: Rails_Helpers must come before Erb for method overrides
    const options = {
      filters: ['Rails_Helpers', 'Erb', 'Functions', 'Return'],
      eslevel: config.eslevel,
      include: ['class', 'call'],
      database: config.database,
      target: config.target,
      file: id
    };

    // Layout mode changes the function signature to layout(context, content)
    if (isLayout) {
      options.layout = true;
    }

    const result = convert(rubySrc, options);

    // Step 3: Export the function
    // For layouts: export function layout(context, content)
    // For views: export function render(context)
    let js = result.toString();
    if (isLayout) {
      js = js.replace(/(^|\n)(async )?function layout/, '$1export $2function layout');
    } else {
      js = js.replace(/(^|\n)(async )?function render/, '$1export $2function render');
    }

    // Step 3.5: Fix import paths for Vite-native structure
    // The selfhost converter generates relative paths assuming .juntos/ structure
    // We redirect everything to virtual modules and source files

    // Paths: ../../../config/paths.js → config/routes.rb (paths exported from routes)
    js = js.replace(/from ["']\.\.\/\.\.\/\.\.\/config\/paths\.js["']/g, 'from "config/routes.rb"');

    // Rails runtime: use virtual module
    js = js.replace(/from ["']\.\.\/\.\.\/\.\.\/lib\/rails\.js["']/g, 'from "juntos:rails"');
    js = js.replace(/from ["']lib\/rails\.js["']/g, 'from "juntos:rails"');

    // Fix partial imports: _./_partial.js -> ./_partial.html.erb
    // Partials are source files that Vite will transform on-the-fly
    js = js.replace(/from ["'](\.\/_\w+)\.js["']/g, 'from "$1.html.erb"');

    // Fix cross-directory partial imports: ../comments/_comment.js -> @views/comments/_comment.html.erb
    js = js.replace(/from ["']\.\.\/(\w+)\/(\_\w+)\.js["']/g, 'from "@views/$1/$2.html.erb"');

    // Fix view module imports: import { PhotoViews } from "../photos.js" -> from "juntos:views/photos"
    // The helpers filter generates these for turbo_stream shorthand: turbo_stream.prepend "photos", @photo
    // Match pattern: import { <Name>Views } from "../<resource>.js"
    js = js.replace(/import\s*\{\s*(\w+)Views\s*\}\s*from\s*["']\.\.\/(\w+)\.js["']/g,
      (match, name, plural) => `import { ${name}Views } from "juntos:views/${plural}"`);

    // Fix model imports from views: ../photos.js -> app/models/photo.rb
    // Views import models like Photo from "../photos.js" (plural, relative up)
    // These should resolve to app/models/<singular>.rb
    // Note: This runs AFTER view module replacement, so it won't affect *Views imports
    js = js.replace(/from ["']\.\.\/(\w+)\.js["']/g, (match, plural) => {
      const singular = singularize(plural);
      return `from "app/models/${singular}.rb"`;
    });

    // Step 4: Generate source map pointing to original ERB
    const map = result.sourcemap;
    if (map) {
      map.sources = [id];
      map.sourcesContent = [code];
    }

    return { code: js, map };
  }

  return {
    name: 'juntos-erb',
    enforce: 'pre',  // Run before other plugins

    async buildStart() {
      await ensureReady();
    },

    // Use load hook to handle .erb files as JavaScript modules
    async load(id) {
      if (!id.endsWith('.erb')) return null;

      // Detect layout files - they need special handling (yield -> content)
      const isLayout = id.includes('/layouts/');
      if (isLayout) {
        console.log('[juntos-erb] Transforming layout:', id);
      }

      try {
        // Read the file content
        const code = await fs.promises.readFile(id, 'utf-8');
        return await transformErb(code, id, isLayout);
      } catch (error) {
        const errorMsg = error?.message || error?.toString?.() || String(error);
        console.error('[juntos-erb] Transform error details:', error);
        throw new Error(`Juntos ERB transform error in ${id}: ${errorMsg}`);
      }
    },

  };
}

/**
 * Ruby transformation plugin - transforms ALL .rb files on-the-fly.
 *
 * This is the core Vite-native plugin that eliminates the need for
 * a .juntos/ staging directory. All Ruby files are transformed
 * on-the-fly when imported.
 *
 * Handles:
 * - app/models/*.rb → JS classes
 * - app/controllers/*.rb → JS modules
 * - config/routes.rb → routes + paths
 * - db/migrate/*.rb → migrations
 * - db/seeds.rb → seeds
 *
 * Virtual modules:
 * - juntos:models → model registry (imports all models)
 * - juntos:migrations → migration registry
 * - juntos:application-record → ApplicationRecord base class
 */
function createRubyTransformPlugin(config, appRoot) {
  // Ruby2JS converter and initialization
  let convert, initPrism;
  let prismReady = false;

  async function ensureReady() {
    if (!convert) {
      const ruby2jsModule = await import('ruby2js');
      convert = ruby2jsModule.convert;
      initPrism = ruby2jsModule.initPrism;

      // Import Rails filters
      await import('ruby2js/filters/rails/model.js');
      await import('ruby2js/filters/rails/controller.js');
      await import('ruby2js/filters/rails/routes.js');
      await import('ruby2js/filters/rails/seeds.js');
      await import('ruby2js/filters/rails/migration.js');
      await import('ruby2js/filters/functions.js');
      await import('ruby2js/filters/esm.js');
      await import('ruby2js/filters/return.js');
    }
    if (!prismReady && initPrism) {
      await initPrism();
      prismReady = true;
    }
  }

  // Cache for transformed files
  const transformCache = new Map();

  // Find all model files
  function findModels() {
    const modelsDir = path.join(appRoot, 'app/models');
    if (!fs.existsSync(modelsDir)) return [];
    return fs.readdirSync(modelsDir)
      .filter(f => f.endsWith('.rb') && f !== 'application_record.rb' && !f.startsWith('._'))
      .map(f => f.replace('.rb', ''));
  }

  // Find all migration files
  function findMigrations() {
    const migrateDir = path.join(appRoot, 'db/migrate');
    if (!fs.existsSync(migrateDir)) return [];
    return fs.readdirSync(migrateDir)
      .filter(f => f.endsWith('.rb') && !f.startsWith('._'))
      .sort()
      .map(f => ({ file: f, name: f.replace('.rb', '') }));
  }

  // Find all view directories (for unified view modules)
  function findViewResources() {
    const viewsDir = path.join(appRoot, 'app/views');
    if (!fs.existsSync(viewsDir)) return [];
    return fs.readdirSync(viewsDir, { withFileTypes: true })
      .filter(d => d.isDirectory() && d.name !== 'layouts' && !d.name.startsWith('.'))
      .map(d => d.name);
  }

  // Transform Ruby source to JS
  async function transformRuby(source, filePath, section = null) {
    await ensureReady();
    const options = {
      ...getBuildOptions(section, config.target),
      file: path.relative(appRoot, filePath),
      database: config.database,
      target: config.target
    };
    return convert(source, options);
  }

  // Fix imports in transpiled code to use virtual modules and source files
  function fixImports(js, fromFile) {
    // Virtual modules for runtime
    js = js.replace(/from ['"]\.\.\/lib\/rails\.js['"]/g, "from 'juntos:rails'");
    js = js.replace(/from ['"]\.\.\/\.\.\/lib\/rails\.js['"]/g, "from 'juntos:rails'");
    js = js.replace(/from ['"]\.\.\/\.\.\/\.\.\/lib\/rails\.js['"]/g, "from 'juntos:rails'");
    js = js.replace(/from ['"]\.\.\/lib\/active_record\.mjs['"]/g, "from 'juntos:active-record'");
    js = js.replace(/from ['"]\.\.\/\.\.\/lib\/active_record\.mjs['"]/g, "from 'juntos:active-record'");

    // ApplicationRecord → virtual module
    js = js.replace(/from ['"]\.\/application_record\.js['"]/g, "from 'juntos:application-record'");

    // Model imports: .js → .rb (same directory)
    js = js.replace(/from ['"]\.\/(\w+)\.js['"]/g, (match, name) => {
      if (name === 'application_record') return "from 'juntos:application-record'";
      return `from './${name}.rb'`;
    });

    // Model imports from controllers: ../models/*.js → ../models/*.rb
    js = js.replace(/from ['"]\.\.\/models\/(\w+)\.js['"]/g, "from '../models/$1.rb'");

    // Views: ../views/*.js → juntos:views/*
    js = js.replace(/from ['"]\.\.\/views\/(\w+)\.js['"]/g, "from 'juntos:views/$1'");
    js = js.replace(/from ['"]\.\.\/views\/(\w+)\/([\w_]+)\.js['"]/g, "from 'app/views/$1/$2.html.erb'");

    // Config: ../../config/paths.js → juntos:paths (inline in routes)
    js = js.replace(/from ['"]\.\.\/\.\.\/config\/paths\.js['"]/g, "from 'config/routes.rb'");
    js = js.replace(/from ['"]\.\/paths\.js['"]/g, "from 'config/routes.rb'");

    // Controllers: ../app/controllers/*.js → app/controllers/*.rb
    js = js.replace(/from ['"]\.\.\/app\/controllers\/(\w+)\.js['"]/g, "from 'app/controllers/$1.rb'");

    // Migrations: ../db/migrate/index.js → juntos:migrations
    js = js.replace(/from ['"]\.\.\/db\/migrate\/index\.js['"]/g, "from 'juntos:migrations'");

    // Seeds: ../db/seeds.js → db/seeds.rb
    js = js.replace(/from ['"]\.\.\/db\/seeds\.js['"]/g, "from 'db/seeds.rb'");

    // Models index: ../app/models/index.js → juntos:models
    js = js.replace(/from ['"]\.\.\/app\/models\/index\.js['"]/g, "from 'juntos:models'");
    js = js.replace(/from ['"]\.\/index\.js['"]/g, (match) => {
      // Only apply if we're in models directory
      if (fromFile.includes('/models/')) return "from 'juntos:models'";
      return match;
    });

    // Layout: ../app/views/layouts/application.js → app/views/layouts/application.html.erb
    js = js.replace(/from ['"]\.\.\/app\/views\/layouts\/application\.js['"]/g,
      "from 'app/views/layouts/application.html.erb'");

    return js;
  }

  return {
    name: 'juntos-ruby',
    enforce: 'pre',

    // Resolve virtual modules and source file imports
    resolveId(source, importer) {
      // Virtual modules
      if (source === 'juntos:application-record') return '\0juntos:application-record';
      if (source === 'juntos:models') return '\0juntos:models';
      if (source === 'juntos:migrations') return '\0juntos:migrations';
      if (source.startsWith('juntos:views/')) return '\0' + source;

      // Resolve source .rb files from any importer
      if (source.endsWith('.rb')) {
        // Absolute-style imports: app/controllers/foo.rb, config/routes.rb, db/seeds.rb
        if (!source.startsWith('.') && !source.startsWith('/')) {
          const absPath = path.join(appRoot, source);
          if (fs.existsSync(absPath)) return absPath;
        }
      }

      // Resolve .erb files for views (both .html.erb and .turbo_stream.erb)
      if (source.endsWith('.erb')) {
        if (!source.startsWith('.') && !source.startsWith('/')) {
          const absPath = path.join(appRoot, source);
          if (fs.existsSync(absPath)) return absPath;
        }
      }

      return null;
    },

    // Load virtual modules and transform Ruby files
    async load(id) {
      // Virtual module: juntos:application-record
      // Re-exports everything from active-record plus ApplicationRecord class
      if (id === '\0juntos:application-record') {
        return `
import { ActiveRecord } from 'juntos:active-record';
export * from 'juntos:active-record';
export class ApplicationRecord extends ActiveRecord {}
`;
      }

      // Virtual module: juntos:models (registry of all models)
      // Registers models with both Application and the adapter's modelRegistry
      if (id === '\0juntos:models') {
        const models = findModels();
        const imports = models.map(m => {
          const className = m.split('_').map(s => s[0].toUpperCase() + s.slice(1)).join('');
          return `import { ${className} } from 'app/models/${m}.rb';`;
        });
        const classNames = models.map(m =>
          m.split('_').map(s => s[0].toUpperCase() + s.slice(1)).join('')
        );
        return `${imports.join('\n')}
import { Application } from 'juntos:rails';
import { modelRegistry } from 'juntos:active-record';
const models = { ${classNames.join(', ')} };
Application.registerModels(models);
Object.assign(modelRegistry, models);
export { ${classNames.join(', ')} };
`;
      }

      // Virtual module: juntos:migrations (registry of all migrations)
      // Migration filter transforms class to { up: async () => {...}, tableSchemas: {...} }
      if (id === '\0juntos:migrations') {
        const migrations = findMigrations();
        // Import the migration object from each file (filter exports 'migration' constant)
        const imports = migrations.map((m, i) =>
          `import { migration as migration${i} } from 'db/migrate/${m.file}';`
        );
        // Build migration registry entries
        const exports = migrations.map((m, i) =>
          `{ version: '${m.name.split('_')[0]}', name: '${m.name}', ...migration${i} }`
        );
        return `${imports.join('\n')}
export const migrations = [${exports.join(', ')}];
`;
      }

      // Virtual module: juntos:views/* (unified view modules)
      // Exports a namespace object like `ArticleViews` with methods for each view
      if (id.startsWith('\0juntos:views/')) {
        const resource = id.replace('\0juntos:views/', '');

        // JS reserved words that can't be used as identifiers
        const RESERVED = new Set(['new', 'delete', 'class', 'function', 'return', 'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'break', 'continue', 'default', 'var', 'let', 'const', 'import', 'export', 'try', 'catch', 'finally', 'throw', 'typeof', 'instanceof', 'in', 'of', 'with', 'yield', 'await', 'async', 'static', 'super', 'this', 'null', 'true', 'false', 'void']);

        // Handle Turbo Streams: juntos:views/messages_turbo_streams
        // These aggregate *.turbo_stream.erb files from app/views/messages/
        if (resource.endsWith('_turbo_streams')) {
          const plural = resource.replace('_turbo_streams', '');
          const singular = singularize(plural);
          const viewsDir = path.join(appRoot, 'app/views', plural);

          if (!fs.existsSync(viewsDir)) {
            const className = capitalize(singular) + 'TurboStreams';
            return `export const ${className} = {};`;
          }

          const turboViews = fs.readdirSync(viewsDir)
            .filter(f => f.endsWith('.turbo_stream.erb') && !f.startsWith('._'))
            .map(f => {
              // create.turbo_stream.erb → create
              const name = f.replace('.turbo_stream.erb', '');
              let exportName = name;
              // Escape reserved words by adding $ prefix (matches Ruby2JS convention)
              if (RESERVED.has(exportName)) exportName = '$' + exportName;
              return { file: f, name, exportName };
            });

          const imports = turboViews.map(v =>
            `import { render as ${v.exportName}_render } from 'app/views/${plural}/${v.file}';`
          );

          // Create namespace object: MessageTurboStreams = { create: create_render, destroy: destroy_render }
          const className = capitalize(singular) + 'TurboStreams';
          const members = turboViews.map(v => `${v.exportName}: ${v.exportName}_render`);

          return `// ${className} - auto-generated from .turbo_stream.erb templates
${imports.join('\n')}
export const ${className} = { ${members.join(', ')} };
`;
        }

        // Regular views: juntos:views/articles
        const viewsDir = path.join(appRoot, 'app/views', resource);
        if (!fs.existsSync(viewsDir)) return `export const ${capitalize(resource)}Views = {};`;

        const views = fs.readdirSync(viewsDir)
          .filter(f => f.endsWith('.html.erb') && !f.startsWith('._'))
          .map(f => {
            const name = f.replace('.html.erb', '');
            const isPartial = name.startsWith('_');
            let exportName = isPartial ? name.slice(1) : name;
            // Escape reserved words by adding $ prefix (matches Ruby2JS convention)
            if (RESERVED.has(exportName)) exportName = '$' + exportName;
            return { file: f, name, exportName, isPartial };
          });

        const imports = views.map(v =>
          `import { render as ${v.exportName} } from 'app/views/${resource}/${v.file}';`
        );

        // Create namespace object: ArticleViews = { index, show, new_, edit, ... }
        // Use singularized form to match controller filter (ArticleViews, not ArticlesViews)
        const className = capitalize(singularize(resource)) + 'Views';
        const members = views.map(v => v.exportName);

        return `${imports.join('\n')}
export const ${className} = { ${members.join(', ')} };
export { ${members.join(', ')} };
`;
      }

      // Intercept app/javascript/controllers/index.js - generate Vite-compatible controller loading
      // Rails' index.js uses @hotwired/stimulus-loading (importmap-only), so we replace it
      // with import.meta.glob which works with Vite and supports both .js and .rb controllers
      if (id.endsWith('/app/javascript/controllers/index.js')) {
        return `import { Application } from "@hotwired/stimulus";

const application = Application.start();

// Import all controllers (both .js and .rb - Vite transforms .rb on the fly)
const controllers = import.meta.glob([
  './*_controller.js',
  './*_controller.rb'
], { eager: true });

for (const [path, module] of Object.entries(controllers)) {
  // Extract controller name: ./hello_controller.js -> hello
  const match = path.match(/\\.\\/(.+)_controller/);
  if (match) {
    const identifier = match[1].replace(/_/g, '-');
    application.register(identifier, module.default);
  }
}

export { application };
`;
      }

      // Transform Ruby source files
      if (!id.endsWith('.rb')) return null;
      if (id.includes('/node_modules/')) return null;

      // Skip base classes that don't need transformation
      const basename = path.basename(id);
      if (basename === 'application_record.rb' || basename === 'application_controller.rb') {
        return null;
      }

      // Check cache
      let stat;
      try {
        stat = fs.statSync(id);
      } catch {
        return null;
      }
      const cached = transformCache.get(id);
      if (cached && cached.mtime >= stat.mtimeMs) {
        return cached.result;
      }

      try {
        const source = await fs.promises.readFile(id, 'utf-8');
        let section = null;

        // Determine transformation section
        if (id.includes('/app/javascript/controllers/')) section = 'stimulus';
        else if (id.includes('/app/controllers/')) section = 'controllers';
        else if (id.includes('/db/migrate/')) section = null; // Migrations use default options
        else if (id.endsWith('/routes.rb')) section = null; // Routes use default with special options

        // Special handling for routes.rb - include paths inline
        let result;
        if (id.endsWith('/routes.rb')) {
          await ensureReady();
          const options = {
            ...getBuildOptions(null, config.target),
            file: path.relative(appRoot, id),
            database: config.database,
            target: config.target,
            // Don't use paths_file - export paths inline
            base: config.base || '/'
          };
          result = convert(source, options);
        } else {
          result = await transformRuby(source, id, section);
        }

        let js = result.toString();
        js = fixImports(js, id);

        // For routes.rb, re-export database functions from the bundled adapter
        // This allows migrate.mjs and server.mjs to use the same adapter instance
        // - initDatabase, closeDatabase: connection management
        // - query, execute, insert: general database operations
        // - createTable, addIndex, addColumn, removeColumn, dropTable: migration operations
        if (id.endsWith('/routes.rb')) {
          js += '\nexport { initDatabase, query, execute, insert, closeDatabase, createTable, addIndex, addColumn, removeColumn, dropTable } from "juntos:active-record";\n';
        }

        // Normalize sourcemap for Vite bundling
        // Use absolute path for sources - Vite will normalize to correct relative paths
        // Using relative paths from appRoot causes duplication when Vite resolves them
        // relative to the file's directory location
        const map = result.sourcemap;
        if (map) {
          // Use absolute path - Vite normalizes this correctly during bundle
          map.file = path.basename(id).replace('.rb', '.js');
          map.sources = [id];  // Absolute path
          map.sourceRoot = '';
          // Embed source content so browsers don't need to fetch it
          map.sourcesContent = [source];
        }

        // Cache and return
        const output = { code: js, map };
        transformCache.set(id, { result: output, mtime: stat.mtimeMs });

        console.log(`[juntos] Transformed: ${path.relative(appRoot, id)}`);
        return output;
      } catch (error) {
        console.error(`[juntos] Transform error in ${id}:`, error);
        throw error;
      }
    }
  };
}

/**
 * Structure plugin - minimal plugin for Vite-native approach.
 *
 * Everything is virtual or on-the-fly:
 * - Routes: config/routes.rb
 * - Models: app/models/*.rb
 * - Controllers: app/controllers/*.rb
 * - Views: app/views/ (nested .html.erb files)
 * - Migrations: db/migrate/*.rb
 * - Seeds: db/seeds.rb
 *
 * Virtual modules:
 * - juntos:rails, juntos:active-record
 * - juntos:models, juntos:migrations
 * - juntos:views/*, juntos:application-record
 *
 * No .juntos/ directory is generated.
 */
function createStructurePlugin(config, appRoot) {
  return {
    name: 'juntos-structure',

    async buildStart() {
      // Log configuration
      const database = config.database || 'dexie';
      const target = config.target || 'browser';
      console.log(`[juntos] Vite-native mode: database=${database}, target=${target}`);
      console.log('[juntos] All Ruby files transformed on-the-fly');
    },

    // Watch source files for HMR
    configureServer(server) {
      const watchDirs = [
        path.join(appRoot, 'config'),
        path.join(appRoot, 'app'),
        path.join(appRoot, 'db')
      ];

      for (const dir of watchDirs) {
        if (fs.existsSync(dir)) {
          server.watcher.add(dir);
        }
      }

      console.log(`[juntos] Watching source files in ${appRoot}`);
    },

    // For server builds, symlink node_modules for runtime resolution
    async closeBundle() {
      if (!isServerTarget(config.target)) return;

      const distDir = path.join(appRoot, 'dist');
      const nodeModulesLink = path.join(distDir, 'node_modules');
      const nodeModulesTarget = path.join(appRoot, 'node_modules');

      try {
        await fs.promises.unlink(nodeModulesLink).catch(() => {});
        await fs.promises.symlink(nodeModulesTarget, nodeModulesLink, 'junction');
        console.log('[juntos] Linked node_modules to dist/');
      } catch (e) {
        console.warn('[juntos] Could not create node_modules symlink:', e.message);
      }
    }
  };
}

/**
 * Config plugin - platform-specific Vite/Rollup configuration.
 *
 * New Vite-native structure:
 * - vite.config.js at project root
 * - node_modules at project root
 * - Source in app/ (transformed on-the-fly)
 * - Generated files in .juntos/
 * - Build output to dist/
 */
function createConfigPlugin(config, appRoot) {
  return {
    name: 'juntos-config',
    enforce: 'post',  // Run after other plugins to ensure our config takes precedence

    config(userConfig, { command }) {
      const aliases = {
        // Source directories (transformed on-the-fly by Vite plugins)
        '@controllers': path.join(appRoot, 'app/javascript/controllers'),
        '@models': path.join(appRoot, 'app/models'),
        '@views': path.join(appRoot, 'app/views'),
        'components': path.join(appRoot, 'app/components'),

        // Config aliases (used by rails/helpers filter for ERB transforms)
        // @config/paths.js exports path helpers (e.g., articles_path)
        '@config/paths.js': path.join(appRoot, 'config/routes.rb'),

        // Alias for Rails importmap-style imports in Stimulus controllers
        'controllers/application': path.join(appRoot, 'app/javascript/controllers/application.js'),

        // node_modules is now at appRoot (standard Vite structure)
        // No aliases needed - Vite resolves these automatically

        // NOTE: lib/ aliases removed - now using virtual modules:
        // - juntos:rails - target-specific runtime
        // - juntos:active-record - database adapter
        // - juntos:active-record-client - RPC adapter for browser in server builds
      };

      const rollupOptions = getRollupOptions(config.target, config.database);
      const buildTarget = getBuildTarget(config.target);

      // Add external patterns from config (e.g., from ruby2js.yml)
      // Merge with any user-provided external function
      if (config.external && config.external.length > 0) {
        const juntosExternal = createExternalMatcher(config.external);
        const userExternal = userConfig?.build?.rollupOptions?.external;

        if (typeof userExternal === 'function') {
          // Combine user and juntos external functions
          rollupOptions.external = (id, ...args) =>
            juntosExternal(id) || userExternal(id, ...args);
        } else if (Array.isArray(userExternal)) {
          // Combine user array with juntos function
          rollupOptions.external = (id, ...args) =>
            juntosExternal(id) || userExternal.includes(id);
        } else {
          rollupOptions.external = juntosExternal;
        }
      }

      // Vite-native structure: config at root, output to dist/
      return {
        build: {
          target: buildTarget,
          outDir: 'dist',
          emptyOutDir: true, // Clean dist/ on each build
          minify: false, // Disable minification for debugging
          sourcemap: true, // Enable sourcemaps for debugging
          rollupOptions
        },
        resolve: {
          alias: aliases,
          // Add Ruby extensions for auto-resolution
          extensions: ['.mjs', '.js', '.mts', '.ts', '.jsx', '.tsx', '.json', '.jsx.rb', '.rb'],
          // Ensure these packages resolve from the app's node_modules, not from the package
          // (browser rails.js has dynamic imports for optional React and database adapters)
          dedupe: ['react', 'react-dom', 'dexie', 'better-sqlite3', '@neondatabase/serverless', '@libsql/client']
        },
        // Ensure react/react-dom are pre-bundled in dev
        optimizeDeps: {
          include: ['react', 'react-dom', 'react-dom/client']
        },
        // publicDir is public/ by default, which is correct
      };
    },

    // Flatten .browser/ output to dist root for browser targets
    async closeBundle() {
      const browserTargets = ['browser', 'pwa', 'capacitor', 'electron', 'tauri'];
      if (!browserTargets.includes(config.target)) return;

      const distDir = path.join(appRoot, 'dist');
      const browserOutDir = path.join(distDir, '.browser');

      if (!fs.existsSync(browserOutDir)) return;

      // Move all files from dist/.browser/ to dist/
      const files = await fs.promises.readdir(browserOutDir);
      for (const file of files) {
        const src = path.join(browserOutDir, file);
        const dest = path.join(distDir, file);
        await fs.promises.rename(src, dest);
      }

      // Remove the empty .browser/ directory
      await fs.promises.rmdir(browserOutDir);
      console.log('[juntos] Flattened .browser/ output to dist/');
    }
  };
}

/**
 * Create an external matcher function from patterns.
 *
 * @param {string[]} patterns - Module patterns to externalize
 *   - Exact match: 'lodash' matches only 'lodash'
 *   - Wildcard: '@capacitor/*' matches '@capacitor/camera', '@capacitor/filesystem', etc.
 * @returns {Function} Matcher function for rollupOptions.external
 */
function createExternalMatcher(patterns) {
  // Convert patterns to matchers
  const matchers = patterns.map(pattern => {
    if (pattern.endsWith('/*')) {
      // Wildcard pattern: '@capacitor/*' -> matches '@capacitor/anything'
      const prefix = pattern.slice(0, -1); // Remove the '*', keep the '/'
      return (id) => id.startsWith(prefix);
    }
    // Exact match
    return (id) => id === pattern;
  });

  return (id) => matchers.some(matcher => matcher(id));
}

/**
 * Server-side JavaScript runtimes (must match builder.rb SERVER_RUNTIMES)
 */
const SERVER_RUNTIMES = ['node', 'bun', 'deno', 'cloudflare', 'vercel-edge', 'vercel-node', 'deno-deploy', 'fly'];

/**
 * Check if target is a server runtime (requires RPC for client-side model access)
 */
function isServerTarget(target) {
  return SERVER_RUNTIMES.includes(target);
}

/**
 * Get Vite build target based on platform.
 */
function getBuildTarget(target) {
  switch (target) {
    case 'node':
    case 'fly':
      return 'node18';
    case 'bun':
      return 'node18'; // Bun is Node-compatible
    case 'deno':
      return 'esnext';
    case 'cloudflare':
    case 'vercel-edge':
    case 'deno-deploy':
      return 'esnext'; // Edge runtimes support modern JS
    default:
      return undefined; // Use Vite's default browser targets
  }
}

/**
 * Get Rollup options based on target platform.
 */
function getRollupOptions(target, database) {
  switch (target) {
    case 'browser':
    case 'pwa':
    case 'capacitor':
      return {
        input: '.browser/index.html'
      };

    case 'electron':
      return {
        input: {
          main: 'main.js',
          preload: 'preload.js',
          renderer: '.browser/index.html'
        },
        external: ['electron', 'better-sqlite3', 'path', 'fs', 'url']
      };

    case 'tauri':
      return {
        input: '.browser/index.html',
        external: ['@tauri-apps/api']
      };

    case 'node':
    case 'bun':
    case 'deno':
      return {
        input: {
          index: 'node_modules/ruby2js-rails/server.mjs',
          'config/routes': 'config/routes.rb'
        },
        external: getNativeModules(database),
        output: {
          entryFileNames: '[name].js'
        },
        preserveEntrySignatures: 'allow-extension'
      };

    case 'vercel':
    case 'vercel-edge':
    case 'vercel-node':
      return {
        input: 'api/[[...path]].js'
      };

    case 'cloudflare':
      return {
        input: 'src/index.js',
        external: ['__STATIC_CONTENT_MANIFEST'],
        output: {
          entryFileNames: 'worker.js'
        }
      };

    case 'deno-deploy':
      return {
        input: 'main.ts'
      };

    case 'fly':
      return {
        input: 'node_modules/ruby2js-rails/server.mjs',
        external: getNativeModules(database),
        output: {
          entryFileNames: 'index.js'
        }
      };

    default:
      return {
        input: '.browser/index.html'
      };
  }
}

/**
 * Get native modules to externalize based on database adapter.
 */
function getNativeModules(database) {
  // Node.js built-in modules (both with and without node: prefix)
  const nodeBuiltins = ['path', 'fs', 'url', 'crypto', 'http', 'https', 'net', 'tls', 'stream', 'buffer', 'util', 'os', 'string_decoder', 'fs/promises'];
  const baseModules = [
    ...nodeBuiltins,
    ...nodeBuiltins.map(m => `node:${m}`)
  ];

  const dbModules = {
    pg: ['pg', 'pg-native'],
    mysql2: ['mysql2'],
    sqlite: ['better-sqlite3'],
    better_sqlite3: ['better-sqlite3'],
    neon: ['@neondatabase/serverless'],
    turso: ['@libsql/client'],
    d1: []
  };

  // Client-side framework modules that should not be bundled in server builds
  const clientModules = ['@hotwired/stimulus', '@hotwired/turbo', '@hotwired/turbo-rails'];

  // React modules - externalize for SSR (resolved at runtime)
  const reactModules = ['react', 'react-dom', 'react-dom/server', 'react-dom/client'];

  return [...baseModules, ...(dbModules[database] || []), ...clientModules, ...reactModules];
}

/**
 * Browser entry plugin - generates .browser/index.html and main.js for browser targets.
 *
 * This plugin creates entry points for SPA builds only when needed (browser, pwa, capacitor).
 * Files are generated in .browser/ to avoid conflicts with Rails' public/ directory.
 *
 * For server-side targets (Node, Cloudflare, etc.), no index.html is needed.
 */
function createBrowserEntryPlugin(config, appRoot) {
  const browserTargets = ['browser', 'pwa', 'capacitor', 'electron', 'tauri'];
  const isBrowserTarget = browserTargets.includes(config.target);

  return {
    name: 'juntos-browser-entry',

    async buildStart() {
      // Only generate for browser-like targets
      if (!isBrowserTarget) return;

      const browserDir = path.join(appRoot, '.browser');
      const indexPath = path.join(browserDir, 'index.html');
      const mainPath = path.join(browserDir, 'main.js');

      // Create .browser directory if needed
      if (!fs.existsSync(browserDir)) {
        await fs.promises.mkdir(browserDir, { recursive: true });
        console.log('[juntos] Created .browser/ directory');
      }

      // Generate index.html if it doesn't exist
      if (!fs.existsSync(indexPath)) {
        const appName = detectAppName(appRoot);
        const indexContent = generateIndexHtml(appName);
        await fs.promises.writeFile(indexPath, indexContent);
        console.log('[juntos] Generated .browser/index.html');
      }

      // Generate main.js if it doesn't exist
      if (!fs.existsSync(mainPath)) {
        const mainContent = generateMainJs();
        await fs.promises.writeFile(mainPath, mainContent);
        console.log('[juntos] Generated .browser/main.js');
      }
    }
  };
}

/**
 * Detect app name from config/application.rb or directory name.
 */
function detectAppName(appRoot) {
  const appRb = path.join(appRoot, 'config/application.rb');
  if (fs.existsSync(appRb)) {
    const content = fs.readFileSync(appRb, 'utf8');
    const match = content.match(/module\s+(\w+)/);
    if (match) {
      // Convert CamelCase to Title Case
      return match[1].replace(/([a-z])([A-Z])/g, '$1 $2');
    }
  }
  // Fall back to directory name, capitalize first letter
  const dirName = path.basename(appRoot);
  return dirName.charAt(0).toUpperCase() + dirName.slice(1);
}

/**
 * Generate index.html content for browser builds.
 */
function generateIndexHtml(appName) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${appName}</title>
  <link rel="icon" href="data:,">
  <link href="/app/assets/builds/tailwind.css" rel="stylesheet">
</head>
<body>
  <div id="loading">Loading...</div>
  <div id="app" style="display:none">
    <main class="container mx-auto mt-28 px-5" id="content"></main>
  </div>
  <script type="module" src="./main.js"></script>
</body>
</html>
`;
}

/**
 * Generate main.js content for browser builds.
 * Paths are relative from .browser/ directory.
 */
function generateMainJs() {
  return `// Main entry point for Vite bundling
import * as Turbo from '@hotwired/turbo';
import { Application } from '../config/routes.rb';
import '../app/javascript/controllers/index.js';
window.Turbo = Turbo;
Application.start();
`;
}

/**
 * HMR plugin for Stimulus controllers, views, and structural changes.
 *
 * HMR behavior:
 * - Models, Rails controllers, routes → full reload (structural changes)
 * - Stimulus controllers → hot swap via custom event
 * - ERB views → HMR via juntos-erb transform (imported directly from source)
 * - JSX.rb views → HMR via juntos-jsx-rb transform (imported directly from source)
 * - Plain Ruby → Vite default HMR
 */
function createHmrPlugin() {
  return {
    name: 'juntos-hmr',

    // Watch ERB files even though they're not in the module graph
    configureServer(server) {
      // Add app/views/**/*.erb to Vite's watcher
      server.watcher.add('**/app/views/**/*.erb');
    },

    handleHotUpdate({ file, server, modules }) {
      // Normalize path for matching
      const normalizedFile = file.replace(/\\/g, '/');

      // Models: full reload (associations, dependencies unknown)
      if (normalizedFile.includes('/app/models/') && file.endsWith('.rb')) {
        console.log('[juntos] Model changed, triggering full reload:', file);
        server.ws.send({ type: 'full-reload' });
        return [];
      }

      // Routes: full reload (need full regeneration)
      if (normalizedFile.includes('/config/routes')) {
        console.log('[juntos] Routes changed, triggering full reload:', file);
        server.ws.send({ type: 'full-reload' });
        return [];
      }

      // Rails controllers (app/controllers/): full reload (route handlers)
      if (normalizedFile.includes('/app/controllers/') && file.endsWith('.rb')) {
        console.log('[juntos] Rails controller changed, triggering full reload:', file);
        server.ws.send({ type: 'full-reload' });
        return [];
      }

      // Stimulus controllers (app/javascript/controllers/): hot swap
      if (normalizedFile.includes('/app/javascript/controllers/') &&
          file.match(/_controller(\.jsx)?\.rb$/)) {
        const controllerName = extractControllerName(file);

        server.ws.send({
          type: 'custom',
          event: 'ruby2js:stimulus-update',
          data: {
            file,
            controller: controllerName
          }
        });

        console.log('[juntos] Hot updating Stimulus controller:', controllerName);
        return modules;
      }

      // ERB views: now imported directly, Vite handles HMR via juntos-erb transform
      if (file.endsWith('.erb') && normalizedFile.includes('/app/views/')) {
        console.log('[juntos] Hot updating ERB view:', file);
        return modules;
      }

      // JSX.rb views: now imported directly, Vite handles HMR via juntos-jsx-rb transform
      if (file.endsWith('.jsx.rb') && normalizedFile.includes('/app/views/')) {
        console.log('[juntos] Hot updating JSX.rb view:', file);
        return modules;
      }

      // Plain Ruby files: let Vite handle HMR
      // (default behavior - return undefined to use Vite's module graph)
    },

    transformIndexHtml(html, { server }) {
      // Only inject HMR runtime in dev mode (when server is present)
      if (!server) return html;

      return {
        html,
        tags: [
          {
            tag: 'script',
            attrs: { type: 'module' },
            children: STIMULUS_HMR_RUNTIME,
            injectTo: 'head'
          }
        ]
      };
    }
  };
}

/**
 * Extract controller name from file path.
 * e.g., 'app/javascript/controllers/chat_controller.rb' -> 'chat'
 */
function extractControllerName(filePath) {
  const fileName = filePath.split('/').pop() || '';
  return fileName
    .replace(/_controller(\.jsx)?\.rb$/, '')
    .replace(/_/g, '-');
}

/**
 * HMR runtime script for Stimulus controllers.
 */
const STIMULUS_HMR_RUNTIME = `
if (import.meta.hot) {
  import.meta.hot.on('ruby2js:stimulus-update', async (data) => {
    const { file, controller } = data;

    try {
      // Import the updated module with cache bust
      const timestamp = Date.now();
      const modulePath = file.replace(/(\\.jsx)?\\.rb$/, '.js');
      const newModule = await import(/* @vite-ignore */ modulePath + '?t=' + timestamp);

      // Re-register with Stimulus if available
      if (window.Stimulus && newModule.default) {
        // Unregister existing controller
        const existingController = window.Stimulus.router.modulesByIdentifier.get(controller);
        if (existingController) {
          window.Stimulus.unload(existingController);
        }

        // Register updated controller
        window.Stimulus.register(controller, newModule.default);
        console.log('[juntos] Hot updated Stimulus controller:', controller);
      }
    } catch (error) {
      console.error('[juntos] Failed to hot update controller:', controller, error);
      // Fall back to full reload
      import.meta.hot.invalidate();
    }
  });
}
`;

/**
 * Virtual modules plugin.
 * Provides virtual modules for rails runtime and active record adapter,
 * eliminating the need for .juntos/lib/ directory.
 *
 * Virtual modules:
 * - juntos:rails - Re-exports from target-specific runtime
 * - juntos:active-record - Injects DB_CONFIG and re-exports from adapter
 */
function createVirtualPlugin(config, appRoot) {
  // Map targets/runtimes to target directory names
  const TARGET_DIR_MAP = {
    'browser': 'browser',
    'capacitor': 'capacitor',
    'electron': 'electron',
    'tauri': 'tauri',
    'cloudflare': 'cloudflare',
    'node': 'node',
    'bun': 'bun',
    'deno': 'deno',
    'vercel-edge': 'vercel-edge',
    'vercel-node': 'vercel-node',
    'deno-deploy': 'vercel-edge',  // Deno Deploy uses same runtime as Vercel Edge
    'fly': 'node'  // Fly.io runs Node.js
  };

  // Map database names to adapter file names
  const ADAPTER_FILE_MAP = {
    'dexie': 'active_record_dexie.mjs',
    'sqlite': 'active_record_better_sqlite3.mjs',
    'better_sqlite3': 'active_record_better_sqlite3.mjs',
    'pg': 'active_record_pg.mjs',
    'postgres': 'active_record_pg.mjs',
    'mysql2': 'active_record_mysql2.mjs',
    'neon': 'active_record_neon.mjs',
    'turso': 'active_record_turso.mjs',
    'planetscale': 'active_record_planetscale.mjs',
    'd1': 'active_record_d1.mjs',
    'sqljs': 'active_record_sqljs.mjs',
    'pglite': 'active_record_pglite.mjs',
    'supabase': 'active_record_supabase.mjs'
  };

  const targetDir = TARGET_DIR_MAP[config.target] || 'browser';
  const adapterFile = ADAPTER_FILE_MAP[config.database] || 'active_record_dexie.mjs';

  // Load database config for injection
  const dbConfig = loadDatabaseConfig(appRoot, { quiet: true }) || {};
  if (config.database) dbConfig.adapter = config.database;

  return {
    name: 'juntos-virtual',
    enforce: 'pre',

    resolveId(id) {
      if (id === 'juntos:rails') return '\0juntos:rails';
      if (id === 'juntos:active-record') return '\0juntos:active-record';
      if (id === 'juntos:active-record-client') return '\0juntos:active-record-client';
      return null;
    },

    load(id) {
      if (id === '\0juntos:rails') {
        // Re-export from target-specific runtime
        return `export * from 'ruby2js-rails/targets/${targetDir}/rails.js';`;
      }

      if (id === '\0juntos:active-record') {
        // Inject DB_CONFIG and re-export from adapter
        // The adapter expects DB_CONFIG to be defined, but for most databases
        // it prefers runtime environment variables (DATABASE_URL, etc.)
        return `
// Database configuration injected at build time
// Runtime environment variables take precedence
export const DB_CONFIG = ${JSON.stringify(dbConfig)};

export * from 'ruby2js-rails/adapters/${adapterFile}';
`;
      }

      if (id === '\0juntos:active-record-client') {
        // RPC adapter for browser in server-target builds
        return `export * from 'ruby2js-rails/adapters/active_record_rpc.mjs';`;
      }

      return null;
    }
  };
}

export default juntos;
