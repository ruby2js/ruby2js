---
order: 9.5
title: Ruby2JS on Rails
top_section: User's Guide
category: users-guide-rails
next_page_order: 10
---

# Ruby2JS on Rails

Transpile Rails applications to JavaScript. Same models, controllers, views, and routes—running in browsers, on servers, or at the edge.

{% toc %}

## Quick Start

### Option 1: Pre-built Demo

No Ruby required. Node.js 22+ only.

```bash
curl -L https://www.ruby2js.com/demo/ruby2js-on-rails.tar.gz | tar xz
cd ruby2js-on-rails
npm install
bin/dev
```

Open http://localhost:3000. Edit Ruby files, browser hot-reloads.

### Option 2: From Rails Scaffold

Ruby + Rails required.

```bash
rails new blog
cd blog
rails generate scaffold Article title:string body:text
bundle add ruby2js --github ruby2js/ruby2js --require ruby2js/spa
rails generate ruby2js:spa:install
rails ruby2js:spa:build
cd public/spa/blog
npm install && npm run build && npm start
```

The generator auto-detects scaffolded resources and builds a standalone SPA.

## Database Adapters

Configure in `config/database.yml`:

| Adapter | Runtime | Storage |
|---------|---------|---------|
| **dexie** | Browser | IndexedDB |
| **sqljs** | Browser | SQLite/WASM |
| **pglite** | Browser/Edge | PostgreSQL/WASM |
| **better_sqlite3** | Node/Bun | SQLite file |
| **pg** | Node/Bun/Deno | PostgreSQL |
| **mysql2** | Node/Bun | MySQL |
| **d1** | Cloudflare | SQLite/edge |

```yaml
# Browser (offline-capable)
development:
  adapter: dexie
  database: my_app_dev

# Server
production:
  adapter: pg
  host: localhost
  database: my_app_production

# Edge
edge:
  adapter: d1
  binding: DB
```

Same Ruby source. Different adapter. Deploy anywhere JavaScript runs.

## CSS Frameworks

Configure in `config/ruby2js_spa.rb`:

| Framework | Description |
|-----------|-------------|
| **none** | Minimal custom styles (default) |
| **tailwind** | Tailwind CSS (auto-detected from Rails) |
| **pico** | Pico CSS (classless, semantic HTML) |
| **bootstrap** | Bootstrap 5 |
| **bulma** | Bulma CSS |

```ruby
# config/ruby2js_spa.rb
Ruby2JS::SPA.configure do |config|
  config.css = :tailwind
end
```

The SPA generator auto-detects Tailwind when using `rails new --css tailwind`. The generated HTML includes appropriate container classes for each framework.

## Development Workflow

```bash
bin/dev  # Start with hot module reloading
```

Edit `app/models/article.rb`. Save. Browser refreshes with transpiled JavaScript.

**Sourcemaps:** Debug Ruby in browser DevTools. Set breakpoints on Ruby lines. Step through Ruby code.

**Logging:** Rails-style output in console:

```
Article Create {title: "Hello", body: "World", created_at: "..."}
```

Enable "Verbose" in DevTools for detailed output.

**Build for production:**

```bash
npm run build
```

Deploy the `dist/` directory anywhere that serves static files.

## Configuration

### Transpilation Options

```yaml
# config/ruby2js.yml
default:
  eslevel: 2022
  comparison: identity
  autoexports: true
```

| Option | Description |
|--------|-------------|
| **eslevel** | ECMAScript target (2020-2025) |
| **comparison** | `equality` (==) or `identity` (===) |
| **autoexports** | Auto-export top-level declarations |

### SPA Generator Options

```ruby
# config/ruby2js_spa.rb
Ruby2JS::SPA.configure do |config|
  config.database = :dexie
  config.css = :tailwind
  config.scaffolds = %w[Article Comment]  # Auto-detected
  config.root = "articles#index"
end
```

## What Gets Transpiled

Standard Rails patterns work:

- **Models:** `has_many`, `belongs_to`, `validates`, `scope`, callbacks
- **Controllers:** `before_action`, `params`, `render`, `redirect_to`
- **Views:** ERB with `link_to`, `form_for`, `button_to`, `truncate`
- **Routes:** `resources`, `root`, nested routes, path helpers

See [Rails Filter Reference](/docs/filters/rails) for complete documentation and examples.

## Limitations

| Works | Doesn't Work |
|-------|--------------|
| Models with associations | Metaprogramming (`method_missing`) |
| Validations & callbacks | Complex SQL queries |
| Controllers & routes | Action Mailer |
| ERB templates | Action Cable (server component) |

The goal is offline-first SPAs and edge deployment—not replacing Rails entirely.

## See Also

- [Rails Filter Reference](/docs/filters/rails) — Complete transpilation documentation
- [ERB Filter](/docs/filters/erb) — Template transpilation details
- [Blog: The Case for Ruby2JS on Rails](https://intertwingly.net/blog/2025/12/28/The-Case-for-Ruby2JS-on-Rails.html) — Why this matters
- [Demo Source](https://github.com/ruby2js/ruby2js/tree/master/demo/ruby2js-on-rails) — Example project
