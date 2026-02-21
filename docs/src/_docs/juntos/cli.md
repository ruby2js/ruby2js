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

## juntos eject

Write transpiled JavaScript files to disk. Useful for debugging transformation issues or migrating away from Ruby source.

```bash
npx juntos eject [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--output, --out DIR` | Output directory (default: `ejected/`) |
| `-d, --database ADAPTER` | Database adapter |
| `-t, --target TARGET` | Build target |
| `--base PATH` | Base public path |
| `--include PATTERN` | Include only matching files (can be repeated) |
| `--exclude PATTERN` | Exclude matching files (can be repeated) |
| `--only FILES` | Comma-separated list of files to include |
| `-h, --help` | Show help |

**Examples:**

```bash
npx juntos eject                      # Output to ejected/
npx juntos eject --output dist/js     # Custom output directory
npx juntos eject -d sqlite -t node    # Eject for Node.js target

# Selective eject with filtering
npx juntos eject --include "app/models/*.rb"
npx juntos eject --include "app/views/articles/**/*" --exclude "**/test_*"
npx juntos eject --only app/models/article.rb,app/models/comment.rb
```

**Filtering:**

The `--include`, `--exclude`, and `--only` options let you eject a subset of files:

- `--include PATTERN` — Only include files matching the pattern (can be repeated)
- `--exclude PATTERN` — Exclude files matching the pattern (can be repeated)
- `--only FILES` — Comma-separated list of specific files to include

Patterns support glob syntax:
- `*` — Match any characters except `/`
- `**` — Match any characters including `/`
- `?` — Match a single character

**Filtering in ruby2js.yml:**

Instead of command-line flags, you can configure filtering in `config/ruby2js.yml`.
Top-level `include`/`exclude` patterns apply to both the Vite plugin and eject:

```yaml
# Top-level: applies to Vite dev server AND eject
include:
  - app/models/*.rb
  - app/views/articles/**/*
  - config/routes.rb
exclude:
  - "**/*_test.rb"
  - app/models/concerns/*

eject:
  output: ejected
```

Note: Migrations are never filtered — all migrations run regardless of include/exclude
patterns, since excluded models may still depend on the schema they define.

CLI flags take precedence over the config file. This is useful for:
- **Converting piece by piece:** Start with a few models, verify they work, add more
- **Partial migration:** Only eject the parts of the app you want to convert
- **Debugging:** Isolate a specific file to inspect its transpilation

**What it does:**

1. Transforms Ruby source files (models, controllers, views, routes, migrations, seeds)
2. Applies include/exclude filters if specified
3. Writes individual JavaScript files to the output directory
4. Generates index files and runtime configuration

**Output structure:**

```
ejected/
  app/
    models/         # Transpiled models + index.js
    views/          # Transpiled ERB templates
    controllers/    # Transpiled Rails controllers
    javascript/
      controllers/  # Transpiled Stimulus controllers
  config/
    routes.js       # Transpiled routes
  db/
    migrate/        # Transpiled migrations + index.js
    seeds.js        # Transpiled seeds
  lib/
    rails.js        # Runtime library
    active_record.mjs
```

Unlike `juntos build`, which produces bundled output optimized for deployment, `eject` produces unbundled individual files that mirror the source structure. This makes it useful for:

- **Debugging:** Inspect exactly what the Vite plugin produces
- **Migration:** Use the JavaScript output as a new codebase, leaving Ruby behind
- **Incremental adoption:** Convert your app piece by piece

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

## juntos lint

Scan Ruby files for transpilation issues before they surface at runtime.

```bash
npx juntos lint [options] [files...]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--strict` | Enable strict warnings for rare but possible issues |
| `--summary` | Show untyped variable summary (for planning type hints) |
| `--suggest` | Auto-generate type hints in `config/ruby2js.yml` |
| `--disable RULE` | Disable a rule (can be repeated) |
| `--include PATTERN` | Include only matching files (glob, can be repeated) |
| `--exclude PATTERN` | Exclude matching files (glob, can be repeated) |
| `-h, --help` | Show help |

**Examples:**

```bash
npx juntos lint                              # Lint all Ruby source files
npx juntos lint app/models/article.rb        # Lint a specific file
npx juntos lint --strict                     # Include strict warnings
npx juntos lint --disable ambiguous_method   # Skip type-ambiguity warnings
npx juntos lint --include "app/models/**"    # Only lint models
npx juntos lint --summary                    # Show untyped variable summary
npx juntos lint --suggest                    # Auto-generate type hints
```

**What it does:**

1. Discovers Ruby files in `app/models/`, `app/controllers/`, `app/javascript/controllers/`, `app/views/`, `config/routes.rb`, and `db/seeds.rb`
2. **Phase 1 — Structural checks:** Walks the raw AST to detect patterns that cannot be transpiled to JavaScript (e.g., `method_missing`, `eval`, `retry`, operator method definitions like `def <=>`)
3. **Phase 2 — Type-ambiguity checks:** Runs the full transpilation with lint mode enabled. The pragma filter reports methods whose JavaScript output depends on the receiver type (Array, Hash, Set, etc.) when neither a `# Pragma:` annotation nor type inference can determine the type
4. Prints diagnostics with file, line, and column, then exits with code 1 if any errors are found

**Output example:**

```
  app/models/article.rb:15:3 warning: ambiguous method 'delete' - receiver type unknown [ambiguous_method]
    Consider: # Pragma: set or # Pragma: map or # Pragma: array
  app/models/article.rb:42:5 warning: ambiguous method '<<' - receiver type unknown [ambiguous_method]
    Consider: # Pragma: array or # Pragma: set or # Pragma: string

Linted 12 files: 0 errors, 2 warnings
```

### Rules

| Rule | Severity | Description |
|------|----------|-------------|
| `ambiguous_method` | warning | Method has different JavaScript behavior depending on receiver type (see below). |
| `method_missing` | error | `method_missing` has no JavaScript equivalent |
| `eval_call` | error | `eval()` cannot be safely transpiled |
| `instance_eval` | error | `instance_eval` cannot be transpiled |
| `singleton_method` | warning | `def obj.method` has limited JavaScript support |
| `retry_statement` | warning | `retry` has no direct JavaScript equivalent |
| `redo_statement` | warning | `redo` has no direct JavaScript equivalent |
| `ruby_catch_throw` | warning | Ruby `catch`/`throw` differs from JavaScript `try`/`catch` |
| `prepend_call` | warning | `prepend` has no JavaScript equivalent |
| `operator_method` | error | Operator method definitions (e.g., `def <=>`) cannot be transpiled — JavaScript has no operator overloading |
| `force_encoding` | warning | `force_encoding` has no JavaScript equivalent (JS strings are always UTF-16) |
| `parse_error` | error | File could not be parsed |
| `conversion_error` | error | File could not be converted |

**Default vs strict ambiguous method warnings:**

By default, the linter only warns about methods where the JavaScript fallthrough is **silently wrong** — operators like `<<` (bitwise shift instead of append), `+`/`-`/`&`/`|` on arrays (arithmetic instead of set operations), `dup` (no JS equivalent), and `delete`/`clear` (wrong for certain types).

With `--strict`, additional warnings appear for methods where the default JavaScript is **usually correct** but could be wrong for less common types: `include?`, `empty?`, `each`/`map`/`select`/`flat_map`/`each_with_index` (block iteration with 2+ args on unknown types), `[]`, `[]=`, `key?`, `merge`, `any?`, `replace`, `first`, `to_h`, `compact`, and `flatten`.

### Fixing ambiguous method warnings

When the lint reports an ambiguous method, it means the transpiler doesn't know the receiver's type and may produce incorrect JavaScript. There are three ways to fix this:

**1. Add a pragma comment** on the same line:

```ruby
items.delete(x)        # Pragma: array    → items.splice(items.indexOf(x), 1)
items.delete(x)        # Pragma: set      → items.delete(x)  (kept as-is for Set)
```

**2. Initialize the variable** so the type can be inferred:

```ruby
items = []             # Pragma filter now knows items is an Array
items.delete(x)        # → items.splice(items.indexOf(x), 1)
```

**3. Use Sorbet-style annotations:**

```ruby
items = T.let([], Array)
items.delete(x)        # → items.splice(items.indexOf(x), 1)
```

**4. Add type hints** in `config/ruby2js.yml`:

```yaml
lint:
  type_hints:
    items: array
```

Type hints apply globally as a low-priority default. They are overridden by
local type inference and pragma comments. Use `juntos lint --suggest` to
auto-generate hints based on usage patterns.

See the [Pragmas documentation](/docs/users-guide/pragmas) for the full list of type disambiguation pragmas.

### Configuration in ruby2js.yml

```yaml
lint:
  disable:
    - ambiguous_method
    - singleton_method
  include:
    - "app/models/**"
  exclude:
    - "app/models/concerns/**"
  type_hints:
    params: hash
    positions: array
    remaining_seats: number
```

The `type_hints` section maps variable names to their types. Supported types: `array`, `hash`, `string`, `number`, `set`, `map`, `proc`. These hints act as a global fallback — they are overridden by local type inference (e.g., `items = []`) and pragma comments (e.g., `# Pragma: array`).

### Recommended workflow

1. Run `juntos lint --summary` to see which variables produce the most warnings
2. Run `juntos lint --suggest` to auto-generate type hints from usage patterns
3. Review `config/ruby2js.yml` — adjust any incorrect guesses
4. Run `juntos lint` to see remaining warnings
5. Add `# Pragma:` comments for the remaining cases

## Database Adapters

The CLI auto-installs the required npm package for each adapter:

| Adapter | npm Package | Targets |
|---------|-------------|---------|
| `dexie` | dexie | browser |
| `sqlite` | better-sqlite3 | node, bun |
| `sqljs` | sql.js | browser |
| `sqlite-wasm` | @sqlite.org/sqlite-wasm | browser |
| `wa-sqlite` | wa-sqlite | browser |
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
- `sqlite_wasm` → sqlite-wasm
- `wa_sqlite` → wa-sqlite
- `postgres`, `postgresql` → pg
- `mysql2` → mysql

This means existing Rails apps with `adapter: sqlite3` in `database.yml` work without changes.

## Default Targets

When target is not specified, it's inferred from the database:

| Database | Default Target |
|----------|---------------|
| dexie, sqljs, sqlite-wasm, wa-sqlite, pglite | browser |
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
