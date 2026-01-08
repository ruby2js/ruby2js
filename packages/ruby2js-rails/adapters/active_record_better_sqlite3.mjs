// ActiveRecord adapter for better-sqlite3 (Node.js synchronous SQLite)
// This file is copied to dist/lib/active_record.mjs at build time
// better-sqlite3 is a fast, synchronous SQLite3 binding for Node.js

import Database from 'better-sqlite3';

import { SQLiteDialect, SQLITE_TYPE_MAP } from './dialects/sqlite.mjs';
import { attr_accessor, initTimePolyfill } from 'ruby2js-rails/adapters/active_record_base.mjs';
import { modelRegistry } from 'ruby2js-rails/adapters/active_record_sql.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry };

// Configuration injected at build time
const DB_CONFIG = {};

let db = null;

// Initialize the database
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };
  const dbPath = config.database || ':memory:';

  db = new Database(dbPath, {
    verbose: config.verbose ? console.log : null
  });

  // Enable WAL mode for better concurrent read performance
  db.pragma('journal_mode = WAL');

  // Time polyfill for Ruby compatibility (Node.js global)
  initTimePolyfill(globalThis);

  return db;
}

// Execute raw SQL (for schema creation) - legacy, prefer createTable/addIndex
export function execSQL(sql) {
  return db.exec(sql);
}

// Abstract DDL interface - creates SQLite tables from abstract schema
export function createTable(tableName, columns, options = {}) {
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
  return db.exec(sql);
}

export function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.join(', ') : columns;

  const sql = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  return db.exec(sql);
}

export function addColumn(tableName, columnName, columnType) {
  const sqlType = SQLITE_TYPE_MAP[columnType] || 'TEXT';
  const sql = `ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${sqlType}`;
  return db.exec(sql);
}

export function removeColumn(tableName, columnName) {
  // SQLite doesn't support DROP COLUMN directly in older versions
  // For SQLite 3.35.0+ (2021-03-12), this works:
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${columnName}`;
  return db.exec(sql);
}

export function dropTable(tableName) {
  const sql = `DROP TABLE IF EXISTS ${tableName}`;
  return db.exec(sql);
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

// Query interface for rails_base.js migration system
export async function query(sql, params = []) {
  const stmt = db.prepare(sql);
  return stmt.all(...params);
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  const stmt = db.prepare(sql);
  return stmt.run(...params);
}

// Insert a row - SQLite uses ? placeholders
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map(() => '?');
  const sql = `INSERT INTO ${tableName} (${keys.join(', ')}) VALUES (${placeholders.join(', ')})`;
  const stmt = db.prepare(sql);
  stmt.run(...values);
}

// better-sqlite3-specific ActiveRecord implementation
// Extends SQLiteDialect which provides all finder/mutation methods
// Only needs to implement driver-specific execution
export class ActiveRecord extends SQLiteDialect {
  // Execute SQL and return raw result
  static async _execute(sql, params = []) {
    const stmt = db.prepare(sql);
    // For SELECT queries, use all(); for others, use run()
    if (sql.trim().toUpperCase().startsWith('SELECT')) {
      return { rows: stmt.all(...params), type: 'select' };
    } else {
      return { info: stmt.run(...params), type: 'run' };
    }
  }

  // Extract rows array from result
  static _getRows(result) {
    return result.rows || [];
  }

  // Get last insert ID from result
  static _getLastInsertId(result) {
    return result.info?.lastInsertRowid;
  }
}
