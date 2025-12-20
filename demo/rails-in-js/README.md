# Rails-in-JS Demo

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
| `npm run dev:node` | Build for Node.js and start server |
| `npm run dev:bun` | Build for Bun and start server |
| `npm run dev:deno` | Build for Deno and start server |
| `npm run build` | One-shot browser build (selfhost transpilation) |
| `npm run build:ruby` | One-shot browser build (Ruby transpilation) |
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

## Project Structure

```
rails-in-js/
├── app/
│   ├── controllers/      # Ruby controller classes
│   ├── helpers/          # Ruby helper modules
│   ├── models/           # Ruby ActiveRecord-style models
│   └── views/articles/   # ERB templates
├── config/
│   ├── database.yml      # Database configuration (determines target)
│   ├── routes.rb         # Rails-style routing
│   └── schema.rb         # Database schema
├── db/
│   └── seeds.rb          # Seed data
├── lib/
│   ├── adapters/         # Database adapters (copied to dist/lib/active_record.mjs)
│   │   ├── active_record_sqljs.mjs      # Browser: sql.js (SQLite WASM)
│   │   ├── active_record_dexie.mjs      # Browser: Dexie (IndexedDB)
│   │   ├── active_record_better_sqlite3.mjs  # Node: SQLite
│   │   └── active_record_pg.mjs         # Node: PostgreSQL
│   └── targets/          # Target-specific runtimes
│       ├── browser/rails.js  # History API routing, DOM updates
│       ├── node/rails.js     # HTTP server (http.createServer)
│       ├── bun/rails.js      # HTTP server (Bun.serve)
│       └── deno/rails.js     # HTTP server (Deno.serve)
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

- [Rails-in-JS Plan](../../plans/RAILS_IN_JS.md) - Full project plan and roadmap
- [Ruby2JS](https://www.ruby2js.com/) - The transpiler powering this demo
