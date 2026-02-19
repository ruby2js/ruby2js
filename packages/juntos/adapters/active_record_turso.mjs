// ActiveRecord adapter for Turso (libSQL - SQLite at the edge)
// This file is copied to dist/lib/active_record.mjs at build time
// Turso uses HTTP/WebSocket, works in browser, Node.js, and edge runtimes

import { createClient } from '@libsql/client';

import { SQLiteDialect, SQLITE_TYPE_MAP } from './dialects/sqlite.mjs';
import { attr_accessor, initTimePolyfill } from 'juntos/adapters/active_record_base.mjs';
import { modelRegistry, CollectionProxy, Reference, HasOneReference } from 'juntos/adapters/active_record_sql.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry, CollectionProxy, Reference, HasOneReference };

// Configuration injected at build time
const DB_CONFIG = {};

let client = null;

// Initialize the database connection
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };

  // Connection URL: runtime env > options > build-time config
  const url = process.env.TURSO_DATABASE_URL || config.url || config.database_url;
  const authToken = process.env.TURSO_AUTH_TOKEN || config.auth_token || config.authToken;

  if (!url) {
    throw new Error('Turso requires TURSO_DATABASE_URL environment variable or url option');
  }

  const clientConfig = { url };

  // Auth token required for remote databases (not for local file:// URLs)
  if (authToken) {
    clientConfig.authToken = authToken;
  }

  // Embedded replica support (local SQLite that syncs with remote)
  // Useful for read-heavy workloads with local caching
  if (config.syncUrl || config.sync_url) {
    clientConfig.syncUrl = config.syncUrl || config.sync_url;
    clientConfig.syncInterval = config.syncInterval || config.sync_interval || 60;
  }

  client = createClient(clientConfig);

  // Time polyfill for Ruby compatibility
  initTimePolyfill(globalThis);

  // Extract database name from URL for logging
  const dbName = url.match(/libsql:\/\/([^.]+)/)?.[1] || url.split('/').pop() || 'turso';
  console.log(`Connected to Turso: ${dbName}`);

  return client;
}

// Execute raw SQL (for schema creation, migrations)
export async function execSQL(sql) {
  // Handle multiple statements separated by semicolons
  const statements = sql.split(';').filter(s => s.trim());
  for (const stmt of statements) {
    if (stmt.trim()) {
      await client.execute(stmt);
    }
  }
}

// Abstract DDL interface - creates SQLite tables from abstract schema
export async function createTable(tableName, columns, options = {}) {
  const columnDefs = columns.map(col => {
    const sqlType = SQLITE_TYPE_MAP[col.type] || 'TEXT';
    let def = `${col.name} ${sqlType}`;

    if (col.primaryKey) {
      def += ' PRIMARY KEY';
      if (col.autoIncrement) def += ' AUTOINCREMENT';
    }
    if (col.null === false) def += ' NOT NULL';
    if (col.default !== undefined) {
      def += ` DEFAULT ${formatDefaultValue(col.default)}`;
    }

    return def;
  });

  // Add foreign key constraints
  if (options.foreignKeys) {
    for (const fk of options.foreignKeys) {
      columnDefs.push(
        `FOREIGN KEY (${fk.column}) REFERENCES ${fk.references}(${fk.primaryKey})`
      );
    }
  }

  const sql = `CREATE TABLE IF NOT EXISTS ${tableName} (${columnDefs.join(', ')})`;
  return await client.execute(sql);
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.join(', ') : columns;

  const sql = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  return await client.execute(sql);
}

export async function addColumn(tableName, columnName, columnType) {
  const sqlType = SQLITE_TYPE_MAP[columnType] || 'TEXT';
  const sql = `ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${sqlType}`;
  return await client.execute(sql);
}

export async function removeColumn(tableName, columnName) {
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${columnName}`;
  return await client.execute(sql);
}

export async function dropTable(tableName) {
  const sql = `DROP TABLE IF EXISTS ${tableName}`;
  return await client.execute(sql);
}

function formatDefaultValue(value) {
  if (value === null) return 'NULL';
  if (typeof value === 'string') return `'${value.replace(/'/g, "''")}'`;
  if (typeof value === 'boolean') return value ? '1' : '0';
  return String(value);
}

// Get the raw database client
export function getDatabase() {
  return client;
}

// Query interface for rails_base.js migration system
export async function query(sql, params = []) {
  const result = await client.execute({ sql, args: params });
  return result.rows.map(row => ({ ...row }));
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  const result = await client.execute({ sql, args: params });
  return { changes: result.rowsAffected || 0 };
}

// Insert a row - libSQL uses ? placeholders
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map(() => '?');
  const sql = `INSERT INTO ${tableName} (${keys.join(', ')}) VALUES (${placeholders.join(', ')})`;
  await client.execute({ sql, args: values });
}

// Close the connection
export async function closeDatabase() {
  if (client) {
    client.close();
    client = null;
  }
}

// Turso-specific ActiveRecord implementation
// Extends SQLiteDialect which provides all finder/mutation methods
// Only needs to implement driver-specific execution
export class ActiveRecord extends SQLiteDialect {
  // Execute SQL and return raw result
  static async _execute(sql, params = []) {
    return await client.execute({ sql, args: params });
  }

  // Extract rows array from result, converting to plain objects
  static _getRows(result) {
    return (result.rows || []).map(row => ({ ...row }));
  }

  // Get last insert ID from result
  static _getLastInsertId(result) {
    // libSQL returns lastInsertRowid for inserts
    return result.rows?.[0]?.id ?? Number(result.lastInsertRowid);
  }
}
