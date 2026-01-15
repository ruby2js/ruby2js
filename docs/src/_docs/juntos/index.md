---
order: 600
title: What is Juntos?
top_section: Juntos
category: juntos
---

# Juntos

Juntos is a set of Ruby2JS filters that implement a Rails-compatible framework for JavaScript runtimes. Write Rails—models, controllers, views, routes—and deploy to browsers, Node.js, or edge platforms.

{% toc %}

## The Vision

Rails is the fastest way to go from idea to working application. But traditional hosting means paying for capacity whether you use it or not. V8 Isolates—lightweight JavaScript environments that spin up on demand—offer a different model: deploy once, run globally, scale automatically, pay only for what you use.

The catch? V8 runs JavaScript, not Ruby.

Juntos bridges this gap by transpiling Rails to JavaScript. This unlocks platforms Rails can't reach:

- **V8 Isolates** (Cloudflare Workers, Vercel Edge, Deno Deploy) — Rails can't run here; Juntos can
- **Browsers** (IndexedDB, SQLite/WASM) — offline-first apps, local-first data, zero infrastructure

And works everywhere JavaScript runs:

- **Node.js, Bun, Deno** with SQLite, PostgreSQL, or MySQL

Same models, controllers, and views. The sweet spot is where transpilation is necessary—V8 Isolates and browsers—but one codebase runs everywhere.

## How It Works

Rails is built on metaprogramming. Write `has_many :comments` and Rails generates methods at runtime. Juntos inverts this: instead of runtime generation, **filters pre-compute what Rails would generate** at transpile time.

The Rails DSL is finite and declarative—filters recognize every pattern and expand it statically. The output is idiomatic JavaScript: ES2022 classes, async/await, standard patterns.

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  has_many :comments, dependent: :destroy
  validates :title, presence: true
end
```

Becomes:

```javascript
// dist/app/models/article.js
export class Article extends ApplicationRecord {
  static _associations = {
    comments: { type: 'hasMany', dependent: 'destroy', foreignKey: 'article_id' }
  };

  static _validations = {
    title: [{ presence: true }]
  };

  get comments() {
    return new CollectionProxy(this, this.constructor._associations.comments, Comment);
  }
}
```

Not DRY like Rails, but not magic either. The generated code is readable, debuggable, and yours to keep. The `CollectionProxy` wraps associations with Rails-like behavior—synchronous `.size` when eagerly loaded, chainable queries like `.where()` and `.order()`, and methods like `.build()` that pre-set the foreign key.

## Why Juntos?

### Rails Fidelity

Other frameworks are Rails-*inspired*. Juntos aims for Rails patterns exactly. Rails developers feel at home. Rails documentation mostly applies. The mental model transfers.

### Hotwire Ready

Full [Hotwire](https://hotwired.dev/) support for the Rails-native approach to interactivity:

- **Turbo Streams** — Real-time broadcasting with `broadcast_append_to`, `broadcast_remove_to`
- **Stimulus** — Write controllers in Ruby, transpile to JavaScript
- **WebSockets** — Built-in support on Node.js, Bun, Deno, and Cloudflare

### Multi-Target

Write once, deploy anywhere JavaScript runs. The same code runs in browsers with IndexedDB, on Node.js with PostgreSQL, on V8 Isolates with edge databases, on mobile devices via Capacitor, and on desktop via Electron or Tauri.

### Transparency

The generated `dist/` directory is a complete, standalone JavaScript application. You could fork it and continue development in pure JavaScript without ever touching Ruby again. The output isn't compiled bytecode—it's readable code you can understand and modify.

### Minimal Runtime

The generated code is ~95% your application, ~5% framework glue. No massive dependency tree. No framework lock-in beyond what you can read and understand.

## Juntos vs. Other Frameworks

| Framework | Similarity to Rails | Multi-Target | Generated Code |
|-----------|--------------------|--------------| ---------------|
| **AdonisJS** | Inspired by | Node.js only | N/A (runtime) |
| **Next.js** | Different paradigm | Vercel-focused | React/JSX |
| **Remix** | Loaders/actions | Node/Edge | React |
| **Hono** | Minimal (Sinatra-like) | Yes | N/A (runtime) |
| **Juntos** | Direct mapping | Browser/Node/Edge | Idiomatic JS |

### Why not target AdonisJS?

AdonisJS is excellent, but the mapping isn't 1:1. Controllers have different lifecycle hooks. The ORM (Lucid) has different patterns. You'd be learning "Ruby that becomes AdonisJS," not "Rails in JavaScript."

### Why not target Next.js?

Next.js is React-based with a fundamentally different paradigm. App Router, Server Components, and client/server boundaries don't map to Rails MVC. The mental models are too different for a clean transpilation.

### Why not target Hono?

Hono is more Sinatra than Rails—lightweight routing without opinions about models, views, or structure. You'd be starting from scratch on everything Rails provides for free.

## Demos

Three demo applications show Juntos in action:

| Demo | What You Learn |
|------|---------------|
| **[Blog](/docs/juntos/demos/blog)** | CRUD operations, associations, validations, multi-platform deployment |
| **[Chat](/docs/juntos/demos/chat)** | Real-time Turbo Streams, Stimulus controllers in Ruby, WebSocket broadcasting |
| **[Photo Gallery](/docs/juntos/demos/photo-gallery)** | Camera integration, Capacitor mobile apps, Electron desktop apps |

All demos run on browser, Node.js, and edge platforms from the same code. The Photo Gallery also demonstrates mobile (Capacitor) and desktop (Electron) targets. See [Demo Applications](/docs/juntos/demos/) for the full list and walkthroughs.

## Next Steps

- **[Getting Started](/docs/juntos/getting-started)** — Install and run your first app
- **[Demo Applications](/docs/juntos/demos/)** — Hands-on examples
- **[Hotwire](/docs/juntos/hotwire)** — Real-time features and Stimulus controllers
- **[CLI Reference](/docs/juntos/cli)** — The `juntos` commands
- **[Architecture](/docs/juntos/architecture)** — What gets generated and how it works
- **[Testing](/docs/juntos/testing)** — Write tests for your transpiled app
- **[Deployment](/docs/juntos/deploying/)** — Deploy to any target
