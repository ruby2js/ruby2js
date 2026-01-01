---
order: 56
title: Vercel Deployment
top_section: Juntos
category: juntos-deploying
---

# Deploying to Vercel

Run your Rails app on Vercel's Edge Network with serverless databases.

{% toc %}

## Overview

Vercel deployment runs your application as serverless functions with global distribution. Requests hit the nearest edge location for low latency.

**Use cases:**

- Global applications needing low latency
- Pay-per-request pricing
- Automatic scaling
- Integration with Vercel's platform features

## Prerequisites

1. **Vercel CLI**
   ```bash
   npm i -g vercel
   vercel login
   ```

2. **Link project**
   ```bash
   cd your-rails-app
   vercel  # First run links the project
   ```

3. **Create database** — Choose one:
   - [Neon](https://neon.tech) — Serverless PostgreSQL
   - [Turso](https://turso.tech) — SQLite at the edge
   - [PlanetScale](https://planetscale.com) — Serverless MySQL

4. **Connect database**
   - Add `DATABASE_URL` to Vercel Environment Variables
   - Copy to `.env.local` for local migrations

## Database Options

| Adapter | Service | Protocol | Best For |
|---------|---------|----------|----------|
| `neon` | Neon | HTTP | PostgreSQL compatibility |
| `turso` | Turso | HTTP | SQLite, edge replication |
| `planetscale` | PlanetScale | HTTP | MySQL, branching workflow |

All use HTTP protocols that work in edge environments (no TCP sockets).

## Deployment

```bash
# Run migrations first
bin/juntos migrate -t vercel -d neon

# Deploy
bin/juntos deploy -t vercel -d neon
```

The deploy command:

1. Builds the app with Vercel configuration
2. Generates `vercel.json` and `api/[[...path]].js`
3. Verifies the build loads correctly
4. Runs `vercel --prod`

## Manual Deployment

If you prefer manual control:

```bash
# Build only
bin/juntos build -t vercel -d neon

# Deploy with Vercel CLI
cd dist
vercel --prod
```

## Generated Files

### vercel.json

```json
{
  "version": 2,
  "buildCommand": "npm run build",
  "outputDirectory": "dist",
  "routes": [
    { "src": "/app/assets/(.*)", "dest": "/app/assets/$1" },
    { "src": "/(.*)", "dest": "/api/[[...path]]" }
  ]
}
```

### api/[[...path]].js

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

export default Application.handler();

export const config = {
  runtime: 'edge'
};
```

## Environment Variables

Set these in Vercel Dashboard → Settings → Environment Variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `DATABASE_URL` | Neon connection string | `postgres://user:pass@host/db` |
| `TURSO_DATABASE_URL` | Turso database URL | `libsql://db-org.turso.io` |
| `TURSO_AUTH_TOKEN` | Turso auth token | `eyJ...` |

For local development, copy to `.env.local`:

```bash
# .env.local
DATABASE_URL=postgres://user:pass@host/db
```

## Edge vs Node Runtime

Juntos defaults to Edge runtime for Vercel. For Node.js runtime:

```bash
bin/juntos deploy -t vercel-node -d neon
```

**Edge runtime:**
- Faster cold starts (~50ms)
- Global distribution
- Limited Node.js APIs
- HTTP-only database connections

**Node.js runtime:**
- Full Node.js APIs
- TCP database connections possible
- Longer cold starts (~250ms)
- Fewer geographic locations

## Troubleshooting

### "Module not found" errors

```bash
# Clear cache and redeploy
bin/juntos deploy -t vercel -d neon --force
```

### Database connection errors

1. Verify `DATABASE_URL` is set in Vercel
2. Check database is accessible from Vercel's IPs
3. Ensure SSL mode is correct for your database

### Timeout errors

Edge functions have a 30-second limit. For long operations:

- Use background jobs (Inngest, Trigger.dev)
- Stream responses
- Break into smaller operations

## Limitations

- **No filesystem writes** — Use object storage (Vercel Blob, S3)
- **No WebSockets** — Use Pusher, Ably, or similar
- **30-second timeout** — Long operations need different architecture
- **Cold starts** — First request after idle may be slower

## Static Assets

Static assets in `app/assets/` are served directly by Vercel's CDN. The route configuration handles this:

```json
{ "src": "/app/assets/(.*)", "dest": "/app/assets/$1" }
```

For Tailwind CSS, the build process generates `app/assets/builds/tailwind.css`.
