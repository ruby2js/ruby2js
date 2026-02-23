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
 *   import { juntos } from 'juntos-dev/vite';
 *
 *   export default juntos({
 *     database: 'dexie',
 *     target: 'browser'
 *   });
 */

import path from 'node:path';
import fs from 'node:fs';
import { execSync } from 'node:child_process';
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

// Import shared transformation logic
import {
  DEFAULT_TARGETS,
  RESERVED,
  capitalize,
  singularize,
  getBuildOptions,
  findModels,
  findLeafCollisions,
  modelClassName,
  findMigrations,
  findViewResources,
  fixImports,
  generateViewsModule,
  generateBrowserIndexHtml,
  generateBrowserMainJs,
  ensureRuby2jsReady,
  buildAppManifest,
  shouldIncludeFile,
  ErbCompiler
} from './transform.mjs';

// ============================================================
// Dual Bundle Support (SSR + Hydration)
// ============================================================

/**
 * Shared state for tracking RPC usage across plugins.
 * When JSX components import from app/models/*.rb or config/routes.rb,
 * we need to generate both server and client bundles.
 */
const rpcState = {
  // Set of files that import models or routes (RPC triggers)
  rpcImporters: new Set(),
  // Whether dual bundle mode is enabled (detected or configured)
  dualBundleEnabled: false,
  // Reset state for new builds
  reset() {
    this.rpcImporters.clear();
    this.dualBundleEnabled = false;
  }
};

/**
 * Pre-scan source files to detect RPC imports BEFORE build starts.
 * This is called during config() so we can set up the right inputs.
 *
 * Scans .jsx.rb files for:
 * - import [Model], from: 'app/models/*.rb'
 * - import [...], from: 'config/routes.rb'
 */
function preScanForRpcImports(appRoot) {
  const rpcFiles = [];

  // Patterns to detect in Ruby source (before transpilation)
  // Ruby import syntax: import [Foo], from: 'app/models/foo.rb'
  const modelImportPattern = /from:\s*['"]app\/models\/[^'"]+\.rb['"]/;
  const routesImportPattern = /from:\s*['"]config\/routes\.rb['"]/;

  // Scan app/components/*.jsx.rb
  const componentsDir = path.join(appRoot, 'app/components');
  if (fs.existsSync(componentsDir)) {
    const files = fs.readdirSync(componentsDir).filter(f => f.endsWith('.jsx.rb'));
    for (const file of files) {
      const content = fs.readFileSync(path.join(componentsDir, file), 'utf8');
      if (modelImportPattern.test(content) || routesImportPattern.test(content)) {
        rpcFiles.push(path.join(componentsDir, file));
      }
    }
  }

  // Scan app/views/**/*.jsx.rb
  const viewsDir = path.join(appRoot, 'app/views');
  if (fs.existsSync(viewsDir)) {
    const scanDir = (dir) => {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          scanDir(fullPath);
        } else if (entry.name.endsWith('.jsx.rb')) {
          const content = fs.readFileSync(fullPath, 'utf8');
          if (modelImportPattern.test(content) || routesImportPattern.test(content)) {
            rpcFiles.push(fullPath);
          }
        }
      }
    };
    scanDir(viewsDir);
  }

  return rpcFiles;
}

/**
 * Detect RPC imports in transformed JavaScript code.
 * Returns true if the code imports from models or routes.
 */
function detectRpcImports(jsCode, filePath) {
  // Check for model imports: from 'app/models/*.rb' or from "app/models/*.rb"
  const modelImportPattern = /from\s+['"]app\/models\/[^'"]+\.rb['"]/;
  // Check for routes import (path helpers): from 'config/routes.rb' or from "config/routes.rb"
  const routesImportPattern = /from\s+['"]config\/routes\.rb['"]/;

  if (modelImportPattern.test(jsCode) || routesImportPattern.test(jsCode)) {
    rpcState.rpcImporters.add(filePath);
    return true;
  }
  return false;
}

/**
 * Check if dual bundle mode should be enabled.
 * Called after all files are transformed.
 */
function shouldEnableDualBundle(config) {
  // Only for server targets
  if (!isServerTarget(config.target)) return false;
  // Enable if any JSX files import models or routes
  return rpcState.rpcImporters.size > 0;
}

// ============================================================
// Configuration loading (vite-specific, uses yaml)
// ============================================================

import { loadDatabaseConfig } from 'juntos/config.mjs';

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
  let sectionConfigs = {};
  const ruby2jsPath = path.join(appRoot, 'config/ruby2js.yml');
  if (fs.existsSync(ruby2jsPath)) {
    try {
      const parsed = yaml.load(fs.readFileSync(ruby2jsPath, 'utf8'));
      // Environment-specific config (nested under development/production/etc)
      ruby2jsConfig = parsed?.[env] || parsed?.default || {};
      // Top-level config (not nested under environment) - for settings like 'external'
      // that don't vary by environment
      topLevelConfig = parsed || {};

      // Section-specific configs (controllers, stimulus, components, jsx)
      // These are at top level of the YAML, not nested under environment
      const sectionNames = ['controllers', 'stimulus', 'components', 'jsx', 'models', 'routes'];
      for (const name of sectionNames) {
        if (parsed?.[name]) {
          sectionConfigs[name] = parsed[name];
        }
      }
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
    base,
    // Section-specific configs from ruby2js.yml (controllers, stimulus, etc.)
    sections: sectionConfigs,
    // Include/exclude patterns for filtering models and views
    include: topLevelConfig.include || [],
    exclude: topLevelConfig.exclude || []
  };
}

/**
 * Get section-specific config for getBuildOptions.
 * Returns the config for the given section, or null if not defined.
 */
export function getSectionConfig(config, section) {
  if (!config?.sections || !section) return null;
  return config.sections[section] || null;
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
    // Also detects RPC imports for dual bundle mode
    createJsxRbPlugin(config, appRoot),

    // ERB file handling (server-rendered templates as JS modules)
    createErbPlugin(config),

    // Dual bundle support (generates client.js for hydration when RPC detected)
    createDualBundlePlugin(config, appRoot),

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
 * Create plugins for client bundle build.
 * This is a minimal set of plugins for hydration builds:
 * - Virtual plugin for RPC adapter and browser runtime
 * - Ruby transform plugin for .rb files
 * - JSX.rb plugin for React components
 * - ERB plugin for view templates
 *
 * Does NOT include browser entry plugin (no .browser/ directory needed)
 */
export function createClientPlugins(options = {}) {
  const appRoot = options.appRoot || process.cwd();

  // Client always uses RPC adapter and browser runtime
  const config = {
    database: 'rpc',
    target: 'browser',
    eslevel: options.eslevel || 2022
  };

  const plugins = [];

  // Only include virtual plugin if not skipped (caller provides their own)
  if (!options.skipVirtual) {
    plugins.push(createClientVirtualPlugin());
  }

  // JSX.rb file handling (Ruby + JSX)
  plugins.push(createJsxRbPlugin(config, appRoot));

  // ERB file handling
  plugins.push(createErbPlugin(config, appRoot));

  // On-the-fly Ruby transformation
  plugins.push(createRubyTransformPlugin(config, appRoot));

  return plugins;
}

/**
 * Virtual plugin for client builds.
 * Always routes to RPC adapter and browser runtime.
 */
function createClientVirtualPlugin() {
  return {
    name: 'juntos-client-virtual',
    enforce: 'pre',

    resolveId(id) {
      if (id === 'juntos:active-record') return '\0juntos:active-record:rpc';
      if (id === 'juntos:rails') return '\0juntos:rails:browser';
      return null;
    },

    load(id) {
      if (id === '\0juntos:active-record:rpc') {
        return `export * from 'juntos/adapters/active_record_rpc.mjs';`;
      }
      if (id === '\0juntos:rails:browser') {
        return `export * from 'juntos/targets/browser/rails.js';`;
      }
      return null;
    }
  };
}

/**
 * JSX.rb plugin for Ruby + JSX files.
 * Also detects RPC imports for dual bundle mode.
 */
function createJsxRbPlugin(config, appRoot) {
  return {
    name: 'juntos-jsx-rb',

    async transform(code, id) {
      if (!id.endsWith('.jsx.rb')) return null;

      // Use shared initialization (loads all filters including React)
      const { convert } = await ensureRuby2jsReady();

      try {
        // Get section-specific config from ruby2js.yml if available
        const sectionConfig = config.sections?.jsx || null;
        const result = convert(code, {
          ...getBuildOptions('jsx', config.target, sectionConfig),
          eslevel: config.eslevel,
          file: id
        });

        const js = result.toString();
        const map = result.sourcemap;

        // Detect RPC imports for dual bundle mode
        if (isServerTarget(config.target)) {
          detectRpcImports(js, id);
        }

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
      await import('ruby2js/filters/active_support.js');
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

    // Step 1: Compile ERB to Ruby
    const compiler = new ErbCompiler(template);
    const rubySrc = compiler.src;

    // Step 2: Convert Ruby to JavaScript with ERB filters
    // Note: Rails_Helpers must come before Erb for method overrides
    // ActiveSupport provides .present?, .blank?, etc. for Rails idioms
    const options = {
      filters: ['Rails_Helpers', 'ActiveSupport', 'Erb', 'Functions', 'Return'],
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

    // Paths: ../../../config/paths.js → juntos:paths (path helpers virtual module)
    // This breaks the circular dependency between routes.rb and controllers
    js = js.replace(/from ["']\.\.\/\.\.\/\.\.\/config\/paths\.js["']/g, 'from "juntos:paths"');

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
  // ensureRuby2jsReady() from transform.mjs handles all filter loading

  // Cache for transformed files
  const transformCache = new Map();

  // Pre-analysis state: metadata from model transforms
  let metadata = null;
  let manifestPromise = null;

  // Lazily-built map of ClassName → model path (e.g., "Person" → "person")
  let _modelClassMap = null;
  function getModelClassMap() {
    if (_modelClassMap) return _modelClassMap;
    _modelClassMap = {};
    const models = findModels(appRoot).filter(m => m !== 'application_record');
    const collisions = findLeafCollisions(models);
    for (const m of models) {
      const className = modelClassName(m, collisions);
      _modelClassMap[className] = m;
    }
    return _modelClassMap;
  }

  // Add imports for cross-model references in method bodies.
  // Scans for bare ClassName.method or new ClassName( patterns and adds
  // import statements for models that aren't already imported.
  function addCrossModelImports(js, filePath) {
    // Only process model files
    const relPath = path.relative(appRoot, filePath);
    if (!relPath.startsWith('app/models/') && !relPath.startsWith('app' + path.sep + 'models' + path.sep)) return js;

    const modelMap = getModelClassMap();
    const modelRelPath = relPath.replace(/^app\/models\/|^app\\models\\/g, '').replace(/\.rb$|\.js$/, '');

    for (const [className, modelPath] of Object.entries(modelMap)) {
      // Skip self
      if (modelPath === modelRelPath) continue;

      // Skip if already imported
      const importPattern = new RegExp(`import\\s+\\{[^}]*\\b${className}\\b[^}]*\\}\\s+from`);
      if (importPattern.test(js)) continue;

      // Skip if this file defines the class
      const definesClass = new RegExp(`(export\\s+)?(class|const|let|var|function)\\s+${className}\\b`);
      if (definesClass.test(js)) continue;

      // Check if referenced (ClassName.something or new ClassName)
      const refPattern = new RegExp(`\\b${className}\\b\\.\\w|\\bnew\\s+${className}\\b`);
      if (!refPattern.test(js)) continue;

      // Compute relative path from current model to target model
      const currentParts = modelRelPath.split('/');
      const targetParts = modelPath.split('/');
      const currentDir = currentParts.slice(0, -1);
      const targetDir = targetParts.slice(0, -1);
      const targetFile = targetParts[targetParts.length - 1];

      let common = 0;
      while (common < currentDir.length && common < targetDir.length &&
             currentDir[common] === targetDir[common]) {
        common++;
      }
      const up = currentDir.length - common;
      const down = targetDir.slice(common);
      let importPath;
      if (up === 0 && down.length === 0) {
        importPath = `./${targetFile}.rb`;
      } else if (up === 0) {
        importPath = `./${[...down, targetFile + '.rb'].join('/')}`;
      } else {
        importPath = [...Array(up).fill('..'), ...down, targetFile + '.rb'].join('/');
      }

      js = `import { ${className} } from '${importPath}';\n${js}`;
    }

    return js;
  }

  async function ensureManifest() {
    if (!metadata) {
      if (!manifestPromise) {
        manifestPromise = buildAppManifest(appRoot, config, { mode: 'vite' });
      }
      const manifest = await manifestPromise;
      metadata = manifest.metadata;
      // Seed transform cache from pre-analyzed models
      for (const [filePath, result] of manifest.modelCache) {
        try {
          const stat = fs.statSync(filePath);
          let js = fixImports(result.code, filePath);
          js = addCrossModelImports(js, filePath);
          const map = result.map;
          if (map) {
            map.file = path.basename(filePath).replace('.rb', '.js');
            map.sources = [filePath];
            map.sourceRoot = '';
            map.sourcesContent = [fs.readFileSync(filePath, 'utf-8')];
          }
          transformCache.set(filePath, { result: { code: js, map }, mtime: stat.mtimeMs });
        } catch {}
      }
    }
    return metadata;
  }

  // Local wrapper for transformRuby that uses closure's config/appRoot
  async function transformRubyLocal(source, filePath, section = null) {
    const meta = await ensureManifest();
    const { convert } = await ensureRuby2jsReady();
    // Get section-specific config from ruby2js.yml if available
    const sectionConfig = config.sections?.[section] || null;
    const options = {
      ...getBuildOptions(section, config.target, sectionConfig),
      file: path.relative(appRoot, filePath),
      database: config.database,
      target: config.target,
      metadata: meta
    };
    return convert(source, options);
  }

  return {
    name: 'juntos-ruby',
    enforce: 'pre',

    async buildStart() {
      await ensureManifest();
      const modelCount = metadata.models ? Object.keys(metadata.models).length : 0;
      console.log(`[juntos] Pre-analyzed ${modelCount} models`);
    },

    handleHotUpdate({ file, server }) {
      const normalizedFile = file.replace(/\\/g, '/');

      if (normalizedFile.includes('/app/models/') && file.endsWith('.rb')) {
        // Invalidate metadata — model change may affect associations
        metadata = null;
        manifestPromise = null;
        transformCache.delete(file);

        // Rebuild metadata, then hot-swap model and Turbo morph
        ensureManifest().then(() => {
          console.log('[juntos] Model metadata rebuilt after change');
          hmrSend(server, {
            type: 'custom',
            event: 'juntos:model-update',
            data: { file }
          });
        });
        return [];
      }
    },

    // Resolve virtual modules and source file imports
    resolveId(source, importer) {
      // Virtual modules
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
      // Virtual module: juntos:models (registry of all models)
      // Registers models with both Application and the adapter's modelRegistry
      // Also registers for RPC when dual bundle mode is enabled (hydration needs RPC)
      if (id === '\0juntos:models') {
        const allModels = findModels(appRoot).filter(m => m !== 'application_record');
        const models = (config.include?.length || config.exclude?.length)
          ? allModels.filter(m => shouldIncludeFile(`app/models/${m}.rb`, config.include, config.exclude))
          : allModels;
        const collisions = findLeafCollisions(models);
        const imports = models.map(m => {
          const leafClass = m.split('/').pop().split('_').map(s => s.charAt(0).toUpperCase() + s.slice(1)).join('');
          const alias = modelClassName(m, collisions);
          if (alias !== leafClass) {
            return `import { ${leafClass} as ${alias} } from 'app/models/${m}.rb';`;
          }
          return `import { ${alias} } from 'app/models/${m}.rb';`;
        });
        const classNames = models.map(m => modelClassName(m, collisions));
        // Register for RPC if dual bundle mode (client needs to call server for model ops)
        const rpcRegistration = rpcState.dualBundleEnabled
          ? `\nApplication.registerModelsForRPC(models);`
          : '';
        return `${imports.join('\n')}
import { Application } from 'juntos:rails';
import { modelRegistry, attr_accessor } from 'juntos:active-record';
import { migrations } from 'juntos:migrations';
const models = { ${classNames.join(', ')} };
Application.registerModels(models);${rpcRegistration}
Object.assign(modelRegistry, models);

// Define attribute accessors from migration schema (like Rails schema.rb)
for (const migration of migrations) {
  if (!migration.tableSchemas) continue;
  for (const [table, schema] of Object.entries(migration.tableSchemas)) {
    const model = Object.values(models).find(m => m.tableName === table);
    if (!model) continue;
    const columns = schema.split(', ').map(c => c.replace(/^[+&]*/g, '')).filter(c => c !== 'id');
    attr_accessor(model, ...columns);
  }
}

export { ${classNames.join(', ')} };
`;
      }

      // Virtual module: juntos:migrations (registry of all migrations)
      // Migration filter transforms class to { up: async () => {...}, tableSchemas: {...} }
      if (id === '\0juntos:migrations') {
        const migrations = findMigrations(appRoot);
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
      // Uses shared generateViewsModule from transform.mjs
      if (id.startsWith('\0juntos:views/')) {
        const resource = id.replace('\0juntos:views/', '');

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

        // Filter view resources by include/exclude patterns
        // Use a synthetic path to check if any file in this resource dir would be included
        if (config.include?.length || config.exclude?.length) {
          if (!shouldIncludeFile(`app/views/${resource}/index.html.erb`, config.include, config.exclude)) {
            const className = capitalize(singularize(resource)) + 'Views';
            return `export const ${className} = {};`;
          }
        }

        // Regular views: use shared generateViewsModule
        return generateViewsModule(appRoot, resource);
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

      // Transform Ruby source files (but not .jsx.rb - that's handled by juntos-jsx-rb)
      if (!id.endsWith('.rb') || id.endsWith('.jsx.rb')) return null;
      if (id.includes('/node_modules/')) return null;

      // Skip base classes that don't need transformation
      const basename = path.basename(id);
      if (basename === 'application_controller.rb') {
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

        // Special handling for routes.rb - import paths from virtual module
        // This breaks the circular dependency between routes.rb and controllers
        let result;
        if (id.endsWith('/routes.rb')) {
          const { convert } = await ensureRuby2jsReady();
          // Get routes-specific config from ruby2js.yml if available
          const sectionConfig = config.sections?.routes || null;
          const options = {
            ...getBuildOptions(null, config.target, sectionConfig),
            file: path.relative(appRoot, id),
            database: config.database,
            target: config.target,
            paths_file: 'juntos:paths',  // Import path helpers from virtual module
            base: config.base || '/'
          };
          result = convert(source, options);
        } else {
          result = await transformRubyLocal(source, id, section);
        }

        let js = result.toString();
        js = fixImports(js, id);
        js = addCrossModelImports(js, id);

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

    // For server builds, symlink node_modules and copy CSS for runtime resolution
    async closeBundle() {
      if (!isServerTarget(config.target)) return;

      const distDir = path.join(appRoot, 'dist');
      if (!fs.existsSync(distDir)) return;

      const nodeModulesLink = path.join(distDir, 'node_modules');
      const nodeModulesTarget = path.join(appRoot, 'node_modules');

      try {
        await fs.promises.unlink(nodeModulesLink).catch(() => {});
        await fs.promises.symlink(nodeModulesTarget, nodeModulesLink, 'junction');
        console.log('[juntos] Linked node_modules to dist/');
      } catch (e) {
        console.warn('[juntos] Could not create node_modules symlink:', e.message);
      }

      // CSS is now added as a Vite input (see createConfigPlugin)
      // so it gets fingerprinted and added to the manifest
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
        // Uses juntos:paths virtual module to avoid circular dependency with routes.rb
        '@config/paths.js': 'juntos:paths',

        // Alias for Rails importmap-style imports in Stimulus controllers
        'controllers/application': path.join(appRoot, 'app/javascript/controllers/application.js'),

        // node_modules is now at appRoot (standard Vite structure)
        // No aliases needed - Vite resolves these automatically

        // NOTE: lib/ aliases removed - now using virtual modules:
        // - juntos:rails - target-specific runtime
        // - juntos:active-record - database adapter
        // - juntos:active-record-client - RPC adapter for browser in server builds
      };

      // For dev mode with browser targets, don't set rollupOptions.input
      // (HTML is served virtually by configureServer, no real file needed)
      const browserTargets = ['browser', 'pwa', 'capacitor', 'electron', 'tauri', 'electrobun'];
      const isBrowserTarget = browserTargets.includes(config.target);
      const isDevMode = command === 'serve';

      const rollupOptions = (isDevMode && isBrowserTarget)
        ? {} // No input needed for dev - middleware serves virtual HTML
        : getRollupOptions(config.target, config.database);
      const buildTarget = getBuildTarget(config.target);

      // Add CSS to inputs for server targets so Vite fingerprints it
      const serverTargets = ['node', 'bun', 'deno', 'fly', 'vercel-node'];
      if (serverTargets.includes(config.target) && rollupOptions.input) {
        const tailwindPath = path.join(appRoot, 'app/assets/builds/tailwind.css');
        if (fs.existsSync(tailwindPath)) {
          rollupOptions.input['tailwind'] = tailwindPath;
        }
      }

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
        // Define compile-time constants
        // globalThis.JUNTOS_HYDRATION tells rails_server.js whether client.js exists
        // This is set to true by createDualBundlePlugin when RPC is detected
        define: {
          'globalThis.JUNTOS_HYDRATION': rpcState.dualBundleEnabled ? 'true' : 'false'
        },
        build: {
          target: buildTarget,
          outDir: 'dist',
          emptyOutDir: true, // Clean dist/ on each build
          minify: false, // Disable minification for debugging
          sourcemap: true, // Enable sourcemaps for debugging
          manifest: true, // Generate manifest.json for asset fingerprinting
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
        // Exclude packages that use virtual modules esbuild can't resolve
        // Include the database adapter's npm package since juntos is excluded
        optimizeDeps: {
          include: ['react', 'react-dom', 'react-dom/client', ...getDatabasePackages(config.database)],
          exclude: ['juntos'],
          // Replace Rails importmap-style controllers/index.js during esbuild pre-bundling
          esbuildOptions: {
            plugins: [{
              name: 'juntos-controllers-index',
              setup(build) {
                build.onLoad({ filter: /app\/javascript\/controllers\/index\.js$/ }, () => ({
                  contents: `import { Application } from "@hotwired/stimulus";
const application = Application.start();
const controllers = import.meta.glob(['./*_controller.js', './*_controller.rb'], { eager: true });
for (const [path, module] of Object.entries(controllers)) {
  const match = path.match(/\\.\\/(.+)_controller/);
  if (match) application.register(match[1].replace(/_/g, '-'), module.default);
}
export { application };`,
                  loader: 'js'
                }));
              }
            }]
          }
        },
        // publicDir is public/ by default, which is correct
      };
    },

    // Serve virtual index.html for the root URL in dev mode
    configureServer(server) {
      const browserTargets = ['browser', 'pwa', 'capacitor', 'electron', 'tauri', 'electrobun'];
      if (!browserTargets.includes(config.target)) return;

      // Generate index.html content once
      const appName = detectAppName(appRoot);
      const indexHtml = generateBrowserIndexHtml(appName, '/.browser/main.js');

      // Middleware to serve virtual index.html for HTML requests (SPA fallback)
      server.middlewares.use(async (req, res, next) => {
        const url = req.url || '/';
        const pathname = url.split('?')[0];

        // Serve virtual HTML for:
        // - Root path (/)
        // - Paths without file extensions (SPA routes like /articles/new)
        // - Explicit /index.html
        const hasExtension = pathname.includes('.') && !pathname.endsWith('.html');
        const isApiOrAsset = pathname.startsWith('/@') || pathname.startsWith('/node_modules/');

        if (!hasExtension && !isApiOrAsset) {
          try {
            // Transform HTML through Vite's pipeline (handles HMR injection, etc.)
            const transformedHtml = await server.transformIndexHtml(url, indexHtml);
            res.setHeader('Content-Type', 'text/html');
            res.end(transformedHtml);
          } catch (err) {
            next(err);
          }
          return;
        }
        next();
      });
    },

    // Flatten .browser/ output to dist root for browser targets
    async closeBundle() {
      const browserTargets = ['browser', 'pwa', 'capacitor', 'electron', 'tauri', 'electrobun'];
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

      // Generate Electrobun config files
      if (config.target === 'electrobun') {
        generateElectrobunConfig(distDir, appRoot);
      }
    }
  };
}

/**
 * Generate Electrobun configuration files in dist/.
 * Creates electrobun.config.ts and bun/index.ts.
 */
function generateElectrobunConfig(distDir, appRoot) {
  const appName = detectAppName(appRoot);
  const identifier = 'com.example.' + appName.toLowerCase().replace(/\s+/g, '');

  // Generate electrobun.config.ts
  const configContent = `import type { ElectrobunConfig } from "electrobun/config";

const config: ElectrobunConfig = {
  name: ${JSON.stringify(appName)},
  identifier: ${JSON.stringify(identifier)},
  mainEntry: "bun/index.ts",
  views: {
    "main-ui": {
      entry: "index.html"
    }
  },
  window: {
    width: 1200,
    height: 800,
    title: ${JSON.stringify(appName)}
  }
};

export default config;
`;

  fs.writeFileSync(path.join(distDir, 'electrobun.config.ts'), configContent);

  // Generate bun/index.ts (Bun main process entry point)
  const bunDir = path.join(distDir, 'bun');
  if (!fs.existsSync(bunDir)) {
    fs.mkdirSync(bunDir, { recursive: true });
  }

  const bunEntry = `import { BrowserWindow, BrowserView } from "electrobun/bun";

// Define RPC handlers for communication with the WebView
const rpc = BrowserView.defineRPC({
  handlers: {
    requests: {
      // Add custom request handlers here
      // Example: readFile: async ({path}: {path: string}) => await Bun.file(path).text()
    },
    messages: {
      // Add custom message handlers here
      // Example: logToBun: ({msg}: {msg: string}) => console.log(msg)
    }
  }
});

// Create the main window
const win = new BrowserWindow({
  title: ${JSON.stringify(appName)},
  width: 1200,
  height: 800,
  url: "views://main-ui/index.html",
  rpc
});
`;

  fs.writeFileSync(path.join(bunDir, 'index.ts'), bunEntry);
  console.log('[juntos] Generated Electrobun config files');
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
 * Send an HMR message to the client.
 * Supports both Vite 6 (server.ws) and Vite 7+ (server.hot).
 */
function hmrSend(server, message) {
  const hot = server.hot || server.ws;
  if (hot) hot.send(message);
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

    case 'electrobun':
      return {
        input: '.browser/index.html',
        external: ['electrobun/bun', 'electrobun/view']
      };

    case 'node':
    case 'bun':
    case 'deno':
      return {
        input: {
          index: 'node_modules/juntos/server.mjs',
          'config/routes': 'config/routes.rb'
          // Note: client entry is added dynamically by createDualBundlePlugin
          // if RPC imports are detected during pre-scan
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
        input: 'node_modules/juntos/server.mjs',
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
 * Get npm packages to pre-bundle for the database adapter.
 * Since juntos is excluded from optimization (uses virtual modules),
 * we need to explicitly include its database adapter dependencies.
 */
function getDatabasePackages(database) {
  const packages = {
    // Browser-only databases
    dexie: ['dexie'],
    indexeddb: ['dexie'],
    sqljs: ['sql.js'],
    'sql.js': ['sql.js'],
    pglite: ['@electric-sql/pglite'],
    // Universal databases (HTTP-based, work in browser and server)
    neon: ['@neondatabase/serverless'],
    turso: ['@libsql/client'],
    supabase: ['@supabase/supabase-js'],
    // Server-only adapters (native modules, not used in browser dev)
    sqlite: [],
    better_sqlite3: [],
    pg: [],
    postgres: [],
    mysql2: [],
    d1: []  // Cloudflare D1 uses Workers bindings, not npm package
  };
  return packages[database] || [];
}

/**
 * Browser entry plugin - serves virtual entry points for browser targets.
 *
 * In dev mode: Serves index.html and main.js as virtual modules (no files created).
 * In build mode: Creates .browser/ files just before build starts.
 *
 * This avoids cluttering the project with generated files during development,
 * and ensures files exist when Vite's rollup resolver needs them for builds.
 */
function createBrowserEntryPlugin(config, appRoot) {
  const browserTargets = ['browser', 'pwa', 'capacitor', 'electron', 'tauri', 'electrobun'];
  const isBrowserTarget = browserTargets.includes(config.target);

  // Virtual module ID for main.js
  const VIRTUAL_MAIN_ID = '\0virtual:browser-main';

  // Cache generated content
  let indexHtmlContent = null;
  let mainJsContent = null;

  function getIndexHtml() {
    if (!indexHtmlContent) {
      const appName = detectAppName(appRoot);
      indexHtmlContent = generateBrowserIndexHtml(appName, '/.browser/main.js');
    }
    return indexHtmlContent;
  }

  function getMainJs(isVirtual = false) {
    // Virtual modules resolve from project root, real files from .browser/
    const routesPath = isVirtual ? '/config/routes.rb' : '../config/routes.rb';
    const controllersPath = isVirtual ? '/app/javascript/controllers/index.js' : '../app/javascript/controllers/index.js';
    return generateBrowserMainJs(routesPath, controllersPath);
  }

  return {
    name: 'juntos-browser-entry',

    // For build mode: create files synchronously before Vite resolves rollupOptions.input
    config(userConfig, { command }) {
      if (command !== 'build' || !isBrowserTarget) return;

      const browserDir = path.join(appRoot, '.browser');
      const indexPath = path.join(browserDir, 'index.html');
      const mainPath = path.join(browserDir, 'main.js');

      // Create .browser directory if needed
      if (!fs.existsSync(browserDir)) {
        fs.mkdirSync(browserDir, { recursive: true });
      }

      // Generate index.html
      fs.writeFileSync(indexPath, getIndexHtml());

      // Generate main.js (real file, uses relative paths from .browser/)
      fs.writeFileSync(mainPath, getMainJs(false));

      console.log('[juntos] Generated .browser/ entry files for build');
    },

    // For dev mode: resolve /.browser/main.js as a virtual module
    resolveId(id) {
      if (!isBrowserTarget) return null;
      if (id === '/.browser/main.js' || id === '.browser/main.js') {
        return VIRTUAL_MAIN_ID;
      }
      return null;
    },

    // For dev mode: load virtual main.js content
    load(id) {
      if (id === VIRTUAL_MAIN_ID) {
        return getMainJs(true); // Virtual module uses root-relative paths
      }
      return null;
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
 * Dual Bundle Plugin - generates client.js for hydration when RPC is detected.
 *
 * When server-side rendered apps use RPC (model imports or path helpers in JSX),
 * we need both:
 * - Server bundle: SSR + API endpoints (index.js)
 * - Client bundle: Hydration + RPC client calls (client.js)
 *
 * This plugin:
 * 1. Pre-scans files during config() to detect RPC usage
 * 2. Generates .client/main.js entry point
 * 3. Adds client entry to Vite build inputs
 */
function createDualBundlePlugin(config, appRoot) {
  // Only relevant for server targets (not browser/client)
  // Also skip if database is 'rpc' - that means we're already building the client bundle
  if (!isServerTarget(config.target) || config.database === 'rpc') {
    return { name: 'juntos-dual-bundle-noop' };
  }

  // Pre-scan for RPC imports before build
  const rpcFiles = preScanForRpcImports(appRoot);
  const needsDualBundle = rpcFiles.length > 0;

  if (needsDualBundle) {
    rpcState.dualBundleEnabled = true;
    rpcFiles.forEach(f => rpcState.rpcImporters.add(f));
  }

  return {
    name: 'juntos-dual-bundle',

    // Log RPC detection during config (don't add client to this build)
    config(userConfig, { command }) {
      if (!needsDualBundle) return;

      console.log('[juntos] RPC imports detected - will build client bundle separately');
      const relativeRpcFiles = rpcFiles.map(f => path.relative(appRoot, f));
      console.log('[juntos] RPC files:', relativeRpcFiles);

      // Generate client entry file (will be built separately after server build)
      const clientDir = path.join(appRoot, '.client');
      const mainPath = path.join(clientDir, 'main.js');

      if (!fs.existsSync(clientDir)) {
        fs.mkdirSync(clientDir, { recursive: true });
      }

      // Pass relative RPC file paths to generate imports for each view
      const clientEntry = generateClientEntryForHydration(appRoot, config, relativeRpcFiles);
      fs.writeFileSync(mainPath, clientEntry);
      console.log('[juntos] Generated .client/main.js for hydration');

      // Don't add client entry here - it will be built separately
      // This ensures module resolution doesn't get shared between server and client
    },

    // After server build completes, trigger separate client build
    async closeBundle() {
      if (!needsDualBundle) return;
      console.log('[juntos] Server build complete, starting client build...');

      // Build client bundle separately with RPC adapter
      await buildClientBundle(appRoot, config);

      console.log('[juntos] Dual bundle build complete (index.js + client.js)');
    }
  };
}

/**
 * Build client bundle separately from server bundle.
 * This ensures module resolution doesn't get shared - client always uses RPC adapter.
 */
async function buildClientBundle(appRoot, config) {
  // Write a temporary Vite config for the client build
  // Use vite.client.config.js in the root to avoid path issues
  const clientConfigPath = path.join(appRoot, 'vite.client.config.js');

  // Pre-generate the juntos:paths content for the client bundle
  // This must be done here because we need async Ruby2JS conversion
  const pathsContent = await generatePathsModule(appRoot, { ...config, target: 'browser' });
  // Escape for embedding in a template string
  const escapedPathsContent = pathsContent
    .replace(/\\/g, '\\\\')
    .replace(/`/g, '\\`')
    .replace(/\$/g, '\\$');

  // Inline the minimal plugins needed for client build
  // Can't use createClientPlugins() because it imports from the package context
  const clientConfigContent = `
import path from 'node:path';

// Pre-generated juntos:paths content (path helpers for routes)
const PATHS_MODULE_CONTENT = \`${escapedPathsContent}\`;

// Minimal virtual plugin for client - RPC adapter, browser runtime, and paths
const clientVirtualPlugin = {
  name: 'juntos-client-virtual',
  enforce: 'pre',
  resolveId(id) {
    if (id === 'juntos:active-record') return '\\0juntos:active-record:rpc';
    if (id === 'juntos:rails') return '\\0juntos:rails:browser';
    if (id === 'juntos:active-storage') return '\\0juntos:active-storage:client';
    if (id === 'juntos:paths') return '\\0juntos:paths';
    return null;
  },
  load(id) {
    if (id === '\\0juntos:active-record:rpc') {
      return "export * from 'juntos/adapters/active_record_rpc.mjs';";
    }
    if (id === '\\0juntos:rails:browser') {
      return "export * from 'juntos/targets/browser/rails.js';";
    }
    if (id === '\\0juntos:active-storage:client') {
      // No-op: client bundle is for RPC hydration, not Active Storage
      return "export function initActiveStorage() {}";
    }
    if (id === '\\0juntos:paths') {
      return PATHS_MODULE_CONTENT;
    }
    return null;
  }
};

// Import the actual transform plugins from the package
import { createClientPlugins } from 'juntos-dev/vite';

export default {
  plugins: [
    clientVirtualPlugin,
    ...createClientPlugins({ skipVirtual: true })
  ],
  build: {
    outDir: 'dist',
    emptyOutDir: false,  // Don't clear server output
    rollupOptions: {
      input: {
        client: '.client/main.js'
      },
      output: {
        entryFileNames: '[name].js',
        chunkFileNames: 'assets/client-[name]-[hash].js'
      }
    }
  },
  resolve: {
    alias: {
      'components': path.resolve('app/components'),
      '@models': path.resolve('app/models'),
      '@views': path.resolve('app/views'),
      // Path helpers - use virtual module to avoid circular dependency
      '@config/paths.js': 'juntos:paths'
    },
    // Include .jsx.rb extension for Ruby+JSX files
    extensions: ['.mjs', '.js', '.mts', '.ts', '.jsx', '.tsx', '.json', '.jsx.rb', '.rb'],
    // Ensure React is resolved from project's node_modules, not linked package's
    dedupe: ['react', 'react-dom']
  },
  // Dedupe React to prevent multiple instances
  optimizeDeps: {
    include: ['react', 'react-dom', 'react-dom/client']
  },
  logLevel: 'warn'
};
`;

  fs.writeFileSync(clientConfigPath, clientConfigContent);

  try {
    // Run Vite build with the client config
    // Override env vars to force RPC adapter and browser target
    execSync('npx vite build --config vite.client.config.js', {
      cwd: appRoot,
      stdio: 'inherit',
      env: {
        ...process.env,
        JUNTOS_DATABASE: 'rpc',
        JUNTOS_TARGET: 'browser'
      }
    });
  } finally {
    // Clean up the temporary config
    try {
      fs.unlinkSync(clientConfigPath);
    } catch (e) {
      // Ignore cleanup errors
    }
  }
}

/**
 * Generate the client entry point for hydration.
 * This is the entry point for the client bundle that hydrates SSR content.
 *
 * IMPORTANT: The client entry must NOT import views that have model dependencies,
 * as those pull in server-only dependencies (node:http, better-sqlite3, etc.).
 *
 * Instead, we use a minimal hydration approach:
 * 1. React attaches event handlers to existing DOM
 * 2. Browser-only components (ReactFlow, etc.) are loaded dynamically
 * 3. Data is fetched via RPC when needed
 *
 * @param {string} appRoot - Application root directory
 * @param {object} config - Build configuration
 * @param {string[]} rpcFiles - Files that triggered RPC detection (JSX views with model imports)
 */
function generateClientEntryForHydration(appRoot, config, rpcFiles = []) {
  // Generate imports for JSX views that triggered RPC detection.
  // These views import models, which will be routed to RPC adapter
  // by the virtual plugin (since this file is in .client/).

  // Filter to only JSX views (not ERB views which don't need hydration)
  const jsxViews = rpcFiles.filter(f => f.endsWith('.jsx.rb'));

  // Generate import statements for each JSX view
  // Use relative paths from .client/ directory
  const viewImports = jsxViews.map((file, i) => {
    // file is relative to appRoot, e.g., 'app/views/workflows/Show.jsx.rb'
    return `import View${i} from '../${file}';`;
  }).join('\n');

  // Generate a map of paths to views for routing
  // Extract the route pattern from the view path
  // e.g., 'app/views/workflows/Show.jsx.rb' -> '/workflows/:id'
  const viewMap = jsxViews.map((file, i) => {
    // Parse: app/views/{resource}/{Action}.jsx.rb
    const match = file.match(/app\/views\/([^/]+)\/(\w+)\.jsx\.rb$/);
    if (match) {
      const [, resource, action] = match;
      // Map action to route pattern
      let pattern;
      switch (action.toLowerCase()) {
        case 'index': pattern = `/${resource}`; break;
        case 'show': pattern = `/${resource}/:id`; break;
        case 'new': pattern = `/${resource}/new`; break;
        case 'edit': pattern = `/${resource}/:id/edit`; break;
        default: pattern = `/${resource}/${action.toLowerCase()}`;
      }
      return `  '${pattern}': View${i}`;
    }
    return null;
  }).filter(Boolean).join(',\n');

  return `// Auto-generated client entry for hydration
// Generated by juntos dual-bundle mode
//
// This file imports JSX views for React hydration.
// Model imports are routed to RPC adapter (not database) because
// this file is in .client/ and tracked as a client bundle path.

import React from 'react';
import { hydrateRoot } from 'react-dom/client';

// Import JSX views (models will use RPC adapter)
${viewImports}

// Map routes to view components
const views = {
${viewMap}
};

console.log('[juntos] Client bundle loaded');

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}

async function init() {
  console.log('[juntos] Initializing client');

  // Get hydration props from server
  const propsEl = document.getElementById('__JUNTOS_PROPS__');
  const props = propsEl ? JSON.parse(propsEl.textContent) : {};
  console.log('[juntos] Server props:', props);

  // Find elements marked for hydration by the server
  // Server wraps React content in <div data-juntos-view="/path">
  const hydrationTargets = document.querySelectorAll('[data-juntos-view]');
  if (hydrationTargets.length === 0) {
    console.log('[juntos] No hydration targets found (no React views on this page)');
    return;
  }

  // Hydrate each target
  for (const target of hydrationTargets) {
    const path = target.getAttribute('data-juntos-view');
    const { view: ViewComponent, params } = matchRoute(path, views);

    if (ViewComponent) {
      console.log('[juntos] Hydrating view for path:', path);
      try {
        // Get serialized props from data attribute (set by server)
        const propsJson = target.getAttribute('data-juntos-props');
        const serializedProps = propsJson ? JSON.parse(propsJson) : {};

        // Merge: serialized props from server + route params + global props
        const viewProps = { ...props, ...serializedProps, ...params };
        console.log('[juntos] View props:', viewProps);

        hydrateRoot(target, React.createElement(ViewComponent, viewProps));
        console.log('[juntos] Hydration complete for:', path);
      } catch (err) {
        console.error('[juntos] Hydration error for', path, ':', err);
      }
    } else {
      console.log('[juntos] No matching view for path:', path, '- skipping hydration');
    }
  }

  // Set up form handlers for Turbo-style form submission
  setupFormHandlers();

  // Set up link handlers for client-side navigation
  setupLinkHandlers();

  console.log('[juntos] Client initialization complete');
}

// Simple route matching
function matchRoute(path, views) {
  for (const [pattern, view] of Object.entries(views)) {
    const params = matchPattern(pattern, path);
    if (params !== null) {
      return { view, params };
    }
  }
  return { view: null, params: {} };
}

function matchPattern(pattern, path) {
  const patternParts = pattern.split('/').filter(Boolean);
  const pathParts = path.split('/').filter(Boolean);

  if (patternParts.length !== pathParts.length) return null;

  const params = {};
  for (let i = 0; i < patternParts.length; i++) {
    if (patternParts[i].startsWith(':')) {
      params[patternParts[i].slice(1)] = pathParts[i];
    } else if (patternParts[i] !== pathParts[i]) {
      return null;
    }
  }
  return params;
}

// Handle form submissions via fetch (Turbo-style)
function setupFormHandlers() {
  document.addEventListener('submit', async (e) => {
    const form = e.target;
    if (form.tagName !== 'FORM') return;

    // Let forms with data-turbo="false" submit normally
    if (form.dataset.turbo === 'false') return;

    e.preventDefault();

    const action = form.action || window.location.href;
    const method = form.method?.toUpperCase() || 'POST';
    const formData = new FormData(form);

    // Handle _method override
    const methodOverride = formData.get('_method');
    const actualMethod = methodOverride?.toUpperCase() || method;

    console.log(\`[juntos] Form submit: \${actualMethod} \${action}\`);

    try {
      const response = await fetch(action, {
        method: actualMethod === 'GET' ? 'GET' : 'POST',
        body: actualMethod === 'GET' ? null : formData,
        headers: {
          'Accept': 'text/html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      });

      if (response.redirected) {
        window.location.href = response.url;
      } else if (response.ok) {
        const html = await response.text();
        // Check if it's a Turbo Stream response
        if (response.headers.get('Content-Type')?.includes('turbo-stream')) {
          // Process turbo stream
          processTurboStream(html);
        } else {
          // Full page update
          document.body.innerHTML = html;
          init(); // Re-initialize
        }
      }
    } catch (err) {
      console.error('[juntos] Form submit error:', err);
    }
  });
}

// Handle link clicks for client-side navigation
function setupLinkHandlers() {
  document.addEventListener('click', async (e) => {
    const link = e.target.closest('a');
    if (!link) return;

    // Only handle local links
    if (link.origin !== window.location.origin) return;

    // Skip links with data-turbo="false"
    if (link.dataset.turbo === 'false') return;

    // Skip links that should open in new window
    if (link.target === '_blank') return;

    e.preventDefault();

    console.log('[juntos] Navigate:', link.href);

    try {
      const response = await fetch(link.href, {
        headers: {
          'Accept': 'text/html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      });

      if (response.ok) {
        const html = await response.text();
        // Extract body content
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const newBody = doc.body.innerHTML;

        document.body.innerHTML = newBody;
        window.history.pushState({}, '', link.href);

        // Re-initialize
        await loadBrowserComponents();
      }
    } catch (err) {
      console.error('[juntos] Navigation error:', err);
      window.location.href = link.href; // Fallback
    }
  });

  // Handle back/forward navigation
  window.addEventListener('popstate', () => {
    window.location.reload();
  });
}

// Process Turbo Stream HTML
function processTurboStream(html) {
  const parser = new DOMParser();
  const doc = parser.parseFromString(html, 'text/html');
  const streams = doc.querySelectorAll('turbo-stream');

  for (const stream of streams) {
    const action = stream.getAttribute('action');
    const target = stream.getAttribute('target');
    const template = stream.querySelector('template');
    const content = template?.innerHTML || '';

    const targetEl = document.getElementById(target);
    if (!targetEl) continue;

    switch (action) {
      case 'replace':
        targetEl.outerHTML = content;
        break;
      case 'update':
        targetEl.innerHTML = content;
        break;
      case 'append':
        targetEl.insertAdjacentHTML('beforeend', content);
        break;
      case 'prepend':
        targetEl.insertAdjacentHTML('afterbegin', content);
        break;
      case 'remove':
        targetEl.remove();
        break;
    }
  }
}

// Load browser-only components (e.g., ReactFlow) that show placeholders during SSR
async function loadBrowserComponents() {
  // Find placeholder elements that indicate browser-only components
  const placeholders = document.querySelectorAll('[data-browser-component]');

  for (const placeholder of placeholders) {
    const componentName = placeholder.dataset.browserComponent;
    const propsJson = placeholder.dataset.props;

    console.log(\`[juntos] Loading browser component: \${componentName}\`);

    try {
      // Dynamic import of the component
      // This would need a mapping of component names to import paths
      // For now, we just log that we would load it
      console.log(\`[juntos] Would load: \${componentName}\`);
    } catch (err) {
      console.error(\`[juntos] Failed to load \${componentName}:\`, err);
    }
  }
}
`;
}
// Note: capitalize is imported from transform.mjs

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

      // Models: handled by juntos-ruby plugin (metadata rebuild + Turbo reload)

      // Routes: full reload (need full regeneration)
      if (normalizedFile.includes('/config/routes')) {
        console.log('[juntos] Routes changed, triggering reload:', file);
        hmrSend(server, { type: 'custom', event: 'juntos:reload' });
        return [];
      }

      // Rails controllers (app/controllers/): full reload
      if (normalizedFile.includes('/app/controllers/') && file.endsWith('.rb')) {
        console.log('[juntos] Rails controller changed, triggering reload:', file);
        hmrSend(server, { type: 'custom', event: 'juntos:reload' });
        return [];
      }

      // Stimulus controllers (app/javascript/controllers/): hot swap
      if (normalizedFile.includes('/app/javascript/controllers/') &&
          file.match(/_controller(\.jsx)?\.rb$/)) {
        const controllerName = extractControllerName(file);

        hmrSend(server, {
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
 * HMR runtime script for Stimulus controllers and Turbo-aware reloads.
 */
const STIMULUS_HMR_RUNTIME = `
if (import.meta.hot) {
  // Stimulus controller hot updates
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
 *
 * When dual bundle mode is active (RPC detected), imports from the .client/
 * directory are resolved to browser runtime instead of server runtime.
 */
function createVirtualPlugin(config, appRoot) {
  // Map targets/runtimes to target directory names
  const TARGET_DIR_MAP = {
    'browser': 'browser',
    'capacitor': 'capacitor',
    'electron': 'electron',
    'tauri': 'tauri',
    'electrobun': 'electrobun',
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
    'sqlite3': 'active_record_better_sqlite3.mjs',
    'better_sqlite3': 'active_record_better_sqlite3.mjs',
    'pg': 'active_record_pg.mjs',
    'postgres': 'active_record_pg.mjs',
    'mysql2': 'active_record_mysql2.mjs',
    'neon': 'active_record_neon.mjs',
    'turso': 'active_record_turso.mjs',
    'planetscale': 'active_record_planetscale.mjs',
    'd1': 'active_record_d1.mjs',
    'sqljs': 'active_record_sqljs.mjs',
    'sqlite_wasm': 'active_record_sqlite_wasm.mjs',
    'sqlite-wasm': 'active_record_sqlite_wasm.mjs',
    'wa_sqlite': 'active_record_wa_sqlite.mjs',
    'wa-sqlite': 'active_record_wa_sqlite.mjs',
    'pglite': 'active_record_pglite.mjs',
    'supabase': 'active_record_supabase.mjs',
    'rpc': 'active_record_rpc.mjs'  // RPC adapter for client-side model access
  };

  // Map targets to Active Storage adapter file names
  // Browser targets use IndexedDB, server targets use disk, edge targets use S3
  const STORAGE_ADAPTER_MAP = {
    'browser': 'active_storage_indexeddb.mjs',
    'capacitor': 'active_storage_indexeddb.mjs',
    'electron': 'active_storage_indexeddb.mjs',
    'tauri': 'active_storage_indexeddb.mjs',
    'electrobun': 'active_storage_indexeddb.mjs',
    'pwa': 'active_storage_indexeddb.mjs',
    'node': 'active_storage_disk.mjs',
    'bun': 'active_storage_disk.mjs',
    'deno': 'active_storage_disk.mjs',
    'fly': 'active_storage_s3.mjs',        // Edge/serverless - use S3
    'cloudflare': 'active_storage_s3.mjs', // Cloudflare Workers - use R2 via S3 API
    'vercel-edge': 'active_storage_s3.mjs',
    'vercel-node': 'active_storage_disk.mjs',
    'deno-deploy': 'active_storage_s3.mjs'
  };

  const targetDir = TARGET_DIR_MAP[config.target] || 'browser';
  const adapterFile = ADAPTER_FILE_MAP[config.database] || 'active_record_dexie.mjs';
  const storageAdapterFile = STORAGE_ADAPTER_MAP[config.target] || 'active_storage_indexeddb.mjs';

  // Load database config for injection
  const dbConfig = loadDatabaseConfig(appRoot, { quiet: true }) || {};
  if (config.database) dbConfig.adapter = config.database;

  // Track which modules are part of the client bundle
  // This is needed because the client bundle needs browser runtime, not server runtime
  const clientModulePaths = new Set();

  // Helper to check if a path is part of the client bundle
  // Layouts and server-only files should always use server runtime
  function isClientBundlePath(filePath) {
    if (!filePath) return false;

    // Layouts are server-side only - never use client runtime
    // They use server-only helpers like stylesheetLinkTag, getAssetPath, etc.
    if (filePath.includes('/layouts/') || filePath.includes('\\layouts\\')) return false;

    // Direct .client/ path
    if (filePath.includes('/.client/') || filePath.includes('\\.client\\')) return true;

    // Already tracked as part of client bundle
    if (clientModulePaths.has(filePath)) return true;

    return false;
  }

  return {
    name: 'juntos-virtual',
    enforce: 'pre',

    // Track modules imported from .client/ entry
    resolveId(id, importer) {
      // Track client bundle module paths for transitive imports
      // But exclude server-only modules like layouts
      if (importer && isClientBundlePath(importer)) {
        // This module is being imported from the client bundle
        // Track it so we can use browser runtime for its imports too
        if (id.startsWith('.')) {
          // Relative path - resolve to absolute
          const resolvedPath = path.resolve(path.dirname(importer), id);
          // Don't track layouts - they're server-only
          if (!resolvedPath.includes('/layouts/') && !resolvedPath.includes('\\layouts\\')) {
            clientModulePaths.add(resolvedPath);
          }
        } else if (!id.startsWith('\0') && !id.includes(':')) {
          // Non-virtual, non-relative - could be a source file
          const absPath = path.join(appRoot, id);
          // Don't track layouts
          if (!absPath.includes('/layouts/') && !absPath.includes('\\layouts\\')) {
            if (fs.existsSync(absPath)) {
              clientModulePaths.add(absPath);
            }
          }
        }
      }

      // For virtual modules, add suffix to distinguish client vs server versions
      if (id === 'juntos:rails') {
        // Check if this import is from the client bundle
        const isClient = isClientBundlePath(importer);
        return isClient ? '\0juntos:rails:client' : '\0juntos:rails';
      }
      if (id === 'juntos:active-record') {
        const isClient = isClientBundlePath(importer);
        return isClient ? '\0juntos:active-record:client' : '\0juntos:active-record';
      }
      if (id === 'juntos:active-record-client') return '\0juntos:active-record-client';
      if (id === 'juntos:active-storage') {
        const isClient = isClientBundlePath(importer);
        return isClient ? '\0juntos:active-storage:client' : '\0juntos:active-storage';
      }

      // juntos:paths - path helpers extracted from routes (breaks circular dependency)
      if (id === 'juntos:paths') return '\0juntos:paths';

      // For browser targets, use browser-specific path helper that invokes controllers directly
      // instead of making fetch() calls (which require a server)
      if (id === 'juntos/path_helper.mjs' && targetDir === 'browser') {
        return '\0juntos:path-helper:browser';
      }

      return null;
    },

    load(id) {
      // Browser path helper - routes through controllers instead of fetch()
      if (id === '\0juntos:path-helper:browser') {
        return `export * from 'juntos/path_helper_browser.mjs';`;
      }

      // Server version of juntos:rails
      if (id === '\0juntos:rails') {
        return `export * from 'juntos/targets/${targetDir}/rails.js';`;
      }

      // Client version of juntos:rails - always use browser runtime
      if (id === '\0juntos:rails:client') {
        return `export * from 'juntos/targets/browser/rails.js';`;
      }

      // Server version of juntos:active-record
      if (id === '\0juntos:active-record') {
        return `
// Database configuration injected at build time
// Runtime environment variables take precedence
export const DB_CONFIG = ${JSON.stringify(dbConfig)};

export * from 'juntos/adapters/${adapterFile}';
`;
      }

      // Client version of juntos:active-record - use RPC adapter for client
      if (id === '\0juntos:active-record:client') {
        return `export * from 'juntos/adapters/active_record_rpc.mjs';`;
      }

      if (id === '\0juntos:active-record-client') {
        // Legacy alias for RPC adapter
        return `export * from 'juntos/adapters/active_record_rpc.mjs';`;
      }

      // Server version of juntos:active-storage
      if (id === '\0juntos:active-storage') {
        return `export * from 'juntos/adapters/${storageAdapterFile}';`;
      }

      // Client version of juntos:active-storage - always use IndexedDB
      if (id === '\0juntos:active-storage:client') {
        return `export * from 'juntos/adapters/active_storage_indexeddb.mjs';`;
      }

      // juntos:paths - path helpers only (no controller imports)
      // This breaks the circular dependency between routes.rb and controllers
      if (id === '\0juntos:paths') {
        return generatePathsModule(appRoot, config);
      }

      return null;
    }
  };
}

/**
 * Generate the juntos:paths virtual module content.
 * This transforms routes.rb with paths_only: true to get just path helpers.
 */
async function generatePathsModule(appRoot, config) {
  const routesFile = path.join(appRoot, 'config/routes.rb');
  if (!fs.existsSync(routesFile)) {
    return '// No routes.rb found\n';
  }

  const { convert } = await ensureRuby2jsReady();
  const source = fs.readFileSync(routesFile, 'utf-8');

  // Get routes-specific config from ruby2js.yml if available
  const sectionConfig = config.sections?.routes || null;
  const options = {
    ...getBuildOptions(null, config.target, sectionConfig),
    file: 'config/routes.rb',
    database: config.database,
    target: config.target,
    paths_only: true,  // Generate only path helpers, no controller imports
    base: config.base || '/'
  };

  const result = convert(source, options);
  let js = result.toString();

  // Fix path helper import for browser targets
  if (config.target === 'browser') {
    js = js.replace(
      /from ['"]juntos\/path_helper\.mjs['"]/g,
      "from 'juntos/path_helper_browser.mjs'"
    );
  }

  return js;
}

export default juntos;
