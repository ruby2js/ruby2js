// ActiveRecord adapter for SharedWorker target (SQL over MessagePort)
// Application tier adapter: sends SQL to the dedicated database Worker
// via postMessage instead of executing directly.
//
// Database-engine-agnostic — the dedicated Worker runs the real adapter
// (PGlite, SQLite WASM, wa-sqlite). This adapter just serializes SQL
// over the MessagePort boundary.

import { attr_accessor, initTimePolyfill } from 'juntos/adapters/active_record_base.mjs';
import { modelRegistry, CollectionProxy, Reference, HasOneReference } from 'juntos/adapters/active_record_sql.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry, CollectionProxy, Reference, HasOneReference };

// Reference to the dedicated database Worker (set during init)
let dbWorker = null;

// Pending query promises keyed by correlation ID
const pending = new Map();

// Message handler for responses from the dedicated Worker
function handleWorkerMessage({ data }) {
  if ((data.type === 'result' || data.type === 'error') && data.id) {
    const resolver = pending.get(data.id);
    if (resolver) {
      pending.delete(data.id);
      if (data.type === 'error') {
        resolver.reject(new Error(data.error));
      } else {
        resolver.resolve(data);
      }
    }
  }
}

// Send a message to the dedicated Worker and await the response
function sendMessage(message) {
  return new Promise((resolve, reject) => {
    const id = crypto.randomUUID();
    pending.set(id, { resolve, reject });
    dbWorker.postMessage({ ...message, id });
  });
}

// Initialize the database via the dedicated Worker
export async function initDatabase(options = {}) {
  // The dedicated Worker is created by the SharedWorker (Application.start)
  // and passed to us via setWorker()
  if (!dbWorker) {
    throw new Error('Database Worker not set. Call setWorker() before initDatabase().');
  }

  // Time polyfill for Ruby compatibility
  initTimePolyfill(globalThis);
}

// Set the dedicated Worker reference (called by SharedWorker's Application.start)
export function setWorker(worker) {
  dbWorker = worker;
  dbWorker.addEventListener('message', handleWorkerMessage);
}

// Execute raw SQL (for schema creation, migrations)
export async function execSQL(sql) {
  return sendMessage({ type: 'execSQL', sql });
}

// Create a table via the dedicated Worker
export async function createTable(tableName, columns, options = {}) {
  return sendMessage({ type: 'createTable', tableName, columns, options });
}

// Add an index via the dedicated Worker
export async function addIndex(tableName, columns, options = {}) {
  return sendMessage({ type: 'addIndex', tableName, columns, options });
}

// Add a column (forwarded as raw SQL)
export async function addColumn(tableName, columnName, columnType) {
  // This is engine-specific SQL, so we let the dedicated Worker handle it
  return sendMessage({ type: 'exec', sql: `ALTER TABLE ${tableName} ADD COLUMN "${columnName}" TEXT` });
}

// Remove a column (forwarded as raw SQL)
export async function removeColumn(tableName, columnName) {
  return sendMessage({ type: 'exec', sql: `ALTER TABLE ${tableName} DROP COLUMN "${columnName}"` });
}

// Drop a table (forwarded as raw SQL)
export async function dropTable(tableName) {
  return sendMessage({ type: 'exec', sql: `DROP TABLE IF EXISTS ${tableName}` });
}

// Query interface for rails_base.js migration system
export async function query(sql, params = []) {
  const result = await sendMessage({ type: 'exec', sql, params });
  return result.rows;
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  const result = await sendMessage({ type: 'exec', sql, params });
  return { changes: result.changes || 0 };
}

// Insert a row
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map((_, i) => `?`);
  const sql = `INSERT INTO ${tableName} (${keys.map(k => `"${k}"`).join(', ')}) VALUES (${placeholders.join(', ')})`;
  await sendMessage({ type: 'exec', sql, params: values });
}

// Get the raw database instance (not available in worker adapter)
export function getDatabase() {
  return null;
}

// Close the database connection
export async function closeDatabase() {
  // The dedicated Worker manages the database lifecycle
  dbWorker = null;
}

// Import a SQL dump
export async function importDump(sql) {
  return sendMessage({ type: 'execSQL', sql });
}

// Determine the dialect based on configuration
// This is set at build time via Vite define
const dialect = globalThis.__JUNTOS_DB_DIALECT__ || 'sqlite';

// Dynamic base class selection would require async import
// Instead, we import both and select at module level
// The Vite build will tree-shake the unused one
import { SQLiteDialect } from './dialects/sqlite_browser.mjs';

// Worker ActiveRecord implementation
// Sends all SQL to the dedicated Worker via MessagePort
export class ActiveRecord extends SQLiteDialect {
  // Execute SQL via the dedicated Worker
  static async _execute(sql, params = []) {
    const result = await sendMessage({ type: 'exec', sql, params });

    const isSelect = sql.trim().toUpperCase().startsWith('SELECT')
      || sql.trim().toUpperCase().startsWith('PRAGMA');

    if (isSelect) {
      return { rows: result.rows || [], type: 'select' };
    } else {
      return {
        lastInsertRowid: result.lastInsertRowId,
        changes: result.changes || 0,
        type: 'run'
      };
    }
  }

  static _getRows(result) {
    return result.rows || [];
  }

  static _getLastInsertId(result) {
    return result.lastInsertRowid;
  }
}
