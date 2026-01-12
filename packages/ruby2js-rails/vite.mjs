/**
 * Juntos Vite Preset for Ruby2JS Rails Applications
 *
 * Provides full Rails app transformation including:
 * - Ruby file transformation (.rb → .js)
 * - RBX file support (Ruby + JSX with React)
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

// Import React filter for .rbx files
import 'ruby2js/filters/react.js';

/**
 * @typedef {Object} JuntosOptions
 * @property {string} [database] - Database adapter (dexie, sqlite, pg, etc.)
 * @property {string} [target] - Build target (browser, electron, capacitor, node, etc.)
 * @property {string} [broadcast] - Broadcast adapter (supabase, pusher, or null)
 * @property {string} [appRoot] - Application root directory (default: process.cwd())
 * @property {boolean} [hmr] - Enable HMR for Stimulus controllers (default: true)
 * @property {number} [eslevel] - ES level to target (default: 2022)
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
  const ruby2jsPath = path.join(appRoot, 'config/ruby2js.yml');
  if (fs.existsSync(ruby2jsPath)) {
    try {
      const parsed = yaml.load(fs.readFileSync(ruby2jsPath, 'utf8'));
      ruby2jsConfig = parsed?.[env] || parsed?.default || parsed || {};
    } catch (e) {
      console.warn(`[juntos] Warning: Failed to parse ruby2js.yml: ${e.message}`);
    }
  }

  // Get database from overrides, env, or database.yml
  let database = overrides.database;
  if (!database) {
    const dbConfig = SelfhostBuilder.load_database_config(appRoot, { quiet: true });
    database = dbConfig?.adapter || 'dexie';
  }

  // Derive target from database if not specified
  const target = overrides.target ||
                 ruby2jsConfig.target ||
                 SelfhostBuilder.DEFAULT_TARGETS?.[database] ||
                 'browser';

  return {
    eslevel: ruby2jsConfig.eslevel || 2022,
    database: database || 'dexie',
    target,
    broadcast: overrides.broadcast || ruby2jsConfig.broadcast,
    ...ruby2jsConfig,
    ...overrides
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
    appRoot = process.cwd(),
    hmr = true,
    eslevel = 2022,
    ...ruby2jsOptions
  } = options;

  // Load and merge configuration
  const config = loadConfig(appRoot, { database, target, broadcast, eslevel });

  return [
    // Core Ruby transformation with Rails filters
    createRubyPlugin(config, ruby2jsOptions),

    // RBX file handling (Ruby + JSX)
    createRbxPlugin(config),

    // Structural transforms (models, controllers, views, routes)
    createStructurePlugin(config, appRoot),

    // Platform-specific Vite configuration
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
    exclude: ['**/*.rbx'], // RBX files handled separately
    ...options
  });
}

/**
 * RBX plugin for Ruby + JSX files.
 */
function createRbxPlugin(config) {
  // Import convert function dynamically
  let convert, initPrism;
  let prismReady = false;

  return {
    name: 'juntos-rbx',

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
      if (!id.endsWith('.rbx')) return null;

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
          `Juntos RBX transform error in ${id}: ${error.message}`
        );
        enhancedError.id = id;
        enhancedError.plugin = 'juntos-rbx';
        throw enhancedError;
      }
    }
  };
}

/**
 * Structure plugin - runs SelfhostBuilder for models, controllers, views, routes.
 */
function createStructurePlugin(config, appRoot) {
  return {
    name: 'juntos-structure',

    async buildStart() {
      // Set the app root for the builder
      const originalRoot = SelfhostBuilder.DEMO_ROOT;
      SelfhostBuilder.DEMO_ROOT = appRoot;

      try {
        const builder = new SelfhostBuilder(null, {
          database: config.database,
          target: config.target,
          broadcast: config.broadcast
        });

        // Run the full build pipeline
        builder.build();
      } finally {
        // Restore original root
        SelfhostBuilder.DEMO_ROOT = originalRoot;
      }
    }
  };
}

/**
 * Config plugin - platform-specific Vite/Rollup configuration.
 */
function createConfigPlugin(config, appRoot) {
  return {
    name: 'juntos-config',

    config() {
      const aliases = {
        '@controllers': path.join(appRoot, 'app/javascript/controllers'),
        '@models': path.join(appRoot, 'app/models'),
        '@views': path.join(appRoot, 'app/views'),
        'components': path.join(appRoot, 'app/components'),
        // Alias for Rails importmap-style imports in Stimulus controllers
        'controllers/application': path.join(appRoot, 'app/javascript/controllers/application.js')
      };

      const rollupOptions = getRollupOptions(config.target, config.database);

      return {
        root: appRoot,
        build: {
          outDir: 'dist',
          rollupOptions
        },
        resolve: {
          alias: aliases
        }
      };
    }
  };
}

/**
 * Get Rollup options based on target platform.
 */
function getRollupOptions(target, database) {
  switch (target) {
    case 'browser':
    case 'capacitor':
    case 'pwa':
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
        input: 'server.mjs',
        external: getNativeModules(database)
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
        external: ['__STATIC_CONTENT_MANIFEST']
      };

    case 'deno-deploy':
      return {
        input: 'main.ts'
      };

    case 'fly':
      return {
        input: 'server.mjs',
        external: getNativeModules(database)
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

  return [...baseModules, ...(dbModules[database] || [])];
}

/**
 * HMR plugin for Stimulus controllers and structural changes.
 *
 * HMR behavior:
 * - Models, non-Stimulus controllers, routes → full reload
 * - Stimulus controllers → hot swap via custom event
 * - ERB views, RBX files, plain Ruby → Vite default HMR
 */
function createHmrPlugin() {
  return {
    name: 'juntos-hmr',

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
          file.match(/_controller\.(rb|rbx)$/)) {
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

      // ERB views, RBX files, plain Ruby: let Vite handle HMR
      // (default behavior - return undefined to use Vite's module graph)
    },

    transformIndexHtml(html) {
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
    .replace(/_controller\.(rb|rbx)$/, '')
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
      const modulePath = file.replace(/\\.(rb|rbx)$/, '.js');
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
