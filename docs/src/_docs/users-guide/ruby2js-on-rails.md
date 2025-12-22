---
order: 9.5
title: Ruby2JS on Rails
top_section: User's Guide
category: users-guide-rails
next_page_order: 10
---

# Ruby2JS on Rails

This guide covers transpiling Rails applications to JavaScript, enabling Rails patterns to run in browsers and JavaScript runtimes without a Ruby installation.

{% toc %}

## When to Use This Approach

Ruby2JS on Rails is ideal for:

- **Offline-first applications** — Share validation logic and views between server and browser
- **Static deployment** — Deploy to GitHub Pages, Netlify, S3, Cloudflare Pages
- **Edge computing** — Run MVC patterns on Cloudflare Workers or Vercel Edge
- **Portable bundles** — Distribute Rails-patterned functionality without Ruby dependencies

The transpiled output is compact, native JavaScript with direct access to browser APIs—no runtime library required.

## Quick Start

No Ruby installation required. Node.js 22+ is all you need.

```bash
curl -L https://www.ruby2js.com/demo/ruby2js-on-rails.tar.gz | tar xz
cd ruby2js-on-rails
npm install
bin/dev
```

Open http://localhost:3000. The source is Ruby. The runtime is JavaScript.

## Project Structure

A Ruby2JS on Rails project mirrors standard Rails conventions:

```
app/
├── models/
│   ├── application_record.rb
│   ├── article.rb
│   └── comment.rb
├── controllers/
│   ├── application_controller.rb
│   ├── articles_controller.rb
│   └── comments_controller.rb
└── views/
    ├── layouts/
    │   └── application.html.erb
    └── articles/
        ├── index.html.erb
        ├── show.html.erb
        ├── new.html.erb
        └── edit.html.erb
config/
├── routes.rb
└── database.yml
db/
├── schema.rb
└── seeds.rb
```

The build process transpiles this to:

```
dist/
├── models/
│   ├── application_record.js
│   ├── article.js
│   └── comment.js
├── controllers/
│   ├── articles_controller.js
│   └── comments_controller.js
├── views/
│   └── articles/
│       ├── index.js
│       ├── show.js
│       └── ...
├── routes.js
├── schema.js
└── seeds.js
```

## Development Workflow

The workflow mirrors modern JavaScript development:

**Development:**
```bash
bin/dev  # Start hot-reload server
```

Edit a Ruby file, save, and the browser refreshes automatically.

**Production:**
```bash
npm run build  # Generate static assets
```

Deploy the `dist/` directory anywhere that serves static files.

## What Gets Transpiled

### Models

Standard ActiveRecord patterns translate directly:

<div data-controller="combo" data-selfhost="true" data-options='{
  "eslevel": 2022,
  "filters": ["model", "esm", "functions"]
}'></div>

```ruby
class Article < ApplicationRecord
  has_many :comments, dependent: :destroy
  belongs_to :author, optional: true
  validates :title, presence: true
  validates :body, length: { minimum: 10 }

  scope :published, -> { where(status: 'published') }

  before_save :normalize_title

  private

  def normalize_title
    self.title = title.strip.titleize
  end
end
```

### Controllers

Controllers become JavaScript modules with async functions:

<div data-controller="combo" data-selfhost="true" data-options='{
  "eslevel": 2022,
  "filters": ["controller", "esm", "functions"]
}'></div>

```ruby
class ArticlesController < ApplicationController
  before_action :set_article, only: [:show, :edit, :update, :destroy]

  def index
    @articles = Article.all
    render 'articles/index', articles: @articles
  end

  def create
    @article = Article.new(article_params)
    if @article.save
      redirect_to @article
    else
      render 'articles/new', article: @article
    end
  end

  private

  def set_article
    @article = Article.find(params[:id])
  end
end
```

### Routes

Rails routing DSL works as expected:

<div data-controller="combo" data-selfhost="true" data-options='{
  "eslevel": 2022,
  "filters": ["routes", "esm", "functions"]
}'></div>

```ruby
Rails.application.routes.draw do
  root 'articles#index'

  resources :articles do
    resources :comments, only: [:create, :destroy]
  end
end
```

### ERB Templates

ERB templates become JavaScript render functions:

```erb
<h1><%= @article.title %></h1>
<p><%= @article.body %></p>

<h2>Comments</h2>
<% @article.comments.each do |comment| %>
  <div class="comment">
    <%= comment.body %>
  </div>
<% end %>
```

See the [ERB filter documentation](/docs/filters/erb) for details.

## Runtime Architecture

The transpiled JavaScript requires runtime implementations. The demo provides these backed by different storage engines:

### Database Options

| Adapter | Runtime | Storage | Use Case |
|---------|---------|---------|----------|
| Dexie | Browser | IndexedDB | Offline-first apps |
| sql.js | Browser | SQLite (WASM) | SQL compatibility |
| better-sqlite3 | Node.js | SQLite file | Server deployment |
| pg | Node.js | PostgreSQL | Production server |

Configure in `config/database.yml`:

```yaml
development:
  adapter: dexie

production:
  adapter: better_sqlite3
  database: db/production.sqlite3
```

### Server Runtimes

The same transpiled code runs on multiple JavaScript runtimes:

```bash
bin/rails server                    # Browser (default)
bin/rails server --runtime node     # Node.js
bin/rails server --runtime bun      # Bun
bin/rails server --runtime deno     # Deno
```

Each runtime uses its native HTTP server—no Express or framework overhead.

## Developer Experience

### Console Logging

Rails-style logging appears in browser DevTools:

```
Article Create {title: "Hello", body: "World", created_at: "..."}
Article Update {id: 1, title: "Hello", body: "Updated", updated_at: "..."}
```

Enable "Verbose" logging level to see detailed output.

### Sourcemaps

Ruby files appear in browser DevTools sources:

- Set breakpoints on Ruby lines
- Step through Ruby code
- Inspect variables with Ruby names

The sourcemaps connect running JavaScript back to the Ruby source.

## Filter Configuration

Typical configuration for Rails transpilation:

```ruby
Ruby2JS.convert(source,
  eslevel: 2022,
  filters: [:rails, :esm, :functions, :erb, :active_support]
)
```

| Filter | Purpose |
|--------|---------|
| **rails** | Models, controllers, routes, schema |
| **esm** | ES module imports/exports |
| **functions** | Ruby → JS method mappings |
| **erb** | ERB templates → render functions |
| **active_support** | `blank?`, `present?`, `try`, etc. |

## Limitations

This approach transpiles Rails *patterns*, not the full Rails framework:

| Works | Doesn't Work |
|-------|--------------|
| Models with associations | Metaprogramming (`method_missing`) |
| Validations | Complex SQL queries |
| Callbacks | Action Mailer |
| Controllers | Action Cable (server component) |
| Routes | Active Job |
| ERB templates | Migrations at runtime |
| Logging | eval/exec |

The goal is enabling offline-first applications and static deployment—not replacing Rails entirely.

## Dual Runtime Strategy

A powerful pattern: the same Ruby source runs on both server and browser.

```
                    Ruby Source
                         │
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
    Ruby Runtime    Ruby2JS →       Ruby2JS →
         │          Browser JS      Server JS
         │               │               │
         ▼               ▼               ▼
    PostgreSQL       IndexedDB      SQLite/PG
```

This enables:
- **Single source of truth** — Validation logic in one place
- **Progressive enhancement** — Server renders, browser enhances
- **Offline capability** — Browser works without server
- **Fallback** — Server handles what browser can't

## Example: Validation Sharing

Define validations once in the model:

<div data-controller="combo" data-selfhost="true" data-options='{
  "eslevel": 2022,
  "filters": ["model", "esm", "functions"]
}'></div>

```ruby
class Article < ApplicationRecord
  validates :title, presence: true, length: { maximum: 100 }
  validates :body, presence: true
end
```

The same validation runs:
- On the server (Ruby) before database save
- In the browser (JavaScript) for instant feedback
- Guaranteed consistency—same source, same rules

## See Also

- [Rails Filter Reference](/docs/filters/rails) — Complete filter documentation
- [ERB Filter](/docs/filters/erb) — Template transpilation
- [ActiveSupport Filter](/docs/filters/active_support) — Rails helper methods
- [Demo Source](https://github.com/ruby2js/ruby2js/tree/master/demo/ruby2js-on-rails) — Complete example project
- [Blog Post](https://intertwingly.net/blog/2025/12/21/Ruby2JS-on-Rails.html) — Detailed walkthrough
