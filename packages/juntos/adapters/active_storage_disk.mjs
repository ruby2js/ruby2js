// Active Storage adapter for local filesystem (Node.js development)
//
// Stores blobs on the local filesystem
// Blob metadata and attachment records are stored in the database
// This adapter is for development only - use S3 for production

import fs from 'node:fs/promises';
import path from 'node:path';
import { existsSync, mkdirSync } from 'node:fs';
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

// Database connection - set during initialization
let db = null;

// Database-backed store for blobs table
class BlobStore {
  async get(key) {
    if (!db) return null;
    const row = db.prepare('SELECT * FROM active_storage_blobs WHERE key = ?').get(key);
    if (!row) return null;
    return {
      id: row.key,  // Use key as id for compatibility with base adapter
      key: row.key,
      filename: row.filename,
      content_type: row.content_type,
      metadata: row.metadata ? JSON.parse(row.metadata) : null,
      service_name: row.service_name,
      byte_size: row.byte_size,
      checksum: row.checksum,
      created_at: row.created_at
    };
  }

  async put(record) {
    if (!db) return;
    const existing = db.prepare('SELECT id FROM active_storage_blobs WHERE key = ?').get(record.key || record.id);
    if (existing) {
      db.prepare(`
        UPDATE active_storage_blobs
        SET filename = ?, content_type = ?, metadata = ?, service_name = ?, byte_size = ?, checksum = ?
        WHERE key = ?
      `).run(
        record.filename,
        record.content_type,
        record.metadata ? JSON.stringify(record.metadata) : null,
        record.service_name || 'disk',
        record.byte_size,
        record.checksum,
        record.key || record.id
      );
    } else {
      db.prepare(`
        INSERT INTO active_storage_blobs (key, filename, content_type, metadata, service_name, byte_size, checksum, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        record.key || record.id,
        record.filename,
        record.content_type,
        record.metadata ? JSON.stringify(record.metadata) : null,
        record.service_name || 'disk',
        record.byte_size,
        record.checksum,
        record.created_at || new Date().toISOString()
      );
    }
  }

  async delete(key) {
    if (!db) return;
    db.prepare('DELETE FROM active_storage_blobs WHERE key = ?').run(key);
  }

  async toArray() {
    if (!db) return [];
    const rows = db.prepare('SELECT * FROM active_storage_blobs').all();
    return rows.map(row => ({
      id: row.key,
      key: row.key,
      filename: row.filename,
      content_type: row.content_type,
      metadata: row.metadata ? JSON.parse(row.metadata) : null,
      service_name: row.service_name,
      byte_size: row.byte_size,
      checksum: row.checksum,
      created_at: row.created_at
    }));
  }

  async clear() {
    if (!db) return;
    db.prepare('DELETE FROM active_storage_blobs').run();
  }
}

// Database-backed store for attachments table
class AttachmentStore {
  async get(id) {
    if (!db) return null;
    const row = db.prepare('SELECT * FROM active_storage_attachments WHERE id = ?').get(id);
    if (!row) return null;
    return {
      id: row.id,
      name: row.name,
      record_type: row.record_type,
      record_id: row.record_id,
      blob_id: row.blob_id,
      created_at: row.created_at
    };
  }

  async put(record) {
    if (!db) return;
    if (record.id) {
      const existing = db.prepare('SELECT id FROM active_storage_attachments WHERE id = ?').get(record.id);
      if (existing) {
        db.prepare(`
          UPDATE active_storage_attachments
          SET name = ?, record_type = ?, record_id = ?, blob_id = ?
          WHERE id = ?
        `).run(record.name, record.record_type, record.record_id, record.blob_id, record.id);
        return;
      }
    }
    const result = db.prepare(`
      INSERT INTO active_storage_attachments (name, record_type, record_id, blob_id, created_at)
      VALUES (?, ?, ?, ?, ?)
    `).run(
      record.name,
      record.record_type,
      record.record_id,
      record.blob_id,
      record.created_at || new Date().toISOString()
    );
    record.id = result.lastInsertRowid;
  }

  async delete(id) {
    if (!db) return;
    db.prepare('DELETE FROM active_storage_attachments WHERE id = ?').run(id);
  }

  async toArray() {
    if (!db) return [];
    return db.prepare('SELECT * FROM active_storage_attachments').all();
  }

  async clear() {
    if (!db) return;
    db.prepare('DELETE FROM active_storage_attachments').run();
  }

  // Find attachments by record
  async findByRecord(recordType, recordId, name) {
    if (!db) return [];
    if (name) {
      return db.prepare(
        'SELECT * FROM active_storage_attachments WHERE record_type = ? AND record_id = ? AND name = ?'
      ).all(recordType, recordId, name);
    }
    return db.prepare(
      'SELECT * FROM active_storage_attachments WHERE record_type = ? AND record_id = ?'
    ).all(recordType, recordId);
  }
}

// Singleton stores - created once when database is available
let blobStoreInstance = null;
let attachmentStoreInstance = null;

// Disk storage service
export class DiskStorage extends StorageService {
  constructor(options = {}) {
    super(options);
    // Default to storage/ directory in project root
    this.root = options.root || path.join(process.cwd(), 'storage');
    this.initialized = false;
  }

  async initialize() {
    if (this.initialized) return;

    // Create storage directory if it doesn't exist
    if (!existsSync(this.root)) {
      mkdirSync(this.root, { recursive: true });
    }

    // Get database connection from juntos:active-record if available
    try {
      const activeRecord = await import('juntos:active-record');
      if (activeRecord.getDatabase) {
        db = activeRecord.getDatabase();
      }
    } catch (e) {
      // Database not available - will be set later
    }

    // Create store instances
    if (!blobStoreInstance) {
      blobStoreInstance = new BlobStore();
    }
    if (!attachmentStoreInstance) {
      attachmentStoreInstance = new AttachmentStore();
    }

    this.initialized = true;
    return this;
  }

  // Get the file path for a key
  _pathForKey(key) {
    // Use first 2 characters as subdirectory to avoid too many files in one dir
    const subdir = key.substring(0, 2);
    return path.join(this.root, subdir, key);
  }

  // Store data by key
  async upload(key, data, options = {}) {
    await this.initialize();

    const filePath = this._pathForKey(key);
    const dir = path.dirname(filePath);

    // Create subdirectory if needed
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }

    // Convert to Buffer
    let buffer;
    if (data instanceof Buffer) {
      buffer = data;
    } else if (data instanceof Blob) {
      buffer = Buffer.from(typeof data.arrayBuffer === 'function'
        ? await data.arrayBuffer()
        : await new Response(data).arrayBuffer());
    } else if (data instanceof ArrayBuffer) {
      buffer = Buffer.from(data);
    } else if (data instanceof Uint8Array) {
      buffer = Buffer.from(data);
    } else {
      throw new Error('upload() requires a Buffer, Blob, ArrayBuffer, or Uint8Array');
    }

    await fs.writeFile(filePath, buffer);
    return key;
  }

  // Retrieve data by key
  // Returns a Blob for API consistency with IndexedDB adapter
  async download(key) {
    await this.initialize();

    const filePath = this._pathForKey(key);

    try {
      const buffer = await fs.readFile(filePath);
      // Wrap in Blob for consistent API across adapters
      return new Blob([buffer]);
    } catch (e) {
      if (e.code === 'ENOENT') return null;
      throw e;
    }
  }

  // Get URL for the data
  // For disk storage, we return a file:// URL or serve path
  async url(key, options = {}) {
    await this.initialize();

    // If a base URL is provided, use it (for serving via HTTP)
    if (options.baseUrl || this.options.baseUrl) {
      const base = options.baseUrl || this.options.baseUrl;
      const subdir = key.substring(0, 2);
      return `${base}/${subdir}/${key}`;
    }

    // Otherwise return file:// URL
    const filePath = this._pathForKey(key);
    return `file://${filePath}`;
  }

  // Delete data by key
  async delete(key) {
    await this.initialize();

    const filePath = this._pathForKey(key);

    try {
      await fs.unlink(filePath);
    } catch (e) {
      if (e.code !== 'ENOENT') throw e;
    }
  }

  // Check if data exists
  async exists(key) {
    await this.initialize();

    const filePath = this._pathForKey(key);

    try {
      await fs.access(filePath);
      return true;
    } catch {
      return false;
    }
  }

  // Get the blobs store (database-backed)
  get blobStore() {
    return blobStoreInstance || new BlobStore();
  }

  // Get the attachments store (database-backed)
  get attachmentStore() {
    return attachmentStoreInstance || new AttachmentStore();
  }
}

// Singleton storage instance
let storageInstance = null;

// Set database connection explicitly (called by juntos runtime)
export function setDatabase(database) {
  db = database;
}

// Initialize Active Storage with disk backend
export async function initActiveStorage(options = {}) {
  // If database passed in options, use it
  if (options.database) {
    db = options.database;
  }

  const storage = new DiskStorage(options);
  await storage.initialize();

  // Register globally so Attachment/Attachments can access it
  globalThis.ActiveStorage = {
    service: storage,
    blobStore: storage.blobStore,
    attachmentStore: storage.attachmentStore
  };

  storageInstance = storage;

  const dbStatus = db ? 'database-backed' : 'in-memory';
  console.log(`[ActiveStorage] Initialized with disk backend at ${storage.root} (${dbStatus})`);
  return storage;
}

// Get the storage instance
export function getActiveStorage() {
  return storageInstance;
}

// Close storage (cleanup)
export async function closeActiveStorage() {
  storageInstance = null;
  globalThis.ActiveStorage = null;
}

// Purge all storage data (for testing/reset)
export async function purgeActiveStorage() {
  if (!storageInstance) return;

  await storageInstance.initialize();

  // Clear database tables
  if (blobStoreInstance) {
    await blobStoreInstance.clear();
  }
  if (attachmentStoreInstance) {
    await attachmentStoreInstance.clear();
  }

  // Optionally delete files (be careful!)
  // For now, we only clear metadata

  console.log('[ActiveStorage] Metadata purged (files remain on disk)');
}
