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

## juntos db

Database management commands. Supports Rails-style colon syntax (`db:migrate`) or space syntax (`db migrate`).

```bash
bin/juntos db <command> [options]
bin/juntos db:command [options]
```

**Commands:**

| Command | Description |
|---------|-------------|
| `migrate` | Run database migrations |
| `seed` | Run database seeds |
| `prepare` | Migrate + seed if fresh database |
| `reset` | Drop, create, migrate, and seed |
| `create` | Create database (D1, Turso) |
| `drop` | Delete database (D1, Turso, SQLite) |

**Options:**

| Option | Description |
|--------|-------------|
| `-d, --database ADAPTER` | Database adapter (overrides database.yml) |
| `-e, --environment ENV` | Rails environment (default: development) |
| `-t, --target TARGET` | Target runtime |
| `-v, --verbose` | Show detailed output |
| `-h, --help` | Show help |

### db:migrate

Run database migrations.

```bash
bin/juntos db:migrate -d sqlite           # Local SQLite
bin/juntos db:migrate -d d1               # D1 via Wrangler
bin/juntos db:migrate -d neon             # Neon PostgreSQL
```

### db:seed

Run database seeds (always runs, unlike `prepare`).

```bash
bin/juntos db:seed -d sqlite              # Seed local SQLite
bin/juntos db:seed -d d1                  # Seed D1 database
```

### db:prepare

Smart setup: migrate + seed only if database is fresh (no existing tables).

```bash
bin/juntos db:prepare                     # Uses database.yml settings
bin/juntos db:prepare -d sqlite           # SQLite: migrate + seed if fresh
bin/juntos db:prepare -d d1               # D1: create + migrate + seed if fresh
bin/juntos db:prepare -e production       # Prepare production database
```

For D1, `db:prepare` also creates the database if `D1_DATABASE_ID` (or `D1_DATABASE_ID_PRODUCTION` for production) is not set.

### db:reset

Complete database reset: drop, create, migrate, and seed. Useful for development when you want a fresh start.

```bash
bin/juntos db:reset                       # Reset development database
bin/juntos db:reset -d d1                 # Reset D1 database
bin/juntos db:reset -e staging            # Reset staging database
```

**Warning:** This is destructive. D1 and Turso will prompt for confirmation before dropping.

### db:create

Create a new database. Support varies by adapter:

```bash
bin/juntos db:create -d d1                # Create D1 database via Wrangler
bin/juntos db:create -d turso             # Create Turso database via CLI
```

| Adapter | Support |
|---------|---------|
| D1 | Creates via Wrangler, saves ID to `.env.local` |
| Turso | Creates via `turso` CLI |
| SQLite | Created automatically by `db:migrate` |
| Neon, PlanetScale | Use their web console or CLI |
| Dexie | Created automatically in browser |

### db:drop

Delete a database. Support varies by adapter:

```bash
bin/juntos db:drop -d d1                  # Delete D1 database
bin/juntos db:drop -d turso               # Delete Turso database
bin/juntos db:drop -d sqlite              # Delete SQLite file
```

| Adapter | Support |
|---------|---------|
| D1 | Deletes via Wrangler |
| Turso | Deletes via `turso` CLI |
| SQLite | Deletes the `.sqlite3` file |
| Neon, PlanetScale | Use their web console or CLI |
| Dexie | Use browser DevTools |

### Environment Variables

For remote databases, credentials are read from `.env.local`:

```bash
# .env.local
DATABASE_URL=postgres://user:pass@host/db   # Neon, Turso, PlanetScale
D1_DATABASE_ID=xxxx-xxxx-xxxx               # Cloudflare D1 (development)
D1_DATABASE_ID_PRODUCTION=yyyy-yyyy-yyyy    # Cloudflare D1 (production)
D1_DATABASE_ID_STAGING=zzzz-zzzz-zzzz       # Cloudflare D1 (staging)
TURSO_URL=libsql://db-name.turso.io         # Turso
TURSO_TOKEN=your-token                       # Turso auth token
```

D1 database IDs are environment-specific. `juntos db:create -e production` saves to `D1_DATABASE_ID_PRODUCTION`, while development uses `D1_DATABASE_ID`. Commands fall back to `D1_DATABASE_ID` if the per-environment variable is not set.

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
| `D1_DATABASE_ID` | Cloudflare D1 database ID (development) |
| `D1_DATABASE_ID_PRODUCTION` | Cloudflare D1 database ID (production) |

## juntos info

Show current Juntos configuration.

```bash
bin/juntos info [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-v, --verbose` | Show detailed information (dependencies, D1 config) |
| `-h, --help` | Show help |

**Example output:**

```
Juntos Configuration
========================================

Environment:
  RAILS_ENV:        development (default)
  JUNTOS_DATABASE:  (not set)
  JUNTOS_TARGET:    (not set)

Database Configuration:
  config/database.yml (development):
    adapter:  d1
    database: myapp_development

Project:
  Directory: myapp
  Rails app: Yes
  ruby2js:   In Gemfile
  dist/:     Built
  Target:    Cloudflare (wrangler.toml present)
```

Use `--verbose` to also see D1 database IDs and installed dependencies.

## juntos doctor

Check environment and prerequisites for Juntos.

```bash
bin/juntos doctor
```

**What it checks:**

| Check | Requirement |
|-------|-------------|
| Ruby | 3.0+ required, 3.2+ recommended |
| Node.js | 18+ required, 22+ recommended |
| npm | Must be installed |
| Rails app | `app/` and `config/` directories |
| database.yml | Valid configuration |
| .env.local | D1 database ID (if using D1) |
| wrangler | Available (if using Cloudflare) |
| dist/ | Build status |

**Example output:**

```
Juntos Doctor
========================================

Checking Ruby... OK (3.4.0)
Checking Node.js... OK (v22.0.0)
Checking npm... OK (10.0.0)
Checking Rails app structure... OK
Checking config/database.yml... OK (d1)
Checking .env.local... OK (D1 configured)
Checking wrangler CLI... OK
Checking dist/ directory... OK (built)

========================================
All checks passed! Your environment is ready.
```

Issues are reported with actionable suggestions for how to fix them.
