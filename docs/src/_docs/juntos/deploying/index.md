---
order: 620
title: Deployment Overview
top_section: Juntos
category: juntos-deploying
---

# Deploying Juntos Applications

Juntos unlocks platforms Rails can't reach—and works everywhere JavaScript runs.

{% toc %}

## Sweet Spots

These targets require transpilation. Rails can't run here; Juntos can:

| Target | Best For | Database Options |
|--------|----------|------------------|
| **[Browser](/docs/juntos/deploying/browser)** | Offline-first, local-first, demos | Dexie, sql.js, PGlite |
| **[Vercel Edge](/docs/juntos/deploying/vercel)** | Global edge, auto-scaling | [Neon](/docs/juntos/databases/neon), [Turso](/docs/juntos/databases/turso), [PlanetScale](/docs/juntos/databases/planetscale), [Supabase](/docs/juntos/databases/supabase) |
| **[Deno Deploy](/docs/juntos/deploying/deno-deploy)** | Edge, Deno/TypeScript native | [Neon](/docs/juntos/databases/neon), [Turso](/docs/juntos/databases/turso), [PlanetScale](/docs/juntos/databases/planetscale), [Supabase](/docs/juntos/databases/supabase) |
| **[Cloudflare Workers](/docs/juntos/deploying/cloudflare)** | Edge computing, maximum distribution | D1, Turso |
| **[Capacitor](/docs/juntos/deploying/capacitor)** | iOS/Android mobile apps | Dexie, sql.js, HTTP-based |
| **[Electron](/docs/juntos/deploying/electron)** | Desktop apps (macOS/Windows/Linux) | SQLite, sql.js, HTTP-based |
| **[Tauri](/docs/juntos/deploying/tauri)** | Lightweight desktop apps | sql.js, PGlite, HTTP-based |

## Also Works

For traditional hosting, Juntos works but Rails does too. Reasons to choose Juntos on a server runtime:

- **npm ecosystem** — access to JavaScript libraries not available in Ruby
- **Event-driven model** — JavaScript's async I/O may suit some workloads better than Ruby's Global VM Lock (GVL)
- **Unified codebase** — one codebase across browser, edge, and server

| Target | Best For | Database Options |
|--------|----------|------------------|
| **[Fly.io](/docs/juntos/deploying/fly)** | CLI-driven workflow, managed Postgres, native WebSockets | MPG (Managed Postgres) |
| **[Node.js](/docs/juntos/deploying/node)** | VPS, containers, widest compatibility | SQLite, PostgreSQL, MySQL |
| **[Bun](/docs/juntos/deploying/node)** | Fast startup, native SQLite | SQLite, PostgreSQL, MySQL |
| **[Deno](/docs/juntos/deploying/node)** | Secure by default, TypeScript | SQLite, PostgreSQL, MySQL |

## Quick Comparison

| Aspect | Browser | Node.js | Fly.io | Vercel | Cloudflare | Capacitor | Electron | Tauri |
|--------|---------|---------|--------|--------|------------|-----------|----------|-------|
| Infrastructure | None (static) | Server/container | Container | On-demand | On-demand | App stores | User install | User install |
| Scaling | N/A | Manual | Automatic | Automatic | Automatic | Per-device | Per-device | Per-device |
| Cold starts | None | N/A | ~200-500ms | ~50-250ms | ~5-50ms | None | None | None |
| Database | Client-side | TCP/file | MPG (Postgres) | HTTP APIs | D1 binding | Client-side | File/client | Client-side |
| Native APIs | Limited | N/A | N/A | N/A | N/A | Full device | Full OS | Rust backend |
| Distribution | URL | Deploy | Deploy | Deploy | Deploy | App Store | DMG/EXE | DMG/EXE |
| Bundle size | N/A | N/A | N/A | N/A | N/A | ~5MB | ~150MB | ~3-10MB |

## Choosing a Target

**Choose Browser if:**
- Your app works offline or local-first
- Data stays on the user's device
- You want zero infrastructure
- *Rails can't do this*

**Choose Vercel, Deno Deploy, or Cloudflare if:**
- You want global edge distribution
- You need auto-scaling and pay-per-request
- You want fast cold starts (~5-50ms)
- *Rails can't do this*

**Choose Fly.io if:**
- You need native WebSocket support (Turbo Streams without Pusher)
- You want CLI-driven workflow (no dashboard copying)
- You want managed Postgres with automatic failover
- *Rails works here too—but Juntos + MPG provides a streamlined CLI workflow*

**Choose Node.js, Bun, or Deno if:**
- You need npm packages not available in Ruby
- Your workload benefits from JavaScript's event-driven async model
- You want one codebase across browser, edge, and server
- *Rails works here too—but Juntos has advantages*

**Choose Capacitor if:**
- You want native iOS/Android apps
- You need device APIs (camera, GPS, push notifications)
- You want App Store/Google Play distribution
- *Rails can't do this*

**Choose Electron if:**
- You want native desktop apps (macOS, Windows, Linux)
- You need OS integration (system tray, global shortcuts, file system)
- You want distributable installers (DMG, EXE, AppImage)
- *Rails can't do this*

**Choose Tauri if:**
- You want lightweight desktop apps (~3-10MB vs Electron's ~150MB)
- Lower memory usage is important
- You're comfortable with Rust for custom native features
- You want the smallest possible bundle size
- *Rails can't do this*

## Default Target Inference

When you don't specify a target, Juntos infers it from your database:

```bash
bin/juntos up -d dexie      # → browser
bin/juntos up -d sqlite     # → node
bin/juntos up -d neon       # → vercel
bin/juntos up -d d1         # → cloudflare
bin/juntos up -d mpg        # → fly
```

Override with `-t`:

```bash
bin/juntos up -t node -d neon   # Force Node.js with Neon
```

## Hybrid Development

You don't need to hit remote databases during development. Use the familiar `config/database.yml` pattern—a local database for development, a cloud database for production.

### Recommended Pairings

| Deploy Target | Prod Database | Dev Adapter | Dev Target | Notes |
|---------------|---------------|-------------|------------|-------|
| Cloudflare Workers | d1 | sqlite | node | Same SQL dialect |
| Vercel Edge | neon | pglite | browser | No server needed |
| Vercel Edge | turso | sqlite | node | Same SQL dialect |
| Deno Deploy | neon | pg | deno | Requires local PostgreSQL |
| Fly.io | mpg | sqlite | node | Local SQLite, prod Postgres |

### Example Configuration

```yaml
# config/database.yml
development:
  adapter: sqlite
  database: db/development.sqlite3

production:
  adapter: d1
  database: myapp_production
```

```bash
# Development: instant feedback, no cloud round-trips
bin/juntos up -d sqlite

# Production: deploy to Cloudflare with D1
bin/juntos deploy -d d1
```

The SQL dialect matches between SQLite and D1, so your migrations and queries work in both environments.

### Offline-First Browser Apps

The browser target enables offline-first applications that sync with a Rails backend:

1. **Browser app** — runs entirely client-side with IndexedDB (Dexie)
2. **Rails API** — traditional server for sync and shared data
3. **Sync on reconnect** — browser app treats Rails as an API when connectivity returns

This pattern works well for:
- Mobile apps in spotty connectivity
- Field data collection
- Event scoring/judging systems
- Any scenario where the app must work without internet

```yaml
# Same models power both apps
development:
  adapter: dexie      # Browser app
  database: myapp_dev

production:
  adapter: pg         # Rails API backend
  url: <%= ENV['DATABASE_URL'] %>
```

## Database Setup Guides

For detailed setup instructions, see the [Database Overview](/docs/juntos/databases):

- [Neon](/docs/juntos/databases/neon) — Serverless PostgreSQL
- [Turso](/docs/juntos/databases/turso) — SQLite at the edge
- [PlanetScale](/docs/juntos/databases/planetscale) — Serverless MySQL
- [Supabase](/docs/juntos/databases/supabase) — Full backend platform
