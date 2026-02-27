// ActiveRecord adapter using built-in SQLite (node:sqlite on Node/Deno, bun:sqlite on Bun)
// No native compilation required — uses the runtime's built-in SQLite binding.

import { mkdirSync, existsSync } from 'node:fs';
import { dirname } from 'node:path';

import { SQLiteDialect, SQLITE_TYPE_MAP } from './dialects/sqlite.mjs';
import { attr_accessor, initTimePolyfill, quoteId } from 'juntos/adapters/active_record_base.mjs';
import { modelRegistry, _uuidTables, CollectionProxy, Reference, HasOneReference } from 'juntos/adapters/active_record_sql.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry, CollectionProxy, Reference, HasOneReference };

// Configuration injected at build time
const DB_CONFIG = {};

let db = null;

// Initialize the database
export async function initDatabase(options = {}) {
  // Close previous database to prevent native memory accumulation
  if (db) {
    try { db.close(); } catch (e) {}
    db = null;
  }

  const config = { ...DB_CONFIG, ...options };
  const dbPath = config.database || ':memory:';

  // Ensure parent directory exists for file-based databases
  if (dbPath !== ':memory:') {
    const dir = dirname(dbPath);
    if (dir && dir !== '.' && !existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
  }

  // Runtime detection: use bun:sqlite on Bun, node:sqlite elsewhere
  // Uses createRequire for Node to bypass Vite/Vitest module interception
  // (dynamic import('node:sqlite') gets resolved as bare 'sqlite' by Vite)
  let DatabaseClass;
  if (typeof Bun !== 'undefined') {
    DatabaseClass = (await import('bun:sqlite')).Database;
  } else {
    const { createRequire } = await import('node:module');
    const require = createRequire(import.meta.url);
    DatabaseClass = require('node:sqlite').DatabaseSync;
  }

  db = new DatabaseClass(dbPath);

  // Enable WAL mode for better concurrent read performance
  db.exec('PRAGMA journal_mode = WAL');

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
  if (columns.some(c => c.primaryKey && c.type === 'uuid')) _uuidTables.add(tableName);
  const columnDefs = columns.map(col => {
    const sqlType = SQLITE_TYPE_MAP[col.type] || 'TEXT';
    let def = `${quoteId(col.name)} ${sqlType}`;

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
        `FOREIGN KEY (${quoteId(fk.column)}) REFERENCES ${fk.references}(${quoteId(fk.primaryKey)})`
      );
    }
  }

  const sql = `CREATE TABLE IF NOT EXISTS ${tableName} (${columnDefs.join(', ')})`;
  return db.exec(sql);
}

export function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.map(c => quoteId(c)).join(', ') : quoteId(columns);

  const sql = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  return db.exec(sql);
}

export function addColumn(tableName, columnName, columnType) {
  const sqlType = SQLITE_TYPE_MAP[columnType] || 'TEXT';
  const sql = `ALTER TABLE ${tableName} ADD COLUMN ${quoteId(columnName)} ${sqlType}`;
  return db.exec(sql);
}

export function removeColumn(tableName, columnName) {
  // Drop any indexes referencing this column first (SQLite requires this)
  const indexes = db.prepare(
    `SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name=? AND sql IS NOT NULL`
  ).all(tableName);
  for (const idx of indexes) {
    if (idx.sql && idx.sql.includes(columnName)) {
      db.exec(`DROP INDEX IF EXISTS ${idx.name}`);
    }
  }

  // SQLite 3.35.0+ (2021-03-12) supports DROP COLUMN
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${quoteId(columnName)}`;
  return db.exec(sql);
}

export function dropTable(tableName) {
  const sql = `DROP TABLE IF EXISTS ${tableName}`;
  return db.exec(sql);
}

export function renameTable(oldName, newName) {
  const sql = `ALTER TABLE ${oldName} RENAME TO ${newName}`;
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
  const sql = `INSERT INTO ${tableName} (${keys.map(k => quoteId(k)).join(', ')}) VALUES (${placeholders.join(', ')})`;
  const stmt = db.prepare(sql);
  stmt.run(...values);
}

// Transaction support for test isolation (like Rails transactional tests)
export function beginTransaction() {
  if (db) {
    db.exec('BEGIN');
    // Defer FK checks until COMMIT; since we ROLLBACK, they never fire
    db.exec('PRAGMA defer_foreign_keys = ON');
  }
}

export function rollbackTransaction() {
  if (db) db.exec('ROLLBACK');
}

// Savepoint support for per-test isolation with persistent fixtures
export function beginSavepoint() {
  if (db) db.exec('SAVEPOINT test_sp');
}

export function rollbackSavepoint() {
  if (db) {
    db.exec('ROLLBACK TO test_sp');
    db.exec('RELEASE test_sp');
  }
}

// Close database connection and flush WAL to main database file
export async function closeDatabase() {
  if (db) {
    // Checkpoint WAL to ensure all data is written to main database file
    db.exec('PRAGMA wal_checkpoint(TRUNCATE)');
    db.close();
    db = null;
  }
}

// Built-in SQLite ActiveRecord implementation
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
