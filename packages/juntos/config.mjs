// Shared database configuration loading
//
// Used at both runtime (server.mjs) and build time (vite.mjs, build.mjs, cli.mjs, etc.)
// Reads config/database.yml, applies environment variable overrides.

import path from 'node:path';
import fs from 'node:fs';

// Normalize adapter names to canonical Juntos equivalents.
// Handles Rails adapter names (sqlite3, postgresql) and common variations.
export const ADAPTER_ALIASES = {
  indexeddb: 'dexie',
  sqlite3: 'sqlite',
  better_sqlite3: 'sqlite',
  'sql.js': 'sqljs',
  postgres: 'pg',
  postgresql: 'pg',
  mysql2: 'mysql'
};

// Try to load js-yaml. Available at build time (devDependency),
// may not be present in production runtime deploys.
let yaml = null;
try {
  yaml = (await import('js-yaml')).default;
} catch {
  // Not available — will use naive parser fallback
}

/**
 * Load database configuration from config/database.yml with environment overrides.
 *
 * Priority: JUNTOS_DATABASE/DATABASE env > database.yml > defaults
 *
 * @param {string} appRoot - Application root directory
 * @param {Object} [options]
 * @param {boolean} [options.quiet] - Suppress console output
 * @returns {Object} Database configuration object with at least { adapter, database }
 */
export function loadDatabaseConfig(appRoot, { quiet = false } = {}) {
  const env = process.env.RAILS_ENV || process.env.NODE_ENV || 'development';
  const configPath = path.join(appRoot, 'config/database.yml');

  let dbConfig = null;
  if (fs.existsSync(configPath)) {
    try {
      const content = fs.readFileSync(configPath, 'utf8');

      if (yaml) {
        const config = yaml.load(content);
        if (config && config[env]) {
          if (!quiet) console.log(`  Using config/database.yml [${env}]`);
          dbConfig = config[env];
          // Rails 7+ multi-database format nests configs under named keys
          // (primary, cache, queue, cable). Use "primary" when present.
          if (dbConfig && !dbConfig.adapter && dbConfig.primary) {
            dbConfig = dbConfig.primary;
          }
        }
      } else {
        // Naive fallback: handles simple key: value pairs.
        // Does NOT handle YAML anchors (<<: *default).
        dbConfig = parseYamlNaive(content, env);
        if (!quiet && dbConfig) console.log(`  Using config/database.yml [${env}]`);
      }
    } catch (e) {
      if (!quiet) console.warn(`  Warning: Failed to parse database.yml: ${e.message}`);
    }
  }

  // Default config if database.yml not found or empty
  const appName = path.basename(appRoot);
  const defaultDbName = `${appName}_${env}`.toLowerCase().replace(/[^a-z0-9_]/g, '_');
  dbConfig = dbConfig || { adapter: 'dexie', database: defaultDbName };

  if (!dbConfig.database) {
    dbConfig.database = defaultDbName;
  }

  // DATABASE_URL overrides connection string
  if (process.env.DATABASE_URL) {
    dbConfig.url = process.env.DATABASE_URL;
  }

  // JUNTOS_DATABASE or DATABASE env var overrides adapter
  const dbEnv = process.env.JUNTOS_DATABASE || process.env.DATABASE;
  if (dbEnv) {
    if (!quiet) {
      console.log(`  Adapter override: ${process.env.JUNTOS_DATABASE ? 'JUNTOS_DATABASE' : 'DATABASE'}=${dbEnv}`);
    }
    dbConfig.adapter = dbEnv.toLowerCase();
  }

  // Normalize adapter name
  if (dbConfig.adapter && ADAPTER_ALIASES[dbConfig.adapter]) {
    dbConfig.adapter = ADAPTER_ALIASES[dbConfig.adapter];
  }

  return dbConfig;
}

function parseYamlNaive(content, env) {
  const lines = content.split('\n');
  let inEnv = false;
  const result = {};

  for (const line of lines) {
    const envMatch = line.match(/^(\w+):$/);
    if (envMatch) {
      inEnv = envMatch[1] === env;
      continue;
    }

    if (inEnv && line.startsWith('  ')) {
      const match = line.match(/^\s+(\w+):\s*(.+)$/);
      if (match) {
        result[match[1]] = match[2].trim();
      }
    }
  }

  return Object.keys(result).length > 0 ? result : null;
}
