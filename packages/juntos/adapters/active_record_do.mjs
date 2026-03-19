// ActiveRecord adapter for Cloudflare Durable Objects (SQLite storage)
// This file is copied to dist/lib/active_record.mjs at build time
// DO SQLite is per-instance embedded storage, accessed via state.storage.sql

import { SQLiteDialect, SQLITE_TYPE_MAP } from './dialects/sqlite.mjs';
import { attr_accessor, initTimePolyfill, quoteId } from 'juntos/adapters/active_record_base.mjs';
import { modelRegistry, CollectionProxy, Reference, HasOneReference } from 'juntos/adapters/active_record_sql.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry, CollectionProxy, Reference, HasOneReference };

// Configuration injected at build time
const DB_CONFIG = {};

let sql = null;

// Initialize the database with DO's SqlStorage
// Called with state.storage.sql from the Durable Object constructor
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };

  if (config.sql) {
    sql = config.sql;
  } else if (config.state) {
    sql = config.state.storage.sql;
  } else {
    throw new Error('DO SqlStorage not provided. Pass { sql: state.storage.sql } or { state }');
  }

  // Time polyfill for Ruby compatibility
  initTimePolyfill(globalThis);

  console.log('Connected to Durable Object SQLite');
  return sql;
}

// Execute raw SQL (for schema creation, migrations)
// DO's exec() handles multiple statements when separated by semicolons
export async function execSQL(rawSql) {
  // Split on semicolons and execute each statement
  const statements = rawSql.split(';').map(s => s.trim()).filter(s => s.length > 0);
  for (const stmt of statements) {
    sql.exec(stmt);
  }
}

// Abstract DDL interface - creates SQLite tables from abstract schema
export async function createTable(tableName, columns, options = {}) {
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

  const stmt = `CREATE TABLE IF NOT EXISTS ${tableName} (${columnDefs.join(', ')})`;
  sql.exec(stmt);
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.map(c => quoteId(c)).join(', ') : quoteId(columns);

  const stmt = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  sql.exec(stmt);
}

export async function addColumn(tableName, columnName, columnType) {
  const sqlType = SQLITE_TYPE_MAP[columnType] || 'TEXT';
  const stmt = `ALTER TABLE ${tableName} ADD COLUMN ${quoteId(columnName)} ${sqlType}`;
  sql.exec(stmt);
}

export async function removeColumn(tableName, columnName) {
  const stmt = `ALTER TABLE ${tableName} DROP COLUMN ${quoteId(columnName)}`;
  sql.exec(stmt);
}

export async function dropTable(tableName) {
  const stmt = `DROP TABLE IF EXISTS ${tableName}`;
  sql.exec(stmt);
}

function formatDefaultValue(value) {
  if (value === null) return 'NULL';
  if (typeof value === 'string') return `'${value.replace(/'/g, "''")}'`;
  if (typeof value === 'boolean') return value ? '1' : '0';
  return String(value);
}

// Get the raw SqlStorage instance
export function getDatabase() {
  return sql;
}

// Close database connection (no-op for DO - storage is managed by the runtime)
export async function closeDatabase() {
  // DO storage is managed by Cloudflare runtime
}

// Query interface for rails_base.js migration system
export async function query(stmt, params = []) {
  const cursor = params.length > 0 ? sql.exec(stmt, ...params) : sql.exec(stmt);
  return cursor.toArray();
}

// Execute interface for rails_base.js migration system
export async function execute(stmt, params = []) {
  const cursor = params.length > 0 ? sql.exec(stmt, ...params) : sql.exec(stmt);
  return { changes: cursor.rowsWritten };
}

// Insert a row - DO SQLite uses ? placeholders
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map(() => '?');
  const stmt = `INSERT INTO ${tableName} (${keys.map(k => quoteId(k)).join(', ')}) VALUES (${placeholders.join(', ')})`;
  sql.exec(stmt, ...values);
}

// DO SQLite ActiveRecord implementation
// Extends SQLiteDialect which provides all finder/mutation methods
// Only needs to implement driver-specific execution
export class ActiveRecord extends SQLiteDialect {
  // Execute SQL and return raw result
  // DO SQLite uses a single exec() method for all queries
  static async _execute(stmt, params = []) {
    const cursor = params.length > 0 ? sql.exec(stmt, ...params) : sql.exec(stmt);

    // For SELECT queries, return rows; for others, get last insert ID
    if (stmt.trim().toUpperCase().startsWith('SELECT')) {
      return { rows: cursor.toArray(), type: 'select' };
    } else {
      // Get last insert rowid for INSERT statements
      const lastId = sql.exec('SELECT last_insert_rowid() as id').one().id;
      return { meta: { last_row_id: lastId, changes: cursor.rowsWritten }, type: 'run' };
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
