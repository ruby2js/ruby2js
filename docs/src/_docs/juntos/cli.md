---
order: 610
title: CLI Reference
top_section: Juntos
category: juntos
---

# Juntos CLI Reference

The `juntos` command provides Rails-like commands for development, testing, building, and deployment. It can be invoked via:

- `npx juntos` — Run from anywhere (auto-installs required packages)
- `bin/juntos` — Binstub in Rails projects (delegates to npx)

The CLI automatically installs required npm packages based on your options. For example, `juntos dev -d dexie` installs `dexie` if not present.

{% toc %}

## Getting Started

### Install a Demo

Download and set up a complete demo application:

```bash
npx github:ruby2js/juntos --demo blog           # Install blog demo
npx github:ruby2js/juntos --demo blog my-blog   # Install to my-blog/
npx github:ruby2js/juntos --list-demos          # List all demos
```

Available demos: `blog`, `chat`, `notes`, `photo-gallery`, `workflow`, `ssg-blog`, `astro-blog`

### Initialize in Existing Project

Add Juntos to an existing project:

```bash
npx github:ruby2js/juntos init              # Current directory
npx github:ruby2js/juntos init my-app       # Specific directory
```

This creates the configuration files needed for Juntos:
- `package.json` (or merges dependencies into existing)
- `vite.config.js`
- `vitest.config.js`
- `test/setup.mjs`
- `bin/juntos`

## juntos dev

Start a development server with hot reload.

```bash
npx juntos dev [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-d, --database ADAPTER` | Database adapter (dexie, sqlite, pglite, etc.) |
| `-p, --port PORT` | Server port (default: 5173) |
| `-o, --open` | Open browser automatically |
| `-h, --help` | Show help |

**Examples:**

```bash
npx juntos dev                    # Uses database.yml settings
npx juntos dev -d dexie           # Browser with IndexedDB
npx juntos dev -d sqlite          # Node.js with SQLite
npx juntos dev -p 8080            # Custom port
npx juntos dev -o                 # Open browser automatically
```

**What it does:**

1. Loads database configuration (from `-d` flag or `config/database.yml`)
2. Installs required packages if missing (e.g., `dexie` for IndexedDB)
3. Starts Vite dev server with hot module reloading
4. Watches Ruby files for changes and retranspiles automatically

## juntos test

Run tests with Vitest.

```bash
npx juntos test [options] [files...]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-d, --database ADAPTER` | Database adapter for tests |
| `-h, --help` | Show help |

**Examples:**

```bash
npx juntos test                        # Run all tests
npx juntos test articles.test.mjs      # Run specific test file
npx juntos test -d sqlite              # Run tests with SQLite
npx juntos test test/models/           # Run tests in directory
```

**What it does:**

1. Loads database configuration
2. Installs vitest and database packages if missing
3. Runs `vitest run` with any additional arguments passed through

This mirrors `bin/rails test` — tests can be run with Rails (`bin/rails test`), with Juntos (`npx juntos test`), or directly with Vitest (`npx vitest`).

## juntos build

Build the app for deployment.

```bash
npx juntos build [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-d, --database ADAPTER` | Database adapter |
| `-t, --target TARGET` | Build target (browser, node, bun, vercel, cloudflare) |
| `-e, --environment ENV` | Environment (default: development) |
| `--sourcemap` | Generate source maps |
| `--base PATH` | Base public path for assets (e.g., `/demos/blog/`) |
| `-h, --help` | Show help |

**Examples:**

```bash
npx juntos build -d dexie                # Browser build
npx juntos build -e production           # Production (bundled, minified)
npx juntos build -t vercel -d neon       # Vercel Edge build
npx juntos build -t cloudflare -d d1     # Cloudflare Workers build
npx juntos build -d dexie --base /app/   # Serve from subdirectory
npx juntos build --sourcemap             # Include source maps
```

**Output:**

Creates the `dist/` directory containing the built application. Production builds (`-e production`) are bundled, tree-shaken, minified, and fingerprinted by Vite.

## juntos up

Build and run locally. Combines `build` and `server` in one command.

```bash
npx juntos up [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-d, --database ADAPTER` | Database adapter |
| `-t, --target TARGET` | Runtime target (browser, node, bun, deno) |
| `-p, --port PORT` | Server port (default: 3000) |
| `-h, --help` | Show help |

**Examples:**

```bash
npx juntos up -d dexie            # Browser with IndexedDB
npx juntos up -d sqlite           # Node.js with SQLite
npx juntos up -t bun -d postgres  # Bun with PostgreSQL
```

**What it does:**

1. Builds the app to `dist/`
2. Starts a preview server (browser) or runtime server (Node/Bun/Deno)

## juntos server

Start production server (requires prior build).

```bash
npx juntos server [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-t, --target TARGET` | Runtime target (browser, node, bun, deno) |
| `-p, --port PORT` | Server port (default: 3000) |
| `-e, --environment ENV` | Environment (default: production) |
| `-h, --help` | Show help |

**Examples:**

```bash
npx juntos server                 # Start preview server
npx juntos server -t node         # Start Node.js server
npx juntos server -p 8080         # Custom port
```

## juntos db

Database management commands. Supports Rails-style colon syntax (`db:migrate`) or space syntax (`db migrate`).

```bash
npx juntos db <command> [options]
npx juntos db:command [options]
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
| `-e, --environment ENV` | Environment (default: development) |
| `-h, --help` | Show help |

### db:migrate

Run database migrations.

```bash
npx juntos db:migrate -d sqlite           # Local SQLite
npx juntos db:migrate -d d1               # D1 via Wrangler
npx juntos db:migrate -d neon             # Neon PostgreSQL
```

### db:seed

Run database seeds (always runs, unlike `prepare`).

```bash
npx juntos db:seed -d sqlite              # Seed local SQLite
npx juntos db:seed -d d1                  # Seed D1 database
```

### db:prepare

Smart setup: migrate + seed only if database is fresh (no existing tables).

```bash
npx juntos db:prepare                     # Uses database.yml settings
npx juntos db:prepare -d sqlite           # SQLite: migrate + seed if fresh
npx juntos db:prepare -d d1               # D1: create + migrate + seed if fresh
```

### db:reset

Complete database reset: drop, create, migrate, and seed.

```bash
npx juntos db:reset                       # Reset development database
npx juntos db:reset -d d1                 # Reset D1 database
```

**Warning:** This is destructive. D1 and Turso will prompt for confirmation before dropping.

### db:create / db:drop

Create or delete databases. Support varies by adapter:

| Adapter | Support |
|---------|---------|
| D1 | Creates/deletes via Wrangler, saves ID to `.env.local` |
| Turso | Creates/deletes via `turso` CLI |
| SQLite | File created automatically, deleted with `db:drop` |
| Dexie | Created automatically in browser |

## juntos deploy

Build and deploy to a serverless platform.

```bash
npx juntos deploy [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-t, --target TARGET` | Deploy target (vercel, cloudflare) |
| `-d, --database ADAPTER` | Database adapter |
| `-e, --environment ENV` | Environment (default: production) |
| `--skip-build` | Use existing dist/ |
| `-f, --force` | Clear remote build cache |
| `--sourcemap` | Generate source maps |
| `-h, --help` | Show help |

**Examples:**

```bash
npx juntos deploy -d neon             # Vercel with Neon (target inferred)
npx juntos deploy -d d1               # Cloudflare with D1 (target inferred)
npx juntos deploy -t vercel -d neon   # Explicit target
npx juntos deploy --force             # Clear cache and deploy
```

**What it does:**

1. Builds the app (unless `--skip-build`)
2. Generates platform configuration (vercel.json or wrangler.toml)
3. Verifies the build loads correctly
4. Runs the platform CLI (vercel or wrangler)

## juntos info

Show current Juntos configuration.

```bash
npx juntos info [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-v, --verbose` | Show detailed information |
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
    adapter:  dexie
    database: blog_dev

Project:
  Directory:    blog
  Rails app:    Yes
  node_modules: Installed
  dist/:        Not built
```

## juntos doctor

Check environment and prerequisites.

```bash
npx juntos doctor
```

**What it checks:**

| Check | Requirement |
|-------|-------------|
| Node.js | 18+ required |
| npm | Must be installed |
| Rails app | `app/` and `config/` directories |
| database.yml | Valid configuration |
| vite.config.js | Present |
| node_modules | Dependencies installed |
| dist/ | Build status |

## Database Adapters

The CLI auto-installs the required npm package for each adapter:

| Adapter | npm Package | Targets |
|---------|-------------|---------|
| `dexie` | dexie | browser |
| `sqlite` | better-sqlite3 | node, bun |
| `sqljs` | sql.js | browser |
| `pglite` | @electric-sql/pglite | browser, node |
| `pg` | pg | node, bun, deno |
| `neon` | @neondatabase/serverless | vercel, node |
| `turso` | @libsql/client | vercel, node |
| `d1` | (none - Cloudflare binding) | cloudflare |
| `mysql` | mysql2 | node, bun |

**Aliases:** Common variations are accepted automatically:
- `indexeddb` → dexie
- `sqlite3`, `better_sqlite3` → sqlite
- `sql.js` → sqljs
- `postgres`, `postgresql` → pg
- `mysql2` → mysql

This means existing Rails apps with `adapter: sqlite3` in `database.yml` work without changes.

## Default Targets

When target is not specified, it's inferred from the database:

| Database | Default Target |
|----------|---------------|
| dexie, sqljs, pglite | browser |
| sqlite, pg, mysql | node |
| neon, turso | vercel |
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

Environment variables in `.env.local` are automatically loaded.

## Static Hosting

Browser builds (`dexie`, `sqljs`, `pglite`) produce static files that can be hosted anywhere:

```bash
npx juntos build -d dexie
cd dist && npx serve -s
```

For subdirectory hosting, use `--base`:

```bash
npx juntos build -d dexie --base /myapp/
```

Configure SPA fallback routing so client-side routes serve `index.html`:

- **Netlify:** Add `_redirects`: `/* /index.html 200`
- **Vercel:** Add `vercel.json`: `{"rewrites": [{"source": "/(.*)", "destination": "/index.html"}]}`
- **nginx:** `try_files $uri $uri/ /index.html;`
