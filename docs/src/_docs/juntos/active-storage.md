---
order: 619
title: Active Storage
top_section: Juntos
category: juntos
---

# Active Storage

Juntos implements Active Storage for file attachments across all deployment targets. The same `has_one_attached` declaration works whether your app runs in the browser, on Node.js, at the edge, or through RPC.

{% toc %}

## Overview

Declare attachments in your model:

```ruby
class Clip < ApplicationRecord
  has_one_attached :audio
  has_many_attached :images
end
```

Attach files from a Stimulus controller:

```ruby
await clip.audio.attach(@audioBlob,
  filename: "recording.webm",
  content_type: "audio/webm"
)
```

Query attachments:

```ruby
if await clip.audio.attached?
  url = await clip.audio.url
  data = await clip.audio.download
  name = await clip.audio.filename
  type = await clip.audio.content_type
  size = await clip.audio.byte_size
end
```

Remove attachments:

```ruby
await clip.audio.purge
```

## Storage Adapters

The build target determines which storage backend is used. No code changes needed.

| Target | Adapter | Storage |
|--------|---------|---------|
| Browser (dexie) | `active_storage_indexeddb.mjs` | IndexedDB via Dexie |
| Browser (worker) | `active_storage_worker.mjs` | OPFS via dedicated Worker |
| Node.js / Bun / Deno / BEAM | `active_storage_disk.mjs` | Local filesystem |
| Cloudflare / Fly / Vercel Edge | `active_storage_s3.mjs` | S3-compatible (AWS S3, R2, MinIO) |
| RPC (client bundle) | `active_storage_rpc.mjs` | Proxies to server adapter via RPC |

### Browser (IndexedDB)

The default for browser targets. Blobs are stored in IndexedDB alongside blob metadata and attachment records. Data persists across page reloads but may be evicted under storage pressure.

```bash
bin/juntos dev -d dexie
```

### Node.js (Disk)

Files are stored on the local filesystem in `storage/`, with metadata in the database (SQLite or PostgreSQL). The directory structure uses the first two characters of the key as a subdirectory to avoid too many files in one directory.

```bash
bin/juntos up -d sqlite
```

### Edge (S3)

For serverless and edge deployments, configure S3-compatible storage:

```bash
export S3_BUCKET=my-bucket
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=us-east-1
# For Cloudflare R2 or MinIO:
export AWS_ENDPOINT_URL=https://...
```

### RPC (Client to Server)

When the build target is a server (Node.js, Cloudflare, etc.) and a Stimulus controller imports a model, the client bundle uses the RPC adapter. Attachment operations are proxied to the server:

- `clip.audio.attach(blob)` base64-encodes the blob and sends it via `POST /__rpc`
- The server decodes and delegates to its configured storage adapter (disk, S3, etc.)
- `clip.audio.url`, `clip.audio.download`, `clip.audio.purge` work the same way

The Stimulus controller code is identical to the browser version. The build pipeline selects the RPC adapter automatically.

## Initialization

Active Storage must be initialized before use. In Stimulus controllers, call `initActiveStorage()` during connect:

```ruby
import ["initActiveStorage"], from: 'juntos:active-storage'

class DictaphoneController < Stimulus::Controller
  async def connect
    await initActiveStorage()
  end
end
```

The import resolves to the correct adapter based on the build target.

## How It Works

Active Storage uses three stores:

1. **Storage service** — handles the actual blob data (upload, download, delete)
2. **Blob store** — persists metadata (filename, content type, byte size, checksum)
3. **Attachment store** — links blobs to model records (record type, record id, name)

When you call `clip.audio.attach(blob)`:

1. A unique key is generated
2. A checksum is computed
3. The blob is uploaded to the storage service
4. Blob metadata is persisted
5. An attachment record links the blob to the model record

When you call `clip.audio.url`:

1. The attachment record is loaded (cached after first load)
2. The blob metadata is loaded
3. The storage service returns a URL for the blob's key

## Demos

- **[Dictaphone](/docs/juntos/demos/dictaphone)** — audio recording with Active Storage, Whisper transcription, and OPUS-MT translation
- **[Photo Gallery](/docs/juntos/demos/photo-gallery)** — image attachments with device camera integration
