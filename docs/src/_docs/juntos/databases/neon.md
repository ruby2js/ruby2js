---
order: 651
title: Neon
top_section: Juntos
category: juntos/databases
hide_in_toc: true
---

Neon is serverless PostgreSQL with automatic scaling and branching. Great for teams familiar with PostgreSQL.

{% toc %}

## Overview

| Feature | Value |
|---------|-------|
| Database | PostgreSQL 15+ |
| Protocol | HTTP (serverless driver) |
| Free Tier | 0.5 GB storage, 1 compute branch |
| Best For | PostgreSQL apps, Vercel deployment |

## Quick Start

### 1. Create Account

Sign up at [neon.tech](https://neon.tech) (GitHub login available).

### 2. Create Project

1. Click **New Project**
2. Choose a region close to your users
3. Name your project (e.g., `myapp-production`)
4. Copy the connection string

### 3. Configure Juntos

Add to `.env.local`:

```bash
DATABASE_URL=postgres://user:password@ep-cool-name-123456.us-east-2.aws.neon.tech/neondb?sslmode=require
```

### 4. Deploy

```bash
bin/juntos db:prepare -d neon
bin/juntos deploy -d neon
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | Neon connection string |

Get your connection string from **Project Dashboard** → **Connection Details** → **Connection string**.

Make sure to select **Pooled connection** for serverless use.

## Database Branching

Neon supports Git-like branching for databases. Create branches for:

- **Development** — Experiment without affecting production
- **Staging** — Test with production-like data
- **Feature branches** — Isolate feature development

### Create a Branch

1. Go to **Branches** in Neon dashboard
2. Click **New Branch**
3. Select parent branch and point-in-time
4. Use the new connection string for that environment

### Using Branches with Juntos

```yaml
# config/database.yml
development:
  adapter: neon

staging:
  adapter: neon

production:
  adapter: neon
```

```bash
# .env.local (development branch)
DATABASE_URL=postgres://...@ep-dev-branch.../neondb

# .env.staging (staging branch)
DATABASE_URL=postgres://...@ep-staging-branch.../neondb

# Vercel env vars (production branch)
DATABASE_URL=postgres://...@ep-prod-branch.../neondb
```

## Migrations

Neon supports standard PostgreSQL DDL. Migrations run directly:

```bash
bin/juntos db:migrate -d neon
```

For production, migrations run during deployment via `db:prepare`.

## Connection Pooling

Neon provides two connection types:

- **Direct** — For migrations and admin tasks
- **Pooled** — For application queries (recommended for serverless)

Use the pooled connection string in your app. The URL contains `-pooler` in the hostname:

```
postgres://user:pass@ep-xxx-pooler.region.aws.neon.tech/db
```

## Compute Scaling

Neon automatically scales compute up and down:

- **Scale to zero** — No charges when idle
- **Auto-scaling** — Handles traffic spikes
- **Cold starts** — ~500ms to wake from zero

Configure in **Project Settings** → **Compute**:

- **Min compute size** — Minimum CU (0 for scale-to-zero)
- **Max compute size** — Maximum CU
- **Auto-suspend delay** — Time before scaling to zero

## Troubleshooting

### Connection timeout

Neon scales to zero after inactivity. First request may take 500ms+ to wake:

```bash
# Increase connection timeout in serverless
# Handled automatically by the Neon adapter
```

### SSL errors

Ensure `?sslmode=require` is in your connection string.

### Branch not found

Verify you're using the correct branch's connection string. Each branch has its own endpoint.

## Pricing

| Tier | Storage | Compute | Price |
|------|---------|---------|-------|
| Free | 0.5 GB | 1 branch | $0 |
| Pro | 10 GB+ | Unlimited branches | $19+/mo |

Free tier is sufficient for small apps and development.

## Resources

- [Neon Documentation](https://neon.tech/docs)
- [Neon + Vercel Integration](https://neon.tech/docs/guides/vercel)
- [Connection Pooling](https://neon.tech/docs/connect/connection-pooling)
