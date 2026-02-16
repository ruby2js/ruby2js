// ActiveRecord adapter for @sqlite.org/sqlite-wasm
// Uses the official SQLite WASM build with optional OPFS persistence

import {
  setDatabase, getDatabase, execSQL, createTable, addIndex, addColumn,
  removeColumn, dropTable, closeDatabase, query, execute, insert, importDump,
  SQLiteDialect, attr_accessor, modelRegistry, CollectionProxy, Reference, HasOneReference
} from './dialects/sqlite_browser.mjs';
import { initTimePolyfill } from 'ruby2js-rails/adapters/active_record_base.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry, CollectionProxy, Reference, HasOneReference };
export { getDatabase, execSQL, createTable, addIndex, addColumn, removeColumn, dropTable };
export { closeDatabase, query, execute, insert, importDump };

let db = null;

// Initialize the database using @sqlite.org/sqlite-wasm
export async function initDatabase(options = {}) {
  const {
    opfs = true,
    database: dbName = 'app.sqlite3'
  } = options;

  // Dynamic import - the package must be installed by the consuming app
  const { default: sqlite3InitModule } = await import('@sqlite.org/sqlite-wasm');
  const sqlite3 = await sqlite3InitModule();

  // Try OPFS persistence first, fall back to in-memory
  if (opfs && sqlite3.oo1.OpfsDb) {
    try {
      db = new sqlite3.oo1.OpfsDb(dbName);
    } catch {
      // OPFS not available (e.g., not in secure context), fall back
      db = new sqlite3.oo1.DB();
    }
  } else {
    db = new sqlite3.oo1.DB();
  }

  setDatabase(db);

  // Time polyfill for Ruby compatibility
  if (typeof window !== 'undefined') {
    initTimePolyfill(window);
  } else if (typeof globalThis !== 'undefined') {
    initTimePolyfill(globalThis);
  }

  return db;
}

// @sqlite.org/sqlite-wasm-specific ActiveRecord implementation
export class ActiveRecord extends SQLiteDialect {
  static async _execute(sql, params = []) {
    const database = getDatabase();
    const isSelect = sql.trim().toUpperCase().startsWith('SELECT');

    if (isSelect) {
      const rows = [];
      database.exec({
        sql,
        bind: params,
        rowMode: 'object',
        callback: row => rows.push(row)
      });
      return { rows, type: 'select' };
    } else {
      database.exec({ sql, bind: params });
      const changes = database.changes();
      // Get last insert rowid
      const lastId = [];
      database.exec({
        sql: 'SELECT last_insert_rowid()',
        rowMode: 'array',
        callback: row => lastId.push(row[0])
      });
      return {
        lastInsertRowid: lastId[0],
        changes,
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
