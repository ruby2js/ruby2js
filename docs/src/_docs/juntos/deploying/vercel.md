---
order: 635
title: Vercel Deployment
top_section: Juntos
category: juntos/deploying
hide_in_toc: true
---

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
| `supabase` | Supabase | HTTP | Full backend, real-time included |

All use HTTP protocols that work in edge environments (no TCP sockets).

See [Database Overview](/docs/juntos/databases) for detailed setup guides.

## Deployment

```bash
# Prepare database (migrate, seed if fresh)
bin/juntos db:prepare -d neon

# Deploy
bin/juntos deploy -d neon
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

## Real-Time Features

Vercel serverless functions can't maintain WebSocket connections. For Turbo Streams broadcasting (real-time updates), Juntos provides two solutions:

### Option 1: Supabase Database + Realtime

If you're using Supabase as your database, Juntos automatically uses Supabase Realtime:

```bash
bin/juntos deploy -d supabase
```

**Environment variables:**
```bash
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
DATABASE_URL=postgres://...  # For migrations
```

Broadcasts use Supabase's channel system. No additional setup required.

### Option 2: Any Database + Pusher

For Neon, Turso, or PlanetScale, use [Pusher](https://pusher.com) (Vercel's recommended real-time service):

```bash
bin/juntos deploy -d neon
```

**Environment variables:**
```bash
DATABASE_URL=postgres://...

# Pusher credentials
PUSHER_APP_ID=123456
PUSHER_KEY=abc123
PUSHER_SECRET=xyz789
PUSHER_CLUSTER=us2

# Client-side (prefixed for Next.js convention)
NEXT_PUBLIC_PUSHER_KEY=abc123
NEXT_PUBLIC_PUSHER_CLUSTER=us2
```

### How It Works

Your model code stays the same:

```ruby
class Message < ApplicationRecord
  after_create_commit do
    broadcast_append_to "chat_room",
      target: "messages",
      partial: "messages/message"
  end
end
```

Juntos routes broadcasts through the configured adapter:
- **Supabase** → `supabase.channel().send()`
- **Pusher** → `pusher.trigger()`

Clients subscribe the same way:

```erb
<%= turbo_stream_from "chat_room" %>
```

The adapter handles subscription and message delivery.

### Pusher Free Tier

Pusher's free tier includes:
- 200,000 messages/day
- 100 concurrent connections
- Unlimited channels

Sufficient for development and small apps.

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

The `revalidate` value is in seconds. Vercel handles caching automatically:

- First request renders and caches the page
- Subsequent requests serve the cached version
- After the revalidate period, Vercel serves stale content while regenerating in the background

### Cache-Control Headers

The ISR adapter sets appropriate headers:

```
Cache-Control: s-maxage=60, stale-while-revalidate=86400
```

This tells Vercel's edge cache to:
- Cache for 60 seconds
- Serve stale content for up to 24 hours while regenerating

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

🧪 **Feedback requested** — [Share your experience](https://github.com/ruby2js/ruby2js/discussions)

## Limitations

- **No filesystem writes** — Use object storage (Vercel Blob, S3)
- **No native WebSockets** — Use Pusher, Supabase Realtime, or Ably
- **30-second timeout** — Long operations need different architecture
- **Cold starts** — First request after idle may be slower

## Static Assets

Static assets in `app/assets/` are served directly by Vercel's CDN. The route configuration handles this:

```json
{ "src": "/app/assets/(.*)", "dest": "/app/assets/$1" }
```

For Tailwind CSS, the build process generates `app/assets/builds/tailwind.css`.
