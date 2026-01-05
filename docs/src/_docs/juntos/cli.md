---
order: 610
title: CLI Reference
top_section: Juntos
category: juntos
---

# Juntos CLI Reference

The `juntos` command (via `bin/juntos`) provides commands for development, building, and deployment.

{% toc %}

## juntos dev

Start a development server for browser targets with hot reload.

```bash
bin/juntos dev [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-d, --database ADAPTER` | Database adapter (dexie, sqljs, pglite) |
| `-e, --environment ENV` | Rails environment (default: development) |
| `-p, --port PORT` | Server port (default: 3000) |
| `-v, --verbose` | Show detailed output |
| `-h, --help` | Show help |

**Examples:**

```bash
bin/juntos dev                    # Default: dexie adapter
bin/juntos dev -d sqljs           # SQLite in WebAssembly
bin/juntos dev -d pglite          # PostgreSQL in WebAssembly
bin/juntos dev -p 8080            # Custom port
bin/juntos dev -e test            # Use test environment from database.yml
```

**What it does:**

1. Builds the app to `dist/`
2. Starts a development server with hot module reloading
3. Watches Ruby files for changes and rebuilds automatically
4. Opens browser to http://localhost:3000

## juntos up

Build and start a server for Node.js/Bun/Deno targets.

```bash
bin/juntos up [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-t, --target TARGET` | Runtime target (node, bun, deno) |
| `-d, --database ADAPTER` | Database adapter |
| `-e, --environment ENV` | Rails environment (default: development) |
| `-p, --port PORT` | Server port (default: 3000) |
| `-v, --verbose` | Show detailed output |
| `-h, --help` | Show help |

**Examples:**

```bash
bin/juntos up -d sqlite           # Node.js with SQLite
bin/juntos up -t bun -d postgres  # Bun with PostgreSQL
bin/juntos up -e production       # Use production environment
```

**What it does:**

1. Builds the app to `dist/`
2. Starts the server using the specified runtime
3. Connects to the configured database

## juntos build

Build the app without starting a server.

```bash
bin/juntos build [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-t, --target TARGET` | Target (browser, node, bun, deno, vercel, cloudflare) |
| `-d, --database ADAPTER` | Database adapter |
| `-e, --environment ENV` | Rails environment (default: development) |
| `-v, --verbose` | Show detailed output |
| `-h, --help` | Show help |

**Examples:**

```bash
bin/juntos build -d dexie                # Browser build
bin/juntos build -e production           # Build for production environment
bin/juntos build -t vercel -d neon       # Vercel Edge build
bin/juntos build -t cloudflare -d d1     # Cloudflare Workers build
```

**Output:**

Creates the `dist/` directory containing:

- `app/` — Transpiled models, controllers, views
- `config/` — Routes and configuration
- `db/` — Migrations and seeds
- `lib/` — Runtime framework files
- `index.html` — Entry point (browser targets)
- `api/` or `src/` — Entry point (serverless targets)
- `package.json` — Dependencies

## juntos migrate

Run database migrations against a target.

```bash
bin/juntos migrate [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-t, --target TARGET` | Target platform |
| `-d, --database ADAPTER` | Database adapter |
| `-e, --environment ENV` | Rails environment (default: development) |
| `-v, --verbose` | Show detailed output |
| `-h, --help` | Show help |

**Examples:**

```bash
bin/juntos migrate -d sqlite              # Local SQLite
bin/juntos migrate -e production          # Migrate production database
bin/juntos migrate -d d1                  # D1 via Wrangler
```

**Environment:**

For remote databases, credentials are read from `.env.local`:

```bash
# .env.local
DATABASE_URL=postgres://user:pass@host/db   # Neon, Turso, PlanetScale
D1_DATABASE_ID=xxxx-xxxx-xxxx               # Cloudflare D1
```

## juntos deploy

Build and deploy to a serverless platform.

```bash
bin/juntos deploy [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-t, --target TARGET` | Deploy target (vercel, cloudflare) |
| `-d, --database ADAPTER` | Database adapter |
| `-e, --environment ENV` | Rails environment (default: production) |
| `--skip-build` | Use existing dist/ |
| `-f, --force` | Clear remote build cache |
| `-v, --verbose` | Show detailed output |
| `-h, --help` | Show help |

**Examples:**

```bash
bin/juntos deploy -e production       # Deploy production (adapter from database.yml)
bin/juntos deploy -d neon             # Vercel with Neon (target inferred)
bin/juntos deploy -d d1               # Cloudflare with D1 (target inferred)
bin/juntos deploy -d neon --force     # Clear cache and deploy
```

**What it does:**

1. Builds the app (unless `--skip-build`)
2. Generates platform configuration (vercel.json or wrangler.toml)
3. Verifies the build loads correctly
4. Runs the platform CLI (vercel or wrangler)

## Static Hosting

Browser builds (`dexie`, `sqljs`, `pglite`) produce static files in `dist/` that can be hosted anywhere. No server runtime required—the app runs entirely in the browser.

### Quick Start

```bash
bin/juntos build -d dexie
cd dist && npx serve -s
```

### Production Hosting

For traditional web servers, configure SPA fallback routing so client-side routes like `/articles/1` serve `index.html` instead of 404:

**nginx:**

```nginx
server {
    listen 80;
    root /path/to/dist;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

**Apache (.htaccess in dist/):**

```apache
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^ index.html [L]
```

**Static Hosts:**

- **GitHub Pages:** Push `dist/` contents to gh-pages branch, add a 404.html that's a copy of index.html
- **Netlify:** Add `_redirects` file: `/* /index.html 200`
- **Vercel:** Add `vercel.json`: `{"rewrites": [{"source": "/(.*)", "destination": "/index.html"}]}`
- **Cloudflare Pages:** Automatically handles SPA routing

## Database Adapters

| Adapter | Targets | Storage |
|---------|---------|---------|
| `dexie` | browser | IndexedDB |
| `sqljs` | browser | SQLite/WASM |
| `pglite` | browser, node | PostgreSQL/WASM |
| `sqlite` | node, bun | SQLite file |
| `pg` | node, bun, deno | PostgreSQL |
| `mysql2` | node, bun | MySQL |
| `neon` | node, vercel | Serverless PostgreSQL |
| `turso` | node, vercel | SQLite edge |
| `planetscale` | node, vercel | Serverless MySQL |
| `d1` | cloudflare | Cloudflare D1 |

## Default Targets

When target is not specified, it's inferred from the database:

| Database | Default Target |
|----------|---------------|
| dexie, sqljs, pglite | browser |
| sqlite, pg, mysql2 | node |
| neon, turso, planetscale | vercel |
| d1 | cloudflare |

## Configuration

### config/database.yml

```yaml
development:
  adapter: dexie
  database: blog_dev

production:
  adapter: neon
  target: vercel
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `JUNTOS_TARGET` | Override target |
| `JUNTOS_DATABASE` | Override database adapter |
| `DATABASE_URL` | Database connection string |
| `D1_DATABASE_ID` | Cloudflare D1 database ID |
