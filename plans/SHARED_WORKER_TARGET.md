# Worker Target Plan

## Overview

Three-tier architecture running entirely in the browser:

| Tier | Context | Responsibility |
|------|---------|---------------|
| Presentation | Main thread | Turbo, Stimulus, Action Cable, DOM |
| Application | SharedWorker | Router, controllers, models, views |
| Data | Dedicated Worker | SQLite + opfs-sahpool |

Each tier communicates through MessagePort, mirroring how a real three-tier app communicates through HTTP and SQL.

## Architecture

```
Main Thread                    SharedWorker                 Dedicated Worker
(Presentation)                 (Application)                (Data)
──────────────                 ─────────────                ────────────────
Turbo Drive                    Router                       SQLite WASM
  turbo:before-fetch-request     ↓                           opfs-sahpool VFS
    ↓                          Controller                    OPFS persistence
  postMessage(req) ─────→       ↓
                               Model
                                 ↓
                               query ──── postMessage ────→ exec(sql)
                               ← ─────── postMessage ────  rows
                                 ↓
                               View → HTML string
  ← ──── postMessage(res)     response
  synthetic Response
    ↓
  Turbo processes HTML
                               BroadcastChannel ──────────→ (all tabs)
Stimulus Controllers           ↑
  (DOM-only)                   Turbo Stream HTML
BroadcastChannel ←─────────────┘
  Turbo.renderStreamMessage
```

## Why Three Tiers

- **opfs-sahpool requires a dedicated Worker** — `FileSystemSyncAccessHandle` is not available in SharedWorkers or on the main thread
- **SharedWorker gives multi-tab sharing** — one application instance serves all tabs, no coordination needed
- **SharedWorker can own a dedicated Worker** — the dedicated Worker's lifetime is tied to the SharedWorker, not to any individual tab
- **opfs-sahpool requires exclusive lock** — a single dedicated Worker naturally satisfies this; no contention between tabs
- **No COOP/COEP headers needed** — opfs-sahpool avoids the SharedArrayBuffer requirement
- **Main thread stays unblocked** — all application logic and database I/O happen off the main thread

## Key Decisions

- **Separate target**: Existing browser target untouched, selected via `target: 'worker'`
- **Vite fingerprinting**: Worker scripts get content hashes via `new URL('./worker.js', import.meta.url)`
- **Fallback**: When SharedWorker unavailable, dynamically import browser target (Dexie, main thread)

## Message Protocols

### Main Thread ↔ SharedWorker (request/response)

Request (main → shared):
```js
{
  id: crypto.randomUUID(),
  type: 'fetch',
  method: 'GET',
  url: '/articles/1',
  headers: { cookie: '...', accept: '...' },
  body: null | string
}
```

Response (shared → main):
```js
{
  id: '<correlation-id>',
  type: 'response',
  status: 200,
  headers: { 'content-type': 'text/html', 'set-cookie': '...' },
  body: '<html>...</html>'
}
```

### SharedWorker ↔ Dedicated Worker (SQL)

Query (shared → dedicated):
```js
{
  id: crypto.randomUUID(),
  type: 'exec',
  sql: 'SELECT * FROM posts WHERE id = ?',
  params: [1]
}
```

Result (dedicated → shared):
```js
{
  id: '<correlation-id>',
  type: 'result',
  rows: [{ id: 1, title: '...' }],
  changes: 0,
  lastInsertRowId: null
}
```

## Implementation Steps

### Step 1: Database Worker (Dedicated Worker)

**File**: `packages/juntos/targets/worker/db_worker.js`

The simplest tier — receives SQL, executes against the database, returns rows. The Worker is database-engine-agnostic; it uses whichever existing adapter the app is configured for (PGlite or SQLite).

- On init message: dynamically import the configured adapter (existing `active_record_pglite.mjs` or `active_record_sqlite_wasm.mjs`), call `initDatabase()` with OPFS config
- Listen on `self.onmessage` for SQL queries
- Execute queries via the adapter's `query()`/`execute()` functions, post back results
- Handle migrations (received as a batch of SQL statements on init)
- Handle transactions (begin/commit/rollback message types)

```js
// Configured at build time or via init message
let adapter;

self.onmessage = async ({ data }) => {
  if (data.type === 'init') {
    // Import the existing adapter unchanged — PGlite or SQLite
    adapter = await import(data.adapter);
    await adapter.initDatabase(data.config);
    self.postMessage({ type: 'ready' });
    return;
  }

  if (data.type === 'exec') {
    const { id, sql, params } = data;
    const rows = await adapter.query(sql, params);
    self.postMessage({ id, type: 'result', rows });
  }
};
```

The existing adapters (`active_record_pglite.mjs`, `active_record_sqlite_wasm.mjs`) run inside this Worker unchanged — they call `db.query()` directly as they do today.

### Step 2: Application Worker (SharedWorker)

**File**: `packages/juntos/targets/worker/rails.js`

- Import Router, Application from `rails_server.js`
- On load: spawn the dedicated database Worker via `new Worker('./db_worker.js')`
- Listen on `self.onconnect` for MessagePort connections from tabs
- For each tab message: deserialize request → `Router.dispatch()` → serialize response → `port.postMessage()`
- Database adapter sends SQL to dedicated Worker via postMessage instead of executing directly
- Use BroadcastChannel for Turbo Streams (available in SharedWorker context)

Reference: Cloudflare target wraps Fetch API Request/Response similarly.

### Step 3: Client Bridge (Main Thread)

**File**: `packages/juntos/targets/worker/client.js`

- Create `SharedWorker(new URL('./rails.js', import.meta.url), { type: 'module' })`
- `WorkerBridge.fetch(method, url, headers, body)` → postMessage + Promise via correlation ID Map
- Install `turbo:before-fetch-request` listener (same preventDefault/resume pattern as browser target)
- Forward cookies: read `document.cookie` into request headers
- Apply `Set-Cookie` from responses back to `document.cookie`
- Subscribe BroadcastChannel for Turbo Streams
- Fallback: if no SharedWorker, dynamically import browser target

Note: No separate opfs-sahpool adapter needed. The existing PGlite and SQLite adapters run unchanged inside the dedicated Worker (Step 1). The application tier uses the generic MessagePort adapter (Step 4) which forwards SQL to whichever engine the dedicated Worker loaded.

### Step 4: MessagePort SQL Adapter (Application Tier)

**File**: `packages/juntos/adapters/active_record_worker.mjs`

A generic "SQL over MessagePort" adapter used by the SharedWorker (application tier). It has the same interface as the existing SQL adapters but sends SQL to the dedicated Worker instead of executing directly. Database-engine-agnostic — it doesn't know or care whether the dedicated Worker runs PGlite or SQLite.

- `_execute(sql, params)` → postMessage to dedicated Worker, await response
- `_getRows(result)` → extract rows from response
- `_getLastInsertId(result)` → extract from response
- `initDatabase()` → sends init message to dedicated Worker with adapter path and config
- All queries from all tabs serialize through the single dedicated Worker — no lock contention
- Extends the appropriate dialect (Postgres or SQLite) based on configuration, for SQL generation

### Step 5: Vite Build Configuration

Modify `packages/juntos-dev/vite.mjs`:
- Add `'worker'` to `TARGET_DIR_MAP`
- Add `'worker'` to `ADAPTER_FILE_MAP` → `active_record_worker.mjs`
- Add rollup options: three entry points (client + shared worker + dedicated worker), all fingerprinted
- Virtual module `juntos:rails` resolves to worker/client.js on main thread, worker/rails.js in SharedWorker
- Dedicated Worker bundles the existing PGlite or SQLite adapter based on app config

Modify `packages/juntos-dev/transform.mjs`:
- Add worker target mapping

### Step 6: Cookie/Session Handling

- **Request**: Client reads `document.cookie`, sends in message headers
- **Response**: Client applies `Set-Cookie` headers from worker response to `document.cookie`
- **CSRF**: SharedWorker generates tokens, embeds in rendered forms, validates on submission
- **Flash**: Works via `_flash` cookie, no changes needed
- `createContext()` in `rails_server.js` already parses cookie headers

### Step 7: BroadcastChannel (Turbo Streams)

No new work. The existing `TurboBroadcast` class uses `BroadcastChannel` which is available in SharedWorker context. Broadcasts reach all tabs automatically.

## New Files

| File | Purpose |
|------|---------|
| `packages/juntos/targets/worker/db_worker.js` | Dedicated Worker: loads existing PGlite or SQLite adapter |
| `packages/juntos/targets/worker/rails.js` | SharedWorker: router, controllers, models, views |
| `packages/juntos/targets/worker/client.js` | Main thread: Turbo bridge |
| `packages/juntos/adapters/active_record_worker.mjs` | Generic SQL-over-MessagePort adapter for application tier |

## Modified Files

| File | Change |
|------|--------|
| `packages/juntos-dev/vite.mjs` | Worker target in build config |
| `packages/juntos-dev/transform.mjs` | Worker target mapping |

## Risks

1. **SharedWorker + module type**: Requires Chrome 80+, Firefox 114+, Safari 18.2+. Fallback handles older browsers.
2. **opfs-sahpool**: Requires secure context (HTTPS/localhost). Dev servers qualify. Fallback to in-memory SQLite if unavailable.
3. **Database migrations across worker versions**: Fingerprinted workers mean old/new can coexist briefly. Migrations should be backward-compatible.
4. **Serialization**: <1ms for typical HTML responses. Use Transferable ArrayBuffers for large payloads if needed.
5. **Double hop latency**: Main → SharedWorker → Dedicated Worker adds two postMessage round-trips per DB query. But all DB queries within a single request are local to the SharedWorker↔Dedicated Worker boundary — only one Main↔SharedWorker round-trip per user action.
6. **Adapter layering**: The application tier (SharedWorker) uses a generic MessagePort adapter. The data tier (dedicated Worker) runs the real adapter (PGlite or SQLite) unchanged. The database engine choice is a build-time config, not an architectural decision.

## Key Reference Files

- `packages/juntos/targets/browser/rails.js` — turbo:before-fetch-request pattern (lines 578-768), TurboBroadcast (lines 942-995)
- `packages/juntos/rails_server.js` — Router.dispatch, createContext, handleResult
- `packages/juntos/targets/node/rails.js` — pattern for server target extending rails_server.js
- `packages/juntos/targets/cloudflare/rails.js` — pattern for Fetch API Request/Response wrapping
- `packages/juntos/adapters/active_record_sqlite_wasm.mjs` — template for worker adapter
- `packages/juntos-dev/vite.mjs` — createVirtualPlugin, getRollupOptions
