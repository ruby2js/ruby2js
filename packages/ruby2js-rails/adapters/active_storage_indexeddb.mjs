// Active Storage adapter for IndexedDB (browser)
//
// Stores blobs in IndexedDB using Dexie.js
// Blob metadata and attachment records are stored in separate tables
// Actual file data is stored in a 'blobs' table

import Dexie from 'dexie';
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

// IndexedDB storage service
export class IndexedDBStorage extends StorageService {
  constructor(options = {}) {
    super(options);
    this.dbName = options.database || 'active_storage';
    this.db = null;
    this._urlCache = new Map(); // Cache blob URLs to avoid leaks
  }

  async initialize() {
    if (this.db) return this.db;

    this.db = new Dexie(this.dbName);
    this.db.version(1).stores({
      // Actual blob data
      storage: 'key',
      // Blob metadata (filename, content_type, etc.)
      blobs: 'id, key',
      // Attachment records (links records to blobs)
      attachments: 'id, record_type, record_id, name, blob_id'
    });

    await this.db.open();
    return this.db;
  }

  // Store data by key
  async upload(key, data, options = {}) {
    await this.initialize();

    // Convert to Blob if needed
    let blob;
    if (data instanceof Blob) {
      blob = data;
    } else if (data instanceof ArrayBuffer || data instanceof Uint8Array) {
      blob = new Blob([data], { type: options.contentType || 'application/octet-stream' });
    } else {
      throw new Error('upload() requires a Blob, ArrayBuffer, or Uint8Array');
    }

    // Store the blob
    await this.db.storage.put({
      key,
      data: blob,
      contentType: options.contentType || blob.type,
      uploadedAt: new Date().toISOString()
    });

    return key;
  }

  // Retrieve data by key
  async download(key) {
    await this.initialize();

    const record = await this.db.storage.get(key);
    return record?.data || null;
  }

  // Get URL for the data
  async url(key, options = {}) {
    await this.initialize();

    // Check cache first
    if (this._urlCache.has(key)) {
      return this._urlCache.get(key);
    }

    const blob = await this.download(key);
    if (!blob) return null;

    // Create blob URL
    const url = URL.createObjectURL(blob);

    // Cache the URL (caller should revoke when done)
    this._urlCache.set(key, url);

    return url;
  }

  // Revoke a cached URL (to prevent memory leaks)
  revokeUrl(key) {
    if (this._urlCache.has(key)) {
      URL.revokeObjectURL(this._urlCache.get(key));
      this._urlCache.delete(key);
    }
  }

  // Revoke all cached URLs
  revokeAllUrls() {
    for (const url of this._urlCache.values()) {
      URL.revokeObjectURL(url);
    }
    this._urlCache.clear();
  }

  // Delete data by key
  async delete(key) {
    await this.initialize();
    this.revokeUrl(key); // Clean up any cached URL
    await this.db.storage.delete(key);
  }

  // Check if data exists
  async exists(key) {
    await this.initialize();
    const record = await this.db.storage.get(key);
    return record !== undefined;
  }

  // Get the blobs table (for metadata)
  get blobStore() {
    return this.db?.blobs;
  }

  // Get the attachments table
  get attachmentStore() {
    return this.db?.attachments;
  }
}

// Singleton storage instance
let storageInstance = null;

// Initialize Active Storage with IndexedDB backend
export async function initActiveStorage(options = {}) {
  const storage = new IndexedDBStorage(options);
  await storage.initialize();

  // Register globally so Attachment/Attachments can access it
  globalThis.ActiveStorage = {
    service: storage,
    blobStore: storage.blobStore,
    attachmentStore: storage.attachmentStore
  };

  storageInstance = storage;

  console.log('[ActiveStorage] Initialized with IndexedDB backend');
  return storage;
}

// Get the storage instance
export function getActiveStorage() {
  return storageInstance;
}

// Close storage (cleanup)
export async function closeActiveStorage() {
  if (storageInstance) {
    storageInstance.revokeAllUrls();
    if (storageInstance.db) {
      storageInstance.db.close();
    }
    storageInstance = null;
    globalThis.ActiveStorage = null;
  }
}

// Purge all storage data (for testing/reset)
export async function purgeActiveStorage() {
  if (!storageInstance) return;

  await storageInstance.initialize();
  await storageInstance.db.storage.clear();
  await storageInstance.db.blobs.clear();
  await storageInstance.db.attachments.clear();
  storageInstance.revokeAllUrls();

  console.log('[ActiveStorage] All data purged');
}
