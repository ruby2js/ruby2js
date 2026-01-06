---
order: 637
title: Deno Deploy
top_section: Juntos
category: juntos/deploying
hide_in_toc: true
---

Deploy your Rails app globally on Deno's edge network with serverless databases.

{% toc %}

## Overview

Deno Deploy runs your application as serverless functions on Deno's global edge network. Like Vercel Edge, it provides fast cold starts and automatic scaling.

**Use cases:**

- Global applications needing low latency
- Pay-per-request pricing
- Automatic scaling
- Deno/TypeScript native environment

## Prerequisites

1. **Deno CLI**
   ```bash
   # macOS
   brew install deno

   # Or via curl
   curl -fsSL https://deno.land/install.sh | sh
   ```

2. **deployctl CLI**
   ```bash
   deno install -Arf jsr:@deno/deployctl
   ```

3. **Deno Deploy account**
   - Sign up at [dash.deno.com](https://dash.deno.com)
   - Create a new project

4. **Create database** — Choose one:
   - [Neon](https://neon.tech) — Serverless PostgreSQL
   - [Turso](https://turso.tech) — SQLite at the edge
   - [PlanetScale](https://planetscale.com) — Serverless MySQL
   - [Supabase](https://supabase.com) — Full backend platform

## Database Options

| Adapter | Service | Protocol | Best For |
|---------|---------|----------|----------|
| `neon` | Neon | HTTP | PostgreSQL compatibility |
| `turso` | Turso | HTTP | SQLite, edge replication |
| `planetscale` | PlanetScale | HTTP | MySQL, branching workflow |
| `supabase` | Supabase | HTTP | Full backend, real-time included |

All use HTTP protocols that work in edge environments (no TCP sockets).

See [Database Overview](/docs/juntos/databases) for detailed setup guides.

## Deployment

```bash
# Prepare database (migrate, seed if fresh)
bin/juntos db:prepare -d neon

# Deploy
bin/juntos deploy -t deno-deploy -d neon
```

The deploy command:

1. Builds the app with Deno Deploy configuration
2. Generates `main.ts` entry point and `deno.json`
3. Verifies the build loads correctly
4. Runs `deployctl deploy`

## Manual Deployment

If you prefer manual control:

```bash
# Build only
bin/juntos build -t deno-deploy -d neon

# Deploy with deployctl
cd dist
deployctl deploy --project=myapp main.ts
```

## Generated Files

### main.ts

```typescript
// Deno Deploy entry point
import { Application, Router } from './lib/rails.js';
import './config/routes.js';
import { migrations } from './db/migrate/index.js';
import { Seeds } from './db/seeds.js';
import { layout } from './app/views/layouts/application.js';

Application.configure({
  migrations: migrations,
  seeds: Seeds,
  layout: layout
});

Deno.serve(Application.handler());
```

### deno.json

```json
{
  "name": "myapp",
  "tasks": {
    "start": "deno run --allow-net --allow-env --allow-read main.ts"
  }
}
```

## Environment Variables

Set these in Deno Deploy Dashboard → Project Settings → Environment Variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `DATABASE_URL` | Neon/Supabase connection string | `postgres://user:pass@host/db` |
| `TURSO_URL` | Turso database URL | `libsql://db-org.turso.io` |
| `TURSO_TOKEN` | Turso auth token | `eyJ...` |

For local development, create `.env.local`:

```bash
# .env.local
DATABASE_URL=postgres://user:pass@host/db
```

## Real-Time Features

Like Vercel, Deno Deploy can't maintain native WebSocket connections across requests. For Turbo Streams broadcasting, Juntos uses:

- **Supabase Realtime** — If using Supabase as your database
- **Pusher** — For other databases (Neon, Turso, PlanetScale)

```bash
# Supabase: real-time included
bin/juntos deploy -t deno-deploy -d supabase

# Other databases: add Pusher credentials
bin/juntos deploy -t deno-deploy -d neon
```

For Pusher, add environment variables:

```bash
PUSHER_APP_ID=123456
PUSHER_KEY=abc123
PUSHER_SECRET=xyz789
PUSHER_CLUSTER=us2
```

## Local Development

Test locally before deploying:

```bash
cd dist
deno task start
```

Or use Deno's built-in server:

```bash
deno run --allow-net --allow-env --allow-read main.ts
```

## Troubleshooting

### "Module not found" errors

Deno uses URL imports. Ensure all dependencies are available:

```bash
# Check imports resolve
deno check main.ts
```

### Database connection errors

1. Verify environment variables are set in Deno Deploy
2. Check database is accessible (no IP restrictions)
3. Ensure SSL mode is correct for your database

### Permission errors

Deno is secure by default. The entry point needs:

- `--allow-net` — Network access for database and HTTP
- `--allow-env` — Read environment variables
- `--allow-read` — Read local files

## Comparison with Vercel

| Aspect | Deno Deploy | Vercel Edge |
|--------|-------------|-------------|
| Runtime | Deno | V8 Isolates |
| Language | TypeScript/JavaScript | JavaScript |
| Cold starts | ~5-50ms | ~50-250ms |
| Database | HTTP APIs | HTTP APIs |
| WebSockets | Via Pusher/Supabase | Via Pusher/Supabase |
| CLI | deployctl | vercel |

Both are excellent choices for edge deployment. Choose based on your preference for Deno vs Node.js ecosystem.

## Limitations

- **No filesystem writes** — Use object storage
- **No native WebSockets** — Use Pusher, Supabase Realtime, or Ably
- **Request timeout** — 50 second limit on Deno Deploy
- **Cold starts** — First request after idle may be slower

## Resources

- [Deno Deploy Documentation](https://docs.deno.com/deploy/manual/)
- [deployctl Reference](https://docs.deno.com/deploy/manual/deployctl)
- [Deno Deploy Pricing](https://deno.com/deploy/pricing)
