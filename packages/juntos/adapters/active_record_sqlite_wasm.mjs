// ActiveRecord adapter for @sqlite.org/sqlite-wasm
// Uses the official SQLite WASM build with optional OPFS persistence

import {
  setDatabase, getDatabase, execSQL, createTable, addIndex, addColumn,
  removeColumn, dropTable, closeDatabase, query, execute, insert, importDump,
  SQLiteDialect, attr_accessor, modelRegistry, CollectionProxy, Reference, HasOneReference
} from './dialects/sqlite_browser.mjs';
import { initTimePolyfill } from 'juntos/adapters/active_record_base.mjs';

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

  // Try OPFS persistence, fall back to in-memory
  if (opfs && typeof WorkerGlobalScope !== 'undefined' && self instanceof WorkerGlobalScope) {
    // In a Worker: use opfs-sahpool VFS (best performance, no COOP/COEP headers needed)
    try {
      const poolUtil = await sqlite3.installOpfsSAHPoolVfs({
        initialCapacity: 6,
        clearOnInit: false
      });
      db = new poolUtil.OpfsSAHPoolDb('/' + dbName);
    } catch {
      // OPFS not available, fall back to in-memory
      db = new sqlite3.oo1.DB();
    }
  } else if (opfs && sqlite3.oo1.OpfsDb) {
    // On main thread: try legacy OPFS VFS (requires COOP/COEP headers)
    try {
      db = new sqlite3.oo1.OpfsDb(dbName);
    } catch {
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
