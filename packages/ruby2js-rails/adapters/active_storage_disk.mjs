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

// In-memory stores for metadata (in production, use the database)
let blobMetadataStore = new Map();
let attachmentRecordStore = new Map();

// Simple store interface that mimics Dexie's API
class MapStore {
  constructor(map) {
    this._map = map;
  }

  async get(key) {
    return this._map.get(key);
  }

  async put(record) {
    this._map.set(record.id, record);
  }

  async delete(key) {
    this._map.delete(key);
  }

  async toArray() {
    return Array.from(this._map.values());
  }

  async clear() {
    this._map.clear();
  }
}

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
      buffer = Buffer.from(await data.arrayBuffer());
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

  // Get the blobs store (in-memory for dev)
  get blobStore() {
    return new MapStore(blobMetadataStore);
  }

  // Get the attachments store (in-memory for dev)
  get attachmentStore() {
    return new MapStore(attachmentRecordStore);
  }
}

// Singleton storage instance
let storageInstance = null;

// Initialize Active Storage with disk backend
export async function initActiveStorage(options = {}) {
  const storage = new DiskStorage(options);
  await storage.initialize();

  // Register globally so Attachment/Attachments can access it
  globalThis.ActiveStorage = {
    service: storage,
    blobStore: storage.blobStore,
    attachmentStore: storage.attachmentStore
  };

  storageInstance = storage;

  console.log(`[ActiveStorage] Initialized with disk backend at ${storage.root}`);
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

  // Clear in-memory stores
  blobMetadataStore.clear();
  attachmentRecordStore.clear();

  // Optionally delete files (be careful!)
  // For now, we only clear metadata

  console.log('[ActiveStorage] Metadata purged (files remain on disk)');
}
