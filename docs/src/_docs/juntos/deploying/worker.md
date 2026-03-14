---
order: 623
title: Worker Deployment
top_section: Juntos
category: juntos/deploying
hide_in_toc: true
---

Run your Rails app in a SharedWorker with OPFS-backed database persistence.

{% toc %}

## Overview

The worker target runs your application across three tiers, entirely in the browser:

| Tier | Context | Responsibility |
|------|---------|---------------|
| **Presentation** | Main thread | Turbo, Stimulus, DOM |
| **Application** | SharedWorker | Router, controllers, models, views |
| **Data** | Dedicated Worker | SQLite or PGlite with OPFS persistence |

This architecture keeps the main thread unblocked, shares one application instance across all tabs, and uses OPFS for durable persistence that survives browser storage pressure.

### Why Three Tiers?

- **OPFS requires a dedicated Worker** — the synchronous `FileSystemSyncAccessHandle` API is only available in dedicated Workers
- **SharedWorker gives multi-tab sharing** — one application instance serves all tabs, no coordination needed
- **Main thread stays responsive** — all application logic and database I/O happen off-thread

## Database Options

| Adapter | Engine | Storage |
|---------|--------|---------|
| `sqlite-wasm` | SQLite WASM (official) | OPFS |
| `wa-sqlite` | SQLite WASM (wa-sqlite) | OPFS |
| `pglite` | PostgreSQL WASM | OPFS via OpfsAhpFS |

These adapters default to the worker target automatically. OPFS provides persistent storage with better performance and durability than IndexedDB.

## Development

```bash
bin/juntos dev -d sqlite-wasm
```

This starts a development server with hot reload. The SharedWorker architecture is active during development.

## Production Build

```bash
bin/juntos build -d sqlite-wasm
```

Creates a static site in `dist/` — same structure as the browser target. The SharedWorker and dedicated Worker scripts are bundled and fingerprinted by Vite.

## Deployment

Deploy to any static hosting — same as the [browser target](/docs/juntos/deploying/browser#deployment):

- Netlify, GitHub Pages, Vercel (static), S3/CloudFront, etc.

No server infrastructure required.

## How It Works

1. **Page load**: Main thread creates a `SharedWorker` pointing to the application bundle
2. **Navigation**: Turbo's `turbo:before-fetch-request` is intercepted and forwarded to the SharedWorker via `MessagePort`
3. **Dispatch**: The SharedWorker runs `Router.dispatch()` — same routing, controllers, models, and views as server targets
4. **Database**: The SharedWorker sends SQL queries to the dedicated Worker via `postMessage`, which executes them against the real database adapter
5. **Response**: HTML is sent back to the main thread as a synthetic `Response`, and Turbo renders it
6. **Broadcasts**: Turbo Streams use `BroadcastChannel` to reach all tabs

## Fallback

When `SharedWorker` is unavailable (older browsers), the worker target automatically falls back to the [browser target](/docs/juntos/deploying/browser) — loading the app on the main thread with IndexedDB (Dexie) storage.

## Browser Support

The worker target requires SharedWorker with module support:

| Browser | Minimum Version |
|---------|----------------|
| Chrome | 80+ |
| Firefox | 114+ |
| Safari | 18.2+ |

**Safari note:** PGlite's OPFS backend (OpfsAhpFS) is not supported on Safari due to a limit on sync access handles. PGlite falls back to IndexedDB on Safari.

## Limitations

- **No server-side logic** — everything runs client-side
- **No email** — can't send SMTP from browsers
- **Secure context required** — OPFS requires HTTPS or localhost
- **Safari PGlite** — falls back to IndexedDB (see above)

## Worker vs Browser

| Feature | Worker | Browser |
|---------|--------|---------|
| Database persistence | OPFS (durable) | IndexedDB |
| Multi-tab | Shared (one instance) | Independent per tab |
| Main thread | Unblocked | Blocked during queries |
| Default adapters | sqlite-wasm, wa-sqlite, pglite | dexie, sqljs |
| Fallback | Browser target | N/A |

Use the worker target when you want OPFS persistence, multi-tab sharing, or need the main thread free for heavy UI work. Use the browser target for simpler apps or when using Dexie/sql.js.

## Overriding the Default

OPFS-capable adapters default to the worker target. To force the browser target:

```bash
bin/juntos dev -t browser -d pglite    # Force browser with PGlite (uses IndexedDB)
bin/juntos dev -t browser -d sqlite-wasm  # Force browser (uses in-memory fallback)
```
