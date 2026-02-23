// Shared base for browser SQLite adapters (sql.js, @sqlite.org/sqlite-wasm, wa-sqlite)
//
// Provides DDL helpers, query/execute interface, and importDump().
// Subclasses must implement initDatabase() and ActiveRecord._execute().

import { SQLiteDialect, SQLITE_TYPE_MAP } from './sqlite.mjs';
import { attr_accessor, initTimePolyfill, quoteId } from 'juntos/adapters/active_record_base.mjs';
import { modelRegistry, _uuidTables, CollectionProxy, Reference, HasOneReference } from 'juntos/adapters/active_record_sql.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry, CollectionProxy, Reference, HasOneReference };

// Module-level database handle, set by each adapter's initDatabase()
let db = null;

export function setDatabase(instance) {
  db = instance;
}

export function getDatabase() {
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
      def += ` DEFAULT ${SQLiteDialect.formatDefaultValue(col.default)}`;
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
  const sql = `INSERT INTO ${tableName} (${keys.map(k => quoteId(k)).join(', ')}) VALUES (${placeholders.join(', ')})`;
  db.run(sql, values);
}

// Import a SQL dump string (e.g., from `sqlite3 .dump`)
// Splits on statement boundaries and executes each within a transaction
export async function importDump(sqlText) {
  db.exec('BEGIN TRANSACTION');
  try {
    // Split on semicolons followed by newline (preserves semicolons in strings)
    const statements = sqlText.split(/;\s*\n/).filter(s => s.trim());
    for (const stmt of statements) {
      const trimmed = stmt.trim();
      // Skip SQLite-specific meta commands and transaction wrappers
      if (!trimmed || trimmed.startsWith('--') || trimmed === 'BEGIN TRANSACTION' || trimmed === 'COMMIT') continue;
      db.exec(trimmed + ';');
    }
    db.exec('COMMIT');
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}

export { SQLiteDialect, SQLITE_TYPE_MAP };
