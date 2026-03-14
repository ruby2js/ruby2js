// Ruby2JS-on-Rails Micro Framework - Database Worker (Dedicated Worker)
// Data tier: loads the configured database adapter (PGlite or SQLite)
// and executes SQL queries received via postMessage from the SharedWorker.

let adapter = null;

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
};
