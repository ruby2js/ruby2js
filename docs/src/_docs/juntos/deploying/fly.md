---
order: 638
title: Fly.io
top_section: Juntos
category: juntos/deploying
hide_in_toc: true
---

Deploy your Rails app on Fly.io with Managed Postgres and a 100% CLI-driven workflow.

{% toc %}

## Overview

Fly.io runs your application in containers on their global network. Unlike edge platforms, Fly.io provides full Node.js compatibility with persistent connections and managed Postgres databases.

**Use cases:**

- Full Node.js compatibility (no edge runtime limitations)
- Managed Postgres with automatic failover
- CLI-driven workflow (no dashboard copying required)
- Global deployment with regional databases

## Prerequisites

1. **Fly CLI**
   ```bash
   # macOS/Linux
   curl -L https://fly.io/install.sh | sh

   # Or via Homebrew
   brew install flyctl
   ```

2. **Fly.io account**
   ```bash
   fly auth signup
   # or
   fly auth login
   ```

## Database Setup

Fly.io's Managed Postgres (MPG) provides a fully CLI-driven workflow. No dashboard copying required.

### Create Database

One command creates the Fly app, database, and connects them:

```bash
juntos db:create -d mpg
```

This automatically:
1. Creates a Fly app (named after your directory)
2. Creates an MPG Postgres database
3. Attaches the database to your app (sets `DATABASE_URL`)

### Run Migrations

For migrations, you need a local connection to your remote database:

```bash
# Terminal 1: Start the database proxy
fly mpg proxy myapp_production

# Terminal 2: Set DATABASE_URL and run migrations
# Add to .env.local:
#   DATABASE_URL=postgres://postgres:postgres@localhost:5432/myapp_production

juntos db:prepare -d mpg
```

### Local Development

Use a local SQLite for development to avoid cloud round-trips:

```yaml
# config/database.yml
development:
  adapter: sqlite
  database: db/development.sqlite3

production:
  adapter: mpg
  # DATABASE_URL is set automatically on Fly.io
```

## Deployment

The complete workflow uses only `juntos` commands:

```bash
# 1. Create app + database (one-time setup)
juntos db:create -d mpg

# 2. Start proxy for migrations (in separate terminal)
fly mpg proxy myapp_production

# 3. Run migrations
juntos db:prepare -d mpg

# 4. Deploy
juntos deploy -t fly -d mpg
```

The deploy command:

1. Builds the app with Fly.io configuration
2. Generates `fly.toml` and `Dockerfile`
3. Verifies the build loads correctly
4. Runs `fly deploy`

## Generated Files

### fly.toml

```toml
app = 'myapp'
primary_region = 'ord'

[build]

[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = 'stop'
  auto_start_machines = true
  min_machines_running = 0
  processes = ['app']

[[vm]]
  memory = '1gb'
  cpu_kind = 'shared'
  cpus = 1
```

### Dockerfile

```dockerfile
ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-slim AS base

WORKDIR /app
ENV NODE_ENV="production"

# Install build dependencies for native modules
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential pkg-config python-is-python3

COPY package*.json ./
RUN npm ci --include=dev

COPY . .

EXPOSE 3000
CMD [ "npm", "run", "start:node" ]
```

## Environment Variables

Environment variables are managed via the Fly CLI:

```bash
# Set a secret
fly secrets set MY_SECRET=value

# DATABASE_URL is set automatically by fly mpg attach
```

For local development, create `.env.local`:

```bash
# .env.local
DATABASE_URL=postgres://user:pass@localhost:5432/myapp
```

## Real-Time Features

Unlike edge platforms, Fly.io supports native WebSocket connections. Turbo Streams broadcasting works out of the box without external services.

```ruby
# app/models/message.rb
class Message < ApplicationRecord
  after_create_commit { broadcast_append_to "messages" }
end
```

## Database Commands

```bash
# Create database
juntos db:create -d mpg

# Run migrations
juntos db:migrate -d mpg

# Run seeds
juntos db:seed -d mpg

# Prepare (migrate + seed if fresh)
juntos db:prepare -d mpg

# Reset (drop, create, migrate, seed)
juntos db:reset -d mpg
```

## Local Development

For local development, we recommend using SQLite (see [Hybrid Development](/docs/juntos/deploying/#hybrid-development)).

If you need to test against your production database:

```bash
# Terminal 1: Start database proxy
fly mpg proxy myapp_production

# Terminal 2: Run your app
cd dist
DATABASE_URL=postgres://postgres:postgres@localhost:5432/myapp npm run start:node
```

## Comparison with Edge Platforms

| Aspect | Fly.io | Vercel Edge | Deno Deploy |
|--------|--------|-------------|-------------|
| Runtime | Node.js (full) | V8 Isolates | V8 Isolates |
| Cold starts | ~200-500ms | ~50-250ms | ~5-50ms |
| Database | MPG (Postgres), TCP | HTTP APIs only | HTTP APIs only |
| WebSockets | Native support | Via Pusher/etc | Via Pusher/etc |
| Pricing | Per-machine time | Per-request | Per-request |

Choose Fly.io when you need:
- Full Node.js compatibility
- Native WebSocket support
- Managed Postgres with TCP connections
- CLI-driven workflow without dashboard copying

Choose edge platforms when you need:
- Faster cold starts
- Pay-per-request pricing
- Global edge distribution

## Scaling

```bash
# Scale to multiple regions
fly scale count 2 --region ord,lax

# Scale memory
fly scale memory 2048

# View current scale
fly scale show
```

## Troubleshooting

### Database connection errors

1. Verify the database is attached:
   ```bash
   fly secrets list
   # Should show DATABASE_URL
   ```

2. Check database status:
   ```bash
   fly mpg status myapp-db
   ```

### Build errors

1. Check the build logs:
   ```bash
   fly logs
   ```

2. Test locally first:
   ```bash
   cd dist
   npm install
   npm run start:node
   ```

### Module not found

Ensure all dependencies are in `package.json`:
```bash
cd dist
npm install
node -e "import('./config/routes.js')"
```

## Resources

- [Fly.io Documentation](https://fly.io/docs/)
- [Fly MPG Reference](https://fly.io/docs/flyctl/mpg/)
- [Fly Postgres Guide](https://fly.io/docs/postgres/)
