---
order: 652
title: Turso
top_section: Juntos
category: juntos/databases
hide_in_toc: true
---

Turso is SQLite at the edge with global replication. Great for read-heavy apps needing low latency worldwide.

{% toc %}

## Overview

| Feature | Value |
|---------|-------|
| Database | SQLite (libSQL) |
| Protocol | HTTP |
| Free Tier | 9 GB storage, 500 databases |
| Best For | Edge apps, SQLite compatibility |

## Quick Start

### 1. Install Turso CLI

```bash
# macOS
brew install tursodatabase/tap/turso

# Linux/WSL
curl -sSfL https://get.tur.so/install.sh | bash
```

### 2. Sign Up and Login

```bash
turso auth signup    # Create account
turso auth login     # Or login if existing
```

### 3. Create Database

```bash
turso db create myapp
```

### 4. Get Credentials

```bash
turso db show myapp --url
turso db tokens create myapp
```

### 5. Configure Juntos

Add to `.env.local`:

```bash
TURSO_URL=libsql://myapp-yourorg.turso.io
TURSO_TOKEN=eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9...
```

### 6. Deploy

```bash
bin/juntos db:prepare -d turso
bin/juntos deploy -d turso
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `TURSO_URL` | Yes | Database URL (libsql://...) |
| `TURSO_TOKEN` | Yes | Authentication token |

## CLI Integration

Juntos integrates with the Turso CLI for database management:

```bash
# Create database
bin/juntos db:create -d turso

# Delete database
bin/juntos db:drop -d turso

# Migrate
bin/juntos db:migrate -d turso
```

Behind the scenes, `db:create` runs `turso db create` and saves credentials to `.env.local`.

## Edge Replication

Turso can replicate your database to multiple locations for lower latency:

```bash
# Add replica in Frankfurt
turso db replicate myapp fra

# Add replica in Sydney
turso db replicate myapp syd
```

### Location Codes

| Code | Location |
|------|----------|
| `iad` | Washington DC |
| `lhr` | London |
| `fra` | Frankfurt |
| `sin` | Singapore |
| `syd` | Sydney |
| `nrt` | Tokyo |

See full list: `turso db locations`

## Embedded Replicas

For even lower latency, Turso supports embedded replicas that sync to your application:

```javascript
// In lib/active_record.mjs
import { createClient } from '@libsql/client';

const db = createClient({
  url: 'file:local.db',
  syncUrl: process.env.TURSO_URL,
  authToken: process.env.TURSO_TOKEN,
});

// Sync on startup
await db.sync();
```

This keeps a local copy that syncs with the remote database.

## Migrations

Turso uses SQLite syntax. Create migrations in `db/migrate/`:

```ruby
# db/migrate/001_create_users.rb
class CreateUsers < ActiveRecord::Migration
  def up
    create_table :users do |t|
      t.string :email, null: false
      t.string :name
      t.timestamps
    end

    add_index :users, :email, unique: true
  end

  def down
    drop_table :users
  end
end
```

Run migrations:

```bash
bin/juntos db:migrate -d turso
```

## SQLite Limitations

Turso inherits SQLite limitations:

- **No concurrent writes** — Writes are serialized
- **Limited types** — TEXT, INTEGER, REAL, BLOB, NULL
- **No stored procedures** — Use application logic instead
- **No ENUM** — Use TEXT with CHECK constraints

### Type Mapping

| Ruby/Rails Type | SQLite Type |
|-----------------|-------------|
| string, text | TEXT |
| integer, bigint | INTEGER |
| float, decimal | REAL |
| boolean | INTEGER (0/1) |
| datetime | TEXT (ISO8601) |
| binary | BLOB |

## Groups and Organizations

Turso organizes databases into groups for billing and access control:

```bash
# Create a group
turso group create production

# Create database in group
turso db create myapp --group production

# Share access
turso group tokens create production
```

## Troubleshooting

### "SQLITE_BUSY" errors

SQLite only allows one writer at a time. For write-heavy apps, consider:

- Batching writes
- Using PostgreSQL (Neon) instead
- Implementing retry logic

### Token expired

Create a new token:

```bash
turso db tokens create myapp
```

Update `.env.local` and Vercel environment variables.

### Database not found

Verify the database exists:

```bash
turso db list
```

## Pricing

| Tier | Storage | Databases | Rows Read | Price |
|------|---------|-----------|-----------|-------|
| Starter | 9 GB | 500 | 1B/mo | $0 |
| Scaler | 24 GB | 10,000 | 100B/mo | $29/mo |

The free tier is very generous for most applications.

## Resources

- [Turso Documentation](https://docs.turso.tech)
- [Turso CLI Reference](https://docs.turso.tech/reference/turso-cli)
- [libSQL Client](https://docs.turso.tech/sdk/ts/quickstart)
