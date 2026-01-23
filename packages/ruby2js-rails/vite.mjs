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
import ruby2js from 'vite-plugin-ruby2js';
import { SelfhostBuilder } from './build.mjs';

// Import React filter for .jsx.rb files
import 'ruby2js/filters/react.js';

// Import ERB compiler for .erb files
import { ErbCompiler } from './lib/erb_compiler.js';

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
    const dbConfig = SelfhostBuilder.load_database_config(appRoot, { quiet: true });
    database = dbConfig?.adapter || 'dexie';
  }

  // Derive target from env, overrides, config, or database
  // Priority: JUNTOS_TARGET env > overrides > ruby2js.yml > default from database
  const target = process.env.JUNTOS_TARGET ||
                 overrides.target ||
                 ruby2jsConfig.target ||
                 SelfhostBuilder.DEFAULT_TARGETS?.[database] ||
                 'browser';

  // External modules: top-level config, then env-specific, then overrides
  const external = overrides.external ||
                   ruby2jsConfig.external ||
                   topLevelConfig.external ||
                   [];

  // Spread configs first, then override with our calculated values
  // This ensures env vars take precedence over hardcoded vite.config.js values
  return {
    ...ruby2jsConfig,
    ...overrides,
    eslevel: ruby2jsConfig.eslevel || overrides.eslevel || 2022,
    database: database || 'dexie',
    target,
    broadcast: overrides.broadcast || ruby2jsConfig.broadcast,
    external
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
    // Core Ruby transformation with Rails filters
    createRubyPlugin(config, ruby2jsOptions),

    // JSX.rb file handling (Ruby + JSX)
    createJsxRbPlugin(config),

    // ERB file handling (server-rendered templates as JS modules)
    createErbPlugin(config),

    // Structural transforms (models, controllers, views, routes)
    createStructurePlugin(config, appRoot),

    // Platform-specific Vite configuration (includes external from ruby2js.yml)
    createConfigPlugin(config, appRoot),

    // HMR support for Stimulus controllers
    ...(hmr ? [createHmrPlugin()] : [])
  ];
}

/**
 * Core Ruby plugin wrapper with Rails filters.
 */
function createRubyPlugin(config, options) {
  return ruby2js({
    filters: ['Stimulus', 'ESM', 'Functions', 'Return'],
    eslevel: config.eslevel,
    exclude: ['**/*.jsx.rb'], // JSX.rb files handled separately
    ...options
  });
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

  async function transformErb(code, id) {
    await ensureReady();

    console.log('[juntos-erb] Transforming:', id);

    // Step 1: Compile ERB to Ruby
    const compiler = new ErbCompiler(code);
    const rubySrc = compiler.src;

    // Step 2: Convert Ruby to JavaScript with ERB filters
    // Note: Rails_Helpers must come before Erb for method overrides
    const result = convert(rubySrc, {
      filters: ['Rails_Helpers', 'Erb', 'Functions', 'Return'],
      eslevel: config.eslevel,
      include: ['class', 'call'],
      database: config.database,
      target: config.target,
      file: id
    });

    // Step 3: Export the render function
    // Note: Function may not be at start if imports were added by rails/helpers filter
    // Handle both sync and async render functions
    let js = result.toString();
    js = js.replace(/(^|\n)(async )?function render/, '$1export $2function render');

    // Step 3.5: Fix import paths for Vite
    // The selfhost converter generates relative paths for a .juntos/ structure
    // but we're now serving ERB from app/views/, so use aliases instead
    js = js.replace(/from ["']\.\.\/\.\.\/\.\.\/config\/paths\.js["']/g, 'from "@config/paths.js"');
    js = js.replace(/from ["']\.\.\/\.\.\/\.\.\/lib\/rails\.js["']/g, 'from "lib/rails.js"');

    // Fix partial imports: _./_partial.js -> ./_partial.html.erb
    // Partials are source files that Vite will transform on-the-fly
    js = js.replace(/from ["'](\.\/_\w+)\.js["']/g, 'from "$1.html.erb"');

    // Fix cross-directory partial imports: ../comments/_comment.js -> @views/comments/_comment.html.erb
    js = js.replace(/from ["']\.\.\/(\w+)\/(\_\w+)\.js["']/g, 'from "@views/$1/$2.html.erb"');

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

      try {
        // Read the file content
        const code = await fs.promises.readFile(id, 'utf-8');
        return await transformErb(code, id);
      } catch (error) {
        const errorMsg = error?.message || error?.toString?.() || String(error);
        console.error('[juntos-erb] Transform error details:', error);
        throw new Error(`Juntos ERB transform error in ${id}: ${errorMsg}`);
      }
    },

  };
}

/**
 * Structure plugin - generates essential files to .juntos/ directory.
 * Source files (models, controllers, views) are transformed on-the-fly by Vite.
 *
 * Generated files (.juntos/):
 * - routes.js - compiled from config/routes.rb (one-to-many)
 * - lib/ - runtime helpers (rails.js, active_record.mjs, etc.)
 *
 * On-the-fly transformation (via other plugins):
 * - Models - Rails_Model filter
 * - Controllers - Rails_Controller filter
 * - Views - ERB/JSX.rb filters
 * - Stimulus - Stimulus filter
 */
function createStructurePlugin(config, appRoot) {
  const juntosDir = path.join(appRoot, '.juntos');

  // Rebuild routes (generates multiple files)
  async function rebuildRoutes() {
    const originalRoot = SelfhostBuilder.DEMO_ROOT;
    SelfhostBuilder.DEMO_ROOT = appRoot;

    try {
      const builder = new SelfhostBuilder(juntosDir, {
        database: config.database,
        target: config.target,
        broadcast: config.broadcast,
        base: process.env.JUNTOS_BASE
      });
      // Just rebuild routes
      builder.transpile_routes_files();
      console.log(`[juntos] Rebuilt routes`);
    } finally {
      SelfhostBuilder.DEMO_ROOT = originalRoot;
    }
  }

  return {
    name: 'juntos-structure',

    async buildStart() {
      // Ensure .juntos directory exists
      await fs.promises.mkdir(juntosDir, { recursive: true });

      // Set the app root for the builder
      const originalRoot = SelfhostBuilder.DEMO_ROOT;
      SelfhostBuilder.DEMO_ROOT = appRoot;

      try {
        const builder = new SelfhostBuilder(juntosDir, {
          database: config.database,
          target: config.target,
          broadcast: config.broadcast,
          base: process.env.JUNTOS_BASE
        });

        // Only generate essential files - source is transformed on-the-fly
        console.log('[juntos] Generating essential files to .juntos/');

        // These methods need to initialize database/target/runtime first
        // (normally done by build() but we're calling methods directly)
        builder._database = config.database || 'dexie';
        builder._target = config.target || 'browser';

        // Set runtime based on target (mirrors logic in build())
        if (builder._target === 'browser' || builder._target === 'capacitor') {
          builder._runtime = null;
        } else if (builder._target === 'electron') {
          builder._runtime = 'electron';
        } else if (builder._target === 'cloudflare') {
          builder._runtime = 'cloudflare';
        } else {
          builder._runtime = builder._target; // node, bun, deno
        }

        console.log(`[juntos] Config: database=${builder._database}, target=${builder._target}, runtime=${builder._runtime}`);

        // Generate routes (one-to-many transformation)
        builder.transpile_routes_files();

        // Copy lib files (runtime helpers)
        builder.copy_lib_files();

        // Generate database adapter with config
        builder.copy_database_adapter();

        // Setup broadcast adapter if needed
        if (config.broadcast) {
          builder.setup_broadcast_adapter();
        }

        // Generate ApplicationRecord wrapper
        builder.generate_application_record();

        // For now, also generate controllers and views
        // (TODO: Add Rails filters to Vite plugins for on-the-fly transformation)
        const modelsDir = path.join(appRoot, 'app/models');
        const controllersDir = path.join(appRoot, 'app/controllers');
        const viewsDir = path.join(appRoot, 'app/views');

        if (fs.existsSync(modelsDir)) {
          builder.transpile_directory(
            modelsDir,
            path.join(juntosDir, 'app/models'),
            '**/*.rb',
            { skip: ['application_record.rb'] }
          );
        }

        // Generate models index AFTER models are transpiled
        builder.generate_models_index();

        if (fs.existsSync(controllersDir)) {
          builder.transpile_directory(
            controllersDir,
            path.join(juntosDir, 'app/controllers'),
            '**/*.rb',
            { skip: ['application_controller.rb'], section: 'controllers' }
          );
        }

        if (fs.existsSync(viewsDir)) {
          builder.transpile_erb_directory();
          // Server targets need the layout
          if (isServerTarget(config.target)) {
            builder.transpile_layout();
          }
        }

        // Generate migrations and seeds
        const dbSrcDir = path.join(appRoot, 'db');
        const dbDestDir = path.join(juntosDir, 'db');
        if (fs.existsSync(dbSrcDir)) {
          builder.transpile_migrations(dbSrcDir, dbDestDir);
          builder.transpile_seeds(dbSrcDir, dbDestDir);
        }

        console.log('[juntos] Essential files generated');
      } finally {
        // Restore original root
        SelfhostBuilder.DEMO_ROOT = originalRoot;
      }
    },

    // Watch config files for route regeneration
    configureServer(server) {
      // Watch config directory for route changes
      const configDir = path.join(appRoot, 'config');
      if (fs.existsSync(configDir)) {
        server.watcher.add(configDir);
      }

      // Handle route changes
      server.watcher.on('change', async (file) => {
        const relativePath = path.relative(appRoot, file);

        // Route changes need regeneration
        if (relativePath === 'config/routes.rb') {
          console.log(`[juntos] Routes changed, regenerating...`);
          await rebuildRoutes();
        }
      });

      console.log(`[juntos] Watching config files in ${appRoot}`);
    },

    // For server builds, copy essential files to dist/
    async closeBundle() {
      if (!isServerTarget(config.target)) return;

      const distDir = path.join(appRoot, 'dist');
      console.log('[juntos] Copying essential files to dist/ for server build...');

      // Copy .juntos/ structure to dist/
      await copyDirRecursive(juntosDir, distDir);

      // Symlink node_modules into dist/ for package resolution
      const nodeModulesLink = path.join(distDir, 'node_modules');
      const nodeModulesTarget = path.join(appRoot, 'node_modules');
      try {
        await fs.promises.unlink(nodeModulesLink).catch(() => {});
        await fs.promises.symlink(nodeModulesTarget, nodeModulesLink, 'junction');
        console.log('[juntos] Linked node_modules to dist/');
      } catch (e) {
        // Symlink may fail on some systems, copy public folder instead
        console.warn('[juntos] Could not create node_modules symlink:', e.message);
      }

      console.log('[juntos] Server files copied to dist/');
    }
  };
}

/**
 * Recursively copy a directory.
 */
async function copyDirRecursive(src, dest) {
  const entries = await fs.promises.readdir(src, { withFileTypes: true });
  await fs.promises.mkdir(dest, { recursive: true });

  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);

    if (entry.isDirectory()) {
      await copyDirRecursive(srcPath, destPath);
    } else {
      await fs.promises.copyFile(srcPath, destPath);
    }
  }
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
      const juntosDir = path.join(appRoot, '.juntos');

      const aliases = {
        // Source directories (transformed on-the-fly by Vite plugins)
        '@controllers': path.join(appRoot, 'app/javascript/controllers'),
        '@models': path.join(appRoot, 'app/models'),
        '@views': path.join(appRoot, 'app/views'),
        'components': path.join(appRoot, 'app/components'),

        // Generated files in .juntos/
        'lib': path.join(juntosDir, 'lib'),
        '@config': path.join(juntosDir, 'config'),

        // Alias for Rails importmap-style imports in Stimulus controllers
        'controllers/application': path.join(appRoot, 'app/javascript/controllers/application.js'),

        // node_modules is now at appRoot (standard Vite structure)
        // No aliases needed - Vite resolves these automatically
      };

      // For server targets, client bundles should use RPC adapter instead of SQL adapter
      // This redirects lib/active_record.mjs imports to lib/active_record_client.mjs
      // The server runtime uses lib/active_record.mjs directly (SQL adapter)
      if (isServerTarget(config.target)) {
        const rpcAdapterPath = path.join(juntosDir, 'lib/active_record_client.mjs');
        if (fs.existsSync(rpcAdapterPath)) {
          // Match both relative and absolute paths to lib/active_record.mjs
          aliases['lib/active_record.mjs'] = rpcAdapterPath;
          aliases['./lib/active_record.mjs'] = rpcAdapterPath;
          aliases['../lib/active_record.mjs'] = rpcAdapterPath;
          aliases['../../lib/active_record.mjs'] = rpcAdapterPath;
        }
      } else {
        // For browser targets, use path_helper_browser.mjs (direct controller invocation)
        // instead of path_helper.mjs (fetch-based for server targets)
        const browserPathHelper = path.join(juntosDir, 'path_helper_browser.mjs');
        if (fs.existsSync(browserPathHelper)) {
          aliases['ruby2js-rails/path_helper.mjs'] = browserPathHelper;
        }
      }

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
          rollupOptions
        },
        resolve: {
          alias: aliases,
          // Add Ruby extensions for auto-resolution
          extensions: ['.mjs', '.js', '.mts', '.ts', '.jsx', '.tsx', '.json', '.jsx.rb', '.rb']
        },
        // publicDir is public/ by default, which is correct
      };
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
        input: 'index.html'
      };

    case 'electron':
      return {
        input: {
          main: 'main.js',
          preload: 'preload.js',
          renderer: 'index.html'
        },
        external: ['electron', 'better-sqlite3', 'path', 'fs', 'url']
      };

    case 'tauri':
      return {
        input: 'index.html',
        external: ['@tauri-apps/api']
      };

    case 'node':
    case 'bun':
    case 'deno':
      return {
        input: 'node_modules/ruby2js-rails/server.mjs',
        external: getNativeModules(database),
        output: {
          entryFileNames: 'index.js'
        }
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
        input: 'index.html'
      };
  }
}

/**
 * Get native modules to externalize based on database adapter.
 */
function getNativeModules(database) {
  const baseModules = ['path', 'fs', 'url', 'crypto', 'http', 'https', 'net', 'tls', 'stream', 'buffer', 'util', 'os'];

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

  return [...baseModules, ...(dbModules[database] || []), ...clientModules];
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

export default juntos;
