// Active Storage adapter for S3-compatible storage (AWS S3, Cloudflare R2, etc.)
//
// Stores blobs in S3-compatible object storage
// Works in edge runtimes (Cloudflare Workers, Vercel Edge, Deno Deploy)
// Metadata stored in the configured database (not in S3)
//
// Configuration via config/storage.yml:
//   amazon:
//     service: S3
//     access_key_id: <%= ENV['AWS_ACCESS_KEY_ID'] %>
//     secret_access_key: <%= ENV['AWS_SECRET_ACCESS_KEY'] %>
//     region: us-east-1
//     bucket: my-bucket
//     endpoint: https://... (optional, for R2/MinIO)

import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand, HeadObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
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

// Database connection for metadata storage
let db = null;

// Simple ERB evaluation for storage.yml
// Handles common patterns: ENV['KEY'], ENV["KEY"], ENV.fetch('KEY', 'default'), Rails.env
function evalErb(content) {
  return content.replace(/<%=\s*(.+?)\s*%>/g, (_, expr) => {
    expr = expr.trim();

    // ENV['KEY'] or ENV["KEY"]
    const envBracket = expr.match(/^ENV\[['"](\w+)['"]\]$/);
    if (envBracket) return process.env[envBracket[1]] || '';

    // ENV.fetch('KEY', 'default') or ENV.fetch('KEY')
    const envFetch = expr.match(/^ENV\.fetch\(['"](\w+)['"](?:,\s*['"](.+?)['"])?\)$/);
    if (envFetch) return process.env[envFetch[1]] || envFetch[2] || '';

    // Rails.env
    if (expr === 'Rails.env') return process.env.RAILS_ENV || process.env.NODE_ENV || 'development';

    // Rails.application.credentials.dig(:aws, :access_key_id) - not supported, return empty
    if (expr.includes('credentials')) {
      console.warn('[ActiveStorage] Rails credentials not supported, use ENV variables instead');
      return '';
    }

    return '';  // Unknown expression
  });
}

// Database-backed store for blobs table (same as disk adapter)
class BlobStore {
  async get(key) {
    if (!db) return null;
    const row = db.prepare('SELECT * FROM active_storage_blobs WHERE key = ?').get(key);
    if (!row) return null;
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
        record.service_name || 's3',
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
        record.service_name || 's3',
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

// Database-backed store for attachments table (same as disk adapter)
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

// Singleton stores
let blobStoreInstance = null;
let attachmentStoreInstance = null;

// S3 storage service
export class S3Storage extends StorageService {
  constructor(options = {}) {
    super(options);
    this.bucket = options.bucket;
    this.region = options.region || 'us-east-1';
    this.endpoint = options.endpoint;  // For R2, MinIO, etc.
    this.client = null;
    this.initialized = false;
  }

  async initialize() {
    if (this.initialized) return;

    // Build S3 client configuration
    const clientConfig = {
      region: this.region
    };

    // Credentials from options or environment
    const accessKeyId = this.options.access_key_id || process.env.AWS_ACCESS_KEY_ID;
    const secretAccessKey = this.options.secret_access_key || process.env.AWS_SECRET_ACCESS_KEY;

    if (accessKeyId && secretAccessKey) {
      clientConfig.credentials = {
        accessKeyId,
        secretAccessKey
      };
    }

    // Custom endpoint for S3-compatible services (R2, MinIO, etc.)
    if (this.endpoint) {
      clientConfig.endpoint = this.endpoint;
      clientConfig.forcePathStyle = true;  // Required for most S3-compatible services
    }

    this.client = new S3Client(clientConfig);

    // Initialize store instances
    if (!blobStoreInstance) {
      blobStoreInstance = new BlobStore();
    }
    if (!attachmentStoreInstance) {
      attachmentStoreInstance = new AttachmentStore();
    }

    this.initialized = true;
    return this;
  }

  // Get the S3 key for a blob key (can add prefix/path structure)
  _s3Key(key) {
    // Could add prefix here, e.g., return `uploads/${key}`
    return key;
  }

  // Store data by key
  async upload(key, data, options = {}) {
    await this.initialize();

    // Convert to appropriate format for S3
    let body;
    if (data instanceof Blob) {
      body = await data.arrayBuffer();
    } else if (data instanceof ArrayBuffer) {
      body = data;
    } else if (data instanceof Uint8Array) {
      body = data;
    } else if (typeof Buffer !== 'undefined' && data instanceof Buffer) {
      body = data;
    } else {
      throw new Error('upload() requires a Blob, ArrayBuffer, Uint8Array, or Buffer');
    }

    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: this._s3Key(key),
      Body: body,
      ContentType: options.content_type || 'application/octet-stream'
    });

    await this.client.send(command);
    return key;
  }

  // Retrieve data by key
  async download(key) {
    await this.initialize();

    try {
      const command = new GetObjectCommand({
        Bucket: this.bucket,
        Key: this._s3Key(key)
      });

      const response = await this.client.send(command);

      // Convert stream to Blob for consistent API
      const chunks = [];
      for await (const chunk of response.Body) {
        chunks.push(chunk);
      }
      return new Blob(chunks, { type: response.ContentType });
    } catch (e) {
      if (e.name === 'NoSuchKey') return null;
      throw e;
    }
  }

  // Get URL for the data (presigned URL for private buckets)
  async url(key, options = {}) {
    await this.initialize();

    const expiresIn = options.expires_in || 3600;  // Default 1 hour

    const command = new GetObjectCommand({
      Bucket: this.bucket,
      Key: this._s3Key(key)
    });

    return getSignedUrl(this.client, command, { expiresIn });
  }

  // Delete data by key
  async delete(key) {
    await this.initialize();

    try {
      const command = new DeleteObjectCommand({
        Bucket: this.bucket,
        Key: this._s3Key(key)
      });

      await this.client.send(command);
    } catch (e) {
      if (e.name !== 'NoSuchKey') throw e;
    }
  }

  // Check if data exists
  async exists(key) {
    await this.initialize();

    try {
      const command = new HeadObjectCommand({
        Bucket: this.bucket,
        Key: this._s3Key(key)
      });

      await this.client.send(command);
      return true;
    } catch (e) {
      if (e.name === 'NotFound') return false;
      throw e;
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

// Set database connection explicitly
export function setDatabase(database) {
  db = database;
}

// Load S3 configuration from storage.yml
export async function loadStorageConfig(configPath, serviceName = 'amazon') {
  try {
    const fs = await import('node:fs');
    const yaml = (await import('js-yaml')).default;

    const content = fs.readFileSync(configPath, 'utf8');
    const processed = evalErb(content);
    const config = yaml.load(processed);

    return config[serviceName] || null;
  } catch (e) {
    console.warn(`[ActiveStorage] Could not load storage.yml: ${e.message}`);
    return null;
  }
}

// Initialize Active Storage with S3 backend
export async function initActiveStorage(options = {}) {
  // If database passed in options, use it
  if (options.database) {
    db = options.database;
  }

  // Try to get database connection from juntos:active-record
  if (!db) {
    try {
      const activeRecord = await import('juntos:active-record');
      if (activeRecord.getDatabase) {
        db = activeRecord.getDatabase();
      }
    } catch (e) {
      // Database not available
    }
  }

  const storage = new S3Storage(options);
  await storage.initialize();

  // Register globally so Attachment/Attachments can access it
  globalThis.ActiveStorage = {
    service: storage,
    blobStore: storage.blobStore,
    attachmentStore: storage.attachmentStore
  };

  storageInstance = storage;

  const dbStatus = db ? 'database-backed' : 'in-memory';
  console.log(`[ActiveStorage] Initialized with S3 backend: ${options.bucket} (${dbStatus})`);
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
// WARNING: This deletes all blobs from S3!
export async function purgeActiveStorage() {
  if (!storageInstance) return;

  await storageInstance.initialize();

  // Clear database tables
  if (blobStoreInstance) {
    // Get all blob keys before clearing
    const blobs = await blobStoreInstance.toArray();

    // Delete each blob from S3
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
