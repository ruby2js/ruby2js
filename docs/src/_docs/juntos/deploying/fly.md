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

```bash
# Create a Postgres cluster
fly mpg create --name myapp-db

# This outputs connection details automatically
```

### Attach to App

```bash
# First, create your Fly app (if not already done)
cd dist
fly launch --no-deploy

# Attach database to app (sets DATABASE_URL automatically)
fly mpg attach myapp-db --app myapp
```

The `attach` command automatically sets the `DATABASE_URL` secret on your app.

### Local Development

Use the proxy command to connect to your remote database locally:

```bash
# Start proxy (runs in foreground)
fly mpg proxy myapp-db

# In another terminal, run migrations
DATABASE_URL=postgres://postgres:postgres@localhost:5432/myapp juntos db:migrate
```

Or use a local SQLite/Postgres for development:

```yaml
# config/database.yml
development:
  adapter: sqlite
  database: db/development.sqlite3

production:
  adapter: mpg
  # DATABASE_URL is set automatically by fly mpg attach
```

## Deployment

```bash
# Prepare database (migrate, seed if fresh)
juntos db:prepare -d mpg

# Deploy
juntos deploy -t fly -d mpg
```

The deploy command:

1. Builds the app with Fly.io configuration
2. Generates `fly.toml` and `Dockerfile`
3. Verifies the build loads correctly
4. Runs `fly deploy`

## Manual Deployment

If you prefer manual control:

```bash
# Build only
juntos build -t fly -d mpg

# Deploy with fly CLI
cd dist
fly deploy
```

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

Run your app locally with the Fly proxy:

```bash
# Terminal 1: Start database proxy
fly mpg proxy myapp-db

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
