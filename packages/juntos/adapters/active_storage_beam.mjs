// Active Storage adapter for BEAM (QuickBEAM) — S3 via Elixir
//
// Blob data is stored in S3 via Beam.callSync → ExAws.S3 on the Elixir side.
// Metadata (blobs table, attachments table) is stored in the database via
// the same Beam.callSync → Postgrex path used by active_record_postgrex.
//
// Configuration via environment variables on the Elixir side:
//   S3_BUCKET or AWS_S3_BUCKET - Bucket name (required, checked on first use)
//   AWS_ACCESS_KEY_ID          - AWS access key
//   AWS_SECRET_ACCESS_KEY      - AWS secret key
//   AWS_REGION                 - AWS region (default: us-east-1)
//   AWS_ENDPOINT_URL           - Custom endpoint for R2, Tigris, MinIO (optional)

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

// Database-backed store for blobs table (queries go through Beam.callSync → Postgrex)
class BlobStore {
  async get(key) {
    const rows = Beam.callSync('__db_query',
      'SELECT * FROM active_storage_blobs WHERE key = $1', [key]);
    if (!rows || rows.length === 0) return null;
    const row = rows[0];
    return {
      id: row.key,
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
    const key = record.key || record.id;
    const existing = Beam.callSync('__db_query',
      'SELECT id FROM active_storage_blobs WHERE key = $1', [key]);
    if (existing && existing.length > 0) {
      Beam.callSync('__db_execute', `
        UPDATE active_storage_blobs
        SET filename = $1, content_type = $2, metadata = $3, service_name = $4, byte_size = $5, checksum = $6
        WHERE key = $7
      `, [
        record.filename,
        record.content_type,
        record.metadata ? JSON.stringify(record.metadata) : null,
        record.service_name || 's3',
        record.byte_size,
        record.checksum,
        key
      ]);
    } else {
      Beam.callSync('__db_execute', `
        INSERT INTO active_storage_blobs (key, filename, content_type, metadata, service_name, byte_size, checksum, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      `, [
        key,
        record.filename,
        record.content_type,
        record.metadata ? JSON.stringify(record.metadata) : null,
        record.service_name || 's3',
        record.byte_size,
        record.checksum,
        record.created_at || new Date().toISOString()
      ]);
    }
  }

  async delete(key) {
    Beam.callSync('__db_execute',
      'DELETE FROM active_storage_blobs WHERE key = $1', [key]);
  }

  async toArray() {
    const rows = Beam.callSync('__db_query',
      'SELECT * FROM active_storage_blobs', []);
    return (rows || []).map(row => ({
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
    Beam.callSync('__db_execute', 'DELETE FROM active_storage_blobs', []);
  }
}

// Database-backed store for attachments table
class AttachmentStore {
  async get(id) {
    const rows = Beam.callSync('__db_query',
      'SELECT * FROM active_storage_attachments WHERE id = $1', [id]);
    if (!rows || rows.length === 0) return null;
    const row = rows[0];
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
    if (record.id) {
      const existing = Beam.callSync('__db_query',
        'SELECT id FROM active_storage_attachments WHERE id = $1', [record.id]);
      if (existing && existing.length > 0) {
        Beam.callSync('__db_execute', `
          UPDATE active_storage_attachments
          SET name = $1, record_type = $2, record_id = $3, blob_id = $4
          WHERE id = $5
        `, [record.name, record.record_type, record.record_id, record.blob_id, record.id]);
        return;
      }
    }
    const result = Beam.callSync('__db_execute', `
      INSERT INTO active_storage_attachments (name, record_type, record_id, blob_id, created_at)
      VALUES ($1, $2, $3, $4, $5)
      RETURNING id
    `, [
      record.name,
      record.record_type,
      record.record_id,
      record.blob_id,
      record.created_at || new Date().toISOString()
    ]);
    if (result && result.rows && result.rows[0]) {
      record.id = result.rows[0].id;
    }
  }

  async delete(id) {
    Beam.callSync('__db_execute',
      'DELETE FROM active_storage_attachments WHERE id = $1', [id]);
  }

  async toArray() {
    return Beam.callSync('__db_query',
      'SELECT * FROM active_storage_attachments', []) || [];
  }

  async clear() {
    Beam.callSync('__db_execute', 'DELETE FROM active_storage_attachments', []);
  }

  async findByRecord(recordType, recordId, name) {
    if (name) {
      return Beam.callSync('__db_query',
        'SELECT * FROM active_storage_attachments WHERE record_type = $1 AND record_id = $2 AND name = $3',
        [recordType, recordId, name]) || [];
    }
    return Beam.callSync('__db_query',
      'SELECT * FROM active_storage_attachments WHERE record_type = $1 AND record_id = $2',
      [recordType, recordId]) || [];
  }
}

// Singleton stores
let blobStoreInstance = null;
let attachmentStoreInstance = null;

// S3 storage service via Beam.callSync → Elixir ExAws.S3
class BeamS3Storage extends StorageService {
  constructor(options = {}) {
    super(options);
    this.initialized = false;
  }

  async initialize() {
    if (this.initialized) return;

    if (!blobStoreInstance) {
      blobStoreInstance = new BlobStore();
    }
    if (!attachmentStoreInstance) {
      attachmentStoreInstance = new AttachmentStore();
    }

    this.initialized = true;
    return this;
  }

  // Store data by key — base64-encode and send to Elixir for S3 upload
  async upload(key, data, options = {}) {
    await this.initialize();

    let bytes;
    if (data instanceof Blob) {
      bytes = new Uint8Array(await data.arrayBuffer());
    } else if (data instanceof ArrayBuffer) {
      bytes = new Uint8Array(data);
    } else if (data instanceof Uint8Array) {
      bytes = data;
    } else {
      throw new Error('upload() requires a Blob, ArrayBuffer, or Uint8Array');
    }

    // Base64-encode for JSON-safe transfer to Elixir
    // Use chunked approach to avoid stack overflow on large files
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    const base64 = btoa(binary);
    const contentType = options.content_type || options.contentType || 'application/octet-stream';

    Beam.callSync('__storage_upload', key, base64, contentType);
    return key;
  }

  // Retrieve data by key — Elixir downloads from S3 and returns base64
  async download(key) {
    await this.initialize();

    const base64 = Beam.callSync('__storage_download', key);
    if (base64 === null || base64 === undefined) return null;

    // Decode base64 back to binary
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return new Blob([bytes]);
  }

  // Get presigned URL from Elixir
  async url(key, options = {}) {
    await this.initialize();
    const expiresIn = options.expires_in || 3600;
    return Beam.callSync('__storage_url', key, expiresIn);
  }

  // Delete from S3 via Elixir
  async delete(key) {
    await this.initialize();
    Beam.callSync('__storage_delete', key);
  }

  // Check existence via Elixir
  async exists(key) {
    await this.initialize();
    return Beam.callSync('__storage_exists', key);
  }

  get blobStore() {
    return blobStoreInstance || new BlobStore();
  }

  get attachmentStore() {
    return attachmentStoreInstance || new AttachmentStore();
  }
}

// Singleton storage instance
let storageInstance = null;

// Initialize Active Storage with BEAM S3 backend
export async function initActiveStorage(options = {}) {
  const storage = new BeamS3Storage(options);
  await storage.initialize();

  // Register globally so Attachment/Attachments can access it
  globalThis.ActiveStorage = {
    service: storage,
    blobStore: storage.blobStore,
    attachmentStore: storage.attachmentStore
  };

  storageInstance = storage;
  console.log('[ActiveStorage] Initialized with BEAM S3 backend');
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

// Purge all storage data
// WARNING: This deletes all blobs from S3!
export async function purgeActiveStorage() {
  if (!storageInstance) return;

  await storageInstance.initialize();

  if (blobStoreInstance) {
    const blobs = await blobStoreInstance.toArray();
    for (const blob of blobs) {
      try {
        await storageInstance.delete(blob.key);
      } catch (e) {
        console.warn(`[ActiveStorage] Failed to delete S3 object ${blob.key}: ${e.message}`);
      }
    }
    await blobStoreInstance.clear();
  }
  if (attachmentStoreInstance) {
    await attachmentStoreInstance.clear();
  }

  console.log('[ActiveStorage] Purged all S3 objects and metadata');
}
