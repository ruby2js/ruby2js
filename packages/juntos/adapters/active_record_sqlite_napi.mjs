// ActiveRecord adapter for sqlite-napi (QuickBEAM native SQLite)
// sqlite-napi is a Rust-based N-API addon bundled with QuickBEAM
// Supports both file-based and in-memory databases

import { SQLiteDialect, SQLITE_TYPE_MAP } from './dialects/sqlite.mjs';
import { attr_accessor, initTimePolyfill, quoteId } from 'juntos/adapters/active_record_base.mjs';
import { modelRegistry, _uuidTables, CollectionProxy, Reference, HasOneReference } from 'juntos/adapters/active_record_sql.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry, CollectionProxy, Reference, HasOneReference };

// Configuration injected at build time
const DB_CONFIG = {};

let db = null;

// Initialize the database
// sqlite-napi is loaded as a QuickBEAM addon and available as a global
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };
  const dbPath = config.database || ':memory:';

  db = new sqlite.Database(dbPath);

  // Time polyfill for Ruby compatibility
  initTimePolyfill(globalThis);

  console.log(`Connected to SQLite: ${dbPath}`);
  return db;
}

// Execute raw SQL (for schema creation, migrations)
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
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${quoteId(columnName)}`;
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

// Close database connection
export async function closeDatabase() {
  if (db) {
    db.close();
    db = null;
  }
}

// Query interface for rails_base.js migration system
export async function query(sql, params = []) {
  const stmt = db.query(sql);
  return stmt.all(...params);
}

// Escape a value for safe SQL interpolation (used by db.exec which has no params)
// Note: db.query().run() doesn't persist to file in QuickBEAM's sqlite-napi;
// only db.exec() works for mutations on file-based databases.
function escapeValue(value) {
  if (value === null || value === undefined) return 'NULL';
  if (typeof value === 'number') return String(value);
  if (typeof value === 'boolean') return value ? '1' : '0';
  // String: escape single quotes
  return `'${String(value).replace(/'/g, "''")}'`;
}

// Build a SQL string with values interpolated (for db.exec)
function interpolateSQL(sql, params) {
  let i = 0;
  return sql.replace(/\?/g, () => escapeValue(params[i++]));
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  db.exec(params.length > 0 ? interpolateSQL(sql, params) : sql);
}

// Insert a row
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const valueParts = values.map(v => escapeValue(v));
  const sql = `INSERT INTO ${tableName} (${keys.map(k => quoteId(k)).join(', ')}) VALUES (${valueParts.join(', ')})`;
  db.exec(sql);
}

// sqlite-napi ActiveRecord implementation
// Extends SQLiteDialect which provides all finder/mutation methods
// Only needs to implement driver-specific execution
export class ActiveRecord extends SQLiteDialect {
  // Execute SQL and return raw result
  // Note: db.exec() is the only method that persists to file-based databases
  // in QuickBEAM's sqlite-napi. db.run() and db.query().run() silently fail.
  static async _execute(sql, params = []) {
    if (sql.trim().toUpperCase().startsWith('SELECT')) {
      const stmt = db.query(sql);
      return { rows: stmt.all(...params), type: 'select' };
    } else {
      // Use db.exec with interpolated values (only method that persists)
      db.exec(params.length > 0 ? interpolateSQL(sql, params) : sql);

      // Get last insert ID if this was an INSERT
      let lastInsertRowid;
      if (sql.trim().toUpperCase().startsWith('INSERT')) {
        const row = db.query('SELECT last_insert_rowid() as id').get();
        lastInsertRowid = row?.id;
      }

      return { info: { lastInsertRowid }, type: 'run' };
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

  // Disable/enable foreign key checks
  static _deferForeignKeys(enabled) {
    db.exec(`PRAGMA foreign_keys = ${enabled ? 'OFF' : 'ON'}`);
  }
}

// Transaction support for test isolation
export function beginTransaction() {
  if (db) {
    db.exec('BEGIN');
    db.exec('PRAGMA defer_foreign_keys = ON');
  }
}

export function rollbackTransaction() {
  if (db) db.exec('ROLLBACK');
}

export function beginSavepoint() {
  if (db) db.exec('SAVEPOINT test_sp');
}

export function rollbackSavepoint() {
  if (db) {
    db.exec('ROLLBACK TO test_sp');
    db.exec('RELEASE test_sp');
  }
}
