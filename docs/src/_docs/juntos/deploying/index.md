---
order: 54
title: Deployment Overview
top_section: Juntos
category: juntos-deploying
---

# Deploying Juntos Applications

Juntos applications can deploy to any JavaScript runtime. Choose based on your needs.

{% toc %}

## Deployment Targets

| Target | Best For | Database Options |
|--------|----------|------------------|
| **[Browser](/docs/juntos/deploying/browser)** | Offline-first, demos, local-first | Dexie, sql.js, PGlite |
| **[Node.js](/docs/juntos/deploying/node)** | Traditional hosting, VPS, containers | SQLite, PostgreSQL, MySQL |
| **[Vercel](/docs/juntos/deploying/vercel)** | Serverless, global edge, auto-scaling | Neon, Turso, PlanetScale |
| **[Cloudflare](/docs/juntos/deploying/cloudflare)** | Edge computing, D1, maximum distribution | D1, Turso |

## Quick Comparison

| Aspect | Browser | Node.js | Vercel | Cloudflare |
|--------|---------|---------|--------|------------|
| Infrastructure | None (static) | Server/container | Serverless | Serverless |
| Scaling | N/A | Manual | Automatic | Automatic |
| Cold starts | None | N/A | ~50-250ms | ~5-50ms |
| Database | Client-side | TCP/file | HTTP APIs | D1 binding |
| Cost model | Hosting only | Server time | Per-request | Per-request |

## Choosing a Target

**Choose Browser if:**
- Your app works offline
- Data stays on the user's device
- You want zero infrastructure

**Choose Node.js if:**
- You need traditional server capabilities
- You're self-hosting or using containers
- You need TCP database connections

**Choose Vercel if:**
- You want serverless with PostgreSQL/MySQL
- You need Git-based deployments
- You're already in the Vercel ecosystem

**Choose Cloudflare if:**
- You want SQLite simplicity at scale
- You need maximum global distribution
- You're already using Cloudflare

## Default Target Inference

When you don't specify a target, Juntos infers it from your database:

```bash
bin/juntos up -d dexie      # → browser
bin/juntos up -d sqlite     # → node
bin/juntos up -d neon       # → vercel
bin/juntos up -d d1         # → cloudflare
```

Override with `-t`:

```bash
bin/juntos up -t node -d neon   # Force Node.js with Neon
```
