---
order: 660
title: BEAM Deployment
top_section: Juntos
category: juntos/deploying
hide_in_toc: true
---

Run your Rails app on the Erlang/OTP VM via [QuickBEAM](https://github.com/elixir-volt/quickbeam).

{% toc %}

## Overview

BEAM deployment runs your transpiled Rails application inside QuickBEAM—a JavaScript runtime embedded in the Erlang/OTP virtual machine. Your app runs as supervised OTP processes with fault tolerance, distributed clustering, and native WebSocket support.

**Use cases:**

- Fault-tolerant applications with OTP supervision
- Distributed real-time apps with built-in pub/sub (no Redis required)
- Multi-node clusters with automatic broadcast across nodes
- High-concurrency apps with pooled JS runtimes

## Prerequisites

1. **Elixir** (1.18+) and **Erlang/OTP** (27+)
   ```bash
   # macOS
   brew install elixir

   # Or use asdf/mise
   asdf install elixir latest
   ```

## Database Options

| Adapter | Service | Notes |
|---------|---------|-------|
| `sqlite_napi` | SQLite (via sqlite-napi) | File-based, single node |
| `postgrex` | PostgreSQL (via Postgrex) | Full-featured, distributed-ready |

## Development

```bash
bin/juntos db:prepare -d sqlite_napi
bin/juntos up -d sqlite_napi
```

This builds the app and starts a server on port 3000.

## Database Setup

Prepare the database before starting the server:

```bash
bin/juntos db:prepare -d sqlite_napi
bin/juntos up -d sqlite_napi
```

For PostgreSQL:

```bash
# Set connection string in .env.local
echo "DATABASE_URL=postgres://user:pass@host/db" >> .env.local

bin/juntos db:prepare -d postgrex
bin/juntos up -d postgrex
```

The `db:prepare` command runs migrations and seeds if the database is fresh.

## Production Build

```bash
bin/juntos build -d sqlite_napi -t beam
```

Creates a deployable Elixir application in `dist/`:

```bash
cd dist
mix deps.get
mix run --no-halt
```

## How It Works

The build produces an Elixir project in `dist/`:

```
dist/
├── app.js                      # Bundled Juntos application
├── mix.exs                     # Elixir project (deps: quickbeam, bandit)
├── lib/
│   ├── juntos_beam.ex          # QuickBEAM runtime pool + request dispatch
│   └── juntos_beam/
│       ├── application.ex      # OTP application supervisor
│       ├── cable.ex            # WebSocket handler for Turbo Streams
│       ├── database.ex         # Postgrex bridge (when using PostgreSQL)
│       └── router.ex           # Plug router (static files + JS dispatch)
├── assets/                     # Fingerprinted CSS
├── app/javascript/             # Bundled client JS (Turbo + Stimulus)
└── package.json                # sqlite-napi dependency (when using SQLite)
```

Request flow:

1. HTTP request arrives at Bandit (Elixir HTTP server)
2. Static assets served directly by Plug.Static
3. All other requests dispatched to a QuickBEAM runtime from the pool
4. The JS runtime runs the Juntos router, controller, and view logic
5. The response is returned through Bandit

## Concurrency

Requests are handled by a pool of QuickBEAM runtimes. Each runtime has its own JS context and OS thread, providing true parallelism. The default pool size is `max(4, CPU cores)` — ensuring I/O concurrency even on single-core machines.

With SQLite, all runtimes share the same database file via WAL mode (multiple concurrent readers, serialized writes). With PostgreSQL, database connections are pooled on the Elixir side via Postgrex.

## Real-Time Broadcasting

Turbo Streams broadcasting is handled entirely by Elixir:

- Browsers connect via WebSocket to `/cable`
- Elixir manages all subscriptions using OTP's `:pg` (process groups)
- When a model broadcasts, JS calls `Beam.callSync` to Elixir
- Elixir pushes the update to all subscribed WebSocket connections

This provides:

- **Zero-dependency pub/sub** — no Redis, Pusher, or external services
- **Distributed by default** — broadcasts automatically span clustered BEAM nodes
- **Native WebSockets** — Bandit handles WebSocket upgrades natively

## Deployment Options

### Docker

```dockerfile
FROM elixir:1.18-slim

WORKDIR /app
COPY dist/ .
RUN mix local.hex --force && mix deps.get && mix compile

EXPOSE 3000
CMD ["mix", "run", "--no-halt"]
```

```bash
docker build -t myapp .
docker run -p 3000:3000 -e DATABASE_URL=... myapp
```

### Traditional VPS

```bash
# On server
cd dist
mix local.hex --force
mix deps.get
PORT=3000 DATABASE_URL=... MIX_ENV=prod mix run --no-halt
```

Use systemd for process management:

```ini
[Unit]
Description=Juntos BEAM App

[Service]
WorkingDirectory=/opt/myapp/dist
ExecStart=/usr/bin/mix run --no-halt
Environment=PORT=3000
Environment=DATABASE_URL=postgres://...
Restart=always

[Install]
WantedBy=multi-user.target
```

## Advantages Over Other Targets

| Feature | BEAM | Node.js | Cloudflare | Vercel |
|---------|------|---------|------------|--------|
| Fault tolerance | OTP supervision | Process crash = restart | Isolate crash = retry | Function crash = retry |
| Real-time | `:pg` (built-in, distributed) | ws + Redis | Durable Objects | Pusher/external |
| Concurrency | Pooled runtimes, true parallel | Single-threaded + cluster | Per-request isolates | Per-request functions |
| Clustering | Built-in BEAM distribution | Manual | N/A | N/A |
| Hot upgrades | OTP releases | Rolling restart | Instant deploy | Instant deploy |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `PORT` | Server port (default: 3000) |
| `DATABASE_URL` | PostgreSQL connection string |
| `JUNTOS_DATABASE` | Database adapter override |

## Limitations

- **QuickJS engine** — QuickBEAM uses QuickJS-NG, not V8. Most standard JS works, but some V8-specific features may not be available.
- **No WASM** — QuickJS does not support WebAssembly. Use native BEAM NIFs for compute-intensive tasks instead.
- **No JS HMR in dev** — CSS and Stimulus controllers get Vite HMR; server-side Ruby changes trigger a fast reload (~1 second).
