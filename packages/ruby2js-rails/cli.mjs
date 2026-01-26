#!/usr/bin/env node

/**
 * Juntos CLI - Rails patterns, JavaScript runtimes
 *
 * Commands:
 *   dev       Start development server with hot reload
 *   build     Build for deployment
 *   eject     Write transpiled JavaScript files to disk
 *   up        Build and run locally
 *   test      Run tests with Vitest
 *   db        Database commands (migrate, seed, prepare, reset, create, drop)
 *   info      Show current configuration
 *   doctor    Check environment and prerequisites
 */

import { spawn, spawnSync, execSync } from 'child_process';
import { existsSync, readFileSync, writeFileSync, unlinkSync, mkdirSync, chmodSync, readdirSync, copyFileSync, cpSync, statSync } from 'fs';
import { join, basename, dirname, relative } from 'path';
import { fileURLToPath } from 'url';

// Import shared transformation logic
import {
  findModels,
  findMigrations,
  findViewResources,
  findControllers,
  generateModelsModuleForEject,
  generateMigrationsModuleForEject,
  generateViewsModuleForEject,
  generateApplicationRecordForEject,
  generatePackageJsonForEject,
  generateViteConfigForEject,
  generateTestSetupForEject,
  generateMainJsForEject,
  generateVitestConfigForEject,
  generateBrowserIndexHtml,
  generateBrowserMainJs,
  ensureRuby2jsReady,
  transformRuby,
  transformErb,
  transformJsxRb,
  fixImportsForEject,
  fixTestImportsForEject
} from './transform.mjs';

// Try to load js-yaml, fall back to naive parsing if not available
// (js-yaml may not be available when CLI is run standalone from tarball)
let yaml = null;
try {
  yaml = await import('js-yaml');
  yaml = yaml.default || yaml;
} catch {
  // js-yaml not available, will use fallback parser
}

// CLI runs from the app's working directory
const APP_ROOT = process.cwd();

// Path to this package (for migrate.mjs)
const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATE_SCRIPT = join(__dirname, 'migrate.mjs');

// ============================================
// Argument parsing
// ============================================

function parseCommonArgs(args) {
  const options = {
    database: null,
    environment: null,
    target: null,
    port: 3000,
    verbose: false,
    help: false,
    yes: false,
    sourcemap: false,
    base: null,
    open: false,
    skipBuild: false,
    force: false,
    outDir: null
  };

  const remaining = [];
  let i = 0;

  while (i < args.length) {
    const arg = args[i];

    if (arg === '-d' || arg === '--database') {
      options.database = args[++i];
    } else if (arg.startsWith('-d')) {
      options.database = arg.slice(2);
    } else if (arg.startsWith('--database=')) {
      options.database = arg.slice(11);
    } else if (arg === '-e' || arg === '--environment') {
      options.environment = args[++i];
    } else if (arg.startsWith('-e')) {
      options.environment = arg.slice(2);
    } else if (arg.startsWith('--environment=')) {
      options.environment = arg.slice(14);
    } else if (arg === '-t' || arg === '--target') {
      options.target = args[++i];
    } else if (arg.startsWith('-t')) {
      options.target = arg.slice(2);
    } else if (arg.startsWith('--target=')) {
      options.target = arg.slice(9);
    } else if (arg === '-p' || arg === '--port') {
      options.port = parseInt(args[++i], 10);
    } else if (arg.startsWith('-p')) {
      options.port = parseInt(arg.slice(2), 10);
    } else if (arg.startsWith('--port=')) {
      options.port = parseInt(arg.slice(7), 10);
    } else if (arg === '-v' || arg === '--verbose') {
      options.verbose = true;
    } else if (arg === '-y' || arg === '--yes') {
      options.yes = true;
    } else if (arg === '-o' || arg === '--open') {
      options.open = true;
    } else if (arg === '--sourcemap') {
      options.sourcemap = true;
    } else if (arg === '--skip-build') {
      options.skipBuild = true;
    } else if (arg === '-f' || arg === '--force') {
      options.force = true;
    } else if (arg === '--output' || arg === '--out') {
      options.outDir = args[++i];
    } else if (arg.startsWith('--output=')) {
      options.outDir = arg.slice(9);
    } else if (arg.startsWith('--out=')) {
      options.outDir = arg.slice(6);
    } else if (arg === '--base') {
      options.base = args[++i];
    } else if (arg.startsWith('--base=')) {
      options.base = arg.slice(7);
    } else if (arg === '-h' || arg === '--help') {
      options.help = true;
    } else {
      remaining.push(arg);
    }
    i++;
  }

  return { options, remaining };
}

// ============================================
// Configuration helpers
// ============================================

function loadEnvLocal() {
  const envFile = join(APP_ROOT, '.env.local');
  if (!existsSync(envFile)) return;

  const content = readFileSync(envFile, 'utf-8');
  for (const line of content.split('\n')) {
    if (line.startsWith('#') || !line.trim()) continue;
    const match = line.match(/^([^=]+)=["']?([^"'\n]*)["']?$/);
    if (match) {
      process.env[match[1]] = match[2];
    }
  }
}

function loadDatabaseConfig(options) {
  const env = options.environment || process.env.RAILS_ENV || 'development';
  process.env.RAILS_ENV = env;
  process.env.NODE_ENV = env === 'production' ? 'production' : 'development';

  // CLI options take precedence
  if (options.database) {
    options.dbName = options.dbName || `${basename(APP_ROOT)}_${env}`.toLowerCase().replace(/[^a-z0-9_]/g, '_');
    return;
  }

  // Load from database.yml
  const configPath = join(APP_ROOT, 'config/database.yml');
  if (existsSync(configPath)) {
    try {
      const content = readFileSync(configPath, 'utf-8');

      if (yaml) {
        // Use js-yaml for proper YAML parsing (handles anchors like <<: *default)
        const config = yaml.load(content);
        const envConfig = config[env];

        if (envConfig) {
          if (envConfig.adapter) options.database = options.database || envConfig.adapter;
          if (envConfig.database) options.dbName = options.dbName || envConfig.database;
          if (envConfig.target) options.target = options.target || envConfig.target;
        }
      } else {
        // Fallback: naive parsing (doesn't handle YAML anchors)
        // Used when js-yaml isn't available (standalone CLI from tarball)
        const lines = content.split('\n');
        let currentEnv = null;
        let inEnv = false;

        for (const line of lines) {
          const envMatch = line.match(/^(\w+):$/);
          if (envMatch) {
            currentEnv = envMatch[1];
            inEnv = currentEnv === env;
            continue;
          }

          if (inEnv && line.startsWith('  ')) {
            const adapterMatch = line.match(/^\s+adapter:\s*(.+)$/);
            const databaseMatch = line.match(/^\s+database:\s*(.+)$/);
            const targetMatch = line.match(/^\s+target:\s*(.+)$/);

            if (adapterMatch) options.database = options.database || adapterMatch[1].trim();
            if (databaseMatch) options.dbName = options.dbName || databaseMatch[1].trim();
            if (targetMatch) options.target = options.target || targetMatch[1].trim();
          }
        }
      }
    } catch (e) {
      console.warn(`Warning: Could not parse config/database.yml: ${e.message}`);
    }
  }

  // Normalize adapter names to canonical Juntos equivalents
  // This handles Rails adapter names and common variations
  const ADAPTER_ALIASES = {
    // IndexedDB variations
    indexeddb: 'dexie',
    // SQLite variations (Rails uses sqlite3, npm package is better-sqlite3)
    sqlite3: 'sqlite',
    better_sqlite3: 'sqlite',
    // sql.js variations
    'sql.js': 'sqljs',
    // PostgreSQL variations
    postgres: 'pg',
    postgresql: 'pg',
    // MySQL variations (npm package is mysql2)
    mysql2: 'mysql'
  };
  if (options.database && ADAPTER_ALIASES[options.database]) {
    options.database = ADAPTER_ALIASES[options.database];
  }

  // Environment variables take precedence over defaults (but not over CLI/config)
  options.database = options.database || process.env.JUNTOS_DATABASE || 'dexie';
  options.target = options.target || process.env.JUNTOS_TARGET;
  options.dbName = options.dbName || `${basename(APP_ROOT)}_${env}`.toLowerCase().replace(/[^a-z0-9_]/g, '_');

  // Infer target from database if not specified
  if (!options.target && DEFAULT_TARGETS[options.database]) {
    options.target = DEFAULT_TARGETS[options.database];
  }
}

function applyEnvOptions(options) {
  if (options.database) process.env.JUNTOS_DATABASE = options.database;
  if (options.target) process.env.JUNTOS_TARGET = options.target;
  if (options.base) process.env.JUNTOS_BASE = options.base;
  if (options.environment) {
    process.env.RAILS_ENV = options.environment;
    process.env.NODE_ENV = options.environment === 'production' ? 'production' : 'development';
  }
}

function validateRailsApp() {
  if (!existsSync(join(APP_ROOT, 'app')) || !existsSync(join(APP_ROOT, 'config'))) {
    console.error('Error: Not a Rails-like application directory.');
    console.error('Expected to find app/ and config/ directories.');
    process.exit(1);
  }
}

// ============================================
// Init command - set up Juntos in a project
// ============================================

const RELEASES_URL = 'https://ruby2js.github.io/ruby2js/releases';

function runInit(options) {
  const destDir = APP_ROOT;
  const quiet = options.quiet || false;

  if (!quiet) {
    console.log(`Initializing Juntos in ${basename(destDir)}/\n`);
  }

  // Create or merge package.json
  const packagePath = join(destDir, 'package.json');
  if (existsSync(packagePath)) {
    if (!quiet) console.log('  Updating package.json...');
    const existing = JSON.parse(readFileSync(packagePath, 'utf8'));
    existing.type = existing.type || 'module';
    existing.dependencies = existing.dependencies || {};
    existing.devDependencies = existing.devDependencies || {};
    existing.scripts = existing.scripts || {};

    // Add dependencies if missing (ruby2js and vite-plugin-ruby2js are peer deps of ruby2js-rails)
    if (!existing.dependencies['ruby2js']) {
      existing.dependencies['ruby2js'] = `${RELEASES_URL}/ruby2js-beta.tgz`;
    }
    if (!existing.dependencies['ruby2js-rails']) {
      existing.dependencies['ruby2js-rails'] = `${RELEASES_URL}/ruby2js-rails-beta.tgz`;
    }
    if (!existing.dependencies['vite-plugin-ruby2js']) {
      existing.dependencies['vite-plugin-ruby2js'] = `${RELEASES_URL}/vite-plugin-ruby2js-beta.tgz`;
    }
    if (!existing.devDependencies['vite']) {
      existing.devDependencies['vite'] = '^6.0.0';
    }
    if (!existing.devDependencies['vitest']) {
      existing.devDependencies['vitest'] = '^2.0.0';
    }

    // Add scripts if missing
    existing.scripts.dev = existing.scripts.dev || 'vite';
    existing.scripts.build = existing.scripts.build || 'vite build';
    existing.scripts.preview = existing.scripts.preview || 'vite preview';
    existing.scripts.test = existing.scripts.test || 'vitest run';

    writeFileSync(packagePath, JSON.stringify(existing, null, 2) + '\n');
  } else {
    if (!quiet) console.log('  Creating package.json...');
    const appName = basename(destDir).toLowerCase().replace(/[^a-z0-9_-]/g, '_');
    const pkg = {
      name: appName,
      type: 'module',
      scripts: {
        dev: 'vite',
        build: 'vite build',
        preview: 'vite preview',
        test: 'vitest run'
      },
      dependencies: {
        'ruby2js': `${RELEASES_URL}/ruby2js-beta.tgz`,
        'ruby2js-rails': `${RELEASES_URL}/ruby2js-rails-beta.tgz`,
        'vite-plugin-ruby2js': `${RELEASES_URL}/vite-plugin-ruby2js-beta.tgz`
      },
      devDependencies: {
        vite: '^7.0.0',
        vitest: '^2.0.0'
      }
    };
    writeFileSync(packagePath, JSON.stringify(pkg, null, 2) + '\n');
  }

  // Read ruby2js.yml for additional dependencies
  const ruby2jsYmlPath = join(destDir, 'config/ruby2js.yml');
  if (existsSync(ruby2jsYmlPath)) {
    let ruby2jsConfig = {};
    if (yaml) {
      try {
        ruby2jsConfig = yaml.load(readFileSync(ruby2jsYmlPath, 'utf8')) || {};
      } catch (e) {
        if (!quiet) console.warn(`  Warning: Failed to parse ruby2js.yml: ${e.message}`);
      }
    }

    // Add dependencies from ruby2js.yml to package.json
    if (ruby2jsConfig.dependencies) {
      const pkg = JSON.parse(readFileSync(packagePath, 'utf8'));
      let added = false;
      for (const [name, version] of Object.entries(ruby2jsConfig.dependencies)) {
        if (!pkg.dependencies[name]) {
          pkg.dependencies[name] = version;
          added = true;
        }
      }
      if (added) {
        if (!quiet) console.log('  Adding dependencies from ruby2js.yml...');
        writeFileSync(packagePath, JSON.stringify(pkg, null, 2) + '\n');
      }
    }
  }

  // Create vite.config.js
  const viteConfigPath = join(destDir, 'vite.config.js');
  if (!existsSync(viteConfigPath)) {
    if (!quiet) console.log('  Creating vite.config.js...');
    writeFileSync(viteConfigPath, `import { defineConfig } from 'vite';
import { juntos } from 'ruby2js-rails/vite';

export default defineConfig({
  plugins: juntos()
});
`);
  } else {
    if (!quiet) console.log('  Skipping vite.config.js (already exists)');
  }

  // Create vitest.config.js
  const vitestConfigPath = join(destDir, 'vitest.config.js');
  if (!existsSync(vitestConfigPath)) {
    if (!quiet) console.log('  Creating vitest.config.js...');
    writeFileSync(vitestConfigPath, `import { defineConfig, mergeConfig } from 'vitest/config';
import viteConfig from './vite.config.js';

export default mergeConfig(viteConfig, defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['test/**/*.test.mjs', 'test/**/*.test.js'],
    setupFiles: ['./test/setup.mjs']
  }
}));
`);
  } else {
    if (!quiet) console.log('  Skipping vitest.config.js (already exists)');
  }

  // Create test/setup.mjs
  const testDir = join(destDir, 'test');
  const setupPath = join(testDir, 'setup.mjs');
  if (!existsSync(setupPath)) {
    if (!quiet) console.log('  Creating test/setup.mjs...');
    if (!existsSync(testDir)) {
      mkdirSync(testDir, { recursive: true });
    }
    writeFileSync(setupPath, `// Test setup for Vitest
// Initializes the database before each test

import { beforeAll, beforeEach } from 'vitest';

beforeAll(async () => {
  // Import models (registers them with Application and modelRegistry)
  await import('juntos:models');

  // Configure migrations
  const rails = await import('juntos:rails');
  const migrations = await import('juntos:migrations');
  rails.Application.configure({ migrations: migrations.migrations });
});

beforeEach(async () => {
  // Fresh in-memory database for each test
  const activeRecord = await import('juntos:active-record');
  await activeRecord.initDatabase({ database: ':memory:' });

  const rails = await import('juntos:rails');
  await rails.Application.runMigrations(activeRecord);
});
`);
  } else {
    if (!quiet) console.log('  Skipping test/setup.mjs (already exists)');
  }

  // Create bin/juntos binstub
  const binDir = join(destDir, 'bin');
  const binstubPath = join(binDir, 'juntos');
  if (!existsSync(binstubPath)) {
    if (!quiet) console.log('  Creating bin/juntos...');
    if (!existsSync(binDir)) {
      mkdirSync(binDir, { recursive: true });
    }
    writeFileSync(binstubPath, `#!/bin/sh
# Juntos - Rails patterns, JavaScript runtimes
# This binstub delegates to the juntos CLI from ruby2js-rails
exec npx juntos "$@"
`);
    chmodSync(binstubPath, 0o755);
  } else {
    if (!quiet) console.log('  Skipping bin/juntos (already exists)');
  }

  // In quiet mode or --no-install, we're done
  if (quiet || options.noInstall) {
    if (!quiet) {
      console.log('\nJuntos initialized! Run `npm install` to install dependencies.');
    }
    return;
  }

  // Run npm install
  console.log('\nInstalling dependencies...\n');
  const result = spawnSync('npm', ['install'], {
    cwd: destDir,
    stdio: 'inherit'
  });

  if (result.status !== 0) {
    console.error('\nnpm install failed. You can retry manually with: npm install');
    process.exit(1);
  }

  console.log('\nJuntos initialized!\n');
  console.log('Next steps:');
  console.log('  npx juntos dev -d dexie        # Browser with IndexedDB');
  console.log('  npx juntos up -d sqlite        # Node.js with SQLite');
  console.log('\nFor more information: https://www.ruby2js.com/docs/juntos');
}

// ============================================
// Auto-install required packages
// ============================================

const DATABASE_PACKAGES = {
  // Browser databases
  dexie: ['dexie'],
  indexeddb: ['dexie'],
  sqljs: ['sql.js'],
  'sql.js': ['sql.js'],
  pglite: ['@electric-sql/pglite'],
  // Node.js databases
  sqlite: ['better-sqlite3'],
  sqlite3: ['better-sqlite3'],
  better_sqlite3: ['better-sqlite3'],
  pg: ['pg'],
  postgres: ['pg'],
  postgresql: ['pg'],
  mysql: ['mysql2'],
  mysql2: ['mysql2'],
  // Serverless databases
  neon: ['@neondatabase/serverless'],
  turso: ['@libsql/client'],
  d1: []  // No npm package needed, uses Cloudflare bindings
};

const RUNTIME_PACKAGES = {
  browser: ['@hotwired/turbo', '@hotwired/stimulus', 'react', 'react-dom'],
  node: [],
  bun: [],
  deno: []
};

// Valid target environments for each database adapter
const VALID_TARGETS = {
  // Browser-only databases
  dexie: ['browser', 'capacitor'],
  sqljs: ['browser', 'capacitor', 'electron', 'tauri'],
  pglite: ['browser', 'node', 'capacitor', 'electron', 'tauri'],
  // Node.js databases
  sqlite: ['node', 'bun', 'electron'],
  pg: ['node', 'bun', 'deno', 'electron'],
  mysql: ['node', 'bun', 'electron'],
  // Serverless databases
  neon: ['node', 'vercel', 'vercel-edge', 'capacitor', 'electron', 'tauri'],
  turso: ['node', 'vercel', 'vercel-edge', 'cloudflare', 'capacitor', 'electron', 'tauri'],
  d1: ['cloudflare']
};

// Default target for each database adapter
const DEFAULT_TARGETS = {
  dexie: 'browser',
  sqljs: 'browser',
  pglite: 'browser',
  sqlite: 'node',
  pg: 'node',
  mysql: 'node',
  neon: 'vercel',
  turso: 'vercel',
  d1: 'cloudflare'
};

function validateDatabaseTarget(options) {
  const db = options.database;
  const target = options.target;

  if (!db || !target) return; // Will use defaults

  const validTargets = VALID_TARGETS[db];
  if (!validTargets) {
    console.error(`Unknown database adapter: ${db}`);
    console.error(`Valid adapters: ${Object.keys(VALID_TARGETS).join(', ')}`);
    process.exit(1);
  }

  if (!validTargets.includes(target)) {
    console.error(`Invalid combination: ${db} database with ${target} target`);
    console.error(`${db} supports: ${validTargets.join(', ')}`);
    process.exit(1);
  }
}

function ensurePackagesInstalled(options) {
  const missing = [];

  // Check database packages
  if (options.database && DATABASE_PACKAGES[options.database]) {
    for (const pkg of DATABASE_PACKAGES[options.database]) {
      if (!isPackageInstalled(pkg)) {
        missing.push(pkg);
      }
    }
  }

  // Check runtime packages for browser target
  const target = options.target || 'browser';
  if (RUNTIME_PACKAGES[target]) {
    for (const pkg of RUNTIME_PACKAGES[target]) {
      if (!isPackageInstalled(pkg)) {
        missing.push(pkg);
      }
    }
  }

  // Install missing packages
  if (missing.length > 0) {
    console.log(`Installing required packages: ${missing.join(', ')}...`);
    try {
      execSync(`npm install ${missing.join(' ')}`, {
        cwd: APP_ROOT,
        stdio: 'inherit'
      });
    } catch (e) {
      console.error('Failed to install required packages.');
      process.exit(1);
    }
  }
}

function isPackageInstalled(packageName) {
  // Check node_modules directly
  const packagePath = join(APP_ROOT, 'node_modules', packageName);
  return existsSync(packagePath);
}

// ============================================
// Command: dev
// ============================================

function runDev(options) {
  validateRailsApp();
  loadDatabaseConfig(options);
  validateDatabaseTarget(options);
  ensurePackagesInstalled(options);
  applyEnvOptions(options);

  const args = ['vite'];
  if (options.port !== 5173) {
    args.push('--port', String(options.port));
  }
  if (options.open) {
    args.push('--open');
  }

  console.log('Starting Vite dev server...');
  const child = spawn('npx', args, {
    cwd: APP_ROOT,
    stdio: 'inherit',
    env: process.env
  });

  child.on('error', (err) => {
    console.error('Failed to start Vite:', err.message);
    process.exit(1);
  });
}

// ============================================
// Command: build
// ============================================

function runBuild(options) {
  validateRailsApp();
  loadDatabaseConfig(options);
  validateDatabaseTarget(options);
  ensurePackagesInstalled(options);
  applyEnvOptions(options);

  const args = ['vite', 'build'];
  if (options.sourcemap) {
    args.push('--sourcemap');
  }
  if (options.base) {
    args.push('--base', options.base);
  }

  console.log('Building application...');
  const result = spawn('npx', args, {
    cwd: APP_ROOT,
    stdio: 'inherit',
    env: process.env
  });

  result.on('close', (code) => {
    if (code === 0) {
      console.log('Build complete. Output in dist/');
    } else {
      console.error('Build failed.');
      process.exit(code);
    }
  });
}

// ============================================
// Command: eject
// ============================================

async function runEject(options) {
  validateRailsApp();
  loadDatabaseConfig(options);
  applyEnvOptions(options);

  const outDir = options.outDir || join(APP_ROOT, 'ejected');

  // Determine database (command line takes precedence over config file)
  const database = options.database || 'dexie';

  // Determine target: explicit option > infer from database > default to browser
  let target = options.target;
  if (!target) {
    // Infer target from database type
    if (database === 'dexie') {
      target = 'browser';
    } else if (['sqlite3', 'sqlite', 'better_sqlite3'].includes(database)) {
      target = 'node';
    } else {
      target = 'browser';
    }
  }

  const config = {
    target,
    database,
    base: options.base || '/',
    eslevel: 2022
  };

  console.log(`Ejecting transpiled files to ${relative(APP_ROOT, outDir) || outDir}/\n`);

  // Ensure ruby2js is ready
  await ensureRuby2jsReady();

  // Create output directory structure
  const dirs = [
    outDir,
    join(outDir, 'app/models'),
    join(outDir, 'app/views'),
    join(outDir, 'app/views/layouts'),
    join(outDir, 'app/controllers'),
    join(outDir, 'app/javascript/controllers'),
    join(outDir, 'config'),
    join(outDir, 'db/migrate')
  ];

  for (const dir of dirs) {
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
  }

  let fileCount = 0;

  // Transform models
  const modelsDir = join(APP_ROOT, 'app/models');
  if (existsSync(modelsDir)) {
    console.log('  Transforming models...');
    const modelFiles = readdirSync(modelsDir).filter(f => f.endsWith('.rb') && !f.startsWith('._'));
    for (const file of modelFiles) {
      const source = readFileSync(join(modelsDir, file), 'utf-8');
      const result = await transformRuby(source, join(modelsDir, file), null, config, APP_ROOT);
      // Pass relative output path for correct import resolution
      const relativeOutPath = `app/models/${file.replace('.rb', '.js')}`;
      let code = fixImportsForEject(result.code, relativeOutPath, config);
      const outFile = join(outDir, 'app/models', file.replace('.rb', '.js'));
      writeFileSync(outFile, code);
      fileCount++;
    }

    // Generate models index
    const modelsIndex = generateModelsModuleForEject(APP_ROOT, config);
    writeFileSync(join(outDir, 'app/models/index.js'), modelsIndex);
    fileCount++;
  }

  // Transform migrations
  const migrateDir = join(APP_ROOT, 'db/migrate');
  if (existsSync(migrateDir)) {
    console.log('  Transforming migrations...');
    const migrations = findMigrations(APP_ROOT);
    for (const m of migrations) {
      const source = readFileSync(join(migrateDir, m.file), 'utf-8');
      const result = await transformRuby(source, join(migrateDir, m.file), null, config, APP_ROOT);
      // Pass relative output path for correct import resolution
      const relativeOutPath = `db/migrate/${m.name}.js`;
      let code = fixImportsForEject(result.code, relativeOutPath, config);
      const outFile = join(outDir, 'db/migrate', m.name + '.js');
      writeFileSync(outFile, code);
      fileCount++;
    }

    // Generate migrations index
    const migrationsIndex = generateMigrationsModuleForEject(APP_ROOT);
    writeFileSync(join(outDir, 'db/migrate/index.js'), migrationsIndex);
    fileCount++;
  }

  // Transform seeds
  const seedsFile = join(APP_ROOT, 'db/seeds.rb');
  if (existsSync(seedsFile)) {
    console.log('  Transforming seeds...');
    const source = readFileSync(seedsFile, 'utf-8');
    const result = await transformRuby(source, seedsFile, null, config, APP_ROOT);
    // Pass relative output path for correct import resolution
    let code = fixImportsForEject(result.code, 'db/seeds.js', config);
    writeFileSync(join(outDir, 'db/seeds.js'), code);
    fileCount++;
  }

  // Transform routes
  const routesFile = join(APP_ROOT, 'config/routes.rb');
  if (existsSync(routesFile)) {
    console.log('  Transforming routes...');
    const source = readFileSync(routesFile, 'utf-8');
    const result = await transformRuby(source, routesFile, null, config, APP_ROOT);
    // Pass relative output path for correct import resolution
    let code = fixImportsForEject(result.code, 'config/routes.js', config);
    writeFileSync(join(outDir, 'config/routes.js'), code);
    fileCount++;
  }

  // Transform views
  const viewsDir = join(APP_ROOT, 'app/views');
  if (existsSync(viewsDir)) {
    console.log('  Transforming views...');
    const resources = findViewResources(APP_ROOT);

    for (const resource of resources) {
      const resourceDir = join(viewsDir, resource);
      const outResourceDir = join(outDir, 'app/views', resource);
      if (!existsSync(outResourceDir)) {
        mkdirSync(outResourceDir, { recursive: true });
      }

      const files = readdirSync(resourceDir);

      // Transform ERB files
      for (const file of files.filter(f => f.endsWith('.html.erb') && !f.startsWith('._'))) {
        const source = readFileSync(join(resourceDir, file), 'utf-8');
        const result = await transformErb(source, join(resourceDir, file), false, config);
        // Pass relative output path for correct import resolution
        const relativeOutPath = `app/views/${resource}/${file.replace('.html.erb', '.js')}`;
        let code = fixImportsForEject(result.code, relativeOutPath, config);
        const outFile = join(outResourceDir, file.replace('.html.erb', '.js'));
        writeFileSync(outFile, code);
        fileCount++;
      }

      // Transform JSX.rb files
      for (const file of files.filter(f => f.endsWith('.jsx.rb') && !f.startsWith('._'))) {
        const source = readFileSync(join(resourceDir, file), 'utf-8');
        const result = await transformJsxRb(source, join(resourceDir, file), config);
        // Pass relative output path for correct import resolution
        const relativeOutPath = `app/views/${resource}/${file.replace('.jsx.rb', '.js')}`;
        let code = fixImportsForEject(result.code, relativeOutPath, config);
        const outFile = join(outResourceDir, file.replace('.jsx.rb', '.js'));
        writeFileSync(outFile, code);
        fileCount++;
      }
    }

    // Generate view index modules for each resource
    for (const resource of resources) {
      const viewsIndex = generateViewsModuleForEject(APP_ROOT, resource);
      writeFileSync(join(outDir, 'app/views', resource + '.js'), viewsIndex);
      fileCount++;
    }

    // Transform layouts
    const layoutsDir = join(viewsDir, 'layouts');
    if (existsSync(layoutsDir)) {
      const layoutFiles = readdirSync(layoutsDir).filter(f => f.endsWith('.html.erb') && !f.startsWith('._'));
      for (const file of layoutFiles) {
        const source = readFileSync(join(layoutsDir, file), 'utf-8');
        const result = await transformErb(source, join(layoutsDir, file), true, config);
        // Pass relative output path for correct import resolution
        const relativeOutPath = `app/views/layouts/${file.replace('.html.erb', '.js')}`;
        let code = fixImportsForEject(result.code, relativeOutPath, config);
        const outFile = join(outDir, 'app/views/layouts', file.replace('.html.erb', '.js'));
        writeFileSync(outFile, code);
        fileCount++;
      }
    }
  }

  // Transform Stimulus controllers
  const controllersDir = join(APP_ROOT, 'app/javascript/controllers');
  if (existsSync(controllersDir)) {
    console.log('  Transforming Stimulus controllers...');

    // Get all files in the controllers directory
    const allFiles = readdirSync(controllersDir).filter(f => !f.startsWith('._') && !f.startsWith('.'));

    for (const file of allFiles) {
      const inFile = join(controllersDir, file);
      // Skip directories
      if (!statSync(inFile).isFile()) continue;

      if (file.endsWith('.rb')) {
        // Transform Ruby files
        const source = readFileSync(inFile, 'utf-8');
        const result = await transformRuby(source, inFile, 'stimulus', config, APP_ROOT);
        // Pass relative output path for correct import resolution
        const relativeOutPath = `app/javascript/controllers/${file.replace('.rb', '.js')}`;
        let code = fixImportsForEject(result.code, relativeOutPath, config);
        const outFile = join(outDir, 'app/javascript/controllers', file.replace('.rb', '.js'));
        writeFileSync(outFile, code);
        fileCount++;
      } else if (file.endsWith('.js') || file.endsWith('.mjs')) {
        // Copy JS files as-is
        const outFile = join(outDir, 'app/javascript/controllers', file);
        copyFileSync(inFile, outFile);
        fileCount++;
      }
    }
  }

  // Transform Rails controllers
  const appControllersDir = join(APP_ROOT, 'app/controllers');
  if (existsSync(appControllersDir)) {
    console.log('  Transforming Rails controllers...');
    const controllerFiles = readdirSync(appControllersDir)
      .filter(f => f.endsWith('.rb') && !f.startsWith('._'));
    for (const file of controllerFiles) {
      const source = readFileSync(join(appControllersDir, file), 'utf-8');
      const result = await transformRuby(source, join(appControllersDir, file), 'controllers', config, APP_ROOT);
      // Pass relative output path for correct import resolution
      const relativeOutPath = `app/controllers/${file.replace('.rb', '.js')}`;
      let code = fixImportsForEject(result.code, relativeOutPath, config);
      const outFile = join(outDir, 'app/controllers', file.replace('.rb', '.js'));
      writeFileSync(outFile, code);
      fileCount++;
    }
  }

  // Copy and transform test files
  const testDir = join(APP_ROOT, 'test');
  if (existsSync(testDir)) {
    console.log('  Copying test files...');
    const outTestDir = join(outDir, 'test');
    if (!existsSync(outTestDir)) {
      mkdirSync(outTestDir, { recursive: true });
    }

    // Copy .mjs and .js test files with import fixes
    const testFiles = readdirSync(testDir).filter(f =>
      (f.endsWith('.test.mjs') || f.endsWith('.test.js')) && !f.startsWith('._')
    );
    for (const file of testFiles) {
      let content = readFileSync(join(testDir, file), 'utf-8');
      content = fixTestImportsForEject(content);
      writeFileSync(join(outTestDir, file), content);
      fileCount++;
    }
  }

  // Generate application_record.js
  console.log('  Generating project files...');
  writeFileSync(join(outDir, 'app/models/application_record.js'), generateApplicationRecordForEject(config));
  fileCount++;

  // Generate package.json with database config
  const appName = basename(APP_ROOT) + '-ejected';
  writeFileSync(join(outDir, 'package.json'), generatePackageJsonForEject(appName, config));
  fileCount++;

  // Generate vite.config.js
  writeFileSync(join(outDir, 'vite.config.js'), generateViteConfigForEject(config));
  fileCount++;

  // Generate vitest.config.js
  writeFileSync(join(outDir, 'vitest.config.js'), generateVitestConfigForEject(config));
  fileCount++;

  // Generate test/setup.mjs
  const outTestDir = join(outDir, 'test');
  if (!existsSync(outTestDir)) {
    mkdirSync(outTestDir, { recursive: true });
  }
  writeFileSync(join(outTestDir, 'setup.mjs'), generateTestSetupForEject(config));
  fileCount++;

  // Generate entry point(s) based on target
  const browserTargets = ['browser', 'pwa', 'capacitor', 'electron', 'tauri'];
  const isBrowserTarget = browserTargets.includes(config.target);

  if (isBrowserTarget) {
    // Browser targets: generate index.html and browser main.js
    writeFileSync(join(outDir, 'index.html'), generateBrowserIndexHtml(appName, './main.js'));
    fileCount++;
    writeFileSync(join(outDir, 'main.js'), generateBrowserMainJs('./config/routes.js', './app/javascript/controllers/index.js'));
    fileCount++;
  } else {
    // Server targets: generate Node.js server entry
    writeFileSync(join(outDir, 'main.js'), generateMainJsForEject(config));
    fileCount++;
  }

  console.log(`\nEjected ${fileCount} files to ${relative(APP_ROOT, outDir) || outDir}/`);
  console.log('\nThe ejected project depends on ruby2js-rails for runtime support.');
  console.log('To use:');
  console.log('  cd ' + (relative(APP_ROOT, outDir) || outDir));
  console.log('  npm install');
  if (isBrowserTarget) {
    console.log('  npm run dev     # start dev server');
    console.log('  npm run build   # build for production');
  } else {
    console.log('  npm test        # run tests');
    console.log('  npm start       # start server');
  }
}

// ============================================
// Command: up
// ============================================

function runUp(options) {
  validateRailsApp();
  loadDatabaseConfig(options);
  validateDatabaseTarget(options);
  ensurePackagesInstalled(options);
  applyEnvOptions(options);

  const isServerTarget = ['node', 'bun', 'deno'].includes(options.target);

  console.log('Building application...');
  try {
    const buildCmd = options.base
      ? `npx vite build --base ${options.base}`
      : 'npx vite build';
    execSync(buildCmd, { cwd: APP_ROOT, stdio: 'inherit', env: process.env });
  } catch (e) {
    console.error('Build failed.');
    process.exit(1);
  }

  if (isServerTarget) {
    console.log(`Starting ${options.target} server...`);
    const runtime = options.target === 'bun' ? 'bun' : options.target === 'deno' ? 'deno' : 'node';
    const entryPoint = join(APP_ROOT, 'dist', 'index.js');

    if (!existsSync(entryPoint)) {
      console.error(`Error: ${entryPoint} not found. Build may have failed.`);
      process.exit(1);
    }

    spawn(runtime, [entryPoint], {
      cwd: APP_ROOT,  // Run from app root to access node_modules
      stdio: 'inherit',
      env: { ...process.env, PORT: String(options.port) }
    });
  } else {
    console.log('Starting preview server...');
    spawn('npx', ['vite', 'preview', '--port', String(options.port)], {
      cwd: APP_ROOT,
      stdio: 'inherit',
      env: process.env
    });
  }
}

// ============================================
// Command: server
// ============================================

function runServer(options) {
  validateRailsApp();
  loadDatabaseConfig(options);
  validateDatabaseTarget(options);
  ensurePackagesInstalled(options);
  applyEnvOptions(options);

  // Check that app has been built
  if (!existsSync(join(APP_ROOT, 'dist'))) {
    console.error('Error: dist/ not found. Run "juntos build" first.');
    process.exit(1);
  }

  process.env.PORT = String(options.port);
  if (options.environment) {
    process.env.NODE_ENV = options.environment === 'production' ? 'production' : 'development';
  }

  const isServerTarget = ['node', 'bun', 'deno'].includes(options.target);

  if (isServerTarget) {
    // Run the built server directly (like 'up' command)
    const runtime = options.target === 'bun' ? 'bun' : options.target === 'deno' ? 'deno' : 'node';
    const entryPoint = join(APP_ROOT, 'dist', 'index.js');

    if (!existsSync(entryPoint)) {
      console.error(`Error: ${entryPoint} not found. Run "juntos build -t ${options.target}" first.`);
      process.exit(1);
    }

    console.log(`Starting ${runtime} server on port ${options.port}...`);
    spawn(runtime, [entryPoint], {
      cwd: APP_ROOT,
      stdio: 'inherit',
      env: { ...process.env, PORT: String(options.port) }
    });
  } else {
    // Browser target - serve static files with vite preview
    console.log(`Starting static server on port ${options.port}...`);
    spawn('npx', ['vite', 'preview', '--port', String(options.port), '--host'], {
      cwd: APP_ROOT,
      stdio: 'inherit',
      env: process.env
    });
  }
}

// ============================================
// Command: db
// ============================================

const BROWSER_DATABASES = ['dexie'];

function runDb(args, options) {
  const subcommand = args[0];

  if (!subcommand || options.help) {
    showDbHelp();
    process.exit(subcommand ? 0 : 1);
  }

  const validCommands = ['migrate', 'seed', 'prepare', 'reset', 'create', 'drop'];
  if (!validCommands.includes(subcommand)) {
    console.error(`Unknown db command: ${subcommand}`);
    console.error("Run 'juntos db --help' for usage.");
    process.exit(1);
  }

  validateRailsApp();
  loadEnvLocal();
  loadDatabaseConfig(options);
  applyEnvOptions(options);

  switch (subcommand) {
    case 'migrate':
      runDbMigrate(options);
      break;
    case 'seed':
      runDbSeed(options);
      break;
    case 'prepare':
      runDbPrepare(options);
      break;
    case 'reset':
      runDbReset(options);
      break;
    case 'create':
      runDbCreate(options);
      break;
    case 'drop':
      runDbDrop(options);
      break;
  }
}

function validateNotBrowser(options, command) {
  if (BROWSER_DATABASES.includes(options.database)) {
    console.error(`Error: Browser databases (${options.database}) auto-migrate at runtime.`);
    console.error('No CLI command needed - migrations run when the app loads in the browser.');
    process.exit(1);
  }
}

function runDbMigrate(options) {
  validateNotBrowser(options, 'migrate');

  if (options.database === 'd1') {
    runD1Migrate(options);
  } else {
    runNodeMigrate(options);
  }
}

function runDbSeed(options) {
  validateNotBrowser(options, 'seed');

  if (options.database === 'd1') {
    runD1Seed(options);
  } else {
    runNodeSeed(options);
  }
}

function runDbPrepare(options) {
  validateNotBrowser(options, 'prepare');

  if (options.database === 'd1') {
    // Check if database exists, create if not
    const env = options.environment || 'development';
    const dbId = getD1DatabaseId(env);
    if (!dbId) {
      console.log(`No ${d1EnvVar(env)} found. Creating database...`);
      runDbCreate(options);
    }
    runD1Prepare(options);
  } else {
    runNodePrepare(options);
  }
}

function runDbReset(options) {
  validateNotBrowser(options, 'reset');

  const env = options.environment || 'development';
  console.log(`Resetting ${options.database} database for ${env}...`);

  console.log('\nStep 1/4: Dropping database...');
  runDbDrop(options);

  if (['d1', 'turso', 'mpg'].includes(options.database)) {
    console.log('\nStep 2/4: Creating database...');
    runDbCreate(options);
  } else {
    console.log(`\nStep 2/4: Skipping create (${options.database} creates automatically)`);
  }

  console.log('\nStep 3/4: Running migrations...');
  runDbMigrate(options);

  console.log('\nStep 4/4: Running seeds...');
  runDbSeed(options);

  console.log('\nDatabase reset complete.');
}

function runDbCreate(options) {
  switch (options.database) {
    case 'd1':
      runD1Create(options);
      break;
    case 'sqlite':
    case 'better_sqlite3':
      console.log('SQLite databases are created automatically by db:migrate.');
      break;
    case 'dexie':
      console.log('Dexie (IndexedDB) databases are created automatically in the browser.');
      break;
    default:
      console.log(`Database creation for '${options.database}' is not supported via CLI.`);
      console.log('Please create your database using your database provider\'s tools.');
  }
}

function runDbDrop(options) {
  switch (options.database) {
    case 'd1':
      runD1Drop(options);
      break;
    case 'sqlite':
    case 'better_sqlite3':
      runSqliteDrop(options);
      break;
    case 'dexie':
      console.log('Dexie (IndexedDB) databases are managed by the browser.');
      console.log('Use browser DevTools > Application > IndexedDB to delete.');
      break;
    default:
      console.log(`Database deletion for '${options.database}' is not supported via CLI.`);
  }
}

// D1 helpers
function d1EnvVar(env = 'development') {
  return env === 'development' ? 'D1_DATABASE_ID' : `D1_DATABASE_ID_${env.toUpperCase()}`;
}

function getD1DatabaseId(env = 'development') {
  const varName = d1EnvVar(env);
  return process.env[varName] || process.env.D1_DATABASE_ID;
}

function saveD1DatabaseId(databaseId, env = 'development') {
  const envFile = join(APP_ROOT, '.env.local');
  const varName = d1EnvVar(env);

  let lines = [];
  if (existsSync(envFile)) {
    lines = readFileSync(envFile, 'utf-8').split('\n');
    lines = lines.filter(line => !line.startsWith(`${varName}=`));
  }
  lines.push(`${varName}=${databaseId}`);
  writeFileSync(envFile, lines.join('\n') + '\n');
}

function runD1Create(options) {
  const dbName = options.dbName;
  const env = options.environment || 'development';

  console.log(`Creating D1 database '${dbName}' for ${env}...`);

  try {
    const output = execSync(`npx wrangler d1 create ${dbName} 2>&1`, { encoding: 'utf-8' });
    if (options.verbose) console.log(output);

    const match = output.match(/"?database_id"?\s*[=:]\s*"?([a-f0-9-]+)"?/i);
    if (match) {
      const databaseId = match[1];
      saveD1DatabaseId(databaseId, env);
      console.log(`Created D1 database: ${dbName}`);
      console.log(`Database ID: ${databaseId}`);
      console.log(`Saved to .env.local (${d1EnvVar(env)})`);
    } else if (output.includes('already exists')) {
      console.log(`Database '${dbName}' already exists.`);
    } else {
      console.error('Error: Failed to create database.');
      console.error(output);
      process.exit(1);
    }
  } catch (e) {
    console.error('Error: Failed to create database.');
    console.error(e.message);
    process.exit(1);
  }
}

function runD1Drop(options) {
  const dbName = options.dbName;
  const env = options.environment || 'development';

  console.log(`Deleting D1 database '${dbName}'...`);

  try {
    execSync(`npx wrangler d1 delete ${dbName}`, { stdio: 'inherit' });

    // Remove from .env.local
    const envFile = join(APP_ROOT, '.env.local');
    if (existsSync(envFile)) {
      const varName = d1EnvVar(env);
      let lines = readFileSync(envFile, 'utf-8').split('\n');
      lines = lines.filter(line => !line.startsWith(`${varName}=`));
      writeFileSync(envFile, lines.join('\n'));
    }

    console.log('Database deleted and removed from .env.local');
  } catch (e) {
    console.error('Error: Failed to delete database.');
    process.exit(1);
  }
}

function runD1Migrate(options) {
  const dbName = options.dbName;
  console.log(`Running D1 migrations on '${dbName}'...`);

  const migrationsFile = join(APP_ROOT, 'dist', 'db', 'migrations.sql');
  if (!existsSync(migrationsFile)) {
    console.log('Building app to generate migrations...');
    execSync('npx vite build', { cwd: APP_ROOT, stdio: 'inherit', env: process.env });
  }

  const cmd = ['npx', 'wrangler', 'd1', 'execute', dbName, '--remote', '--file', 'dist/db/migrations.sql'];
  if (options.yes) cmd.push('--yes');

  try {
    execSync(cmd.join(' '), { cwd: APP_ROOT, stdio: 'inherit' });
    console.log('Migrations completed.');
  } catch (e) {
    console.error('Error: Migration failed.');
    process.exit(1);
  }
}

function runD1Seed(options) {
  const dbName = options.dbName;
  const seedsFile = join(APP_ROOT, 'dist', 'db', 'seeds.sql');

  if (!existsSync(seedsFile)) {
    console.log('No seeds.sql found - nothing to seed.');
    return;
  }

  console.log(`Running D1 seeds on '${dbName}'...`);

  const cmd = ['npx', 'wrangler', 'd1', 'execute', dbName, '--remote', '--file', 'dist/db/seeds.sql'];
  if (options.yes) cmd.push('--yes');

  try {
    execSync(cmd.join(' '), { cwd: APP_ROOT, stdio: 'inherit' });
    console.log('Seeds completed.');
  } catch (e) {
    console.error('Error: Seeding failed.');
    process.exit(1);
  }
}

function runD1Prepare(options) {
  const dbName = options.dbName;

  // Build first
  console.log('Building app...');
  execSync('npx vite build', { cwd: APP_ROOT, stdio: 'inherit', env: process.env });

  // Check if fresh
  let isFresh = true;
  try {
    const output = execSync(
      `npx wrangler d1 execute ${dbName} --remote --command="SELECT name FROM sqlite_master WHERE type='table' AND name='schema_migrations';"`,
      { encoding: 'utf-8', cwd: APP_ROOT }
    );
    isFresh = !output.includes('schema_migrations');
  } catch (e) {
    // Assume fresh if we can't check
  }

  // Migrate
  console.log('Running D1 migrations...');
  try {
    execSync(`npx wrangler d1 execute ${dbName} --remote --file dist/db/migrations.sql --yes`, {
      cwd: APP_ROOT,
      stdio: 'inherit'
    });
  } catch (e) {
    console.error('Error: Migration failed.');
    process.exit(1);
  }

  // Seed if fresh
  const seedsFile = join(APP_ROOT, 'dist', 'db', 'seeds.sql');
  if (isFresh && existsSync(seedsFile)) {
    console.log('Running D1 seeds (fresh database)...');
    try {
      execSync(`npx wrangler d1 execute ${dbName} --remote --file dist/db/seeds.sql --yes`, {
        cwd: APP_ROOT,
        stdio: 'inherit'
      });
    } catch (e) {
      console.error('Error: Seeding failed.');
      process.exit(1);
    }
  } else if (!isFresh) {
    console.log('Skipping seeds (existing database)');
  }

  console.log('Database prepared.');
}

// Node.js database helpers
function runNodeMigrate(options) {
  console.log('Running migrations...');
  try {
    // Run migrate.mjs from this package
    execSync(`node "${MIGRATE_SCRIPT}" --migrate-only`, {
      cwd: APP_ROOT,
      stdio: 'inherit',
      env: { ...process.env, JUNTOS_DIST_DIR: join(APP_ROOT, 'dist') }
    });
    console.log('Migrations completed.');
  } catch (e) {
    console.error('Error: Migration failed.');
    process.exit(1);
  }
}

function runNodeSeed(options) {
  console.log('Running seeds...');
  try {
    execSync(`node "${MIGRATE_SCRIPT}" --seed-only`, {
      cwd: APP_ROOT,
      stdio: 'inherit',
      env: { ...process.env, JUNTOS_DIST_DIR: join(APP_ROOT, 'dist') }
    });
    console.log('Seeds completed.');
  } catch (e) {
    console.error('Error: Seeding failed.');
    process.exit(1);
  }
}

function runNodePrepare(options) {
  console.log('Running migrations and seeds...');
  try {
    execSync(`node "${MIGRATE_SCRIPT}"`, {
      cwd: APP_ROOT,
      stdio: 'inherit',
      env: { ...process.env, JUNTOS_DIST_DIR: join(APP_ROOT, 'dist') }
    });
    console.log('Database prepared.');
  } catch (e) {
    console.error('Error: Database preparation failed.');
    process.exit(1);
  }
}

function runSqliteDrop(options) {
  const patterns = [
    'storage/development.sqlite3',
    'storage/production.sqlite3',
    'db/development.sqlite3',
    'db/production.sqlite3'
  ];

  for (const pattern of patterns) {
    const fullPath = join(APP_ROOT, pattern);
    if (existsSync(fullPath)) {
      console.log(`Deleting SQLite database: ${pattern}`);
      unlinkSync(fullPath);
      console.log('Database deleted.');
      return;
    }
  }

  console.log('No SQLite database file found.');
}

function showDbHelp() {
  console.log(`
Juntos Database Commands

Usage: juntos db <command> [options]
       juntos db:command [options]

Commands:
  migrate   Run database migrations
  seed      Run database seeds
  prepare   Migrate, and seed if fresh database
  reset     Drop, create, migrate, and seed
  create    Create database (D1, Turso)
  drop      Delete database (D1, SQLite)

Options:
  -d, --database ADAPTER   Database adapter (d1, sqlite, dexie, etc.)
  -e, --environment ENV    Rails environment (development, production, etc.)
  -y, --yes                Skip confirmation prompts
  -v, --verbose            Show detailed output
  -h, --help               Show this help message

Examples:
  juntos db:migrate                    # Run migrations (uses database.yml)
  juntos db:seed                       # Run seeds
  juntos db:prepare                    # Migrate + seed if fresh
  juntos db:prepare -e production      # Prepare production database
  juntos db:create -d d1               # Create D1 database
  juntos db:drop                       # Delete database

Note: Browser databases (dexie) auto-migrate at runtime.
`);
}

// ============================================
// Command: info
// ============================================

function runInfo(options) {
  loadEnvLocal();
  loadDatabaseConfig(options);

  const env = options.environment || process.env.RAILS_ENV || 'development';

  console.log('Juntos Configuration');
  console.log('========================================\n');

  console.log('Environment:');
  console.log(`  RAILS_ENV:        ${env}`);
  console.log(`  JUNTOS_DATABASE:  ${process.env.JUNTOS_DATABASE || '(not set)'}`);
  console.log(`  JUNTOS_TARGET:    ${process.env.JUNTOS_TARGET || '(not set)'}`);
  console.log();

  console.log('Database Configuration:');
  console.log(`  Adapter:  ${options.database}`);
  console.log(`  Database: ${options.dbName}`);
  if (options.target) console.log(`  Target:   ${options.target}`);
  console.log();

  console.log('Project:');
  console.log(`  Directory:    ${basename(APP_ROOT)}`);
  console.log(`  Rails app:    ${existsSync(join(APP_ROOT, 'app')) ? 'Yes' : 'No'}`);
  console.log(`  node_modules: ${existsSync(join(APP_ROOT, 'node_modules')) ? 'Installed' : 'Not installed'}`);
  console.log(`  dist/:        ${existsSync(join(APP_ROOT, 'dist')) ? 'Built' : 'Not built'}`);
}

// ============================================
// Command: doctor
// ============================================

function runDoctor(options) {
  console.log('Juntos Doctor');
  console.log('========================================\n');

  let allOk = true;

  // Check Node.js
  try {
    const nodeVersion = execSync('node --version', { encoding: 'utf-8' }).trim();
    const major = parseInt(nodeVersion.slice(1).split('.')[0], 10);
    if (major >= 18) {
      console.log(`Checking Node.js... OK (${nodeVersion})`);
    } else {
      console.log(`Checking Node.js... WARNING (${nodeVersion}, 18+ recommended)`);
    }
  } catch (e) {
    console.log('Checking Node.js... FAILED (not found)');
    allOk = false;
  }

  // Check npm
  try {
    const npmVersion = execSync('npm --version', { encoding: 'utf-8' }).trim();
    console.log(`Checking npm... OK (${npmVersion})`);
  } catch (e) {
    console.log('Checking npm... FAILED (not found)');
    allOk = false;
  }

  // Check Rails app structure
  if (existsSync(join(APP_ROOT, 'app')) && existsSync(join(APP_ROOT, 'config'))) {
    console.log('Checking Rails app structure... OK');
  } else {
    console.log('Checking Rails app structure... FAILED (app/ or config/ missing)');
    allOk = false;
  }

  // Check database.yml
  if (existsSync(join(APP_ROOT, 'config/database.yml'))) {
    console.log('Checking config/database.yml... OK');
  } else {
    console.log('Checking config/database.yml... WARNING (not found)');
  }

  // Check node_modules
  if (existsSync(join(APP_ROOT, 'node_modules'))) {
    console.log('Checking node_modules... OK');
  } else {
    console.log('Checking node_modules... FAILED (run npm install)');
    allOk = false;
  }

  // Check vite.config.js
  if (existsSync(join(APP_ROOT, 'vite.config.js'))) {
    console.log('Checking vite.config.js... OK');
  } else {
    console.log('Checking vite.config.js... WARNING (not found)');
  }

  console.log('\n========================================');
  if (allOk) {
    console.log('All checks passed! Your environment is ready.');
  } else {
    console.log('Some checks failed. Please fix the issues above.');
    process.exit(1);
  }
}

// ============================================
// Command: test
// ============================================

function runTest(options, testArgs) {
  validateRailsApp();
  loadDatabaseConfig(options);
  validateDatabaseTarget(options);
  ensurePackagesInstalled(options);
  applyEnvOptions(options);

  // Ensure vitest is installed
  if (!isPackageInstalled('vitest')) {
    console.log('Installing vitest...');
    try {
      execSync('npm install vitest', {
        cwd: APP_ROOT,
        stdio: 'inherit'
      });
    } catch (e) {
      console.error('Failed to install vitest.');
      process.exit(1);
    }
  }

  // Build vitest command
  const args = ['vitest', 'run'];

  // Pass through any additional arguments (file patterns, etc.)
  if (testArgs && testArgs.length > 0) {
    args.push(...testArgs);
  }

  console.log('Running tests...');
  const result = spawnSync('npx', args, {
    cwd: APP_ROOT,
    stdio: 'inherit',
    env: process.env
  });

  process.exit(result.status || 0);
}

// ============================================
// Command: deploy
// ============================================

const DEPLOY_TARGETS = {
  vercel: ['turso', 'neon', 'planetscale', 'supabase', 'dexie'],
  'vercel-edge': ['turso', 'neon', 'planetscale', 'supabase'],
  cloudflare: ['d1', 'turso', 'dexie'],
  'deno-deploy': ['turso', 'neon', 'dexie']
};

function runDeploy(options) {
  validateRailsApp();
  loadEnvLocal();
  loadDatabaseConfig(options);
  validateDatabaseTarget(options);
  ensurePackagesInstalled(options);

  // Default to production environment for deploy
  options.environment = options.environment || 'production';
  process.env.RAILS_ENV = options.environment;
  process.env.NODE_ENV = 'production';

  // Infer target from database if not specified
  if (!options.target && options.database) {
    if (options.database === 'd1') options.target = 'cloudflare';
    else if (['neon', 'turso', 'planetscale', 'supabase'].includes(options.database)) options.target = 'vercel';
  }

  if (!options.target) {
    console.error('Error: Deploy target required.');
    console.error('Use -t/--target to specify: vercel, cloudflare');
    console.error('\nExample: juntos deploy -t cloudflare -d d1');
    process.exit(1);
  }

  if (!DEPLOY_TARGETS[options.target]) {
    console.error(`Error: Unknown target '${options.target}'.`);
    console.error('Valid targets: vercel, cloudflare');
    process.exit(1);
  }

  if (options.database) {
    const validDbs = DEPLOY_TARGETS[options.target];
    if (!validDbs.includes(options.database)) {
      console.error(`Error: Database '${options.database}' not supported for ${options.target}.`);
      console.error(`Valid databases: ${validDbs.join(', ')}`);
      process.exit(1);
    }
  }

  applyEnvOptions(options);

  // Generate platform entry point BEFORE build (Vite needs it)
  if (options.target === 'cloudflare') {
    generateCloudflareEntryPoint(options);
  } else if (options.target === 'vercel' || options.target === 'vercel-edge') {
    generateVercelEntryPoint(options);
  } else if (options.target === 'deno-deploy') {
    generateDenoDeployEntryPoint(options);
  }

  // Build first unless skipped
  if (!options.skipBuild) {
    console.log(`Building for ${options.target} (${options.environment})...`);
    try {
      const buildArgs = ['vite', 'build'];
      if (options.sourcemap) buildArgs.push('--sourcemap');
      execSync(`npx ${buildArgs.join(' ')}`, { cwd: APP_ROOT, stdio: 'inherit', env: process.env });
    } catch (e) {
      console.error('Build failed.');
      process.exit(1);
    }
  }

  // Generate platform config (after build, in dist/)
  if (options.target === 'cloudflare') {
    generateCloudflareConfig(options);
  } else if (options.target === 'vercel') {
    generateVercelConfig(options);
  }

  // Run platform deploy
  runPlatformDeploy(options);
}

function generateCloudflareEntryPoint(options) {
  // Generate Worker entry point in src/ BEFORE build
  // This is needed because Vite requires the entry point to exist
  const srcDir = join(APP_ROOT, 'src');
  if (!existsSync(srcDir)) {
    mkdirSync(srcDir, { recursive: true });
  }

  // Check if app uses Turbo broadcasting
  const usesBroadcasting = checkUsesBroadcasting();

  const imports = usesBroadcasting
    ? "import { Application, Router, TurboBroadcaster } from 'juntos:rails';"
    : "import { Application, Router } from 'juntos:rails';";

  const exports = usesBroadcasting
    ? "export default Application.worker();\nexport { TurboBroadcaster };"
    : "export default Application.worker();";

  // Use virtual modules - Vite transforms these at build time
  const workerJs = `// Cloudflare Worker entry point
// Generated by Juntos

${imports}
import '../config/routes.rb';
import { migrations } from 'juntos:migrations';
import { Seeds } from '../db/seeds.rb';
import { layout } from 'juntos:views/layouts';

// Configure application
Application.configure({
  migrations: migrations,
  seeds: Seeds,
  layout: layout
});

${exports}
`;

  writeFileSync(join(srcDir, 'index.js'), workerJs);
  console.log('  Generated src/index.js (worker entry point)');
}

function generateDenoDeployEntryPoint(options) {
  // Generate Deno Deploy entry point as main.ts
  const entryTs = `// Deno Deploy entry point
// Generated by Juntos

import { Application, Router } from 'juntos:rails';
import './config/routes.rb';
import { migrations } from 'juntos:migrations';
import { Seeds } from './db/seeds.rb';
import { layout } from 'juntos:views/layouts';

// Configure application
Application.configure({
  migrations: migrations,
  seeds: Seeds,
  layout: layout
});

Deno.serve(Application.handler());
`;

  writeFileSync(join(APP_ROOT, 'main.ts'), entryTs);
  console.log('  Generated main.ts (Deno Deploy entry point)');
}

function generateVercelEntryPoint(options) {
  // Generate Vercel Edge Function entry point in api/ BEFORE build
  const apiDir = join(APP_ROOT, 'api');
  if (!existsSync(apiDir)) {
    mkdirSync(apiDir, { recursive: true });
  }

  const isEdge = options.target === 'vercel-edge';

  // Use virtual modules - Vite transforms these at build time
  const entryJs = `// Vercel ${isEdge ? 'Edge' : 'Node'} Function entry point
// Generated by Juntos

import { Application, Router } from 'juntos:rails';
import '../config/routes.rb';
import { migrations } from 'juntos:migrations';
import { Seeds } from '../db/seeds.rb';
import { layout } from 'juntos:views/layouts';

// Configure application
Application.configure({
  migrations: migrations,
  seeds: Seeds,
  layout: layout
});

${isEdge ? `export const config = { runtime: 'edge' };` : ''}

export default Application.handler();
`;

  writeFileSync(join(apiDir, '[[...path]].js'), entryJs);
  console.log('  Generated api/[[...path]].js (Vercel entry point)');
}

function generateCloudflareConfig(options) {
  const appName = basename(APP_ROOT).toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const env = options.environment || 'production';
  const dbName = options.dbName || `${appName}_${env}`.toLowerCase().replace(/[^a-z0-9_]/g, '_');

  // Get D1 database ID
  const envVar = env === 'development' ? 'D1_DATABASE_ID' : `D1_DATABASE_ID_${env.toUpperCase()}`;
  const d1DatabaseId = process.env[envVar] || process.env.D1_DATABASE_ID;

  if (!d1DatabaseId && options.database === 'd1') {
    console.error(`Error: ${envVar} not found.`);
    console.error('Set it in .env.local or as an environment variable.');
    console.error(`\nCreate with: juntos db:create -d d1 -e ${env}`);
    process.exit(1);
  }

  // Check if app uses Turbo broadcasting
  const usesBroadcasting = checkUsesBroadcasting();

  let wranglerToml = `name = "${appName}"
main = "worker.js"
compatibility_date = "${new Date().toISOString().split('T')[0]}"
compatibility_flags = ["nodejs_compat"]
workers_dev = true
preview_urls = true

# D1 database binding
[[d1_databases]]
binding = "DB"
database_name = "${dbName}"
database_id = "${d1DatabaseId}"

# Static assets (Rails convention: public/)
[assets]
directory = "./public"
`;

  if (usesBroadcasting) {
    wranglerToml += `
# Durable Objects for Turbo Streams broadcasting
[[durable_objects.bindings]]
name = "TURBO_BROADCASTER"
class_name = "TurboBroadcaster"

[[migrations]]
tag = "v1"
new_sqlite_classes = ["TurboBroadcaster"]
`;
  }

  const distDir = join(APP_ROOT, 'dist');
  writeFileSync(join(distDir, 'wrangler.toml'), wranglerToml);
  console.log('  Generated wrangler.toml');

  // Generate Worker entry point
  const srcDir = join(distDir, 'src');
  if (!existsSync(srcDir)) {
    mkdirSync(srcDir, { recursive: true });
  }

  const imports = usesBroadcasting
    ? "import { Application, Router, TurboBroadcaster } from '../lib/rails.js';"
    : "import { Application, Router } from '../lib/rails.js';";

  const exports = usesBroadcasting
    ? "export default Application.worker();\nexport { TurboBroadcaster };"
    : "export default Application.worker();";

  const workerJs = `// Cloudflare Worker entry point
// Generated by Juntos

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

  writeFileSync(join(srcDir, 'index.js'), workerJs);
  console.log('  Generated src/index.js');
}

function generateVercelConfig(options) {
  const vercelJson = {
    version: 2,
    buildCommand: "",
    routes: [
      { src: "/assets/(.*)", dest: "/public/assets/$1" },
      { src: "/(.*)", dest: "/api/[[...path]]" }
    ]
  };

  if (options.force) {
    vercelJson.installCommand = "npm cache clean --force && npm install";
  }

  const distDir = join(APP_ROOT, 'dist');
  writeFileSync(join(distDir, 'vercel.json'), JSON.stringify(vercelJson, null, 2));
  console.log('  Generated vercel.json');
}

function checkUsesBroadcasting() {
  const modelsDir = join(APP_ROOT, 'app/models');
  const viewsDir = join(APP_ROOT, 'app/views');

  // Check models for broadcast_*_to calls
  if (existsSync(modelsDir)) {
    try {
      const files = execSync(`find ${modelsDir} -name "*.rb"`, { encoding: 'utf-8' }).trim().split('\n');
      for (const file of files) {
        if (file && existsSync(file)) {
          const content = readFileSync(file, 'utf-8');
          if (/broadcast_\w+_to/.test(content)) return true;
        }
      }
    } catch (e) {}
  }

  // Check views for turbo_stream_from helper
  if (existsSync(viewsDir)) {
    try {
      const files = execSync(`find ${viewsDir} -name "*.erb"`, { encoding: 'utf-8' }).trim().split('\n');
      for (const file of files) {
        if (file && existsSync(file)) {
          const content = readFileSync(file, 'utf-8');
          if (/turbo_stream_from/.test(content)) return true;
        }
      }
    } catch (e) {}
  }

  return false;
}

function runPlatformDeploy(options) {
  console.log(`\nDeploying to ${options.target}...`);

  const distDir = join(APP_ROOT, 'dist');

  if (options.target === 'cloudflare') {
    try {
      execSync('which wrangler', { stdio: 'ignore' });
      console.log('Running: wrangler deploy');
      execSync('wrangler deploy', { cwd: distDir, stdio: 'inherit' });
    } catch (e) {
      if (e.status === undefined) {
        console.log('\nTo deploy, install Wrangler and run:');
        console.log('  npm install -g wrangler');
        console.log('  cd dist && wrangler deploy');
      } else {
        console.error('Deploy failed.');
        process.exit(1);
      }
    }
  } else if (options.target === 'vercel') {
    try {
      execSync('which vercel', { stdio: 'ignore' });
      const args = ['vercel', '--prod'];
      if (options.force) args.push('--force');
      console.log(`Running: ${args.join(' ')}`);
      execSync(args.join(' '), { cwd: distDir, stdio: 'inherit' });
    } catch (e) {
      if (e.status === undefined) {
        console.log('\nTo deploy, install Vercel CLI and run:');
        console.log('  npm install -g vercel');
        console.log('  cd dist && vercel --prod');
      } else {
        console.error('Deploy failed.');
        process.exit(1);
      }
    }
  }
}

// ============================================
// Main help
// ============================================

function showHelp() {
  console.log(`
Juntos - Rails patterns, JavaScript runtimes

Usage: juntos [options] <command> [command-options]

Commands:
  init      Initialize Juntos in a project
  dev       Start development server with hot reload
  build     Build for deployment
  eject     Write transpiled JavaScript files to disk (for debugging/migration)
  test      Run tests with Vitest
  server    Start production server (requires prior build)
  deploy    Build and deploy to serverless platform
  up        Build and run locally (node, bun, browser)
  db        Database commands (create, migrate, seed, prepare, drop, reset)
  info      Show current configuration
  doctor    Check environment and prerequisites

Common Options:
  -d, --database ADAPTER   Database adapter (dexie, sqlite, d1, etc.)
  -e, --environment ENV    Environment (development, production, test)
  -t, --target TARGET      Deploy target (browser, node, vercel, cloudflare)
  -p, --port PORT          Server port (default: 3000)

Examples:
  juntos dev                           # Start dev server (uses database.yml)
  juntos dev -d dexie                  # Dev with IndexedDB
  juntos build                         # Build for deployment
  juntos test                          # Run all tests
  juntos test -d sqlite                # Run tests with SQLite
  juntos up -d sqlite                  # Build and run with SQLite
  juntos deploy -t cloudflare -d d1    # Deploy to Cloudflare with D1
  juntos deploy -t vercel -d neon      # Deploy to Vercel with Neon
  juntos db:prepare                    # Migrate and seed if fresh
  juntos db:migrate -d d1              # Migrate D1 database

Run 'juntos <command> --help' for command-specific options.
`);
}

// ============================================
// Main entry point
// ============================================

const args = process.argv.slice(2);
const { options, remaining } = parseCommonArgs(args);

let command = remaining[0];
const commandArgs = remaining.slice(1);

// Handle db:command syntax
if (command && command.includes(':')) {
  const [cmd, subcmd] = command.split(':', 2);
  command = cmd;
  commandArgs.unshift(subcmd);
}

if (!command || options.help && !command) {
  showHelp();
  process.exit(command ? 0 : 1);
}

switch (command) {
  case 'init':
    if (options.help) {
      console.log('Usage: juntos init [options]\n\nInitialize Juntos in a project.\n');
      console.log('Options:');
      console.log('  --no-install   Skip npm install');
      console.log('  --quiet        Suppress output');
      process.exit(0);
    }
    // Parse --no-install flag
    options.noInstall = process.argv.includes('--no-install');
    options.quiet = process.argv.includes('--quiet');
    runInit(options);
    break;

  case 'dev':
    if (options.help) {
      console.log('Usage: juntos dev [options]\n\nStart development server with hot reload.\n');
      console.log('Options:');
      console.log('  -d, --database ADAPTER   Database adapter');
      console.log('  -p, --port PORT          Server port (default: 5173)');
      console.log('  -o, --open               Open browser automatically');
      process.exit(0);
    }
    runDev(options);
    break;

  case 'build':
    if (options.help) {
      console.log('Usage: juntos build [options]\n\nBuild application for deployment.\n');
      console.log('Options:');
      console.log('  -d, --database ADAPTER   Database adapter');
      console.log('  -t, --target TARGET      Build target');
      console.log('  -e, --environment ENV    Environment');
      console.log('  --sourcemap              Generate source maps');
      console.log('  --base PATH              Base public path for assets');
      process.exit(0);
    }
    runBuild(options);
    break;

  case 'eject':
    if (options.help) {
      console.log('Usage: juntos eject [options]\n\nWrite transpiled JavaScript files to disk.\n');
      console.log('This is useful for debugging or migrating away from Ruby source.\n');
      console.log('Options:');
      console.log('  --output, --out DIR      Output directory (default: ejected/)');
      console.log('  -d, --database ADAPTER   Database adapter');
      console.log('  -t, --target TARGET      Build target');
      console.log('  --base PATH              Base public path');
      process.exit(0);
    }
    runEject(options).catch(err => {
      console.error('Eject failed:', err.message);
      if (options.verbose) console.error(err.stack);
      process.exit(1);
    });
    break;

  case 'up':
    if (options.help) {
      console.log('Usage: juntos up [options]\n\nBuild and run locally.\n');
      console.log('Options:');
      console.log('  -d, --database ADAPTER   Database adapter');
      console.log('  -t, --target TARGET      Runtime target (browser, node, bun)');
      console.log('  -p, --port PORT          Server port (default: 3000)');
      process.exit(0);
    }
    runUp(options);
    break;

  case 'server':
    if (options.help) {
      console.log('Usage: juntos server [options]\n\nStart production server (requires prior build).\n');
      console.log('Options:');
      console.log('  -t, --target TARGET      Runtime target (browser, node, bun, deno)');
      console.log('  -p, --port PORT          Server port (default: 3000)');
      console.log('  -e, --environment ENV    Environment (default: production)');
      process.exit(0);
    }
    runServer(options);
    break;

  case 'db':
    runDb(commandArgs, options);
    break;

  case 'info':
    runInfo(options);
    break;

  case 'doctor':
    runDoctor(options);
    break;

  case 'test':
    if (options.help) {
      console.log('Usage: juntos test [options] [files...]\n\nRun tests with Vitest.\n');
      console.log('Options:');
      console.log('  -d, --database ADAPTER   Database adapter for tests');
      console.log('\nExamples:');
      console.log('  juntos test                    # Run all tests');
      console.log('  juntos test articles.test.mjs  # Run specific test file');
      console.log('  juntos test -d sqlite          # Run tests with SQLite');
      process.exit(0);
    }
    runTest(options, commandArgs);
    break;

  case 'deploy':
    if (options.help) {
      console.log('Usage: juntos deploy [options]\n\nBuild and deploy to a serverless platform.\n');
      console.log('Options:');
      console.log('  -t, --target TARGET      Deploy target (vercel, cloudflare)');
      console.log('  -d, --database ADAPTER   Database adapter');
      console.log('  -e, --environment ENV    Environment (default: production)');
      console.log('  --skip-build             Skip the build step');
      console.log('  -f, --force              Force deploy (clear cache)');
      console.log('  --sourcemap              Generate source maps');
      process.exit(0);
    }
    runDeploy(options);
    break;

  default:
    console.error(`Unknown command: ${command}`);
    console.error("Run 'juntos --help' for usage.");
    process.exit(1);
}
