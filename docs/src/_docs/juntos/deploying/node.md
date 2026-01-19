---
order: 630
title: Server Runtimes
top_section: Juntos
category: juntos/deploying
hide_in_toc: true
---

Run your Rails app on Node.js, Bun, or Deno with traditional server databases.

{% toc %}

## Overview

Server deployment runs your application on a JavaScript runtime with access to server-side databases. This is closest to traditional Rails deployment.

**Use cases:**

- Traditional web applications
- Apps requiring server-side processing
- Integration with npm ecosystem (Puppeteer, LangChain, etc.)
- Self-hosted deployment

## Runtime Options

| Runtime | Command | Notes |
|---------|---------|-------|
| Node.js | `bin/juntos up -t node` | Default, widest compatibility |
| Bun | `bin/juntos up -t bun` | Faster startup, native SQLite |
| Deno | `bin/juntos up -t deno` | Secure by default, TypeScript |

## Database Options

| Adapter | Databases | Notes |
|---------|-----------|-------|
| `sqlite` | SQLite file | Simple, no server needed |
| `pg` | PostgreSQL | Full-featured, production-ready |
| `mysql2` | MySQL/MariaDB | Wide hosting support |

## Development

```bash
bin/juntos up -d sqlite
```

This builds the app and starts a server on port 3000.

## Database Setup

Prepare the database before starting the server:

```bash
bin/juntos db:prepare -d sqlite
bin/juntos up -d sqlite
```

For remote databases:

```bash
# Set connection string in .env.local
echo "DATABASE_URL=postgres://user:pass@host/db" >> .env.local

bin/juntos db:prepare -d pg
bin/juntos up -d pg
```

The `db:prepare` command runs migrations and seeds if the database is fresh.

## Production Build

```bash
bin/juntos build -t node -d pg
```

Creates a deployable application in `dist/`:

```bash
cd dist
npm install
node lib/rails.js  # Or use package.json scripts
```

## Deployment Options

### Docker

```dockerfile
FROM node:22-slim

WORKDIR /app
COPY dist/ .
RUN npm install --production

EXPOSE 3000
CMD ["node", "lib/rails.js"]
```

```bash
docker build -t myapp .
docker run -p 3000:3000 -e DATABASE_URL=... myapp
```

### Fly.io

```bash
cd dist
fly launch
fly deploy
```

### Railway / Render

1. Push `dist/` to a Git repository
2. Connect the repository to the platform
3. Set `DATABASE_URL` environment variable
4. Deploy

### Traditional VPS

```bash
# On server
git clone your-repo
cd your-repo/dist
npm install --production
DATABASE_URL=... node lib/rails.js
```

Use PM2 or systemd for process management:

```bash
npm install -g pm2
pm2 start lib/rails.js --name myapp
pm2 save
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `PORT` | Server port (default: 3000) |
| `DATABASE_URL` | Database connection string |
| `NODE_ENV` | Environment (development/production) |

## Configuration

### config/database.yml

```yaml
development:
  adapter: sqlite3
  database: db/development.sqlite3

production:
  adapter: pg
  url: <%= ENV['DATABASE_URL'] %>
```

The adapter is selected at build time. Different environments can use different adapters by building with the appropriate configuration.

## npm Ecosystem

Server targets can use the full npm ecosystem:

```javascript
// In a controller or service
import puppeteer from 'puppeteer';
import { ChatOpenAI } from 'langchain/chat_models/openai';

// Generate PDFs, call LLMs, etc.
```

Add dependencies to `dist/package.json` after building, or maintain a separate package.json that gets merged during build.

## ISR Caching

Server deployments can use in-memory ISR for data caching:

```ruby
import ['withRevalidate', 'invalidate'], from: '../lib/isr.js'

# Cache data for 60 seconds
posts = await withRevalidate('posts:all', 60, -> { Post.all })

# Invalidate on mutations
invalidate('posts:all')
```

The in-memory cache reduces database load for frequently accessed data. See the [ISR documentation](/docs/juntos/isr) for details.

## Performance

- **Cold start:** ~100-500ms depending on app size
- **Request handling:** Similar to Express.js
- **Memory:** Depends on database connection pooling

For high-traffic applications, consider:

- Connection pooling (pg-pool, mysql2 pooling)
- Clustering (PM2 cluster mode)
- Caching (Redis, in-memory ISR)
