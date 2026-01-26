// Active Storage Base - Shared logic for all storage adapters
//
// This file contains storage-agnostic Active Storage functionality:
// - StorageService base class (upload, download, url, delete)
// - Blob model for metadata
// - Attachment proxy for has_one_attached / has_many_attached
// - AttachmentRegistry for tracking attachments
//
// Storage-specific adapters extend StorageService and implement:
// - async upload(key, data, options)
// - async download(key)
// - async url(key, options)
// - async delete(key)
// - async exists(key)

// Generate a unique key for a blob
export function generateKey() {
  const timestamp = Date.now().toString(36);
  const random = Math.random().toString(36).substring(2, 10);
  return `${timestamp}-${random}`;
}

// Compute MD5 checksum of a blob (browser-compatible)
export async function computeChecksum(data) {
  // Convert to ArrayBuffer if needed
  let buffer;
  if (data instanceof Blob) {
    buffer = await data.arrayBuffer();
  } else if (data instanceof ArrayBuffer) {
    buffer = data;
  } else if (typeof data === 'string') {
    buffer = new TextEncoder().encode(data);
  } else {
    buffer = data;
  }

  // Use SubtleCrypto for hashing (available in browsers and Node 15+)
  if (globalThis.crypto?.subtle) {
    const hashBuffer = await crypto.subtle.digest('SHA-256', buffer);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  }

  // Fallback: simple hash for environments without SubtleCrypto
  const bytes = new Uint8Array(buffer);
  let hash = 0;
  for (let i = 0; i < bytes.length; i++) {
    hash = ((hash << 5) - hash) + bytes[i];
    hash = hash & hash; // Convert to 32bit integer
  }
  return Math.abs(hash).toString(16);
}

// Base class for storage services
export class StorageService {
  constructor(options = {}) {
    this.options = options;
  }

  // Store data, return the key
  async upload(key, data, options = {}) {
    throw new Error('StorageService.upload() must be implemented by subclass');
  }

  // Retrieve data by key
  async download(key) {
    throw new Error('StorageService.download() must be implemented by subclass');
  }

  // Get URL for the data (may be data URL, blob URL, signed URL, etc.)
  async url(key, options = {}) {
    throw new Error('StorageService.url() must be implemented by subclass');
  }

  // Delete data by key
  async delete(key) {
    throw new Error('StorageService.delete() must be implemented by subclass');
  }

  // Check if data exists
  async exists(key) {
    throw new Error('StorageService.exists() must be implemented by subclass');
  }
}

// Blob metadata - stored in the database alongside other models
// This is a simple data class, not a full ActiveRecord model
export class BlobMetadata {
  constructor(attrs = {}) {
    this.id = attrs.id || null;
    this.key = attrs.key || null;
    this.filename = attrs.filename || null;
    this.content_type = attrs.content_type || 'application/octet-stream';
    this.byte_size = attrs.byte_size || 0;
    this.checksum = attrs.checksum || null;
    this.created_at = attrs.created_at || new Date().toISOString();
  }

  toJSON() {
    return {
      id: this.id,
      key: this.key,
      filename: this.filename,
      content_type: this.content_type,
      byte_size: this.byte_size,
      checksum: this.checksum,
      created_at: this.created_at
    };
  }
}

// Attachment proxy - returned by has_one_attached getter
// Provides Rails-compatible API: attach(), attached?, url, download, purge
export class Attachment {
  constructor(record, name, options = {}) {
    this.record = record;
    this.name = name;
    this.options = options;
    this._blob = null;
    this._loaded = false;
  }

  // Get the storage service (injected by the adapter)
  get storage() {
    return globalThis.ActiveStorage?.service;
  }

  // Get the blob store (for metadata persistence)
  get blobStore() {
    return globalThis.ActiveStorage?.blobStore;
  }

  // Get the attachment store (for record-blob associations)
  get attachmentStore() {
    return globalThis.ActiveStorage?.attachmentStore;
  }

  // Attach a file/blob to this record
  async attach(data, options = {}) {
    if (!this.storage) {
      throw new Error('Active Storage service not initialized. Call initActiveStorage() first.');
    }

    // Ensure record is persisted
    if (!this.record.id) {
      throw new Error('Cannot attach to unpersisted record. Save the record first.');
    }

    // Purge existing attachment if any
    if (await this.attached()) {
      await this.purge();
    }

    // Determine file metadata
    let filename, contentType, byteSize, blob;

    if (data instanceof File) {
      filename = options.filename || data.name;
      contentType = options.content_type || data.type;
      byteSize = data.size;
      blob = data;
    } else if (data instanceof Blob) {
      filename = options.filename || `${this.name}-${Date.now()}`;
      contentType = options.content_type || data.type || 'application/octet-stream';
      byteSize = data.size;
      blob = data;
    } else if (data instanceof ArrayBuffer || data instanceof Uint8Array) {
      filename = options.filename || `${this.name}-${Date.now()}`;
      contentType = options.content_type || 'application/octet-stream';
      byteSize = data.byteLength;
      blob = new Blob([data], { type: contentType });
    } else {
      throw new Error('attach() requires a File, Blob, ArrayBuffer, or Uint8Array');
    }

    // Generate unique key
    const key = generateKey();

    // Compute checksum
    const checksum = await computeChecksum(blob);

    // Upload to storage
    await this.storage.upload(key, blob, { contentType });

    // Create blob metadata
    const blobMetadata = new BlobMetadata({
      id: generateKey(), // Use generated ID for blob
      key,
      filename,
      content_type: contentType,
      byte_size: byteSize,
      checksum
    });

    // Persist blob metadata
    await this.blobStore.put(blobMetadata.toJSON());

    // Create attachment record (links blob to our record)
    const attachmentRecord = {
      id: `${this.record.constructor.tableName}-${this.record.id}-${this.name}`,
      record_type: this.record.constructor.tableName,
      record_id: this.record.id,
      name: this.name,
      blob_id: blobMetadata.id
    };
    await this.attachmentStore.put(attachmentRecord);

    // Cache the blob
    this._blob = blobMetadata;
    this._loaded = true;

    return this;
  }

  // Check if an attachment exists
  async attached() {
    await this._ensureLoaded();
    return this._blob !== null;
  }

  // Alias for attached() - Ruby uses attached? which transpiles to attached()
  async isAttached() {
    return await this.attached();
  }

  // Get URL for the attachment
  async url(options = {}) {
    await this._ensureLoaded();
    if (!this._blob) return null;
    return await this.storage.url(this._blob.key, options);
  }

  // Download the attachment data
  async download() {
    await this._ensureLoaded();
    if (!this._blob) return null;
    return await this.storage.download(this._blob.key);
  }

  // Get blob metadata
  async blob() {
    await this._ensureLoaded();
    return this._blob;
  }

  // Get filename
  async filename() {
    await this._ensureLoaded();
    return this._blob?.filename;
  }

  // Get content type
  async contentType() {
    await this._ensureLoaded();
    return this._blob?.content_type;
  }

  // Get byte size
  async byteSize() {
    await this._ensureLoaded();
    return this._blob?.byte_size;
  }

  // Delete the attachment
  async purge() {
    await this._ensureLoaded();
    if (!this._blob) return;

    // Delete from storage
    await this.storage.delete(this._blob.key);

    // Delete blob metadata
    await this.blobStore.delete(this._blob.id);

    // Delete attachment record
    const attachmentId = `${this.record.constructor.tableName}-${this.record.id}-${this.name}`;
    await this.attachmentStore.delete(attachmentId);

    this._blob = null;
    this._loaded = true;
  }

  // Load attachment data from stores
  async _ensureLoaded() {
    if (this._loaded) return;

    if (!this.attachmentStore || !this.blobStore) {
      this._loaded = true;
      return;
    }

    // Find attachment record
    const attachmentId = `${this.record.constructor.tableName}-${this.record.id}-${this.name}`;
    const attachmentRecord = await this.attachmentStore.get(attachmentId);

    if (attachmentRecord) {
      // Load blob metadata
      const blobData = await this.blobStore.get(attachmentRecord.blob_id);
      if (blobData) {
        this._blob = new BlobMetadata(blobData);
      }
    }

    this._loaded = true;
  }

  // Reset loaded state (call after record changes)
  reset() {
    this._blob = null;
    this._loaded = false;
  }
}

// Attachments collection proxy - returned by has_many_attached getter
export class Attachments {
  constructor(record, name, options = {}) {
    this.record = record;
    this.name = name;
    this.options = options;
    this._blobs = [];
    this._loaded = false;
  }

  get storage() {
    return globalThis.ActiveStorage?.service;
  }

  get blobStore() {
    return globalThis.ActiveStorage?.blobStore;
  }

  get attachmentStore() {
    return globalThis.ActiveStorage?.attachmentStore;
  }

  // Attach a file/blob (adds to collection)
  async attach(data, options = {}) {
    if (!this.storage) {
      throw new Error('Active Storage service not initialized');
    }

    if (!this.record.id) {
      throw new Error('Cannot attach to unpersisted record');
    }

    // Determine file metadata
    let filename, contentType, byteSize, blob;

    if (data instanceof File) {
      filename = options.filename || data.name;
      contentType = options.content_type || data.type;
      byteSize = data.size;
      blob = data;
    } else if (data instanceof Blob) {
      filename = options.filename || `${this.name}-${Date.now()}`;
      contentType = options.content_type || data.type || 'application/octet-stream';
      byteSize = data.size;
      blob = data;
    } else {
      throw new Error('attach() requires a File or Blob');
    }

    const key = generateKey();
    const checksum = await computeChecksum(blob);

    await this.storage.upload(key, blob, { contentType });

    const blobMetadata = new BlobMetadata({
      id: generateKey(),
      key,
      filename,
      content_type: contentType,
      byte_size: byteSize,
      checksum
    });

    await this.blobStore.put(blobMetadata.toJSON());

    // For has_many, use a unique ID per attachment
    const attachmentRecord = {
      id: `${this.record.constructor.tableName}-${this.record.id}-${this.name}-${blobMetadata.id}`,
      record_type: this.record.constructor.tableName,
      record_id: this.record.id,
      name: this.name,
      blob_id: blobMetadata.id
    };
    await this.attachmentStore.put(attachmentRecord);

    this._blobs.push(blobMetadata);

    return this;
  }

  // Check if any attachments exist
  async attached() {
    await this._ensureLoaded();
    return this._blobs.length > 0;
  }

  // Get count of attachments
  async count() {
    await this._ensureLoaded();
    return this._blobs.length;
  }

  // Get all blobs
  async blobs() {
    await this._ensureLoaded();
    return [...this._blobs];
  }

  // Iterate over attachments
  async forEach(callback) {
    await this._ensureLoaded();
    for (const blob of this._blobs) {
      await callback(blob);
    }
  }

  // Map over attachments
  async map(callback) {
    await this._ensureLoaded();
    return Promise.all(this._blobs.map(callback));
  }

  // Delete all attachments
  async purge() {
    await this._ensureLoaded();

    for (const blob of this._blobs) {
      await this.storage.delete(blob.key);
      await this.blobStore.delete(blob.id);
    }

    // Delete all attachment records for this name
    // This requires iterating since we don't have a where clause
    const prefix = `${this.record.constructor.tableName}-${this.record.id}-${this.name}-`;
    const allAttachments = await this.attachmentStore.toArray();
    for (const att of allAttachments) {
      if (att.id.startsWith(prefix)) {
        await this.attachmentStore.delete(att.id);
      }
    }

    this._blobs = [];
    this._loaded = true;
  }

  async _ensureLoaded() {
    if (this._loaded) return;

    if (!this.attachmentStore || !this.blobStore) {
      this._loaded = true;
      return;
    }

    // Find all attachment records for this record/name
    const prefix = `${this.record.constructor.tableName}-${this.record.id}-${this.name}-`;
    const allAttachments = await this.attachmentStore.toArray();
    const attachmentRecords = allAttachments.filter(att => att.id.startsWith(prefix));

    // Load blob metadata for each
    this._blobs = [];
    for (const att of attachmentRecords) {
      const blobData = await this.blobStore.get(att.blob_id);
      if (blobData) {
        this._blobs.push(new BlobMetadata(blobData));
      }
    }

    this._loaded = true;
  }

  reset() {
    this._blobs = [];
    this._loaded = false;
  }
}

// Helper to create has_one_attached getter
export function hasOneAttached(record, name, options = {}) {
  // Cache attachment proxy on the record instance
  const cacheKey = `_attachment_${name}`;
  if (!record[cacheKey]) {
    record[cacheKey] = new Attachment(record, name, options);
  }
  return record[cacheKey];
}

// Helper to create has_many_attached getter
export function hasManyAttached(record, name, options = {}) {
  const cacheKey = `_attachments_${name}`;
  if (!record[cacheKey]) {
    record[cacheKey] = new Attachments(record, name, options);
  }
  return record[cacheKey];
}
