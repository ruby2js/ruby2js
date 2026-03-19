---
order: 640
title: Cloudflare Deployment
top_section: Juntos
category: juntos/deploying
hide_in_toc: true
---

Run your Rails app on Cloudflare's global network with D1 database.

{% toc %}

## Overview

Cloudflare Workers deployment runs your application on Cloudflare's edge network—over 300 cities worldwide. Two database options are available:

- **D1** — Cloudflare's shared SQLite database, accessed via Worker bindings
- **Durable Objects (DO)** — Per-instance embedded SQLite, co-located with your app logic and WebSockets

**Use cases:**

- Global applications with SQLite simplicity
- Cloudflare ecosystem integration
- Edge computing with D1's read replicas
- Cost-effective serverless deployment
- Cell architecture with isolated per-instance databases (DO)

## Prerequisites

1. **Wrangler CLI**
   ```bash
   npm i -g wrangler
   wrangler login
   ```

That's it! The `db:prepare` command handles D1 database creation automatically.

## Database Options

| Adapter | Service | Notes |
|---------|---------|-------|
| `d1` | Cloudflare D1 | Shared SQLite database, recommended for most apps |
| `do` | Durable Objects | Per-instance SQLite, app + DB + WebSockets in one object |
| `turso` | Turso | SQLite with sync, HTTP protocol |

Choose **D1** when you need a shared database that multiple Workers can query (traditional web app pattern). Choose **DO** when each instance should own its own database—the cell architecture where app logic, storage, and WebSockets are co-located in a single hibernatable object.

## Deployment

```bash
# Prepare database (creates if needed, migrates, seeds if fresh)
bin/juntos db:prepare -d d1

# Deploy
bin/juntos deploy -d d1
```

The deploy command:

1. Builds the app with Cloudflare configuration
2. Generates `wrangler.toml` and `src/index.js`
3. Verifies the build loads correctly
4. Runs `wrangler deploy`

## Manual Deployment

If you prefer manual control:

```bash
# Build only
bin/juntos build -t cloudflare -d d1

# Deploy with Wrangler
cd dist
wrangler deploy
```

## Generated Files

### wrangler.toml

```toml
name = "myapp"
main = "src/index.js"
compatibility_date = "2026-01-01"
compatibility_flags = ["nodejs_compat"]

[[d1_databases]]
binding = "DB"
database_name = "myapp_production"
database_id = "${D1_DATABASE_ID}"

[assets]
directory = "./app/assets"
```

### src/index.js

```javascript
import { Application, Router } from '../lib/rails.js';
import '../config/routes.js';
import { migrations } from '../db/migrate/index.js';
import { Seeds } from '../db/seeds.js';
import { layout } from '../app/views/layouts/application.js';

Application.configure({
  migrations: migrations,
  seeds: Seeds,
  layout: layout
});

export default Application.worker();
```

## Database Commands

D1 database management uses Wrangler under the hood:

```bash
bin/juntos db:create -d d1     # Create D1 database
bin/juntos db:migrate -d d1    # Run migrations only
bin/juntos db:seed -d d1       # Run seeds only
bin/juntos db:prepare -d d1    # All of the above (smart)
bin/juntos db:drop -d d1       # Delete database
```

The `db:prepare` command is the most common—it creates the database if needed, runs migrations, and seeds only if the database is fresh.

## Environment Variables

Database IDs are stored in `.env.local` and are environment-specific:

| Variable | Description |
|----------|-------------|
| `D1_DATABASE_ID` | D1 database ID (development) |
| `D1_DATABASE_ID_PRODUCTION` | D1 database ID (production) |
| `D1_DATABASE_ID_STAGING` | D1 database ID (staging) |

When you run `juntos db:create -e production`, the ID is saved to `D1_DATABASE_ID_PRODUCTION`. Commands fall back to `D1_DATABASE_ID` if the per-environment variable is not set.

For secrets:

```bash
wrangler secret put API_KEY
```

Access in code via `env.API_KEY`.

## D1 Specifics

### Bindings

D1 is accessed via bindings, not connection strings. The Worker receives the database as `env.DB`:

```javascript
// In the runtime
await env.DB.prepare("SELECT * FROM articles").all();
```

The Juntos adapter handles this automatically.

### SQL Dialect

D1 uses SQLite syntax. Most Rails migrations work, but some PostgreSQL-specific features won't:

- ✅ `create_table`, `add_column`, `add_index`
- ✅ Standard SQL types
- ❌ Arrays, JSONB (use JSON instead)
- ❌ PostgreSQL-specific functions

### Read Replicas

D1 automatically replicates reads to edge locations. Writes go to the primary. This is transparent to your application.

## Static Assets

Assets in `app/assets/` are served via Cloudflare's CDN:

```toml
[assets]
directory = "./app/assets"
```

For Tailwind CSS, ensure the built CSS is in `app/assets/builds/`.

## Troubleshooting

### "D1_ERROR: no such table"

Migrations haven't run:

```bash
bin/juntos db:migrate -d d1
```

### "Binding not found: DB"

The D1 database isn't bound. Check `wrangler.toml`:

```toml
[[d1_databases]]
binding = "DB"
database_name = "myapp_production"
database_id = "your-actual-id"  # Not ${D1_DATABASE_ID}
```

### Local development

Use Wrangler's local mode:

```bash
cd dist
wrangler dev
```

This runs locally with a local D1 instance.

## ISR (Incremental Static Regeneration)

Juntos supports ISR for pages that benefit from caching. Add a pragma comment to cache pages:

```ruby
# Pragma: revalidate 60

@posts = Post.all
__END__
<ul>
  <% @posts.each do |post| %>
    <li><%= post.title %></li>
  <% end %>
</ul>
```

The `revalidate` value is in seconds. The Cloudflare ISR adapter uses the Cache API:

- First request renders and caches the page
- Subsequent requests serve the cached version
- After the revalidate period, stale content is served while regenerating in the background via `waitUntil`

### How It Works

The adapter checks the cache, serves cached responses, and handles background regeneration:

```javascript
// Simplified - actual implementation in the adapter
const cache = caches.default;
let response = await cache.match(cacheKey);

if (response && age < revalidate) {
  return response;  // Fresh cache hit
}

if (response) {
  // Stale - serve and regenerate in background
  context.waitUntil(regenerate(context, cacheKey, renderFn));
  return response;
}

// Cache miss - generate and cache
return await regenerate(context, cacheKey, renderFn);
```

### On-Demand Revalidation

For immediate cache invalidation (e.g., after a content update):

```ruby
class ArticlesController < ApplicationController
  def update
    @article.update!(article_params)
    ISR.revalidate("/articles/#{@article.id}")
    redirect_to @article
  end
end
```

This deletes the cached page, forcing regeneration on the next request.

🧪 **Feedback requested** — [Share your experience](https://github.com/ruby2js/ruby2js/discussions)

## Durable Objects Mode

When using `do` as the database adapter, your entire application runs inside a Durable Object—app logic, SQLite database, and WebSocket connections are co-located in a single instance.

### Deployment

```bash
# Prepare database and deploy
bin/juntos deploy -d do
```

### Generated Files

#### wrangler.toml

```toml
name = "myapp"
main = "src/index.js"
compatibility_date = "2026-01-01"
compatibility_flags = ["nodejs_compat"]

[durable_objects]
bindings = [{ name = "APP", class_name = "DurableApp" }]

[[migrations]]
tag = "v1"
new_sqlite_classes = ["DurableApp"]

[assets]
directory = "./app/assets"
```

#### src/index.js

```javascript
import { Application, Router, DurableApp } from '../lib/rails.js';
import '../config/routes.js';
import { migrations } from '../db/migrate/index.js';
import { Seeds } from '../db/seeds.js';
import { layout } from '../app/views/layouts/application.js';

Application.configure({
  migrations: migrations,
  seeds: Seeds,
  layout: layout
});

export default Application.durableWorker();
export { DurableApp };
```

### Architecture

```
Request → Worker (thin router) → DurableApp {
                                   SQLite (state.storage.sql)
                                   App logic (controllers, models)
                                   WebSockets (Turbo Streams)
                                 }
```

The Worker is just a routing stub—all application logic runs inside the DO. This means:

- **Zero-latency database queries** — SQLite is in-process, no network hops
- **Built-in WebSockets** — Turbo Streams work without a separate broadcaster DO
- **Hibernation** — The DO sleeps between requests, paying nothing when idle
- **Isolated storage** — Each DO instance has its own database

### D1 vs DO

| Aspect | D1 | Durable Objects |
|--------|-----|-----------------|
| Database scope | Shared across all Workers | Private per DO instance |
| Query latency | Network round-trip | Zero (in-process) |
| WebSockets | Requires separate TurboBroadcaster DO | Built in |
| Cross-instance queries | Yes (it's one database) | No (each DO is isolated) |
| Hibernation | N/A (Worker is stateless) | Yes — sleeps between requests |
| Scaling model | One DB, many Workers | Many DOs, each with own DB |
| Backups | D1 time-travel UI | Manual |
| Best for | Traditional shared-database apps | Cell architecture, per-tenant isolation |

### When to Use DO

- **Per-tenant apps** — Each user, team, or event gets its own DO with isolated data
- **Real-time apps** — WebSockets and database in the same object, no coordination overhead
- **Offline-capable cells** — Small, self-contained databases that hibernate when idle
- **Conference demos** — The audience interacts with a live DO that has no traditional server

## Limitations

### D1 mode
- **No filesystem** — Use R2 for object storage
- **No WebSockets** — Use Durable Objects (TurboBroadcaster) or external services
- **CPU limits** — 10-50ms CPU time per request (not wall time)
- **Memory limits** — 128MB per Worker

### DO mode
- **No cross-instance queries** — Each DO has its own database
- **No D1 time-travel backups** — You manage durability
- **Single-threaded** — One request processed at a time per DO instance

## Comparison with Vercel

| Aspect | Cloudflare | Vercel |
|--------|------------|--------|
| Database | D1 or DO (SQLite) | Neon/Turso/PlanetScale |
| Edge locations | 300+ cities | ~20 regions |
| Pricing model | Requests + duration | Requests + compute |
| Static assets | Integrated CDN | Integrated CDN |
| Local dev | `wrangler dev` | `vercel dev` |

Choose Cloudflare for SQLite simplicity and maximum global distribution. Choose Vercel for PostgreSQL/MySQL compatibility or tighter Git integration.
