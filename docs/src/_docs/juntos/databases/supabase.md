---
order: 654
title: Supabase
top_section: Juntos
category: juntos/databases
hide_in_toc: true
---

Supabase is an open-source Firebase alternative with PostgreSQL, auth, storage, and real-time built in.

{% toc %}

## Overview

| Feature | Value |
|---------|-------|
| Database | PostgreSQL 15 |
| Protocol | HTTP (PostgREST) |
| Free Tier | 500 MB storage, 2 projects |
| Best For | Full backend, real-time apps |

## Quick Start

### 1. Create Account

Sign up at [supabase.com](https://supabase.com) (GitHub login available).

### 2. Create Project

1. Click **New Project**
2. Choose organization
3. Name your project and set a database password
4. Choose a region close to your users
5. Wait for provisioning (~2 minutes)

### 3. Get Credentials

Go to **Project Settings** → **API**:

- **Project URL** — `https://xxx.supabase.co`
- **anon public key** — For client-side access

Go to **Project Settings** → **Database**:

- **Connection string** — For migrations (use URI format)

### 4. Configure Juntos

Add to `.env.local`:

```bash
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
DATABASE_URL=postgres://postgres:password@db.xxx.supabase.co:5432/postgres
```

### 5. Deploy

```bash
bin/juntos db:prepare -d supabase
bin/juntos deploy -d supabase
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `SUPABASE_URL` | Yes | Project URL |
| `SUPABASE_ANON_KEY` | Yes | Anonymous/public key |
| `DATABASE_URL` | Yes | Direct Postgres URL (for migrations) |

## Architecture

Supabase uses two connection methods:

1. **PostgREST (HTTP)** — For application queries via REST API
2. **Direct PostgreSQL** — For migrations and admin tasks

Juntos automatically uses:
- PostgREST for normal CRUD operations (works in serverless)
- Direct PostgreSQL for migrations (requires `DATABASE_URL`)

## Migrations

Since PostgREST doesn't support DDL (schema changes), migrations use a direct PostgreSQL connection:

```bash
# Runs via direct Postgres connection
bin/juntos db:migrate -d supabase
```

This requires `DATABASE_URL` to be set. In CI/CD, ensure this variable is available during build.

### Migration Files

Create migrations in `db/migrate/`:

```ruby
# db/migrate/001_create_messages.rb
class CreateMessages < ActiveRecord::Migration
  def up
    create_table :messages do |t|
      t.string :content, null: false
      t.string :room, null: false
      t.timestamps
    end
  end

  def down
    drop_table :messages
  end
end
```

## Real-Time Features

Supabase includes real-time subscriptions. Juntos automatically uses Supabase Realtime for Turbo Streams when deployed with Supabase:

```erb
<%# In your view %>
<%= turbo_stream_from "chat_room" %>
```

### How It Works

1. Server broadcasts to `chat_room` channel via Supabase Realtime
2. Client subscribes and receives updates
3. Turbo renders the stream automatically

### Configuration

Real-time is enabled by default. Juntos detects Supabase and configures the broadcast adapter automatically.

## Row Level Security (RLS)

Supabase encourages Row Level Security for authorization. Enable RLS on tables:

```sql
-- In a migration or Supabase SQL editor
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Allow anyone to read messages
CREATE POLICY "Messages are viewable by everyone"
  ON messages FOR SELECT
  USING (true);

-- Only authenticated users can insert
CREATE POLICY "Users can insert messages"
  ON messages FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');
```

### With Juntos

Since Juntos apps typically handle auth at the application layer, you might use broader policies:

```sql
-- Allow all operations (auth handled in app)
CREATE POLICY "Allow all" ON messages
  USING (true)
  WITH CHECK (true);
```

## Authentication

Supabase includes authentication, but Juntos apps typically implement their own auth. You can:

1. **Use Supabase Auth** — Integrate with `@supabase/supabase-js`
2. **Use application auth** — Handle in your Rails models/controllers

## Storage

Supabase includes object storage. Access via the Supabase client:

```javascript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_ANON_KEY
);

// Upload file
const { data, error } = await supabase.storage
  .from('avatars')
  .upload('public/avatar.png', file);
```

## Edge Functions

Supabase offers Deno-based edge functions. These are separate from Juntos—use them for:

- Webhooks
- Background jobs
- Third-party integrations

## Local Development

Supabase provides a local development stack:

```bash
# Install Supabase CLI
npm install -g supabase

# Start local stack
supabase start
```

This runs PostgreSQL, PostgREST, and other services locally.

### Local Environment

```bash
# .env.local for local development
SUPABASE_URL=http://localhost:54321
SUPABASE_ANON_KEY=your-local-anon-key
DATABASE_URL=postgres://postgres:postgres@localhost:54322/postgres
```

## Troubleshooting

### PostgREST errors

PostgREST returns structured errors. Common issues:

| Error | Cause | Fix |
|-------|-------|-----|
| `PGRST301` | Table doesn't exist | Run migrations |
| `PGRST204` | Column doesn't exist | Check schema |
| `42501` | Permission denied | Check RLS policies |

### Migration failures

Ensure `DATABASE_URL` uses the direct connection (port 5432), not the pooled connection (port 6543).

### Real-time not working

1. Verify Realtime is enabled in Supabase dashboard
2. Check that the table has REPLICA IDENTITY set:
   ```sql
   ALTER TABLE messages REPLICA IDENTITY FULL;
   ```

## Pricing

| Tier | Storage | Bandwidth | Price |
|------|---------|-----------|-------|
| Free | 500 MB | 2 GB/mo | $0 |
| Pro | 8 GB | 250 GB/mo | $25/mo |

The free tier includes 2 projects, sufficient for development and small apps.

## Resources

- [Supabase Documentation](https://supabase.com/docs)
- [PostgREST Documentation](https://postgrest.org)
- [Supabase Realtime](https://supabase.com/docs/guides/realtime)
- [Row Level Security](https://supabase.com/docs/guides/auth/row-level-security)
