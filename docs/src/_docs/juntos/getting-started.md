---
order: 51
title: Getting Started
top_section: Juntos
category: juntos
---

# Getting Started with Juntos

Build a Rails blog and run it in your browser, on Node.js, and deploy to Vercel—all from the same code.

{% toc %}

## Prerequisites

- Ruby 3.2+ and Rails 7+
- Node.js 22+
- Git

## Create the Blog App

```bash
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/blog/create-blog | bash
cd blog
```

This creates a Rails app with:

- **Article scaffold** — title, body, CRUD operations
- **Comment scaffold** — nested under articles, `belongs_to :article`
- **Associations** — `has_many :comments, dependent: :destroy`
- **Validations** — `validates :title, presence: true`, `validates :body, length: { minimum: 10 }`
- **Nested routes** — `resources :articles { resources :comments }`
- **Tailwind CSS** — styled forms and layouts
- **Sample data** — seeded articles and comments

## Run with Rails (Baseline)

First, verify it works as a standard Rails app:

```bash
RAILS_ENV=production bin/rails db:prepare
bin/rails server -e production
```

Open http://localhost:3000. Browse articles. Add comments. Delete them. This is Rails as you know it—CRuby, SQLite, the full stack.

## Run in the Browser

Stop Rails. Run the same app in your browser:

```bash
bin/juntos dev -d dexie
```

Open http://localhost:3000. Same blog. Same articles. Same comments. But now:

- **No Ruby runtime** — the browser runs transpiled JavaScript
- **IndexedDB storage** — data persists in your browser via [Dexie](https://dexie.org/)
- **Hot reload** — edit a Ruby file, save, browser refreshes
- **Auto-migrations** — database schema updates automatically on startup

### Debugging

Open DevTools. In the Sources panel, find your Ruby files—`app/models/article.rb`, `app/controllers/articles_controller.rb`. Set breakpoints on Ruby lines. Step through Ruby code. Inspect variables with Ruby names.

The Console shows Rails-style logging:

```
Article Create {title: "Hello", body: "World", created_at: "..."}
Article Update {id: 1, title: "Updated", updated_at: "..."}
```

## Run on Node.js

```bash
bin/juntos migrate -d sqlite
bin/juntos up -d sqlite
```

Open http://localhost:3000. Same blog—but now Node.js serves requests, and [better-sqlite3](https://github.com/WiseLibs/better-sqlite3) provides the database.

The `migrate` command runs pending database migrations. The `up` command builds and starts the server.

Other runtimes work too:

```bash
bin/juntos up -t bun -d sqlite    # Bun runtime
bin/juntos up -t deno -d postgres  # Deno with PostgreSQL
```

## Deploy to Vercel

```bash
bin/juntos migrate -t vercel -d neon
bin/juntos deploy -t vercel -d neon
```

**Prerequisites:**

1. [Vercel CLI](https://vercel.com/docs/cli) — `npm i -g vercel` and `vercel login`
2. [Create a Vercel project](https://vercel.com/docs/projects/overview) — run `vercel` once to link
3. [Create a Neon database](https://neon.tech/docs/get-started-with-neon/signing-up)
4. Connect database — add `DATABASE_URL` as a Vercel environment variable
5. Local environment — copy credentials to `.env.local` for migrations

Like Rails, migrations run separately from deployment. The `migrate` command applies migrations to your production database. The `deploy` command builds and deploys.

## Deploy to Cloudflare

```bash
bin/juntos migrate -t cloudflare -d d1
bin/juntos deploy -t cloudflare -d d1
```

**Prerequisites:**

1. [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/) — `npm i -g wrangler` and `wrangler login`
2. [Create a D1 database](https://developers.cloudflare.com/d1/get-started/) — `wrangler d1 create blog_production`
3. Local environment — add `D1_DATABASE_ID` to `.env.local`

## The Code

The code is idiomatic Rails:

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  has_many :comments, dependent: :destroy
  validates :title, presence: true
  validates :body, presence: true, length: { minimum: 10 }
end
```

```ruby
# app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  before_action :set_article, only: %i[show edit update destroy]

  def index
    @articles = Article.all
  end

  def show
  end

  # ... standard scaffold code
end
```

Nothing special. Nothing modified for transpilation. Standard Rails conventions work.

## What Works

- **Models** — associations, validations, callbacks, scopes
- **Controllers** — actions, before_action, params, render, redirect_to
- **Views** — ERB templates with link_to, form_with, button_to
- **Routes** — resources, root, nested routes, path helpers
- **Migrations** — create_table, add_column, add_index

## What Works Differently

- **Migrations** — In browsers, migrations run automatically on startup
- **Background jobs** — Use Promises or setTimeout (JavaScript's event loop is already non-blocking)
- **Real-time** — Action Cable becomes BroadcastChannel for cross-tab or WebRTC for peer-to-peer

## What Doesn't Work

- **Action Mailer** — browsers can't send SMTP
- **Metaprogramming** — no `method_missing` or `define_method` at runtime
- **Complex SQL** — the ORM supports basic queries, not raw SQL

## Next Steps

- **[CLI Reference](/docs/juntos/cli)** — All commands and options
- **[Architecture](/docs/juntos/architecture)** — What gets generated
- **[Deployment Guides](/docs/juntos/deploying/vercel)** — Detailed platform guides
