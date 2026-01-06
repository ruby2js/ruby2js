---
order: 640
title: Cloudflare Deployment
top_section: Juntos
category: juntos-deploying
---

# Deploying to Cloudflare Workers

Run your Rails app on Cloudflare's global network with D1 database.

{% toc %}

## Overview

Cloudflare Workers deployment runs your application on Cloudflare's edge network—over 300 cities worldwide. D1 is Cloudflare's native SQLite database, purpose-built for Workers.

**Use cases:**

- Global applications with SQLite simplicity
- Cloudflare ecosystem integration
- Edge computing with D1's read replicas
- Cost-effective serverless deployment

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
| `d1` | Cloudflare D1 | Native SQLite, recommended |
| `turso` | Turso | SQLite with sync, HTTP protocol |

D1 is the primary choice for Cloudflare deployments.

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

## Limitations

- **No filesystem** — Use R2 for object storage
- **No WebSockets** — Use Durable Objects or external services
- **CPU limits** — 10-50ms CPU time per request (not wall time)
- **Memory limits** — 128MB per Worker

## Comparison with Vercel

| Aspect | Cloudflare | Vercel |
|--------|------------|--------|
| Database | D1 (native SQLite) | Neon/Turso/PlanetScale |
| Edge locations | 300+ cities | ~20 regions |
| Pricing model | Requests + duration | Requests + compute |
| Static assets | Integrated CDN | Integrated CDN |
| Local dev | `wrangler dev` | `vercel dev` |

Choose Cloudflare for SQLite simplicity and maximum global distribution. Choose Vercel for PostgreSQL/MySQL compatibility or tighter Git integration.
