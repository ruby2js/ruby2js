# Ruby2JS-on-Rails Demo

A Rails-like blog application running entirely in JavaScript. Ruby source files are transpiled to JavaScript via Ruby2JS, demonstrating that idiomatic Rails code can run in the browser **or** as a server on Node.js, Bun, or Deno.

## Quick Start

### Browser (Default)

```bash
npm install
npm run dev           # Start dev server with hot reload
# Open http://localhost:3000
```

### Server (Node.js / Bun / Deno)

```bash
npm install
npm run dev:node      # Build for Node.js and start server
npm run dev:bun       # Build for Bun and start server
npm run dev:deno      # Build for Deno and start server
# Open http://localhost:3000
```

## Target Platforms

The same Ruby source code can be transpiled to run on different platforms:

| Target | Runtime | Database | Use Case |
|--------|---------|----------|----------|
| **Browser** | - | sql.js (SQLite WASM) | SPA with client-side storage |
| **Browser** | - | Dexie (IndexedDB) | SPA with persistent storage |
| **Server** | Node.js | better-sqlite3 | Development server, testing |
| **Server** | Node.js | PostgreSQL | Production server |
| **Server** | Bun | better-sqlite3 | Fast development server |
| **Server** | Deno | better-sqlite3 | Secure runtime |

The target is determined by the database adapter in `config/database.yml` or the `DATABASE` environment variable. The runtime can be set via the `RUNTIME` environment variable (node, bun, or deno).

## Selecting a Database Adapter

### Browser Adapters

For browser builds, two database adapters are available:

| Adapter | Size | Persistence | Use Case |
|---------|------|-------------|----------|
| **dexie** (default) | ~50KB | Persistent (IndexedDB) | Most browser apps |
| **sqljs** | ~2.7MB | In-memory only | Full SQL support, testing |

**Using Dexie (default):**
```bash
npm run dev
# Or explicitly:
DATABASE=dexie npm run dev
```

**Using sql.js:**
```bash
DATABASE=sqljs npm run dev
```

Or edit `config/database.yml`:
```yaml
development:
  adapter: sqljs
  database: ruby2js_rails_dev
```

The sql.js adapter loads the ~2.7MB WASM file dynamically when the app starts. This is loaded on-demand, so apps using Dexie don't pay this cost.

### Server Adapters

For server builds (Node.js, Bun, Deno):

```bash
DATABASE=better_sqlite3 npm run dev:node   # SQLite (default for server)
DATABASE=pg npm run dev:node               # PostgreSQL
```

## Available Commands

| Command | Description |
|---------|-------------|
| `npm run dev` | Browser dev server with hot reload |
| `npm run dev:ruby` | Dev server using Ruby transpilation |
| `npm run dev:node` | Build for Node.js and start server |
| `npm run dev:bun` | Build for Bun and start server |
| `npm run dev:deno` | Build for Deno and start server |
| `npm run build` | One-shot browser build (selfhost transpilation) |
| `npm run build:ruby` | One-shot browser build (Ruby transpilation) |
| `npm run start` | Serve browser build (npx serve) |
| `npm run start:node` | Start Node.js server (after build) |
| `npm run start:bun` | Start Bun server (after build) |
| `npm run start:deno` | Start Deno server (after build) |

Both transpilation modes (Ruby and selfhost) produce **identical output**, verified by automated diff comparison.

## How It Works

```
app/models/*.rb          → dist/models/*.js
app/controllers/*.rb     → dist/controllers/*.js
app/views/*.html.erb     → dist/views/erb/*.js
config/*.rb              → dist/config/*.js
db/*.rb                  → dist/db/*.js
```

Ruby source files in `app/`, `config/`, and `db/` are transpiled to JavaScript using Ruby2JS with Rails-specific filters. The transpiled JavaScript runs in the browser with sql.js (SQLite compiled to WebAssembly) as the database.

## Development Workflow

1. Start `npm run dev`
2. Edit any `.rb` or `.erb` file in `app/`, `config/`, or `db/`
3. Save the file
4. Browser automatically reloads with changes

## Rails-like CLI

For Rails users, familiar commands are available via `bin/rails`:

```bash
bin/dev                      # Start dev server (wraps npm run dev)
bin/rails server             # Start dev server
bin/rails server -p 4000     # Use custom port
bin/rails server --runtime node  # Run on Node.js
bin/rails build              # Build for production
```

## npm Packages

This demo depends on two npm packages distributed via URL:

| Package | URL | Contents |
|---------|-----|----------|
| `ruby2js` | ruby2js.com/releases/ruby2js-beta.tgz | Core converter, CLI, filters |
| `ruby2js-rails` | ruby2js.com/releases/ruby2js-rails-beta.tgz | Adapters, targets, erb_runtime, build tools, dev server |

The `ruby2js-rails` package provides bin commands used by npm scripts:
- `ruby2js-rails-dev` - Development server with hot reload
- `ruby2js-rails-build` - Transpile Ruby to JavaScript
- `ruby2js-rails-server` - Production server for Node.js

To update to the latest:

```bash
npm update
```

## Developing Ruby2JS Itself

When working on ruby2js core or filters (not just the demo app):

### Ruby Transpilation (Recommended)

The simplest approach - uses the local gem directly:

```bash
npm run build:ruby   # Uses lib/ruby2js from the repo
npm run dev:ruby     # Dev server using Ruby transpilation
```

Changes to `lib/ruby2js/**/*.rb` take effect immediately on rebuild.

### Selfhost Transpilation

To test the JavaScript converter, rebuild the selfhost packages first:

```bash
cd ../selfhost
npm run build        # Rebuild selfhost converter and filters
cd ../ruby2js-on-rails
npm run dev          # Uses selfhost transpilation
```

## Packaging for Distribution

The demo tarball is built automatically during website deployment. To build manually:

```bash
# From the docs directory
cd ../../docs
bundle exec rake rails_demo_tarball
```

This creates `src/demo/ruby2js-on-rails.tar.gz` containing:
- User app (app/, config/, db/)
- package.json with URL dependencies
- Development server with hot reload

Users download and run with just Node.js - no Ruby needed.

## Testing

### Selfhost CI Tests

To run the selfhost test suite (from the repository):

```bash
cd ../selfhost
node run_all_specs.mjs
```

### Smoke Test (Repository Only)

When developing in the repository, you can compare Ruby and selfhost transpilation:

```bash
node scripts/smoke-test.mjs
```

This verifies both transpilation modes produce identical output.

## Project Structure

```
ruby2js-on-rails/
├── app/
│   ├── controllers/      # Ruby controller classes
│   ├── helpers/          # Ruby helper modules
│   ├── models/           # Ruby ActiveRecord-style models
│   └── views/articles/   # ERB templates
├── bin/
│   ├── dev               # Start dev server (wraps npm run dev)
│   └── rails             # Rails-like CLI (server, build)
├── config/
│   ├── database.yml      # Database configuration (determines target)
│   ├── routes.rb         # Rails-style routing
│   └── schema.rb         # Database schema
├── db/
│   └── seeds.rb          # Seed data
├── scripts/
│   └── build.rb          # Ruby transpilation script (for local dev)
├── vendor/ruby2js/       # ruby2js-rails package source (for local dev)
│   ├── package.json      # Package definition (depends on ruby2js)
│   ├── build.mjs         # JavaScript (selfhost) transpilation script
│   ├── dev-server.mjs    # Hot reload dev server
│   ├── server.mjs        # Node.js server entry point
│   ├── adapters/         # Database adapters (copied to dist/lib/active_record.mjs)
│   │   ├── active_record_sqljs.mjs      # Browser: sql.js (SQLite WASM)
│   │   ├── active_record_dexie.mjs      # Browser: Dexie (IndexedDB)
│   │   ├── active_record_better_sqlite3.mjs  # Node: SQLite
│   │   └── active_record_pg.mjs         # Node: PostgreSQL
│   ├── targets/          # Target-specific runtimes
│   │   ├── browser/rails.js  # History API routing, DOM updates
│   │   ├── node/rails.js     # HTTP server (http.createServer)
│   │   ├── bun/rails.js      # HTTP server (Bun.serve)
│   │   └── deno/rails.js     # HTTP server (Deno.serve)
│   └── erb_runtime.mjs   # ERB template runtime
├── node_modules/
│   ├── ruby2js/          # Core converter (from npm URL)
│   └── ruby2js-rails/    # Rails runtime (from npm URL)
├── dist/                 # Generated JavaScript (git-ignored)
├── index.html            # Browser entry point
└── package.json
```

## Sourcemaps

The build generates sourcemaps so you can debug Ruby in the browser:

1. Open DevTools → Sources
2. Find your `.rb` files (e.g., `app/models/article.rb`)
3. Set breakpoints directly in Ruby code
4. Step through Ruby source when debugging

## See Also

- [Ruby2JS-on-Rails Plan](../../plans/RUBY2JS_ON_RAILS.md) - Full project plan and roadmap
- [Ruby2JS](https://www.ruby2js.com/) - The transpiler powering this demo
