// Active Storage adapter for RPC (browser client → server)
//
// Proxies all Active Storage operations to the server via the RPC channel.
// Blob data is base64-encoded for transport over JSON.
// The server-side storage adapter (disk, S3, etc.) handles actual persistence.

import { rpc } from '../rpc/client.mjs';
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

// Convert a Blob/File/ArrayBuffer/Uint8Array to base64 string
async function toBase64(data) {
  let buffer;
  if (data instanceof Blob) {
    buffer = await data.arrayBuffer();
  } else if (data instanceof ArrayBuffer) {
    buffer = data;
  } else if (data instanceof Uint8Array) {
    buffer = data.buffer;
  } else {
    throw new Error('toBase64 requires a Blob, ArrayBuffer, or Uint8Array');
  }

  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

// Convert base64 string back to Blob
function fromBase64(base64, contentType = 'application/octet-stream') {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new Blob([bytes], { type: contentType });
}

// RPC-backed storage service
export class RPCStorage extends StorageService {
  constructor(options = {}) {
    super(options);
  }

  async upload(key, data, options = {}) {
    const base64 = await toBase64(data);
    await rpc('ActiveStorage.upload', [key, base64, options]);
    return key;
  }

  async download(key) {
    const result = await rpc('ActiveStorage.download', [key]);
    if (!result) return null;
    return fromBase64(result.data, result.content_type);
  }

  async url(key, options = {}) {
    return await rpc('ActiveStorage.url', [key, options]);
  }

  async delete(key) {
    await rpc('ActiveStorage.delete', [key]);
  }

  async exists(key) {
    return await rpc('ActiveStorage.exists', [key]);
  }
}

// RPC-backed blob store
class RPCBlobStore {
  async get(key) {
    return await rpc('ActiveStorage.blobGet', [key]);
  }

  async put(record) {
    await rpc('ActiveStorage.blobPut', [record]);
  }

  async delete(key) {
    await rpc('ActiveStorage.blobDelete', [key]);
  }

  async toArray() {
    return await rpc('ActiveStorage.blobAll', []);
  }
}

// RPC-backed attachment store
class RPCAttachmentStore {
  async get(id) {
    return await rpc('ActiveStorage.attachmentGet', [id]);
  }

  async put(record) {
    await rpc('ActiveStorage.attachmentPut', [record]);
  }

  async delete(id) {
    await rpc('ActiveStorage.attachmentDelete', [id]);
  }

  async toArray() {
    return await rpc('ActiveStorage.attachmentAll', []);
  }
}

// Singleton instances
let storageInstance = null;
let blobStoreInstance = null;
let attachmentStoreInstance = null;

// Initialize Active Storage with RPC backend
export async function initActiveStorage(options = {}) {
  const storage = new RPCStorage(options);

  blobStoreInstance = new RPCBlobStore();
  attachmentStoreInstance = new RPCAttachmentStore();

  // Register globally so Attachment/Attachments can access it
  globalThis.ActiveStorage = {
    service: storage,
    blobStore: blobStoreInstance,
    attachmentStore: attachmentStoreInstance
  };

  storageInstance = storage;
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
