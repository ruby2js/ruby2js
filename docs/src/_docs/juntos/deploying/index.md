---
order: 620
title: Deployment Overview
top_section: Juntos
category: juntos-deploying
---

# Deploying Juntos Applications

Juntos unlocks platforms Rails can't reach—and works everywhere JavaScript runs.

{% toc %}

## Sweet Spots

These targets require transpilation. Rails can't run here; Juntos can:

| Target | Best For | Database Options |
|--------|----------|------------------|
| **[Browser](/docs/juntos/deploying/browser)** | Offline-first, local-first, demos | Dexie, sql.js, PGlite |
| **[Vercel Edge](/docs/juntos/deploying/vercel)** | Global edge, auto-scaling | Neon, Turso, PlanetScale |
| **[Cloudflare Workers](/docs/juntos/deploying/cloudflare)** | Edge computing, maximum distribution | D1, Turso |

## Also Works

For traditional hosting, Juntos works but Rails does too. Reasons to choose Juntos on Node.js:

- **npm ecosystem** — access to JavaScript libraries not available in Ruby
- **Event-driven model** — JavaScript's async I/O may suit some workloads better than Ruby's Global VM Lock (GVL)
- **Unified codebase** — one codebase across browser, edge, and server

| Target | Best For | Database Options |
|--------|----------|------------------|
| **[Node.js](/docs/juntos/deploying/node)** | VPS, containers, traditional hosting | SQLite, PostgreSQL, MySQL |

## Quick Comparison

| Aspect | Browser | Node.js | Vercel | Cloudflare |
|--------|---------|---------|--------|------------|
| Infrastructure | None (static) | Server/container | On-demand | On-demand |
| Scaling | N/A | Manual | Automatic | Automatic |
| Cold starts | None | N/A | ~50-250ms | ~5-50ms |
| Database | Client-side | TCP/file | HTTP APIs | D1 binding |
| Cost model | Hosting only | Server time | Per-request | Per-request |

## Choosing a Target

**Choose Browser if:**
- Your app works offline or local-first
- Data stays on the user's device
- You want zero infrastructure
- *Rails can't do this*

**Choose Vercel or Cloudflare if:**
- You want global edge distribution
- You need auto-scaling and pay-per-request
- You want fast cold starts (~5-50ms)
- *Rails can't do this*

**Choose Node.js if:**
- You need npm packages not available in Ruby
- Your workload benefits from JavaScript's event-driven async model
- You want one codebase across browser, edge, and server
- *Rails works here too—but Juntos has advantages*

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
