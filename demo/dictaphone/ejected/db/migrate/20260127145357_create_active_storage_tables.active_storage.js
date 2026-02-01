export const migration = {
  up: async (adapter) => {
    await adapter.createTable("active_storage_blobs", [
      {name: "id", type: "integer", primaryKey: true, autoIncrement: true},
      {name: "key", type: "string", null: false},
      {name: "filename", type: "string", null: false},
      {name: "content_type", type: "string"},
      {name: "metadata", type: "text"},
      {name: "service_name", type: "string", null: false},
      {name: "byte_size", type: "bigint", null: false},
      {name: "checksum", type: "string"}
    ]);

    await adapter.createTable("active_storage_attachments", [
      {name: "id", type: "integer", primaryKey: true, autoIncrement: true},
      {name: "name", type: "string", null: false},
      {name: "record_id", type: "integer", null: false},
      {name: "blob_id", type: "integer", null: false},
      {name: "active_storage_blobs", type: "foreign_key"}
    ]);

    return await adapter.createTable("active_storage_variant_records", [
      {name: "id", type: "integer", primaryKey: true, autoIncrement: true},
      {name: "blob_id", type: "integer", null: false},
      {name: "variation_digest", type: "string", null: false},
      {name: "active_storage_blobs", type: "foreign_key"}
    ])
  },

  tableSchemas: {
    active_storage_blobs: "++id, key, filename, content_type, metadata, service_name, byte_size, checksum",
    active_storage_attachments: "++id, name, record_id, blob_id, active_storage_blobs",
    active_storage_variant_records: "++id, blob_id, variation_digest, active_storage_blobs"
  }
}

// This migration comes from active_storage (originally 20170806125915)
// Use Active Record's configured type for primary and foreign keys