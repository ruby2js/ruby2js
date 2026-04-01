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

BEAM deployment runs your transpiled Rails application inside QuickBEAM—a JavaScript runtime embedded in the Erlang/OTP virtual machine. Your app runs as a supervised OTP process with fault tolerance, distributed clustering, and native WebSocket support.

**Use cases:**

- Fault-tolerant applications with OTP supervision
- Distributed real-time apps with built-in pub/sub (no Redis required)
- Multi-node clusters with automatic broadcast across nodes
- High-concurrency apps (10K+ lightweight JS contexts per node)

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
| `sqlite_napi` | SQLite (via sqlite-napi) | File or in-memory, bundled with QuickBEAM |

## Deployment

```bash
# Build the BEAM target
juntos build -d sqlite_napi -t beam

# Enter the output directory
cd dist

# Install Elixir dependencies
mix deps.get

# Run the server
mix run --no-halt
```

The server starts on port 4000 by default. Set the `PORT` environment variable to change it:

```bash
PORT=8080 mix run --no-halt
```

## How It Works

The build produces an Elixir project in `dist/` with:

```
dist/
├── app.js              # Bundled Juntos application
├── mix.exs             # Elixir project (deps: quickbeam, bandit)
├── lib/
│   ├── juntos_beam.ex          # QuickBEAM runtime + request dispatch
│   └── juntos_beam/
│       ├── application.ex      # OTP application supervisor
│       └── router.ex           # Plug router (static files + JS dispatch)
├── package.json        # sqlite-napi dependency
└── public/             # Static assets (CSS, JS, images)
```

Request flow:

1. HTTP request arrives at Bandit (Elixir HTTP server)
2. Static assets are served directly by Plug.Static
3. All other requests are forwarded to the QuickBEAM JS runtime
4. The JS runtime runs the Juntos router, controller, and view logic
5. The response is returned through Bandit

## Real-Time Broadcasting

Turbo Streams broadcasting uses QuickBEAM's `BroadcastChannel`, which is backed by OTP's `:pg` (process groups). This provides:

- **Zero-dependency pub/sub** — no Redis, Pusher, or external services needed
- **Distributed by default** — broadcasts automatically span clustered BEAM nodes
- **Native WebSockets** — Cowboy handles WebSocket upgrades natively

## Advantages Over Other Targets

| Feature | BEAM | Node.js | Cloudflare | Vercel |
|---------|------|---------|------------|--------|
| Fault tolerance | OTP supervision | Process crash = restart | Isolate crash = retry | Function crash = retry |
| Real-time | `:pg` (built-in, distributed) | ws + Redis | Durable Objects | Pusher/external |
| Concurrency | 10K+ lightweight contexts | Single-threaded + cluster | Per-request isolates | Per-request functions |
| Clustering | Built-in BEAM distribution | Manual | N/A | N/A |
| Hot upgrades | OTP releases | Rolling restart | Instant deploy | Instant deploy |

## Limitations

- **Single-node SQLite** — sqlite-napi is file-based, not distributed. For multi-node deployments, a PostgreSQL adapter via `Beam.callSync` would be needed.
- **QuickJS engine** — QuickBEAM uses QuickJS-NG, not V8. Most standard JS works, but some V8-specific features may not be available.
- **No WASM** — QuickJS does not support WebAssembly. Use native BEAM NIFs for compute-intensive tasks instead.
