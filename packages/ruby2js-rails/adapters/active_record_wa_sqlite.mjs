// ActiveRecord adapter for wa-sqlite with OPFS VFS
// Uses rhashimoto/wa-sqlite for flexible VFS-based SQLite in the browser

import {
  setDatabase, getDatabase, execSQL, createTable, addIndex, addColumn,
  removeColumn, dropTable, closeDatabase as basecloseDatabase, query, execute,
  insert, importDump, SQLiteDialect, attr_accessor, modelRegistry,
  CollectionProxy, Reference, HasOneReference
} from './dialects/sqlite_browser.mjs';
import { initTimePolyfill } from 'ruby2js-rails/adapters/active_record_base.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry, CollectionProxy, Reference, HasOneReference };
export { getDatabase, execSQL, createTable, addIndex, addColumn, removeColumn, dropTable };
export { query, execute, insert, importDump };

// wa-sqlite uses a C-style API, so we need to wrap it for the base's db.exec/prepare/etc
let sqlite3 = null;
let dbPointer = null;

// Wrapper that provides a sql.js-compatible interface over wa-sqlite's C-style API
class WaSqliteWrapper {
  constructor(api, ptr) {
    this._api = api;
    this._ptr = ptr;
  }

  exec(sql) {
    const str = typeof sql === 'string' ? sql : sql.sql;
    const params = (typeof sql === 'object' && sql.bind) ? sql.bind : [];

    // For simple exec without results
    if (typeof sql === 'string' && params.length === 0) {
      return this._api.exec(this._ptr, str);
    }

    // For exec with callbacks (used by sqlite-wasm adapter pattern)
    const results = [];
    for (const stmt of this._api.statements(this._ptr, str)) {
      if (params.length > 0) {
        this._api.bind_collection(stmt, params);
      }
      const columns = this._api.column_names(stmt);
      while (this._api.step(stmt) === /* SQLITE_ROW */ 100) {
        const row = {};
        for (let i = 0; i < columns.length; i++) {
          row[columns[i]] = this._api.column(stmt, i);
        }
        results.push(row);
      }
    }
    return results;
  }

  prepare(sql) {
    const api = this._api;
    const ptr = this._ptr;
    let stmtPtr = null;

    // Get the first statement
    for (const s of api.statements(ptr, sql)) {
      stmtPtr = s;
      break;
    }

    return {
      _bound: false,
      bind(params) {
        if (params && params.length > 0) {
          api.bind_collection(stmtPtr, params);
        }
        this._bound = true;
      },
      step() {
        return api.step(stmtPtr) === /* SQLITE_ROW */ 100;
      },
      getAsObject() {
        const columns = api.column_names(stmtPtr);
        const row = {};
        for (let i = 0; i < columns.length; i++) {
          row[columns[i]] = api.column(stmtPtr, i);
        }
        return row;
      },
      free() {
        // wa-sqlite auto-finalizes via the statements iterator
      }
    };
  }

  run(sql, params = []) {
    for (const stmt of this._api.statements(this._ptr, sql)) {
      if (params.length > 0) {
        this._api.bind_collection(stmt, params);
      }
      this._api.step(stmt);
    }
  }

  getRowsModified() {
    return this._api.changes(this._ptr);
  }

  changes() {
    return this._api.changes(this._ptr);
  }

  close() {
    this._api.close(this._ptr);
  }
}

// Initialize the database using wa-sqlite
export async function initDatabase(options = {}) {
  const {
    database: dbName = 'app.sqlite3'
  } = options;

  // Dynamic import - the package must be installed by the consuming app
  const SQLiteModule = await import('wa-sqlite');
  const SQLite = SQLiteModule.default || SQLiteModule;

  let module;
  let vfs;

  // Try OPFS VFS for persistence
  try {
    const { OPFSCoopSyncVFS } = await import('wa-sqlite/src/examples/OPFSCoopSyncVFS.js');
    module = await SQLite();
    sqlite3 = SQLite.Factory(module);
    vfs = await OPFSCoopSyncVFS.create('opfs-coop-sync', module);
    sqlite3.vfs_register(vfs, true);
  } catch {
    // OPFS not available, use default (in-memory) VFS
    if (!module) {
      module = await SQLite();
      sqlite3 = SQLite.Factory(module);
    }
  }

  dbPointer = await sqlite3.open_v2(dbName);
  const wrapper = new WaSqliteWrapper(sqlite3, dbPointer);

  setDatabase(wrapper);

  // Time polyfill for Ruby compatibility
  if (typeof window !== 'undefined') {
    initTimePolyfill(window);
  } else if (typeof globalThis !== 'undefined') {
    initTimePolyfill(globalThis);
  }

  return wrapper;
}

// Close database connection
export async function closeDatabase() {
  if (dbPointer !== null && sqlite3) {
    sqlite3.close(dbPointer);
    dbPointer = null;
    sqlite3 = null;
    setDatabase(null);
  }
}

// wa-sqlite-specific ActiveRecord implementation
export class ActiveRecord extends SQLiteDialect {
  static async _execute(sql, params = []) {
    const database = getDatabase();
    const isSelect = sql.trim().toUpperCase().startsWith('SELECT');

    if (isSelect) {
      const stmt = database.prepare(sql);
      stmt.bind(params);
      const rows = [];
      while (stmt.step()) {
        rows.push(stmt.getAsObject());
      }
      stmt.free();
      return { rows, type: 'select' };
    } else {
      database.run(sql, params);
      // Get last insert rowid
      const lastIdStmt = database.prepare('SELECT last_insert_rowid()');
      let lastInsertRowid = null;
      if (lastIdStmt.step()) {
        const obj = lastIdStmt.getAsObject();
        lastInsertRowid = obj['last_insert_rowid()'];
      }
      lastIdStmt.free();
      return {
        lastInsertRowid,
        changes: database.changes(),
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
