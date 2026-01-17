---
order: 605
title: Getting Started
top_section: Juntos
category: juntos
---

# Getting Started with Juntos

Install Juntos and run your first Rails app across multiple platforms.

{% toc %}

## Prerequisites

- Ruby 3.2+ and Rails 7+
- Node.js 22+
- Git

## Installation

Add Juntos to your Rails app:

```ruby
# Gemfile
gem 'ruby2js', require: 'ruby2js/rails'
```

```bash
bundle install
```

The `bin/juntos` command is available automatically.

## Quick Start with a Demo

The fastest way to see Juntos in action is to run a demo app:

```bash
# Blog demo (CRUD, associations, validations)
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/blog/create-blog | bash -s myapp

# Chat demo (real-time, Turbo Streams, Stimulus)
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/chat/create-chat | bash -s myapp
```

See [Demo Applications](/docs/juntos/demos/) for detailed walkthroughs.

## Run Modes

Juntos supports multiple ways to run the same Rails code:

### Development Mode (Browser)

```bash
bin/juntos dev -d dexie
```

Runs in your browser with IndexedDB storage. Features:
- Hot reload on file changes
- Auto-migrations
- Ruby debugging in DevTools
- No server required

### Server Mode (Node.js)

```bash
bin/juntos db:prepare -d sqlite
bin/juntos up -d sqlite
```

Runs on Node.js with SQLite. Also supports:
- Bun: `bin/juntos up -t bun -d sqlite`
- Deno: `bin/juntos up -t deno -d postgres`

### Deploy Mode (Edge)

```bash
bin/juntos deploy -d neon     # Vercel Edge
bin/juntos deploy -d d1       # Cloudflare Workers
```

Builds and deploys to serverless platforms.

## Database Adapters

| Adapter | Runtime | Storage | Model Operations |
|---------|---------|---------|------------------|
| `dexie` | Browser | IndexedDB | Direct (local) |
| `sqljs` | Browser | SQLite/WASM | Direct (local) |
| `pglite` | Browser, Node | PostgreSQL/WASM | Direct (local) |
| `sqlite` | Node, Bun | SQLite file | Direct (server) |
| `pg` | Node, Bun, Deno | PostgreSQL | Direct (server) |
| `neon` | Vercel | Serverless PostgreSQL | Direct (server) |
| `d1` | Cloudflare | Edge SQLite | Direct (server) |

### RPC for Server Targets

When using server targets (Node.js, Cloudflare, etc.), browser-side code uses RPC to communicate with the server for model operations. The same Ruby code works on both sides:

```ruby
# This code works identically on both targets
@articles = Article.where(status: 'published')
```

- **Browser target**: Queries IndexedDB directly via Dexie
- **Server target**: Browser sends RPC request → Server queries SQLite → Returns results

The RPC transport is transparent—your code doesn't change. See [Architecture](/docs/juntos/architecture) for details.

## Development to Production Workflow

Configure different databases per environment in `config/database.yml`:

```yaml
development:
  adapter: sqlite
  database: db/development.sqlite3

production:
  adapter: d1
  database: myapp_production
```

Then use environment flags:

```bash
# Local development (uses sqlite from database.yml)
bin/juntos up

# Prepare production database (creates D1, runs migrations)
bin/juntos db:prepare -e production

# Deploy to production (uses d1 from database.yml)
bin/juntos deploy -e production
```

The `-e` flag (or `RAILS_ENV` environment variable) selects which `database.yml` section to use. Commands read from `database.yml` by default; `-d` overrides the adapter if you need to.

**Common patterns:**

| Development | Production | Use Case |
|-------------|------------|----------|
| `sqlite` | `d1` | Cloudflare Workers |
| `sqlite` | `neon` | Vercel Edge |
| `dexie` | `dexie` | Browser-only (static hosting) |
| `sqlite` | `pg` | Traditional Node.js server |

## Using with an Existing App

Any Rails app can run with Juntos:

```bash
cd your-rails-app
bin/juntos dev -d dexie
```

If transpilation fails, check:
1. Unsupported Ruby features (see [What Works](#what-works) below)
2. Gems that require native extensions
3. Complex metaprogramming

## What Works

### Models

**Try it** — edit the Ruby to see how models transpile:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["model", "esm", "functions"]
}'></div>

```ruby
class Article < ApplicationRecord
  has_many :comments, dependent: :destroy
  belongs_to :author
  validates :title, presence: true
  validates :body, length: { minimum: 10 }

  after_create_commit { broadcast_append_to "articles" }
end
```

Associations, validations, and callbacks transpile directly.

### Controllers

**Try it** — controllers transpile with the same patterns:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["controller", "esm", "functions"]
}'></div>

```ruby
class ArticlesController < ApplicationController
  before_action :set_article, only: %i[show edit update destroy]

  def index
    @articles = Article.all
  end

  def create
    @article = Article.new(article_params)
    if @article.save
      redirect_to @article
    else
      render :new, status: :unprocessable_entity
    end
  end
end
```

Standard CRUD patterns work without modification.

### Views

```erb
<%= form_with model: @article do |f| %>
  <%= f.text_field :title %>
  <%= f.text_area :body %>
  <%= f.submit %>
<% end %>

<%= link_to "Back", articles_path %>
<%= button_to "Delete", @article, method: :delete %>
```

ERB helpers transpile to JavaScript functions.

### Routes

```ruby
Rails.application.routes.draw do
  resources :articles do
    resources :comments
  end
  root "articles#index"
end
```

Nested routes and path helpers work as expected.

## What Works Differently

| Feature | Rails | Juntos |
|---------|-------|--------|
| Migrations | Run manually | Auto-run in browser |
| Database | Any ActiveRecord adapter | Juntos-supported adapters |
| Background jobs | Sidekiq, etc. | Promises, setTimeout |
| Real-time | Action Cable | BroadcastChannel, WebSocket |

## What Doesn't Work

- **Action Mailer** — browsers can't send SMTP
- **Runtime metaprogramming** — no `method_missing` or `define_method`
- **Complex SQL** — supports basic raw SQL conditions like `where('updated_at > ?', timestamp)`, but complex joins and subqueries are not supported
- **Native gems** — gems requiring C extensions
- **File uploads** — no filesystem in browsers (use external storage)

## Next Steps

- **[Demo Applications](/docs/juntos/demos/)** — Hands-on examples
- **[Path Helpers](/docs/juntos/path-helpers)** — Server Functions-style data fetching with path helper RPC
- **[CLI Reference](/docs/juntos/cli)** — All commands and options
- **[Architecture](/docs/juntos/architecture)** — What gets generated
- **[Testing](/docs/juntos/testing)** — Write tests for your transpiled app
- **[Hotwire](/docs/juntos/hotwire)** — Real-time features
- **[Deployment](/docs/juntos/deploying/)** — Platform-specific guides
