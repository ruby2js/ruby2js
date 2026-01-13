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

Build and run a server locally. Supports all targets including browser.

```bash
bin/juntos up [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-t, --target TARGET` | Runtime target (browser, node, bun, deno) |
| `-d, --database ADAPTER` | Database adapter |
| `-e, --environment ENV` | Rails environment (default: development) |
| `-p, --port PORT` | Server port (default: 3000) |
| `-v, --verbose` | Show detailed output |
| `--sourcemap` | Generate source maps |
| `-h, --help` | Show help |

**Examples:**

```bash
bin/juntos up -d dexie            # Browser with IndexedDB
bin/juntos up -d sqlite           # Node.js with SQLite
bin/juntos up -t bun -d postgres  # Bun with PostgreSQL
bin/juntos up -e production       # Production build (bundled, minified)
```

**What it does:**

1. Builds the app to `dist/`
2. For browser targets: runs Vite production build (bundles, tree-shakes, fingerprints)
3. Starts a static server (browser) or runtime server (Node/Bun/Deno)
4. Connects to the configured database

## juntos build

Build the app without starting a server.

```bash
bin/juntos build [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-t, --target TARGET` | Target (browser, node, bun, deno, vercel, cloudflare, capacitor, electron, tauri) |
| `-d, --database ADAPTER` | Database adapter |
| `-e, --environment ENV` | Rails environment (default: development) |
| `-v, --verbose` | Show detailed output |
| `--sourcemap` | Generate source maps |
| `-h, --help` | Show help |

**Examples:**

```bash
bin/juntos build -d dexie                # Browser build
bin/juntos build -e production           # Build for production environment
bin/juntos build -t vercel -d neon       # Vercel Edge build
bin/juntos build -t cloudflare -d d1     # Cloudflare Workers build
bin/juntos build -t capacitor -d dexie   # Mobile app (iOS/Android)
bin/juntos build -t electron -d sqlite   # Desktop app (macOS/Windows/Linux)
bin/juntos build -t tauri -d sqljs       # Lightweight desktop app
bin/juntos build -e production --sourcemap  # Production with source maps
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
- `assets/` — Bundled JS/CSS with fingerprinted filenames (production builds)

**Production vs Development:**

The build mode is derived from `RAILS_ENV` or `NODE_ENV`:

- **Development** (default): Unbundled modules, fast rebuilds
- **Production** (`-e production`): Vite bundles, tree-shakes, minifies, and fingerprints assets

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
| `--sourcemap` | Generate source maps |
| `-h, --help` | Show help |

**Examples:**

```bash
bin/juntos deploy -e production       # Deploy production (adapter from database.yml)
bin/juntos deploy -d neon             # Vercel with Neon (target inferred)
bin/juntos deploy -d d1               # Cloudflare with D1 (target inferred)
bin/juntos deploy -d neon --force     # Clear cache and deploy
bin/juntos deploy --sourcemap         # Deploy with source maps for debugging
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
| `dexie` | browser, capacitor | IndexedDB |
| `sqljs` | browser, capacitor, electron, tauri | SQLite/WASM |
| `pglite` | browser, node, tauri | PostgreSQL/WASM |
| `sqlite` | node, bun, electron | SQLite file |
| `pg` | node, bun, deno | PostgreSQL |
| `mysql2` | node, bun | MySQL |
| `neon` | node, vercel, capacitor, electron, tauri | Serverless PostgreSQL |
| `turso` | node, vercel, capacitor, electron, tauri | SQLite edge |
| `planetscale` | node, vercel, capacitor, electron, tauri | Serverless MySQL |
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

### config/ruby2js.yml

Configure Ruby2JS transpilation options. Supports environment-specific and section-specific settings.

```yaml
# Base configuration inherited by all environments
default: &default
  eslevel: 2022
  include:
    - class
    - call
  autoexports: true
  comparison: identity

# Environment-specific overrides
development:
  <<: *default

production:
  <<: *default
  strict: true

# Section-specific configuration
components:
  <<: *default
  filters:
    - phlex
    - functions
    - esm
```

**Supported sections:**

| Section | Directory | Purpose |
|---------|-----------|---------|
| `controllers` | `app/controllers/` | Rails controllers |
| `components` | `app/components/` | Phlex view components |
| `stimulus` | `app/javascript/controllers/` | Stimulus controllers |

Section config overrides the environment config for files in that directory.

**Using preset mode:**

```yaml
# Preset enables: functions, esm, pragma, return + ES2022 + identity comparison
preset: true

# Add extra filters on top of preset
filters:
  - camelCase

# Remove specific filters from preset
disable_filters:
  - return
```

**Available options:**

| Option | Type | Description |
|--------|------|-------------|
| `preset` | boolean | Enable preset configuration |
| `eslevel` | integer | ECMAScript target (2020-2025) |
| `filters` | array | Filters to apply |
| `disable_filters` | array | Filters to remove from preset |
| `autoexports` | boolean/string | Auto-export declarations (true, false, "default") |
| `comparison` | string | "equality" or "identity" |
| `include` | array | Methods to opt-in for conversion |
| `exclude` | array | Methods to exclude |
| `strict` | boolean | Add "use strict" directive |
| `dependencies` | object | NPM packages to add to generated package.json |
| `external` | array | Modules to externalize (not bundled, resolved at runtime) |

**Build configuration:**

```yaml
# Add npm dependencies to the generated package.json
# These are installed and bundled by Vite
dependencies:
  "@capacitor/camera": "^6.0.0"
  "chart.js": "^4.0.0"

# Externalize modules (resolve at runtime, not bundled)
# Use for CDN-loaded libraries or platform-provided modules
external:
  - "react"
  - "react-dom"
```

**Available filters:**

`functions`, `esm`, `cjs`, `return`, `erb`, `pragma`, `camelCase`, `tagged_templates`, `phlex`, `stimulus`, `active_support`, `securerandom`, `nokogiri`, `haml`, `jest`, `rails/model`, `rails/controller`, `rails/routes`, `rails/seeds`, `rails/helpers`, `rails/migration`

See [Ruby2JS Options](/docs/options) for the full list of transpilation options.

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
