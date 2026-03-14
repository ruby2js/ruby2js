// Active Storage adapter for SharedWorker target (OPFS via dedicated Worker)
//
// Stores file content in OPFS via the dedicated database Worker.
// Blob metadata and attachment records are stored in SQL tables
// (active_storage_blobs, active_storage_attachments) via the
// existing MessagePort SQL adapter.
//
// The dedicated Worker has access to OPFS (synchronous file handles),
// so file I/O is fast and doesn't block the main thread.

import {
  StorageService,
  Attachment,
  Attachments,
  hasOneAttached,
  hasManyAttached,
  generateKey,
  computeChecksum,
  BlobMetadata
} from './active_storage_base.mjs';

// Re-export helpers for use by models
export {
  Attachment,
  Attachments,
  hasOneAttached,
  hasManyAttached,
  generateKey,
  computeChecksum,
  BlobMetadata
};

// Reference to the dedicated Worker (set by setWorker from active_record_worker.mjs)
let dbWorker = null;
// Pending file operation promises
const pending = new Map();

function handleFileMessage({ data }) {
  if ((data.type === 'file:result' || data.type === 'file:error') && data.id) {
    const resolver = pending.get(data.id);
    if (resolver) {
      pending.delete(data.id);
      if (data.type === 'file:error') {
        resolver.reject(new Error(data.error));
      } else {
        resolver.resolve(data);
      }
    }
  }
}

function sendFileMessage(message, transfer) {
  return new Promise((resolve, reject) => {
    const id = crypto.randomUUID();
    pending.set(id, { resolve, reject });
    if (transfer) {
      dbWorker.postMessage({ ...message, id }, transfer);
    } else {
      dbWorker.postMessage({ ...message, id });
    }
  });
}

// OPFS storage service — delegates to dedicated Worker
class OPFSWorkerStorage extends StorageService {
  constructor(options = {}) {
    super(options);
    this._urlCache = new Map();
  }

  async initialize() {
    // Nothing to initialize — the dedicated Worker manages OPFS
  }

  async upload(key, data, options = {}) {
    let buffer;
    if (data instanceof Blob) {
      buffer = await data.arrayBuffer();
    } else if (data instanceof ArrayBuffer) {
      buffer = data;
    } else if (data instanceof Uint8Array) {
      buffer = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
    } else {
      throw new Error('upload() requires a Blob, ArrayBuffer, or Uint8Array');
    }

    // Send buffer as message data and transfer ownership to avoid copying
    await sendFileMessage({
      type: 'file:upload',
      key,
      data: buffer,
      contentType: options.contentType || 'application/octet-stream'
    }, [buffer]);

    return key;
  }

  async download(key) {
    const result = await sendFileMessage({ type: 'file:download', key });
    if (!result.data) return null;
    return new Blob([result.data], { type: result.contentType || 'application/octet-stream' });
  }

  async url(key, options = {}) {
    // Check cache first
    if (this._urlCache.has(key)) {
      return this._urlCache.get(key);
    }

    const blob = await this.download(key);
    if (!blob) return null;

    const url = URL.createObjectURL(blob);
    this._urlCache.set(key, url);
    return url;
  }

  revokeUrl(key) {
    if (this._urlCache.has(key)) {
      URL.revokeObjectURL(this._urlCache.get(key));
      this._urlCache.delete(key);
    }
  }

  revokeAllUrls() {
    for (const url of this._urlCache.values()) {
      URL.revokeObjectURL(url);
    }
    this._urlCache.clear();
  }

  async delete(key) {
    this.revokeUrl(key);
    await sendFileMessage({ type: 'file:delete', key });
  }

  async exists(key) {
    const result = await sendFileMessage({ type: 'file:exists', key });
    return result.exists;
  }
}

// Singleton storage instance
let storageInstance = null;

// Set the dedicated Worker reference (called by SharedWorker's Application.start)
export function setStorageWorker(worker) {
  dbWorker = worker;
  dbWorker.addEventListener('message', handleFileMessage);
}

// Initialize Active Storage with OPFS backend via dedicated Worker
export async function initActiveStorage(options = {}) {
  if (storageInstance) return storageInstance;

  if (!dbWorker) {
    throw new Error('Storage Worker not set. Call setStorageWorker() before initActiveStorage().');
  }

  const storage = new OPFSWorkerStorage(options);

  // Initialize OPFS storage directory in the dedicated Worker
  await sendFileMessage({ type: 'file:init' });

  // Blob metadata and attachment records use SQL tables.
  // These are managed by Attachment/Attachments classes from active_storage_base.mjs
  // which access globalThis.ActiveStorage.blobStore and attachmentStore.
  // For the worker target, we use a SQL-backed store that goes through
  // the MessagePort adapter (same as all other queries).
  const blobStore = new SQLBlobStore();
  const attachmentStore = new SQLAttachmentStore();

  globalThis.ActiveStorage = {
    service: storage,
    blobStore,
    attachmentStore
  };

  storageInstance = storage;
  console.log('[ActiveStorage] Initialized with OPFS backend (via Worker)');
  return storage;
}

export function getActiveStorage() {
  return storageInstance;
}

export async function closeActiveStorage() {
  if (storageInstance) {
    storageInstance.revokeAllUrls();
    storageInstance = null;
    globalThis.ActiveStorage = null;
  }
}

export async function purgeActiveStorage() {
  if (!storageInstance) return;
  await sendFileMessage({ type: 'file:purge' });
  storageInstance.revokeAllUrls();
  console.log('[ActiveStorage] All data purged');
}

// SQL-backed blob metadata store
// Mimics Dexie's put/get/delete/toArray interface using SQL via the MessagePort adapter
import { query, execute } from './active_record_worker.mjs';

class SQLBlobStore {
  async put(record) {
    const existing = await query(
      'SELECT id FROM active_storage_blobs WHERE id = ?', [record.id]
    );
    if (existing.length > 0) {
      await execute(
        `UPDATE active_storage_blobs SET key = ?, filename = ?, content_type = ?, byte_size = ?, checksum = ?, created_at = ? WHERE id = ?`,
        [record.key, record.filename, record.content_type, record.byte_size, record.checksum, record.created_at, record.id]
      );
    } else {
      await execute(
        `INSERT INTO active_storage_blobs (id, key, filename, content_type, byte_size, checksum, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [record.id, record.key, record.filename, record.content_type, record.byte_size, record.checksum, record.created_at]
      );
    }
  }

  async get(id) {
    const rows = await query('SELECT * FROM active_storage_blobs WHERE id = ?', [id]);
    return rows[0] || undefined;
  }

  async delete(id) {
    await execute('DELETE FROM active_storage_blobs WHERE id = ?', [id]);
  }

  async toArray() {
    return query('SELECT * FROM active_storage_blobs');
  }

  async clear() {
    await execute('DELETE FROM active_storage_blobs');
  }
}

class SQLAttachmentStore {
  async put(record) {
    const existing = await query(
      'SELECT id FROM active_storage_attachments WHERE id = ?', [record.id]
    );
    if (existing.length > 0) {
      await execute(
        `UPDATE active_storage_attachments SET record_type = ?, record_id = ?, name = ?, blob_id = ? WHERE id = ?`,
        [record.record_type, record.record_id, record.name, record.blob_id, record.id]
      );
    } else {
      await execute(
        `INSERT INTO active_storage_attachments (id, record_type, record_id, name, blob_id) VALUES (?, ?, ?, ?, ?)`,
        [record.id, record.record_type, record.record_id, record.name, record.blob_id]
      );
    }
  }

  async get(id) {
    const rows = await query('SELECT * FROM active_storage_attachments WHERE id = ?', [id]);
    return rows[0] || undefined;
  }

  async delete(id) {
    await execute('DELETE FROM active_storage_attachments WHERE id = ?', [id]);
  }

  async toArray() {
    return query('SELECT * FROM active_storage_attachments');
  }

  async clear() {
    await execute('DELETE FROM active_storage_attachments');
  }
}
