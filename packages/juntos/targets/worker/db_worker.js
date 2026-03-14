// Ruby2JS-on-Rails Micro Framework - Database Worker (Dedicated Worker)
// Data tier: loads the configured database adapter (PGlite or SQLite)
// and executes SQL queries received via postMessage from the SharedWorker.
// Also handles file storage via OPFS for Active Storage.

let adapter = null;

// OPFS directory handle for file storage
let storageDir = null;

self.onmessage = async ({ data }) => {
  if (data.type === 'init') {
    try {
      // Import the existing adapter unchanged — PGlite or SQLite WASM
      adapter = await import(data.adapter);
      await adapter.initDatabase(data.config || {});
      self.postMessage({ type: 'ready' });
    } catch (e) {
      self.postMessage({ type: 'error', error: e.message });
    }
    return;
  }

  if (data.type === 'exec') {
    const { id, sql, params } = data;
    try {
      const isSelect = sql.trim().toUpperCase().startsWith('SELECT')
        || sql.trim().toUpperCase().startsWith('PRAGMA');

      let result;
      if (isSelect) {
        const rows = await adapter.query(sql, params || []);
        result = { id, type: 'result', rows, changes: 0, lastInsertRowId: null };
      } else {
        const execResult = await adapter.execute(sql, params || []);
        result = {
          id,
          type: 'result',
          rows: [],
          changes: execResult.changes || 0,
          lastInsertRowId: execResult.lastInsertRowid || null
        };
      }

      self.postMessage(result);
    } catch (e) {
      self.postMessage({ id, type: 'error', error: e.message });
    }
    return;
  }

  if (data.type === 'execSQL') {
    const { id, sql } = data;
    try {
      await adapter.execSQL(sql);
      self.postMessage({ id, type: 'result', rows: [], changes: 0, lastInsertRowId: null });
    } catch (e) {
      self.postMessage({ id, type: 'error', error: e.message });
    }
    return;
  }

  if (data.type === 'createTable') {
    const { id, tableName, columns, options } = data;
    try {
      await adapter.createTable(tableName, columns, options || {});
      self.postMessage({ id, type: 'result', rows: [], changes: 0, lastInsertRowId: null });
    } catch (e) {
      self.postMessage({ id, type: 'error', error: e.message });
    }
    return;
  }

  if (data.type === 'addIndex') {
    const { id, tableName, columns, options } = data;
    try {
      await adapter.addIndex(tableName, columns, options || {});
      self.postMessage({ id, type: 'result', rows: [], changes: 0, lastInsertRowId: null });
    } catch (e) {
      self.postMessage({ id, type: 'error', error: e.message });
    }
    return;
  }

  // Transaction support: begin, commit, rollback
  if (data.type === 'begin') {
    const { id } = data;
    try {
      await adapter.execute('BEGIN');
      self.postMessage({ id, type: 'result', rows: [], changes: 0, lastInsertRowId: null });
    } catch (e) {
      self.postMessage({ id, type: 'error', error: e.message });
    }
    return;
  }

  if (data.type === 'commit') {
    const { id } = data;
    try {
      await adapter.execute('COMMIT');
      self.postMessage({ id, type: 'result', rows: [], changes: 0, lastInsertRowId: null });
    } catch (e) {
      self.postMessage({ id, type: 'error', error: e.message });
    }
    return;
  }

  if (data.type === 'rollback') {
    const { id } = data;
    try {
      await adapter.execute('ROLLBACK');
      self.postMessage({ id, type: 'result', rows: [], changes: 0, lastInsertRowId: null });
    } catch (e) {
      self.postMessage({ id, type: 'error', error: e.message });
    }
    return;
  }

  // ── File storage via OPFS (Active Storage) ──

  if (data.type === 'file:init') {
    const { id } = data;
    try {
      const root = await navigator.storage.getDirectory();
      storageDir = await root.getDirectoryHandle('active_storage', { create: true });
      self.postMessage({ id, type: 'file:result' });
    } catch (e) {
      self.postMessage({ id, type: 'file:error', error: e.message });
    }
    return;
  }

  if (data.type === 'file:upload') {
    const { id, key, contentType } = data;
    try {
      const fileHandle = await storageDir.getFileHandle(key, { create: true });
      const writable = await fileHandle.createSyncAccessHandle();
      const buffer = data.data || new ArrayBuffer(0);
      writable.write(buffer);
      writable.flush();
      writable.close();
      self.postMessage({ id, type: 'file:result' });
    } catch (e) {
      self.postMessage({ id, type: 'file:error', error: e.message });
    }
    return;
  }

  if (data.type === 'file:download') {
    const { id, key } = data;
    try {
      const fileHandle = await storageDir.getFileHandle(key);
      const accessHandle = await fileHandle.createSyncAccessHandle();
      const size = accessHandle.getSize();
      const buffer = new ArrayBuffer(size);
      accessHandle.read(buffer, { at: 0 });
      accessHandle.close();
      self.postMessage({ id, type: 'file:result', data: buffer }, [buffer]);
    } catch (e) {
      if (e.name === 'NotFoundError') {
        self.postMessage({ id, type: 'file:result', data: null });
      } else {
        self.postMessage({ id, type: 'file:error', error: e.message });
      }
    }
    return;
  }

  if (data.type === 'file:delete') {
    const { id, key } = data;
    try {
      await storageDir.removeEntry(key);
      self.postMessage({ id, type: 'file:result' });
    } catch (e) {
      if (e.name === 'NotFoundError') {
        self.postMessage({ id, type: 'file:result' }); // Already gone
      } else {
        self.postMessage({ id, type: 'file:error', error: e.message });
      }
    }
    return;
  }

  if (data.type === 'file:exists') {
    const { id, key } = data;
    try {
      await storageDir.getFileHandle(key);
      self.postMessage({ id, type: 'file:result', exists: true });
    } catch (e) {
      if (e.name === 'NotFoundError') {
        self.postMessage({ id, type: 'file:result', exists: false });
      } else {
        self.postMessage({ id, type: 'file:error', error: e.message });
      }
    }
    return;
  }

  if (data.type === 'file:purge') {
    const { id } = data;
    try {
      // Remove and recreate the storage directory
      const root = await navigator.storage.getDirectory();
      await root.removeEntry('active_storage', { recursive: true });
      storageDir = await root.getDirectoryHandle('active_storage', { create: true });
      self.postMessage({ id, type: 'file:result' });
    } catch (e) {
      self.postMessage({ id, type: 'file:error', error: e.message });
    }
    return;
  }
};
