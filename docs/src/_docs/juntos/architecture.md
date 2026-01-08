---
order: 615
title: Architecture
top_section: Juntos
category: juntos
---

# Juntos Architecture

Understanding what Juntos generates and how the pieces connect.

{% toc %}

## The dist/ Directory

Running `juntos build` creates a self-contained JavaScript application:

```
dist/
├── app/
│   ├── models/
│   │   ├── application_record.js   # Base class wrapping ActiveRecord
│   │   ├── article.js              # Transpiled model
│   │   ├── comment.js
│   │   └── index.js                # Re-exports all models
│   ├── controllers/
│   │   ├── application_controller.js
│   │   ├── articles_controller.js
│   │   └── comments_controller.js
│   ├── views/
│   │   ├── articles/
│   │   │   ├── index.js            # Transpiled ERB
│   │   │   ├── show.js
│   │   │   ├── _article.js         # Partials
│   │   │   └── *.html.erb          # Source (for sourcemaps)
│   │   └── layouts/
│   │       └── application.js      # Layout wrapper
│   ├── javascript/
│   │   └── controllers/            # Stimulus controllers
│   │       ├── index.js            # Auto-generated manifest
│   │       └── *_controller.js     # Transpiled from .rb
│   └── helpers/
├── config/
│   ├── routes.js                   # Route definitions + dispatch
│   └── paths.js                    # Path helper functions
├── db/
│   ├── migrate/
│   │   ├── 20241231_create_articles.js
│   │   ├── 20241231_create_comments.js
│   │   └── index.js                # Migration registry
│   └── seeds.js                    # Seed data
├── lib/
│   ├── rails.js                    # Framework runtime (target-specific)
│   ├── rails_base.js               # Shared base classes
│   ├── active_record.mjs           # Database adapter (selected at build time)
│   ├── erb_runtime.mjs             # ERB helper functions
│   └── dialects/                   # SQL dialect (SQLite, PostgreSQL, or MySQL)
│       └── sqlite.mjs              # Example: SQLite dialect for Turso/D1
├── node_modules/
│   └── ruby2js-rails/              # Shared runtime modules
│       └── adapters/               # ActiveRecord base classes, query builder, CollectionProxy
├── index.html                      # Entry point (browser targets)
├── api/[[...path]].js              # Entry point (Vercel)
├── src/index.js                    # Entry point (Cloudflare)
├── vercel.json                     # Platform config (Vercel)
├── wrangler.toml                   # Platform config (Cloudflare)
├── package.json
└── tailwind.config.js              # If using Tailwind
```

## Standalone JavaScript

The `dist/` directory is a complete application. You can:

```bash
cd dist
npm install
npm start
```

No Ruby required. The generated code is idiomatic JavaScript—ES2022 classes, async/await, standard module patterns. You could fork this directory and continue development in pure JavaScript.

## Target Differences

### Browser

- Entry: `index.html` loads `config/routes.js`
- Routing: Client-side, updates `#hash` or uses History API
- Database: IndexedDB (Dexie), SQLite/WASM, or PGlite
- Rendering: Direct DOM manipulation via `innerHTML`

### Node.js / Bun / Deno

- Entry: `lib/rails.js` exports `Application.listen()`
- Routing: HTTP server, parses request path
- Database: better-sqlite3, pg, mysql2
- Rendering: Returns HTML string responses

### Vercel Edge

- Entry: `api/[[...path]].js` catch-all route
- Routing: Vercel routes requests to the handler
- Database: Neon, Turso, PlanetScale (HTTP-based)
- Rendering: Returns `Response` objects

### Cloudflare Workers

- Entry: `src/index.js` exports `fetch` handler
- Routing: Worker receives all requests
- Database: D1 binding, Turso
- Rendering: Returns `Response` objects

## WebSocket Support

Turbo Streams broadcasting uses WebSockets for real-time updates. Support varies by target:

| Target | WebSocket Implementation |
|--------|-------------------------|
| Browser | `BroadcastChannel` (same-origin tabs) |
| Node.js | `ws` package |
| Bun | Native `Bun.serve` WebSocket |
| Deno | Native `Deno.upgradeWebSocket` |
| Cloudflare | Durable Objects with hibernation |
| Vercel | Not supported (platform limitation) |

WebSocket connections use the `/cable` endpoint:

```javascript
// Client subscribes to a channel
const ws = new WebSocket('ws://localhost:3000/cable');
ws.send(JSON.stringify({ command: 'subscribe', channel: 'chat_room' }));

// Server broadcasts to subscribers
TurboBroadcast.broadcast('chat_room', '<turbo-stream action="append">...</turbo-stream>');
```

## The Runtime

### Application

The `Application` class manages initialization and request handling:

```javascript
// Browser
Application.start();  // Initialize DB, render initial route

// Node.js
Application.listen(3000);  // Start HTTP server

// Vercel
export default Application.handler();  // Export request handler

// Cloudflare
export default Application.worker();  // Export Worker handler
```

### Router

Routes are registered at build time and dispatched at runtime:

```javascript
// Generated from config/routes.rb
Router.resources('articles', ArticlesController);
Router.resources('comments', CommentsController, { shallow: true });
Router.root('articles#index');
```

Path helpers are generated as standalone functions:

```javascript
// config/paths.js
export function article_path(article) {
  return `/articles/${article.id || article}`;
}

export function edit_article_path(article) {
  return `/articles/${article.id || article}/edit`;
}
```

### ActiveRecord

Models extend `ApplicationRecord` which wraps the database adapter:

```javascript
class Article extends ApplicationRecord {
  static _tableName = 'articles';
  static _associations = { comments: { type: 'hasMany', foreignKey: 'article_id' } };
  static _validations = { title: [{ presence: true }] };

  // Generated association method returns CollectionProxy
  get comments() {
    return new CollectionProxy(this, this.constructor._associations.comments, Comment);
  }
}
```

The adapter is selected at build time based on the database configuration:

| Adapter | File |
|---------|------|
| Dexie | `active_record_dexie.mjs` |
| sql.js | `active_record_sqljs.mjs` |
| better-sqlite3 | `active_record_better_sqlite3.mjs` |
| Neon | `active_record_neon.mjs` |
| D1 | `active_record_d1.mjs` |

All adapters implement the same interface:

```javascript
// Finders
Model.all()                              // All records
Model.find(id)                           // Find by ID (throws if not found)
Model.findBy({ status: 'active' })       // Find first matching (returns null)
Model.where({ status: 'active' })        // Find all matching
Model.first()                            // First record by ID
Model.last()                             // Last record by ID
Model.count()                            // Count records

// Chainable query builder (returns Relation)
Model.where({ published: true })
     .order({ created_at: 'desc' })
     .limit(10)
     .offset(20)

// Raw SQL conditions (SQL adapters)
Model.where('created_at > ?', timestamp)
Model.where('status = ? AND priority > ?', 'active', 5)

// Eager loading associations
Article.includes('comments').find(id)    // Preloads article.comments
Article.includes('comments', 'author')   // Multiple associations

// CollectionProxy (for has_many associations)
article.comments.size                    // Synchronous when eagerly loaded
article.comments.build({ body: '...' }) // Pre-sets article_id automatically
article.comments.where({ approved: true }) // Returns chainable Relation

// Instance methods
record.save()                            // Insert or update
record.update({ title: 'New' })          // Update attributes
record.destroy()                         // Delete record
record.reload()                          // Refresh from database
```

**Note:** Raw SQL conditions work on all SQL adapters. For Dexie (IndexedDB), simple conditions like `>`, `<`, `>=`, `<=`, `=` are translated to Dexie's query API; complex conditions fall back to JavaScript filtering.

## Sourcemaps

Each transpiled file includes a sourcemap linking back to the original Ruby:

```javascript
// article.js
export class Article extends ApplicationRecord { ... }
//# sourceMappingURL=article.js.map
```

The original `.rb` files are copied alongside for debugger access. In browser DevTools, you can set breakpoints on Ruby lines and step through Ruby code.

## The Build Process

1. **Load configuration** — Read `config/database.yml`, determine target
2. **Copy runtime** — Copy target-specific `rails.js` and database adapter
3. **Transpile models** — Apply rails/model filter
4. **Transpile controllers** — Apply rails/controller filter
5. **Transpile views** — Compile ERB to Ruby, apply rails/helpers filter
6. **Transpile routes** — Generate route definitions and path helpers
7. **Transpile migrations** — Generate async migration functions
8. **Generate entry point** — Create index.html or serverless handler
9. **Setup Tailwind** — If detected, configure and build CSS

**Note:** Shared modules (ActiveRecord base classes, query builder, inflector) are imported from the `ruby2js-rails` npm package rather than copied to `dist/`. This keeps builds smaller and provides a single source of truth for the runtime code.

## Continuing in JavaScript

After building, you can take `dist/` and develop purely in JavaScript:

1. The generated code follows standard patterns
2. No Ruby required at runtime—it's pure JavaScript (the `ruby2js-rails` npm package provides the runtime)
3. Add npm packages directly to `dist/package.json`
4. Modify transpiled files as needed

The generated code isn't obfuscated or minified—it's meant to be readable and maintainable. This is an intentional escape hatch: Juntos gets you started quickly, but you're not locked in.
