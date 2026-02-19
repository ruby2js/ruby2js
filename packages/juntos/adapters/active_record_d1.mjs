// ActiveRecord adapter for Cloudflare D1 (SQLite at the edge)
// This file is copied to dist/lib/active_record.mjs at build time
// D1 is Cloudflare's serverless SQLite database, accessed via Worker bindings

import { SQLiteDialect, SQLITE_TYPE_MAP } from './dialects/sqlite.mjs';
import { attr_accessor, initTimePolyfill } from 'juntos/adapters/active_record_base.mjs';
import { modelRegistry, CollectionProxy, Reference, HasOneReference } from 'juntos/adapters/active_record_sql.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry, CollectionProxy, Reference, HasOneReference };

// Configuration injected at build time
const DB_CONFIG = {};

let db = null;

// Initialize the database with D1 binding from Worker env
// Called with env.DB from the Worker's fetch handler
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };

  // D1 binding must be passed in - it comes from the Worker's env
  if (config.binding) {
    db = config.binding;
  } else if (config.env && config.env[config.bindingName || 'DB']) {
    db = config.env[config.bindingName || 'DB'];
  } else {
    throw new Error('D1 binding not provided. Pass { binding: env.DB } or { env, bindingName: "DB" }');
  }

  // Time polyfill for Ruby compatibility
  initTimePolyfill(globalThis);

  console.log('Connected to Cloudflare D1');
  return db;
}

// Execute raw SQL (for schema creation, migrations)
export async function execSQL(sql) {
  // D1's exec() supports multiple statements
  return await db.exec(sql);
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
  return await db.exec(sql);
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.join(', ') : columns;

  const sql = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  return await db.exec(sql);
}

export async function addColumn(tableName, columnName, columnType) {
  const sqlType = SQLITE_TYPE_MAP[columnType] || 'TEXT';
  const sql = `ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${sqlType}`;
  return await db.exec(sql);
}

export async function removeColumn(tableName, columnName) {
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${columnName}`;
  return await db.exec(sql);
}

export async function dropTable(tableName) {
  const sql = `DROP TABLE IF EXISTS ${tableName}`;
  return await db.exec(sql);
}

function formatDefaultValue(value) {
  if (value === null) return 'NULL';
  if (typeof value === 'string') return `'${value.replace(/'/g, "''")}'`;
  if (typeof value === 'boolean') return value ? '1' : '0';
  return String(value);
}

// Get the raw database instance
export function getDatabase() {
  return db;
}

// Close database connection (no-op for D1 - Worker runtime manages connections)
export async function closeDatabase() {
  // D1 connections are managed by Cloudflare Workers runtime
}

// Query interface for rails_base.js migration system
export async function query(sql, params = []) {
  const stmt = db.prepare(sql);
  const result = params.length > 0 ? await stmt.bind(...params).all() : await stmt.all();
  return result.results;
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  const stmt = db.prepare(sql);
  const result = params.length > 0 ? await stmt.bind(...params).run() : await stmt.run();
  return { changes: result.meta?.changes || 0 };
}

// Insert a row - D1 uses ? placeholders
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map(() => '?');
  const sql = `INSERT INTO ${tableName} (${keys.join(', ')}) VALUES (${placeholders.join(', ')})`;
  const stmt = db.prepare(sql);
  await stmt.bind(...values).run();
}

// D1-specific ActiveRecord implementation
// Extends SQLiteDialect which provides all finder/mutation methods
// Only needs to implement driver-specific execution
export class ActiveRecord extends SQLiteDialect {
  // Execute SQL and return raw result
  // D1 uses prepare/bind pattern
  static async _execute(sql, params = []) {
    const stmt = db.prepare(sql);
    const bound = params.length > 0 ? stmt.bind(...params) : stmt;

    // For SELECT queries, use all(); for others, use run()
    if (sql.trim().toUpperCase().startsWith('SELECT')) {
      const result = await bound.all();
      return { rows: result.results, type: 'select' };
    } else {
      const result = await bound.run();
      return { meta: result.meta, type: 'run' };
    }
  }

  // Extract rows array from result
  static _getRows(result) {
    return result.rows || [];
  }

  // Get last insert ID from result
  static _getLastInsertId(result) {
    return result.meta?.last_row_id;
  }
}
