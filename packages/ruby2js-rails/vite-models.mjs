/**
 * Ruby2JS Models Vite Plugin
 *
 * Framework-agnostic plugin for transpiling Ruby models and migrations.
 * Works with Astro, Vue, Svelte, or any Vite-based framework.
 *
 * Usage:
 *   import { ruby2jsModels } from 'ruby2js-rails/vite-models';
 *
 *   export default defineConfig({
 *     plugins: [
 *       ruby2jsModels({
 *         database: 'dexie',
 *         modelsDir: 'src/models',      // default: 'app/models'
 *         migrationsDir: 'db/migrate',  // default: 'db/migrate'
 *         outDir: 'src/lib/models'      // default: derived from modelsDir
 *       }),
 *       astro()  // or vue(), svelte(), etc.
 *     ]
 *   });
 */

import path from 'node:path';
import fs from 'node:fs';
import yaml from 'js-yaml';
import { SelfhostBuilder } from './build.mjs';

/**
 * @typedef {Object} Ruby2jsModelsOptions
 * @property {string} [database] - Database adapter (dexie, d1, sqlite, etc.)
 * @property {string} [target] - Build target (browser, cloudflare, node, etc.)
 * @property {string} [modelsDir] - Models directory (default: 'app/models')
 * @property {string} [migrationsDir] - Migrations directory (default: 'db/migrate')
 * @property {string} [outDir] - Output directory for transpiled files
 * @property {number} [eslevel] - ES level to target (default: 2022)
 */

/**
 * Default target mapping based on database adapter
 */
const DEFAULT_TARGETS = {
  dexie: 'browser',
  indexeddb: 'browser',
  sqljs: 'browser',
  pglite: 'browser',
  better_sqlite3: 'node',
  sqlite3: 'node',
  pg: 'node',
  mysql2: 'node',
  d1: 'cloudflare',
  neon: 'vercel',
  turso: 'node'
};

/**
 * Load database configuration from database.yml or environment
 */
function loadDatabaseConfig(appRoot, options = {}) {
  // Priority: JUNTOS_DATABASE env > options > database.yml
  let database = process.env.JUNTOS_DATABASE || options.database;

  if (!database) {
    const dbYmlPath = path.join(appRoot, 'config/database.yml');
    if (fs.existsSync(dbYmlPath)) {
      try {
        const env = process.env.RAILS_ENV || process.env.NODE_ENV || 'development';
        const parsed = yaml.load(fs.readFileSync(dbYmlPath, 'utf8'));
        database = parsed?.[env]?.adapter || parsed?.default?.adapter || 'dexie';
      } catch (e) {
        console.warn(`[ruby2js-models] Warning: Failed to parse database.yml: ${e.message}`);
      }
    }
  }

  return database || 'dexie';
}

/**
 * Create the Ruby2JS Models Vite plugin.
 *
 * @param {Ruby2jsModelsOptions} options
 * @returns {import('vite').Plugin}
 */
export function ruby2jsModels(options = {}) {
  const {
    database: dbOption,
    target: targetOption,
    modelsDir = 'app/models',
    migrationsDir = 'db/migrate',
    outDir,
    eslevel = 2022
  } = options;

  let appRoot;
  let database;
  let target;
  let convert, initPrism;
  let prismReady = false;

  // Ensure ruby2js is ready
  async function ensureReady() {
    if (!convert) {
      const ruby2jsModule = await import('ruby2js');
      convert = ruby2jsModule.convert;
      initPrism = ruby2jsModule.initPrism;

      // Import model filter
      await import('ruby2js/filters/rails/model.js');
      await import('ruby2js/filters/rails/migration.js');
    }
    if (!prismReady && initPrism) {
      await initPrism();
      prismReady = true;
    }
  }

  // Transpile a Ruby model file
  async function transpileModel(filePath, destDir) {
    await ensureReady();

    const code = await fs.promises.readFile(filePath, 'utf-8');
    const fileName = path.basename(filePath, '.rb');

    try {
      const result = convert(code, {
        filters: ['Rails_Model', 'Functions', 'ESM', 'Return'],
        eslevel,
        file: filePath
      });

      const jsPath = path.join(destDir, `${fileName}.mjs`);
      await fs.promises.mkdir(destDir, { recursive: true });
      await fs.promises.writeFile(jsPath, result.toString());

      console.log(`[ruby2js-models] Transpiled ${path.basename(filePath)} → ${fileName}.mjs`);
      return jsPath;
    } catch (error) {
      console.error(`[ruby2js-models] Error transpiling ${filePath}:`, error.message);
      return null;
    }
  }

  // Transpile a migration file
  async function transpileMigration(filePath, destDir) {
    await ensureReady();

    const code = await fs.promises.readFile(filePath, 'utf-8');
    const fileName = path.basename(filePath, '.rb');

    try {
      const result = convert(code, {
        filters: ['Rails_Migration', 'Functions', 'ESM', 'Return'],
        eslevel,
        file: filePath
      });

      const jsPath = path.join(destDir, `${fileName}.mjs`);
      await fs.promises.mkdir(destDir, { recursive: true });
      await fs.promises.writeFile(jsPath, result.toString());

      console.log(`[ruby2js-models] Transpiled migration ${fileName}`);
      return jsPath;
    } catch (error) {
      console.error(`[ruby2js-models] Error transpiling migration ${filePath}:`, error.message);
      return null;
    }
  }

  // Generate migrations index
  async function generateMigrationsIndex(migrationsDestDir) {
    const files = await fs.promises.readdir(migrationsDestDir).catch(() => []);
    const migrationFiles = files
      .filter(f => f.endsWith('.mjs') && f !== 'index.mjs')
      .sort();

    if (migrationFiles.length === 0) return;

    const imports = migrationFiles.map((f, i) => {
      const version = f.match(/^(\d+)/)?.[1] || i;
      return `import { migration as m${version} } from './${f}';`;
    }).join('\n');

    const exports = migrationFiles.map((f) => {
      const version = f.match(/^(\d+)/)?.[1];
      return `  { version: '${version}', ...m${version} }`;
    }).join(',\n');

    const indexContent = `// Auto-generated migrations index
${imports}

export const migrations = [
${exports}
];
`;

    await fs.promises.writeFile(
      path.join(migrationsDestDir, 'index.mjs'),
      indexContent
    );
    console.log(`[ruby2js-models] Generated migrations index`);
  }

  // Generate models index
  async function generateModelsIndex(modelsDestDir, modelFiles) {
    const models = modelFiles
      .filter(f => f !== 'application_record.rb')
      .map(f => {
        const name = path.basename(f, '.rb');
        const className = name.charAt(0).toUpperCase() + name.slice(1).replace(/_([a-z])/g, (_, c) => c.toUpperCase());
        return { name, className };
      });

    const imports = models.map(m =>
      `import { ${m.className} } from './${m.name}.mjs';`
    ).join('\n');

    const registrations = models.map(m =>
      `modelRegistry.${m.className} = ${m.className};`
    ).join('\n');

    const exports = models.map(m => m.className).join(', ');

    const indexContent = `// Auto-generated models index
import { modelRegistry } from 'ruby2js-rails/adapters/active_record_dexie.mjs';
${imports}

// Register models for association resolution
${registrations}

export { ${exports} };
`;

    await fs.promises.writeFile(
      path.join(modelsDestDir, 'index.mjs'),
      indexContent
    );
    console.log(`[ruby2js-models] Generated models index`);
  }

  // Map database adapters to their files
  const adapterMap = {
    dexie: 'active_record_dexie.mjs',
    d1: 'active_record_d1.mjs',
    better_sqlite3: 'active_record_better_sqlite3.mjs',
    sqlite3: 'active_record_better_sqlite3.mjs',
    pg: 'active_record_pg.mjs',
    mysql2: 'active_record_mysql2.mjs',
    neon: 'active_record_neon.mjs',
    turso: 'active_record_turso.mjs',
    sqljs: 'active_record_sqljs.mjs',
    pglite: 'active_record_pglite.mjs'
  };

  // Generate bridge files for imports
  async function generateBridgeFiles(modelsDestDir, migrationsDestDir) {
    const adapterFile = adapterMap[database];
    if (!adapterFile) {
      console.warn(`[ruby2js-models] Unknown database adapter: ${database}`);
      return;
    }

    const adapterPath = `ruby2js-rails/adapters/${adapterFile}`;

    // Generate application_record.js bridge file (for model imports)
    // Models import from ./application_record.js (with .js extension)
    const applicationRecordBridge = `// ApplicationRecord base class - bridges generated models with the adapter
// Auto-generated by ruby2js-models plugin

import {
  ActiveRecord,
  CollectionProxy
} from '${adapterPath}';

// ApplicationRecord is the app-specific base class
export class ApplicationRecord extends ActiveRecord {
  // App-specific customizations can be added here
}

export { CollectionProxy };
`;
    await fs.promises.mkdir(modelsDestDir, { recursive: true });
    await fs.promises.writeFile(
      path.join(modelsDestDir, 'application_record.js'),
      applicationRecordBridge
    );

    // Generate dist/lib/active_record.mjs bridge file (for migration imports)
    // Migrations import from ../../lib/active_record.mjs, so lib/ is two levels up from migrate/
    const libDir = path.join(path.dirname(path.dirname(migrationsDestDir)), 'lib');
    const activeRecordBridge = `// ActiveRecord bridge - re-exports from the adapter
// Auto-generated by ruby2js-models plugin

export {
  createTable,
  addIndex,
  addColumn,
  removeColumn,
  dropTable,
  getDatabase,
  initDatabase,
  defineSchema,
  openDatabase,
  registerSchema,
  ActiveRecord
} from '${adapterPath}';
`;
    await fs.promises.mkdir(libDir, { recursive: true });
    await fs.promises.writeFile(
      path.join(libDir, 'active_record.mjs'),
      activeRecordBridge
    );

    console.log(`[ruby2js-models] Using adapter: ${adapterFile} (database: ${database})`);
  }

  return {
    name: 'ruby2js-models',

    async configResolved(config) {
      appRoot = config.root;
      database = loadDatabaseConfig(appRoot, { database: dbOption });
      target = targetOption || process.env.JUNTOS_TARGET || DEFAULT_TARGETS[database] || 'browser';

      console.log(`[ruby2js-models] Database: ${database}, Target: ${target}`);
    },

    async buildStart() {
      await ensureReady();

      const modelsSrcDir = path.join(appRoot, modelsDir);
      const migrationsSrcDir = path.join(appRoot, migrationsDir);
      const modelsDestDir = outDir ? path.join(appRoot, outDir) : path.join(appRoot, modelsDir.replace('app/', 'dist/app/').replace('src/', 'dist/'));
      const migrationsDestDir = path.join(appRoot, 'dist', migrationsDir);

      // Transpile models (skip application_record.rb - it's replaced by bridge file)
      if (fs.existsSync(modelsSrcDir)) {
        const modelFiles = (await fs.promises.readdir(modelsSrcDir))
          .filter(f => f.endsWith('.rb') && f !== 'application_record.rb');

        for (const file of modelFiles) {
          await transpileModel(path.join(modelsSrcDir, file), modelsDestDir);
        }

        if (modelFiles.length > 0) {
          await generateModelsIndex(modelsDestDir, modelFiles);
        }
      }

      // Transpile migrations
      if (fs.existsSync(migrationsSrcDir)) {
        const migrationFiles = (await fs.promises.readdir(migrationsSrcDir))
          .filter(f => f.endsWith('.rb'));

        for (const file of migrationFiles) {
          await transpileMigration(path.join(migrationsSrcDir, file), migrationsDestDir);
        }

        if (migrationFiles.length > 0) {
          await generateMigrationsIndex(migrationsDestDir);
        }
      }

      // Generate bridge files for adapter imports
      await generateBridgeFiles(modelsDestDir, migrationsDestDir);
    },

    // Watch model and migration files
    configureServer(server) {
      const modelsSrcDir = path.join(appRoot, modelsDir);
      const migrationsSrcDir = path.join(appRoot, migrationsDir);

      // Add directories to watcher
      if (fs.existsSync(modelsSrcDir)) {
        server.watcher.add(path.join(modelsSrcDir, '**/*.rb'));
      }
      if (fs.existsSync(migrationsSrcDir)) {
        server.watcher.add(path.join(migrationsSrcDir, '**/*.rb'));
      }

      server.watcher.on('change', async (file) => {
        if (!file.endsWith('.rb')) return;

        const modelsDestDir = outDir ? path.join(appRoot, outDir) : path.join(appRoot, modelsDir.replace('app/', 'dist/app/').replace('src/', 'dist/'));
        const migrationsDestDir = path.join(appRoot, 'dist', migrationsDir);

        if (file.startsWith(modelsSrcDir)) {
          // Skip application_record.rb - it's replaced by bridge file
          if (path.basename(file) === 'application_record.rb') return;

          await transpileModel(file, modelsDestDir);
          // Regenerate index
          const modelFiles = (await fs.promises.readdir(modelsSrcDir))
            .filter(f => f.endsWith('.rb') && f !== 'application_record.rb');
          await generateModelsIndex(modelsDestDir, modelFiles);

          // Trigger full reload for model changes
          server.ws.send({ type: 'full-reload' });
        } else if (file.startsWith(migrationsSrcDir)) {
          await transpileMigration(file, migrationsDestDir);
          await generateMigrationsIndex(migrationsDestDir);
          server.ws.send({ type: 'full-reload' });
        }
      });

      console.log(`[ruby2js-models] Watching for model and migration changes`);
    }
  };
}

export default ruby2jsModels;
