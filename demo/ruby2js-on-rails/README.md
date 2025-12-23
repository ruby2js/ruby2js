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

## Available Commands

| Command | Description |
|---------|-------------|
| `npm run dev` | Browser dev server with hot reload |
| `npm run dev:ruby` | Dev server using Ruby transpilation |
| `npm run dev:selfhost` | Rebuild selfhost packages and start dev server |
| `npm run dev:node` | Build for Node.js and start server |
| `npm run dev:bun` | Build for Bun and start server |
| `npm run dev:deno` | Build for Deno and start server |
| `npm run build` | One-shot browser build (selfhost transpilation) |
| `npm run build:ruby` | One-shot browser build (Ruby transpilation) |
| `npm run build:selfhost` | Rebuild and install local selfhost packages |
| `npm run build:node` | Build for Node.js with SQLite |
| `npm run build:bun` | Build for Bun with SQLite |
| `npm run build:deno` | Build for Deno with SQLite |
| `npm run build:pg` | Build for Node.js with PostgreSQL |
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
| `ruby2js-rails` | ruby2js.com/releases/ruby2js-rails-beta.tgz | Adapters, targets, erb_runtime |

To update to the latest:

```bash
npm update
```

## Developing Ruby2JS Itself

When working on ruby2js core or filters (not just the demo app):

### Option 1: Ruby Transpilation (Recommended)

The simplest approach - uses the local gem directly:

```bash
npm run build:ruby   # Uses lib/ruby2js from the repo
npm run dev
```

Changes to `lib/ruby2js/**/*.rb` take effect immediately on rebuild.

### Option 2: Selfhost Transpilation

To test the JavaScript converter with your changes:

```bash
npm run dev:selfhost   # Rebuilds selfhost, packs, installs, and starts dev server
```

This runs `build:selfhost` which handles all the packaging steps automatically.

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

### Smoke Test

Compare Ruby and selfhost transpilation to ensure identical output:

```bash
npm run test:smoke
```

This verifies:
- Both Ruby and selfhost builds complete successfully
- Generated JavaScript has valid syntax
- Both builds produce identical output
- All relative imports resolve correctly

### Running from Repository

When developing Ruby2JS itself, see the "Developing Ruby2JS Itself" section above for local package setup.

To run selfhost CI tests:

```bash
cd ../selfhost
node run_all_specs.mjs
```

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
├── vendor/ruby2js/       # ruby2js-rails package source (for local dev)
│   ├── package.json      # Package definition (depends on ruby2js)
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
├── scripts/
│   ├── build.rb          # Ruby transpilation script
│   └── build.mjs         # JavaScript (selfhost) transpilation script
├── dev-server.mjs        # Hot reload dev server (browser)
├── server.mjs            # Node.js server entry point
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
