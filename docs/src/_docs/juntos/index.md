---
order: 50
title: What is Juntos?
top_section: Juntos
category: juntos
---

# Juntos

Juntos is a set of Ruby2JS filters that implement a Rails-compatible framework for JavaScript runtimes. Write Rails—models, controllers, views, routes—and deploy to browsers, Node.js, or serverless edge platforms.

{% toc %}

## The Vision

Rails is the fastest way to go from idea to working application. Serverless is the future of deployment. Until now, you had to choose.

Juntos bridges this gap. The same Rails code runs:

- **In browsers** with IndexedDB or SQLite/WASM
- **On Node.js** with SQLite, PostgreSQL, or MySQL
- **On Vercel Edge** with Neon, Turso, or PlanetScale
- **On Cloudflare Workers** with D1

Same models, controllers, and views. Different runtimes, same conventions. No lock-in—switch platforms without rewriting your application.

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
    comments: { type: 'hasMany', dependent: 'destroy' }
  };

  static _validations = {
    title: [{ presence: true }]
  };

  async comments() {
    return await Comment.where({ article_id: this.id });
  }
}
```

Not DRY like Rails, but not magic either. The generated code is readable, debuggable, and yours to keep.

## Why Juntos?

### Rails Fidelity

Other frameworks are Rails-*inspired*. Juntos aims for Rails patterns exactly. Rails developers feel at home. Rails documentation mostly applies. The mental model transfers.

### Multi-Target

Write once, deploy anywhere JavaScript runs. No other framework offers the same code running in browsers with IndexedDB, on Node.js with PostgreSQL, and on edge functions with serverless databases.

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

## Next Steps

- **[Getting Started](/docs/juntos/getting-started)** — Build a blog app in 10 minutes
- **[CLI Reference](/docs/juntos/cli)** — The `juntos` commands
- **[Architecture](/docs/juntos/architecture)** — What gets generated and how it works
- **[Deployment](/docs/juntos/deploying/browser)** — Deploy to any target
