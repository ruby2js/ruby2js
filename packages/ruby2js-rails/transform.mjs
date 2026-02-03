/**
 * Shared transformation logic for Ruby2JS Rails applications.
 *
 * Used by both vite.mjs (on-the-fly transformation) and cli.mjs (eject command).
 * This ensures ejected output matches what Vite produces.
 */

import path from 'node:path';
import fs from 'node:fs';

// Import ERB compiler for .erb files
import { ErbCompiler } from './lib/erb_compiler.js';

// Import inflector for singularization
import { singularize } from 'ruby2js-rails/adapters/inflector.mjs';

// ============================================================
// Constants
// ============================================================

/**
 * Default target for each database adapter (used when target not specified).
 */
export const DEFAULT_TARGETS = Object.freeze({
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
 * Reserved words that need escaping in exports.
 */
export const RESERVED = new Set([
  'break', 'case', 'catch', 'continue', 'debugger', 'default', 'delete',
  'do', 'else', 'finally', 'for', 'function', 'if', 'in', 'instanceof',
  'new', 'return', 'switch', 'this', 'throw', 'try', 'typeof', 'var',
  'void', 'while', 'with', 'class', 'const', 'enum', 'export', 'extends',
  'import', 'super', 'implements', 'interface', 'let', 'package', 'private',
  'protected', 'public', 'static', 'yield'
]);

// ============================================================
// Helper functions
// ============================================================

/**
 * Capitalize first letter of a string.
 */
export function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

// Re-export singularize for convenience
export { singularize };

// ============================================================
// Build options
// ============================================================

/**
 * Get Ruby2JS transpilation options for a given section.
 * Uses filter names as strings (resolved by ruby2js).
 *
 * @param {string} section - The section type ('stimulus', 'controllers', 'jsx', or null for default)
 * @param {string} target - The build target ('browser', 'node', etc.)
 * @param {Object} sectionConfig - Optional section config from ruby2js.yml (e.g., { filters: [...], eslevel: 2022 })
 * @returns {Object} Ruby2JS options
 */
export function getBuildOptions(section, target, sectionConfig = null) {
  const baseOptions = {
    eslevel: sectionConfig?.eslevel || 2022,
    include: sectionConfig?.include || ['class', 'call']
  };

  // Default filter sets for each section
  // Node filter is included for targets with Node.js-compatible APIs (fs, child_process, process.env).
  // See docs/src/_docs/juntos/deploying/index.md for full target list.
  const nodeTargets = ['node', 'bun', 'deno', 'fly', 'electron'];
  const nodeFilter = target && nodeTargets.includes(target) ? ['Node'] : [];
  const defaultFilters = {
    stimulus: ['Pragma', 'Stimulus', 'Functions', 'ESM', 'Return'],
    controllers: ['Pragma', 'Rails_Controller', ...nodeFilter, 'Functions', 'ESM', 'Return'],
    jsx: ['Pragma', 'Rails_Helpers', 'React', 'Functions', 'ESM', 'Return'],
    default: ['Pragma', 'Rails_Model', 'Rails_Controller', 'Rails_Routes', 'Rails_Seeds', 'Rails_Migration', ...nodeFilter, 'Functions', 'ESM', 'Return']
  };

  // Use filters from sectionConfig if provided, otherwise use defaults
  // Filter names from config are normalized to match Ruby2JS conventions
  const filters = sectionConfig?.filters
    ? normalizeFilterNames(sectionConfig.filters)
    : defaultFilters[section] || defaultFilters.default;

  switch (section) {
    case 'stimulus':
      return {
        ...baseOptions,
        autoexports: sectionConfig?.autoexports ?? 'default',
        filters,
        target
      };

    case 'controllers':
      return {
        ...baseOptions,
        autoexports: sectionConfig?.autoexports ?? true,
        filters,
        target
      };

    case 'jsx':
      return {
        ...baseOptions,
        autoexports: sectionConfig?.autoexports ?? 'default',
        filters,
        target
      };

    default:
      // Models, routes, seeds, migrations
      return {
        ...baseOptions,
        autoexports: sectionConfig?.autoexports ?? true,
        filters,
        target
      };
  }
}

/**
 * Normalize filter names from ruby2js.yml to Ruby2JS conventions.
 * Converts lowercase names to proper case (e.g., 'stimulus' -> 'Stimulus')
 */
function normalizeFilterNames(filters) {
  const filterMap = {
    // Lowercase to proper case mapping
    'pragma': 'Pragma',
    'stimulus': 'Stimulus',
    'functions': 'Functions',
    'esm': 'ESM',
    'return': 'Return',
    'react': 'React',
    'camelcase': 'CamelCase',
    'rails_controller': 'Rails_Controller',
    'rails_model': 'Rails_Model',
    'rails_routes': 'Rails_Routes',
    'rails_seeds': 'Rails_Seeds',
    'rails_migration': 'Rails_Migration',
    'rails_helpers': 'Rails_Helpers',
    'phlex': 'Phlex',
    'node': 'Node',
    // Also handle slash notation from config
    'rails/controller': 'Rails_Controller',
    'rails/model': 'Rails_Model',
    'rails/routes': 'Rails_Routes',
    'rails/seeds': 'Rails_Seeds',
    'rails/migration': 'Rails_Migration',
    'rails/helpers': 'Rails_Helpers'
  };

  return filters.map(f => filterMap[f.toLowerCase()] || f);
}

// ============================================================
// File discovery
// ============================================================

/**
 * Find all model files in app/models/.
 * Returns array of model names (without .rb extension).
 */
export function findModels(appRoot) {
  const modelsDir = path.join(appRoot, 'app/models');
  if (!fs.existsSync(modelsDir)) return [];
  return fs.readdirSync(modelsDir)
    .filter(f => f.endsWith('.rb') && f !== 'application_record.rb' && !f.startsWith('._'))
    .map(f => f.replace('.rb', ''));
}

/**
 * Find all migration files in db/migrate/.
 * Returns array of { file, name } objects.
 */
export function findMigrations(appRoot) {
  const migrateDir = path.join(appRoot, 'db/migrate');
  if (!fs.existsSync(migrateDir)) return [];
  return fs.readdirSync(migrateDir)
    .filter(f => f.endsWith('.rb') && !f.startsWith('._'))
    .sort()
    .map(f => ({ file: f, name: f.replace('.rb', '') }));
}

/**
 * Find all view resource directories in app/views/.
 * Returns array of directory names (e.g., ['articles', 'comments']).
 */
export function findViewResources(appRoot) {
  const viewsDir = path.join(appRoot, 'app/views');
  if (!fs.existsSync(viewsDir)) return [];
  return fs.readdirSync(viewsDir, { withFileTypes: true })
    .filter(d => d.isDirectory() && d.name !== 'layouts' && !d.name.startsWith('.'))
    .map(d => d.name);
}

/**
 * Find all Stimulus controllers in app/javascript/controllers/.
 * Returns array of { file, name } objects.
 */
export function findControllers(appRoot) {
  const controllersDir = path.join(appRoot, 'app/javascript/controllers');
  if (!fs.existsSync(controllersDir)) return [];
  return fs.readdirSync(controllersDir)
    .filter(f => (f.endsWith('_controller.rb') || f.endsWith('_controller.js')) && !f.startsWith('._'))
    .map(f => ({
      file: f,
      name: f.replace(/_controller\.(rb|js)$/, '').replace(/_/g, '-')
    }));
}

// ============================================================
// Import path rewriting
// ============================================================

/**
 * Fix imports in transpiled code to use virtual modules and source files.
 * Used by Vite plugin for on-the-fly transformation.
 */
export function fixImports(js, fromFile) {
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

  // Config: ../../config/paths.js → juntos:paths (path helpers virtual module)
  // This breaks the circular dependency between routes.rb and controllers
  js = js.replace(/from ['"]\.\.\/\.\.\/config\/paths\.js['"]/g, "from 'juntos:paths'");
  js = js.replace(/from ['"]\.\/paths\.js['"]/g, "from 'juntos:paths'");

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

/**
 * Fix imports in test files for ejected code.
 * Rewrites virtual module imports to concrete paths.
 */
export function fixTestImportsForEject(js) {
  // Virtual modules → concrete paths
  js = js.replace(/from ['"]juntos:models['"]/g, "from '../app/models/index.js'");
  js = js.replace(/await import\(['"]juntos:models['"]\)/g, "await import('../app/models/index.js')");

  js = js.replace(/from ['"]juntos:rails['"]/g, "from 'ruby2js-rails/rails_base.js'");
  js = js.replace(/await import\(['"]juntos:rails['"]\)/g, "await import('ruby2js-rails/rails_base.js')");

  js = js.replace(/from ['"]juntos:migrations['"]/g, "from '../db/migrate/index.js'");
  js = js.replace(/await import\(['"]juntos:migrations['"]\)/g, "await import('../db/migrate/index.js')");

  js = js.replace(/from ['"]juntos:active-record['"]/g, "from 'ruby2js-rails/adapters/active_record.mjs'");
  js = js.replace(/await import\(['"]juntos:active-record['"]\)/g, "await import('ruby2js-rails/adapters/active_record.mjs')");

  // Path helpers virtual module → concrete paths.js file
  js = js.replace(/from ['"]juntos:paths['"]/g, "from '../config/paths.js'");
  js = js.replace(/await import\(['"]juntos:paths['"]\)/g, "await import('../config/paths.js')");

  // Controller imports: .rb → .js
  js = js.replace(/from ['"]\.\.\/app\/controllers\/(\w+)\.rb['"]/g, "from '../app/controllers/$1.js'");
  js = js.replace(/await import\(['"]\.\.\/app\/controllers\/(\w+)\.rb['"]\)/g, "await import('../app/controllers/$1.js')");

  return js;
}

/**
 * Fix imports for ejected code - rewrites to use ruby2js-rails package.
 * Ejected code depends on the juntos runtime, not copied local files.
 * @param {string} js - The JavaScript code to fix
 * @param {string} fromFile - Relative output path of the file (e.g., 'app/models/article.js')
 * @param {object} config - Configuration with target/database info
 */
export function fixImportsForEject(js, fromFile, config = {}) {
  // Determine the target runtime based on config
  // Default to 'node' for sqlite3/better_sqlite3, 'browser' for dexie
  let target = config.target || 'node';
  if (!config.target && config.database === 'dexie') {
    target = 'browser';
  }

  const railsModule = `ruby2js-rails/targets/${target}/rails.js`;

  // Runtime modules → target-specific rails.js
  js = js.replace(/from ['"]\.\.\/lib\/rails\.js['"]/g, `from '${railsModule}'`);
  js = js.replace(/from ['"]\.\.\/\.\.\/lib\/rails\.js['"]/g, `from '${railsModule}'`);
  js = js.replace(/from ['"]\.\.\/\.\.\/\.\.\/lib\/rails\.js['"]/g, `from '${railsModule}'`);
  js = js.replace(/from ['"]lib\/rails\.js['"]/g, `from '${railsModule}'`);
  js = js.replace(/from ['"]ruby2js-rails\/rails_base\.js['"]/g, `from '${railsModule}'`);
  js = js.replace(/from ['"]\.\.\/lib\/active_record\.mjs['"]/g, "from 'ruby2js-rails/adapters/active_record.mjs'");
  js = js.replace(/from ['"]\.\.\/\.\.\/lib\/active_record\.mjs['"]/g, "from 'ruby2js-rails/adapters/active_record.mjs'");

  // Virtual module @config/paths.js → config/paths.js with correct relative path
  // Path helpers are in a separate file to avoid circular dependency with routes.js
  if (fromFile) {
    // Calculate relative path from the file to config/paths.js
    const depth = fromFile.split('/').length - 1;
    const prefix = '../'.repeat(depth);
    js = js.replace(/from ['"]@config\/paths\.js['"]/g, `from '${prefix}config/paths.js'`);
  } else {
    // Fallback: assume we're one level deep
    js = js.replace(/from ['"]@config\/paths\.js['"]/g, "from '../config/paths.js'");
  }

  // Handle relative paths to config/paths.js (keep as paths.js, not routes.js)
  // This is used for controllers: ../../config/paths.js → ../../config/paths.js
  // No change needed - paths.js is the correct target

  // ApplicationRecord → local file (generated separately)
  js = js.replace(/from ['"]\.\/application_record\.js['"]/g, "from './application_record.js'");

  // Model imports: .js extension for ejected files
  js = js.replace(/from ['"]\.\/(\w+)\.js['"]/g, "from './$1.js'");

  // Path helper → ruby2js-rails package
  js = js.replace(/from ['"]ruby2js-rails\/path_helper\.mjs['"]/g, "from 'ruby2js-rails/path_helper.mjs'");

  return js;
}

// ============================================================
// Virtual module content generators
// ============================================================

/**
 * Generate content for juntos:models virtual module.
 */
export function generateModelsModule(appRoot) {
  const models = findModels(appRoot);
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

/**
 * Generate content for juntos:models for ejected output.
 * Uses ruby2js-rails package for runtime, local paths for app code.
 */
export function generateModelsModuleForEject(appRoot, config = {}) {
  const models = findModels(appRoot);
  const adapterFile = getActiveRecordAdapterFile(config.database);

  // Determine target for importing Application
  let target = config.target || 'node';
  if (!config.target && config.database === 'dexie') {
    target = 'browser';
  }
  const railsModule = `ruby2js-rails/targets/${target}/rails.js`;

  const imports = models.map(m => {
    const className = m.split('_').map(s => s[0].toUpperCase() + s.slice(1)).join('');
    return `import { ${className} } from './${m}.js';`;
  });
  const classNames = models.map(m =>
    m.split('_').map(s => s[0].toUpperCase() + s.slice(1)).join('')
  );
  return `${imports.join('\n')}
import { Application } from '${railsModule}';
import { modelRegistry, attr_accessor } from 'ruby2js-rails/adapters/${adapterFile}';
import { migrations } from '../../db/migrate/index.js';
const models = { ${classNames.join(', ')} };
Application.registerModels(models);
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

/**
 * Generate application_record.js for ejected output.
 * This provides the base class for all models.
 */
export function generateApplicationRecordForEject(config = {}) {
  const adapterFile = getActiveRecordAdapterFile(config.database);
  return `import { ActiveRecord as Base, CollectionProxy } from 'ruby2js-rails/adapters/${adapterFile}';

export class ApplicationRecord extends Base {
  static primaryAbstractClass = true;
}

export { CollectionProxy };
`;
}

/**
 * Generate package.json for ejected output.
 */
export function generatePackageJsonForEject(appName, config = {}) {
  const RELEASES_BASE = 'https://ruby2js.github.io/ruby2js/releases';

  // Determine if this is a browser target
  const browserTargets = ['browser', 'pwa', 'capacitor', 'electron', 'tauri'];
  const isBrowserTarget = browserTargets.includes(config.target);

  const scripts = {
    dev: 'vite',
    build: 'vite build',
    preview: 'vite preview',
    test: 'vitest run'
  };

  // Only add start script for server targets
  if (!isBrowserTarget) {
    scripts.start = 'node main.js';
  }

  const pkg = {
    name: appName,
    type: 'module',
    scripts,
    dependencies: {
      'ruby2js': `${RELEASES_BASE}/ruby2js-beta.tgz`,
      'ruby2js-rails': `${RELEASES_BASE}/ruby2js-rails-beta.tgz`,
      'react': '^18.0.0',
      'react-dom': '^18.0.0'
    },
    devDependencies: {
      'vite': '^7.0.0',
      'vitest': '^2.0.0'
    }
  };

  // Add browser dependencies
  if (isBrowserTarget) {
    pkg.dependencies['@hotwired/turbo'] = '^8.0.0';
    pkg.dependencies['@hotwired/stimulus'] = '^3.2.0';
  }

  // Add database adapter dependency based on config
  if (config.database === 'sqlite3' || config.database === 'sqlite' || config.database === 'better_sqlite3') {
    pkg.dependencies['better-sqlite3'] = '^11.10.0';
  } else if (config.database === 'dexie') {
    pkg.dependencies['dexie'] = '^4.0.0';
  }

  return JSON.stringify(pkg, null, 2) + '\n';
}

/**
 * Generate test/setup.mjs for ejected output.
 */
export function generateTestSetupForEject(config = {}) {
  const adapterFile = getActiveRecordAdapterFile(config.database);

  // Determine target for importing Application
  let target = config.target || 'node';
  if (!config.target && config.database === 'dexie') {
    target = 'browser';
  }
  const railsModule = `ruby2js-rails/targets/${target}/rails.js`;

  return `// Test setup for Vitest - ejected version
import { beforeAll, beforeEach } from 'vitest';

beforeAll(async () => {
  // Import models (registers them with Application and modelRegistry)
  await import('../app/models/index.js');

  // Configure migrations
  const { Application } = await import('${railsModule}');
  const { migrations } = await import('../db/migrate/index.js');
  Application.configure({ migrations });
});

beforeEach(async () => {
  // Fresh in-memory database for each test
  const activeRecord = await import('ruby2js-rails/adapters/${adapterFile}');
  await activeRecord.initDatabase({ database: ':memory:' });

  const { Application } = await import('${railsModule}');
  await Application.runMigrations(activeRecord);
});
`;
}

/**
 * Get the active record adapter filename for a database.
 */
function getActiveRecordAdapterFile(database) {
  const adapterMap = {
    'sqlite': 'active_record_better_sqlite3.mjs',
    'sqlite3': 'active_record_better_sqlite3.mjs',
    'better_sqlite3': 'active_record_better_sqlite3.mjs',
    'dexie': 'active_record_dexie.mjs',
    'pg': 'active_record_pg.mjs',
    'postgres': 'active_record_pg.mjs',
    'neon': 'active_record_neon.mjs',
    'd1': 'active_record_d1.mjs',
    'turso': 'active_record_turso.mjs',
    'pglite': 'active_record_pglite.mjs',
    'sqljs': 'active_record_sqljs.mjs',
    'mysql': 'active_record_mysql2.mjs',
    'mysql2': 'active_record_mysql2.mjs'
  };
  return adapterMap[database] || 'active_record_dexie.mjs';
}

/**
 * Generate main.js entry point for ejected Node.js server.
 */
export function generateMainJsForEject(config = {}) {
  const adapterFile = getActiveRecordAdapterFile(config.database);
  const dbConfig = config.database === 'sqlite' || config.database === 'sqlite3' || config.database === 'better_sqlite3'
    ? `{ adapter: 'better_sqlite3', database: './db/development.sqlite3' }`
    : `{ adapter: '${config.database || 'dexie'}', database: 'app_dev' }`;

  // Determine target for importing Application
  let target = config.target || 'node';
  if (!config.target && config.database === 'dexie') {
    target = 'browser';
  }
  const railsModule = `ruby2js-rails/targets/${target}/rails.js`;

  return `// Main entry point for ejected Node.js server
import { Application, Router } from '${railsModule}';
import * as activeRecord from 'ruby2js-rails/adapters/${adapterFile}';

// Import models (registers them)
import './app/models/index.js';

// Import migrations and seeds
import { migrations } from './db/migrate/index.js';
import { Seeds } from './db/seeds.js';

// Import routes (sets up the router)
import './config/routes.js';

async function main() {
  // Configure application
  Application.configure({ migrations });

  // Initialize database
  console.log('Initializing database...');
  await activeRecord.initDatabase(${dbConfig});

  // Run migrations
  console.log('Running migrations...');
  await Application.runMigrations(activeRecord);

  // Run seeds if database is fresh
  if (Seeds && typeof Seeds.run === 'function') {
    console.log('Running seeds...');
    await Seeds.run();
  }

  // Start server
  const port = process.env.PORT || 3000;
  console.log(\`Starting server on http://localhost:\${port}\`);

  // Create HTTP server with Router dispatch
  const { createServer } = await import('http');
  const server = createServer(async (req, res) => {
    await Router.dispatch(req, res);
  });

  server.listen(port);
}

main().catch(console.error);
`;
}

/**
 * Generate vitest.config.js for ejected output.
 */
export function generateVitestConfigForEject(config = {}) {
  const externals = [];

  // Native modules need to be externalized
  if (config.database === 'sqlite3') {
    externals.push('better-sqlite3');
  }

  const externalConfig = externals.length > 0
    ? `\n  server: {\n    deps: {\n      external: ${JSON.stringify(externals)}\n    }\n  },`
    : '';

  return `import { defineConfig } from 'vitest/config';

export default defineConfig({${externalConfig}
  test: {
    globals: true,
    environment: 'node',
    include: ['test/**/*.test.mjs', 'test/**/*.test.js'],
    setupFiles: ['./test/setup.mjs']
  }
});
`;
}

/**
 * Generate vite.config.js for ejected output.
 * This is a plain Vite config - no ruby2js plugins needed since code is already JS.
 */
export function generateViteConfigForEject(config = {}) {
  const adapterFile = getActiveRecordAdapterFile(config.database);

  // Determine if this is a browser target
  const browserTargets = ['browser', 'pwa', 'capacitor', 'electron', 'tauri'];
  const isBrowserTarget = browserTargets.includes(config.target);

  // Build aliases - always include app paths
  const aliases = [
    `      'app/': './app/'`,
    `      'config/': './config/'`,
    `      'db/': './db/'`
  ];

  // Add virtual module aliases for browser targets
  if (isBrowserTarget) {
    aliases.push(`      'juntos:active-record': 'ruby2js-rails/adapters/${adapterFile}'`);
  }

  return `import { defineConfig } from 'vite';

export default defineConfig({
  // Ejected JavaScript - no ruby2js transformation needed
  resolve: {
    alias: {
${aliases.join(',\n')}
    }
  }
});
`;
}

/**
 * Generate index.html for browser builds.
 * Used by both Vite plugin (dev) and eject command (standalone).
 * @param {string} appName - Application name for the title
 * @param {string} mainJsPath - Path to main.js (e.g., '/.browser/main.js' or './main.js')
 */
export function generateBrowserIndexHtml(appName, mainJsPath = './main.js') {
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
  <script type="module" src="${mainJsPath}"></script>
</body>
</html>
`;
}

/**
 * Generate main.js entry point for browser builds.
 * Used by both Vite plugin (dev) and eject command (standalone).
 * @param {string} routesPath - Import path for routes (e.g., '../config/routes.rb' or './config/routes.js')
 * @param {string} controllersPath - Import path for controllers (e.g., '../app/javascript/controllers/index.js')
 */
export function generateBrowserMainJs(routesPath = './config/routes.js', controllersPath = './app/javascript/controllers/index.js') {
  return `// Main entry point for browser
import * as Turbo from '@hotwired/turbo';
import { Application } from '${routesPath}';
import '${controllersPath}';
window.Turbo = Turbo;
Application.start();
`;
}

/**
 * Generate content for juntos:migrations virtual module.
 */
export function generateMigrationsModule(appRoot) {
  const migrations = findMigrations(appRoot);
  const imports = migrations.map((m, i) =>
    `import { migration as migration${i} } from 'db/migrate/${m.file}';`
  );
  const exports = migrations.map((m, i) =>
    `{ version: '${m.name.split('_')[0]}', name: '${m.name}', ...migration${i} }`
  );
  return `${imports.join('\n')}
export const migrations = [${exports.join(', ')}];
`;
}

/**
 * Generate content for juntos:migrations for ejected output.
 */
export function generateMigrationsModuleForEject(appRoot) {
  const migrations = findMigrations(appRoot);
  const imports = migrations.map((m, i) =>
    `import { migration as migration${i} } from './${m.name}.js';`
  );
  const exports = migrations.map((m, i) =>
    `{ version: '${m.name.split('_')[0]}', name: '${m.name}', ...migration${i} }`
  );
  return `${imports.join('\n')}
export const migrations = [${exports.join(', ')}];
`;
}

/**
 * Deduplicate view exports when a partial and non-partial share the same name.
 * E.g., _index.html.erb and index.html.erb both produce exportName "index".
 * Non-partials win; partials keep their _ prefix to avoid collision.
 */
function deduplicateViewExports(views) {
  const seen = new Set();
  // First pass: collect non-partial export names
  for (const v of views) {
    if (!v.isPartial) seen.add(v.exportName);
  }
  // Second pass: rename partials that conflict with non-partials
  for (const v of views) {
    if (v.isPartial && seen.has(v.exportName)) {
      v.exportName = '_' + v.exportName;
    }
    seen.add(v.exportName);
  }
  return views;
}

/**
 * Generate content for juntos:views/* virtual module.
 * @param {string} appRoot - Application root
 * @param {string} resource - Resource name (e.g., 'articles', 'workflows')
 * @returns {string} Module content
 */
export function generateViewsModule(appRoot, resource) {
  const viewsDir = path.join(appRoot, 'app/views', resource);
  if (!fs.existsSync(viewsDir)) return `export const ${capitalize(resource)}Views = {};`;

  // Collect ERB views (.html.erb)
  const erbViews = fs.readdirSync(viewsDir)
    .filter(f => f.endsWith('.html.erb') && !f.startsWith('._'))
    .map(f => {
      const name = f.replace('.html.erb', '');
      const isPartial = name.startsWith('_');
      let exportName = isPartial ? name.slice(1) : name;
      // Escape reserved words by adding $ prefix (matches Ruby2JS convention)
      if (RESERVED.has(exportName)) exportName = '$' + exportName;
      return { file: f, name, exportName, isPartial, isReact: false };
    });

  // Collect React views (.jsx.rb) - these export default, not render
  const reactViews = fs.readdirSync(viewsDir)
    .filter(f => f.endsWith('.jsx.rb') && !f.startsWith('._'))
    .map(f => {
      // Show.jsx.rb -> show (lowercase)
      const name = f.replace('.jsx.rb', '');
      let exportName = name.toLowerCase();
      if (RESERVED.has(exportName)) exportName = '$' + exportName;
      return { file: f, name, exportName, isPartial: false, isReact: true };
    });

  const views = deduplicateViewExports([...erbViews, ...reactViews]);

  const imports = views.map(v => {
    if (v.isReact) {
      // React components export default
      return `import ${v.exportName} from 'app/views/${resource}/${v.file}';`;
    } else {
      // ERB views export { render }
      return `import { render as ${v.exportName} } from 'app/views/${resource}/${v.file}';`;
    }
  });

  // Create namespace object: ArticleViews = { index, show, new_, edit, ... }
  // Use singularized form to match controller filter (ArticleViews, not ArticlesViews)
  const className = capitalize(singularize(resource)) + 'Views';
  const members = views.map(v => v.exportName);

  return `${imports.join('\n')}
export const ${className} = { ${members.join(', ')} };
export { ${members.join(', ')} };
`;
}

/**
 * Generate content for views module for ejected output.
 */
export function generateViewsModuleForEject(appRoot, resource) {
  const viewsDir = path.join(appRoot, 'app/views', resource);
  if (!fs.existsSync(viewsDir)) return `export const ${capitalize(resource)}Views = {};`;

  // Collect ERB views (.html.erb)
  const erbViews = fs.readdirSync(viewsDir)
    .filter(f => f.endsWith('.html.erb') && !f.startsWith('._'))
    .map(f => {
      const name = f.replace('.html.erb', '');
      const isPartial = name.startsWith('_');
      let exportName = isPartial ? name.slice(1) : name;
      if (RESERVED.has(exportName)) exportName = '$' + exportName;
      // Output filename: index.html.erb → index.js
      const outputFile = f.replace('.html.erb', '.js');
      return { file: f, outputFile, name, exportName, isPartial, isReact: false };
    });

  // Collect React views (.jsx.rb)
  const reactViews = fs.readdirSync(viewsDir)
    .filter(f => f.endsWith('.jsx.rb') && !f.startsWith('._'))
    .map(f => {
      const name = f.replace('.jsx.rb', '');
      let exportName = name.toLowerCase();
      if (RESERVED.has(exportName)) exportName = '$' + exportName;
      // Output filename: Show.jsx.rb → Show.js
      const outputFile = f.replace('.jsx.rb', '.js');
      return { file: f, outputFile, name, exportName, isPartial: false, isReact: true };
    });

  const views = deduplicateViewExports([...erbViews, ...reactViews]);

  const imports = views.map(v => {
    if (v.isReact) {
      return `import ${v.exportName} from './${resource}/${v.outputFile}';`;
    } else {
      return `import { render as ${v.exportName} } from './${resource}/${v.outputFile}';`;
    }
  });

  const className = capitalize(singularize(resource)) + 'Views';
  const members = views.map(v => v.exportName);

  return `${imports.join('\n')}
export const ${className} = { ${members.join(', ')} };
export { ${members.join(', ')} };
`;
}

// ============================================================
// Transformation functions
// ============================================================

// Lazy-loaded ruby2js module
let ruby2jsModule = null;
let filtersLoaded = false;

/**
 * Ensure ruby2js module is loaded, Prism is initialized, and filters are loaded.
 */
export async function ensureRuby2jsReady() {
  if (!ruby2jsModule) {
    ruby2jsModule = await import('ruby2js');
    await ruby2jsModule.initPrism();
  }

  // Load all filters needed for Rails apps (used by both Vite and eject)
  if (!filtersLoaded) {
    // Core filters
    await import('ruby2js/filters/functions.js');
    await import('ruby2js/filters/esm.js');
    await import('ruby2js/filters/return.js');
    await import('ruby2js/filters/pragma.js');
    await import('ruby2js/filters/polyfill.js');

    // Rails filters
    await import('ruby2js/filters/rails/model.js');
    await import('ruby2js/filters/rails/controller.js');
    await import('ruby2js/filters/rails/routes.js');
    await import('ruby2js/filters/rails/seeds.js');
    await import('ruby2js/filters/rails/migration.js');
    await import('ruby2js/filters/rails/helpers.js');

    // Template filters
    await import('ruby2js/filters/erb.js');

    // Component filters
    await import('ruby2js/filters/react.js');
    await import('ruby2js/filters/stimulus.js');

    // Node.js filter (File operations, backtick commands, etc.)
    await import('ruby2js/filters/node.js');

    filtersLoaded = true;
  }

  return ruby2jsModule;
}

/**
 * Transform Ruby source to JavaScript.
 *
 * @param {string} source - Ruby source code
 * @param {string} filePath - Path to source file (for sourcemaps)
 * @param {string} section - Transformation section (stimulus, controllers, jsx, or null for default)
 * @param {Object} config - Configuration object with target, database, base, etc.
 * @param {string} appRoot - Application root directory
 * @returns {Promise<{code: string, map: Object}>}
 */
export async function transformRuby(source, filePath, section, config, appRoot) {
  const { convert } = await ensureRuby2jsReady();

  // Get section-specific config from ruby2js.yml if available
  const sectionConfig = config.sections?.[section] || null;
  const options = {
    ...getBuildOptions(section, config.target, sectionConfig),
    file: path.relative(appRoot, filePath),
    database: config.database,
    target: config.target
  };

  // Routes need additional options
  if (filePath.endsWith('/routes.rb')) {
    options.base = config.base || '/';
  }

  const result = convert(source, options);
  return {
    code: result.toString(),
    map: result.sourcemap
  };
}

/**
 * Transform ERB template to JavaScript.
 *
 * @param {string} code - ERB source code
 * @param {string} id - File path
 * @param {boolean} isLayout - Whether this is a layout file
 * @param {Object} config - Configuration object
 * @returns {Promise<{code: string, map: Object|null}>}
 */
export async function transformErb(code, id, isLayout, config) {
  const { convert } = await ensureRuby2jsReady();

  let template = code;

  // Step 1: Compile ERB to Ruby
  const compiler = new ErbCompiler(template);
  const rubySrc = compiler.src;

  // Step 2: Convert Ruby to JavaScript with ERB filters
  const nodeTargets = ['node', 'bun', 'deno', 'fly', 'electron'];
  const nodeFilter = config.target && nodeTargets.includes(config.target) ? ['Node'] : [];
  const options = {
    filters: ['Rails_Helpers', 'Erb', ...nodeFilter, 'Functions', 'Return'],
    eslevel: config.eslevel || 2022,
    include: ['class', 'call'],
    database: config.database,
    target: config.target,
    file: id
  };

  if (isLayout) {
    options.layout = true;
  }

  const result = convert(rubySrc, options);

  // Step 3: Export the function
  let js = result.toString();
  if (isLayout) {
    js = js.replace(/(^|\n)(async )?function layout/, '$1export $2function layout');
  } else {
    js = js.replace(/(^|\n)(async )?function render/, '$1export $2function render');
  }

  return {
    code: js,
    map: result.sourcemap || null
  };
}

/**
 * Transform JSX.rb (Ruby + JSX) to JavaScript.
 *
 * @param {string} source - Ruby + JSX source code
 * @param {string} filePath - File path
 * @param {Object} config - Configuration object
 * @returns {Promise<{code: string, map: Object|null}>}
 */
export async function transformJsxRb(source, filePath, config) {
  const { convert } = await ensureRuby2jsReady();

  // Get section-specific config from ruby2js.yml if available
  const sectionConfig = config.sections?.jsx || null;
  const options = {
    ...getBuildOptions('jsx', config.target, sectionConfig),
    file: filePath
  };

  const result = convert(source, options);
  return {
    code: result.toString(),
    map: result.sourcemap || null
  };
}

// Re-export ErbCompiler for direct use if needed
export { ErbCompiler };
