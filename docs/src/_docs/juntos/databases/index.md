---
order: 645
title: Databases
top_section: Juntos
category: juntos-databases
---

# Database Options

Juntos supports multiple databases for different deployment targets. Choose based on where you're deploying.

{% toc %}

## Quick Reference

| Database | Protocol | Best For | Free Tier |
|----------|----------|----------|-----------|
| [Neon](/docs/juntos/databases/neon) | HTTP | Vercel, PostgreSQL apps | 0.5 GB |
| [Turso](/docs/juntos/databases/turso) | HTTP | Edge, SQLite compatibility | 9 GB |
| [PlanetScale](/docs/juntos/databases/planetscale) | HTTP | MySQL apps, branching | 5 GB |
| [Supabase](/docs/juntos/databases/supabase) | HTTP | Full backend, real-time | 500 MB |

## Universal Databases

These databases use HTTP protocols, making them compatible with serverless and edge environments where TCP connections aren't available.

**Why HTTP matters:**

- **Serverless functions** can't maintain TCP connections between requests
- **Edge runtimes** (Vercel Edge, Cloudflare Workers) don't support TCP
- **Browsers** can only make HTTP requests

All four universal databases provide HTTP-based APIs that work everywhere JavaScript runs.

## Choosing a Database

### Neon

Best for teams already using PostgreSQL. Full PostgreSQL compatibility with serverless scaling.

```bash
bin/juntos up -d neon
```

**Pros:** PostgreSQL compatibility, branching for dev/staging, fast cold starts
**Cons:** Smallest free tier (0.5 GB)

### Turso

Best for edge-first applications. SQLite at the edge with global replication.

```bash
bin/juntos up -d turso
```

**Pros:** Largest free tier (9 GB), edge replication, SQLite familiarity
**Cons:** SQLite limitations (no concurrent writes, limited types)

### PlanetScale

Best for MySQL applications. Serverless MySQL with a Git-like branching workflow.

```bash
bin/juntos up -d planetscale
```

**Pros:** MySQL compatibility, branching workflow, good free tier
**Cons:** Some MySQL features disabled (foreign keys use application-level enforcement)

### Supabase

Best when you need more than just a database. Includes auth, storage, and real-time.

```bash
bin/juntos up -d supabase
```

**Pros:** Full backend platform, built-in real-time, auth included
**Cons:** Smallest free tier (500 MB), PostgREST has some limitations

## Default Target Inference

When you specify a universal database, Juntos defaults to Vercel deployment:

```bash
bin/juntos up -d neon        # → vercel target
bin/juntos up -d turso       # → vercel target
bin/juntos up -d planetscale # → vercel target
bin/juntos up -d supabase    # → vercel target
```

Override with `-t`:

```bash
bin/juntos up -t node -d neon   # Force Node.js runtime
```

## Environment Variables

All universal databases require credentials in `.env.local`:

```bash
# Neon
DATABASE_URL=postgres://user:pass@host/db

# Turso
TURSO_URL=libsql://db-org.turso.io
TURSO_TOKEN=eyJ...

# PlanetScale
PLANETSCALE_URL=mysql://user:pass@host/db

# Supabase
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
DATABASE_URL=postgres://...  # For migrations
```

See each database's guide for detailed setup instructions.

## Local Development

For local development, you have two options:

1. **Use the remote database** — Simple, but requires internet
2. **Use a local database** — Faster, works offline

```yaml
# config/database.yml
development:
  adapter: sqlite    # Local SQLite for dev
  database: db/development.sqlite3

production:
  adapter: neon      # Neon for production
```

The schema is the same across adapters, so you can develop locally with SQLite and deploy to Neon.
