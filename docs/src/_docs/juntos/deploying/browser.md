---
order: 625
title: Browser Deployment
top_section: Juntos
category: juntos/deploying
hide_in_toc: true
---

Run your Rails app entirely in the browser with client-side storage.

{% toc %}

## Overview

Browser deployment creates a static site that runs your entire application client-side. Data is stored in the browser using IndexedDB or WebAssembly-based databases.

**Use cases:**

- Offline-first applications
- Local-first data ownership
- Demos and prototypes
- Apps that don't need server infrastructure

## Database Options

| Adapter | Storage | Best For |
|---------|---------|----------|
| `dexie` | IndexedDB | Most apps, best performance |
| `sqljs` | SQLite/WASM | SQL compatibility, smaller datasets |
| `pglite` | PostgreSQL/WASM | PostgreSQL features, larger apps |

## Development

```bash
bin/juntos dev -d dexie
```

This starts a development server with hot reload. Edit Ruby files and the browser refreshes automatically.

## Production Build

```bash
bin/juntos build -d dexie
```

Creates a static site in `dist/`:

```
dist/
├── index.html          # Entry point
├── app/                # Transpiled application
├── config/             # Routes and configuration
├── lib/                # Runtime
└── package.json        # Dependencies
```

## Deployment

Install dependencies and serve static files:

```bash
cd dist
npm install
npm start  # Uses 'serve' package
```

Or deploy to any static hosting:

- **Netlify:** Drop the `dist/` folder
- **GitHub Pages:** Push `dist/` to gh-pages branch
- **Vercel:** `vercel --prod` from `dist/`
- **S3/CloudFront:** Upload `dist/` contents

### Netlify Example

```bash
# netlify.toml in dist/
[build]
  publish = "."
  command = "npm install"

[[redirects]]
  from = "/*"
  to = "/index.html"
  status = 200
```

### GitHub Pages

```bash
cd dist
git init
git add .
git commit -m "Deploy"
git remote add origin git@github.com:user/repo.git
git push -f origin main:gh-pages
```

## Migrations

Browser migrations run automatically on startup. The schema is versioned in IndexedDB, and pending migrations apply when the app loads.

No manual migration step needed—the app self-upgrades.

## Data Persistence

Data persists in the browser:

- **IndexedDB (Dexie):** Survives browser restarts, ~50MB+ storage
- **sql.js:** In-memory by default, can persist to IndexedDB
- **PGlite:** Persists to IndexedDB

To clear data, use browser DevTools → Application → Storage → Clear site data.

## Limitations

- **No server-side logic** — Everything runs client-side
- **No email** — Can't send SMTP from browsers
- **Storage limits** — Browser quotas apply (~50MB-unlimited depending on browser)
- **No background jobs** — Use `setTimeout` or Web Workers

## Hybrid Approaches

For apps needing both offline and server sync:

1. Run browser target for offline capability
2. Sync data to a server when online
3. Use Turso or PGlite which support sync protocols

This is an advanced pattern not fully implemented yet.
