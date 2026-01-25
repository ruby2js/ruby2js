// ActiveRecord adapter for sql.js (SQLite in WebAssembly)
// This file is copied to dist/lib/active_record.mjs at build time

import { SQLiteDialect, SQLITE_TYPE_MAP } from './dialects/sqlite.mjs';
import { attr_accessor, initTimePolyfill } from 'ruby2js-rails/adapters/active_record_base.mjs';
import { modelRegistry, CollectionProxy } from 'ruby2js-rails/adapters/active_record_sql.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry, CollectionProxy };

// Configuration injected at build time
const DB_CONFIG = {};

let db = null;

// Dynamically load sql-wasm.js if not already loaded
async function loadSqlJs(scriptPath) {
  if (typeof window !== 'undefined' && window.initSqlJs) {
    return; // Already loaded
  }

  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = scriptPath;
    script.onload = resolve;
    script.onerror = () => reject(new Error(`Failed to load sql.js from ${scriptPath}`));
    document.head.appendChild(script);
  });
}

// Initialize the database
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };

  // Determine sql.js path based on environment
  // Priority: config option > base href detection > default path
  let sqlJsPath = config.sqlJsPath;
  if (!sqlJsPath) {
    // Check for <base href> tag (used in hosted demo)
    const baseTag = document.querySelector('base[href]');
    if (baseTag) {
      const baseHref = baseTag.getAttribute('href');
      sqlJsPath = `${baseHref}node_modules/sql.js/dist`;
    } else {
      sqlJsPath = '/node_modules/sql.js/dist';
    }
  }

  // Load sql-wasm.js dynamically if needed
  await loadSqlJs(`${sqlJsPath}/sql-wasm.js`);

  const SQL = await window.initSqlJs({
    locateFile: file => `${sqlJsPath}/${file}`
  });

  db = new SQL.Database();

  // Time polyfill for Ruby compatibility
  initTimePolyfill(window);

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
  // sql.js uses SQLite which supports DROP COLUMN in 3.35.0+
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

// Close database connection
export async function closeDatabase() {
  if (db) {
    db.close();
    db = null;
  }
}

// Query interface for rails_base.js migration system
export async function query(sql, params = []) {
  const stmt = db.prepare(sql);
  stmt.bind(params);
  const results = [];
  while (stmt.step()) {
    results.push(stmt.getAsObject());
  }
  stmt.free();
  return results;
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  db.run(sql, params);
  return { changes: db.getRowsModified() };
}

// Insert a row - SQLite uses ? placeholders
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map(() => '?');
  const sql = `INSERT INTO ${tableName} (${keys.join(', ')}) VALUES (${placeholders.join(', ')})`;
  db.run(sql, values);
}

// sql.js-specific ActiveRecord implementation
// Extends SQLiteDialect which provides all finder/mutation methods
// Only needs to implement driver-specific execution
export class ActiveRecord extends SQLiteDialect {
  // Execute SQL and return raw result
  // sql.js has different APIs for SELECT vs mutations
  static async _execute(sql, params = []) {
    const isSelect = sql.trim().toUpperCase().startsWith('SELECT');

    if (isSelect) {
      // Use prepared statement for SELECT to handle params properly
      const stmt = db.prepare(sql);
      stmt.bind(params);
      const rows = [];
      while (stmt.step()) {
        rows.push(stmt.getAsObject());
      }
      stmt.free();
      return { rows, type: 'select' };
    } else {
      // Use run() for mutations
      db.run(sql, params);
      // Get last insert rowid for INSERT statements
      const lastId = db.exec('SELECT last_insert_rowid()');
      const lastInsertRowid = lastId[0]?.values[0]?.[0];
      return {
        lastInsertRowid,
        changes: db.getRowsModified(),
        type: 'run'
      };
    }
  }

  // Extract rows array from result
  static _getRows(result) {
    return result.rows || [];
  }

  // Get last insert ID from result
  static _getLastInsertId(result) {
    return result.lastInsertRowid;
  }
}
