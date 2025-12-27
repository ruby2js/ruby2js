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

There are two ways to get started with Ruby2JS on Rails:

### Option 1: Pre-built Demo

No Ruby installation required. Node.js 22+ is all you need.

```bash
curl -L https://www.ruby2js.com/demo/ruby2js-on-rails.tar.gz | tar xz
cd ruby2js-on-rails
npm install
bin/dev
```

Open http://localhost:3000. The source is Ruby. The runtime is JavaScript.

This demo includes hand-crafted views showcasing various Rails patterns including nested resources (articles with comments), custom layouts, and helper methods.

### Option 2: Rails 8 Scaffolds

If you have Ruby and Rails installed, you can generate an SPA from standard Rails scaffolds:

```bash
rails new blog
cd blog
rails generate scaffold Article title:string body:text
bundle add ruby2js --github ruby2js/ruby2js --require ruby2js/spa
rails generate ruby2js:spa:install
rails ruby2js:spa:build
```

The generated SPA is in `public/spa/blog/`. Run it with:

```bash
cd public/spa/blog
npm install
npm start
```

This approach lets you use familiar Rails generators and conventions, then export to a standalone JavaScript SPA.

## Getting Updates

The demo depends on `ruby2js-rails` which provides adapters, targets, and the ERB runtime. To update to the latest version:

```bash
npm update
```

This fetches the latest beta from ruby2js.com and updates your local installation.

{% rendercontent "docs/note", type: "info" %}
**Beta Distribution**: Ruby2JS 6.0 is distributed via URL-based tarballs during beta. After stable release, packages will be available on npm registry as `ruby2js` and `ruby2js-rails`.
{% endrendercontent %}

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
├── database.yml
└── ruby2js.yml
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

ERB templates become JavaScript render functions. Instance variables become
destructured parameters, and Rails helpers like `link_to` and `truncate` are
transformed:

<div data-controller="combo" data-selfhost="true" data-erb="true" data-options='{
  "eslevel": 2022,
  "filters": ["helpers", "erb", "functions"]
}'></div>

```ruby
<h1><%= link_to @article.title, article_path(@article) %></h1>
<p><%= truncate(@article.body, length: 100) %></p>

<h2>Comments</h2>
<% @article.comments.each do |comment| %>
  <div class="comment">
    <%= comment.body %>
  </div>
<% end %>

<%= link_to "Edit", edit_article_path(@article) %>
<%= button_to "Delete", @article, method: :delete, data: { confirm: "Are you sure?" } %>
```

See the [ERB filter documentation](/docs/filters/erb) for details.

### Validation Errors

Model validations work in the browser just like on the server. When validation fails, errors are displayed in the form:

```erb
<% if @article.errors && @article.errors.length > 0 %>
  <div class="errors">
    <ul>
      <% @article.errors.each do |error| %>
        <li><%= error %></li>
      <% end %>
    </ul>
  </div>
<% end %>

<%= form_for @article do |f| %>
  <%= f.text_field :title %>
  <%= f.text_area :body %>
  <%= f.submit %>
<% end %>
```

The controller uses standard Rails patterns:

```ruby
def create
  @article = Article.new(article_params)
  if @article.save
    redirect_to @article
  else
    render :new  # Re-renders with validation errors
  end
end
```

When `render :new` is called after a failed save, the view automatically receives the model with its populated `errors` array.

## Rails 8 Scaffold Generator

Ruby2JS includes an SPA generator that converts standard Rails scaffolds into standalone JavaScript applications.

### Installation

Add Ruby2JS to an existing Rails application:

```bash
bundle add ruby2js --github ruby2js/ruby2js --require ruby2js/spa
```

### Generate SPA from Scaffolds

After creating scaffolds with `rails generate scaffold`, install and build the SPA:

```bash
rails generate ruby2js:spa:install
rails ruby2js:spa:build
```

The generator:
- Detects all scaffolded resources automatically
- Transpiles models, controllers, and views
- Generates a complete SPA in `public/spa/<app_name>/`
- Configures routes and database adapter

### Configuration

The generator creates `config/ruby2js_spa.rb` with options:

```ruby
Ruby2JS::SPA.configure do |config|
  config.runtime = :browser      # :browser or :node
  config.database = :dexie       # :dexie, :sqljs, :pglite, etc.
  config.scaffolds = %w[Article Comment]  # Auto-detected
  config.root = "articles#index"
end
```

### Running the SPA

```bash
cd public/spa/<app_name>
npm install
npm start        # Development server with hot reload
npm run build    # Production build
```

### Supported Scaffold Features

| Feature | Status |
|---------|--------|
| CRUD operations | ✓ |
| `form_for` / `form_with` | ✓ |
| Validations | ✓ |
| Validation error display | ✓ |
| `has_many` / `belongs_to` | ✓ |
| Nested resources | ✓ |
| `link_to` with models | ✓ |
| `button_to` for delete | ✓ |

## Runtime Architecture

The transpiled JavaScript requires runtime implementations. The demo provides these backed by different storage engines:

### Database Options

| Adapter | Runtime | Storage | npm package |
|---------|---------|---------|-------------|
| dexie | Browser | IndexedDB | `dexie` |
| sql.js | Browser | SQLite (WASM) | `sql.js` |
| pglite | Browser | PostgreSQL (WASM) | `@electric-sql/pglite` |
| better_sqlite3 | Node.js | SQLite file | `better-sqlite3` |
| pg | Node.js | PostgreSQL | `pg` |
| mysql2 | Node.js | MySQL | `mysql2` |

Configure in `config/database.yml`:

```yaml
development:
  adapter: dexie

# Browser with persistence
browser_persistent:
  adapter: pglite
  database: my_app

production:
  adapter: pg
  host: localhost
  database: my_app_production
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

## Transpilation Configuration

Configure transpilation options in `config/ruby2js.yml`:

```yaml
# config/ruby2js.yml
default: &default
  eslevel: 2022
  include:
    - class
    - call
  autoexports: true
  comparison: identity

development:
  <<: *default

production:
  <<: *default
  strict: true
```

### Available Options

| Option | Description |
|--------|-------------|
| **eslevel** | ECMAScript target (2020-2025) |
| **include** | Method conversion opt-ins (`class`, `call`) |
| **autoexports** | Auto-export top-level declarations |
| **comparison** | `equality` (==) or `identity` (===) |
| **strict** | Add "use strict" directive |

### Custom Filters

For applications using Phlex or Stimulus, specify filters explicitly:

```yaml
default: &default
  eslevel: 2022
  filters:
    - phlex
    - stimulus
    - camelCase
    - functions
    - esm
    - return
```

Available filter names:

| Filter | Purpose |
|--------|---------|
| **functions** | Ruby → JS method mappings (`.map`, `.select` → `.filter`, etc.) |
| **esm** | ES module imports/exports |
| **return** | Implicit return handling |
| **erb** | ERB templates → render functions |
| **camelCase** | Convert snake_case to camelCase |
| **phlex** | Phlex components → JS (template literals or React) |
| **stimulus** | Stimulus controllers → JS classes |
| **rails/model** | ActiveRecord models |
| **rails/controller** | ActionController patterns |
| **rails/routes** | Routing DSL |
| **rails/schema** | Schema definitions |
| **rails/seeds** | Database seeds |
| **rails/helpers** | View helpers (`link_to`, `truncate`, etc.) |

{% rendercontent "docs/note", type: "info" %}
When no `filters` key is present, the build uses default Rails filters. Specify filters explicitly when using Phlex, Stimulus, or other non-Rails filters.
{% endrendercontent %}

{% rendercontent "docs/note", type: "info" %}
Filter order matters. When using both `rails/helpers` and `erb` filters, ensure `rails/helpers` comes before `erb` for proper helper support.
{% endrendercontent %}

### Section-Specific Configuration

Different directories can use different filters. Define named sections in `ruby2js.yml`:

```yaml
# config/ruby2js.yml
default: &default
  eslevel: 2022
  comparison: identity
  autoexports: true
  include:
    - class
    - call

# Phlex components use the phlex filter
components:
  <<: *default
  filters:
    - phlex
    - functions
    - esm

# Stimulus controllers use the stimulus filter
controllers:
  <<: *default
  filters:
    - stimulus
    - camelCase
    - functions
    - esm
```

The build process automatically uses section-specific config:
- Files in `app/controllers/` use the `controllers` section
- Files in `app/components/` use the `components` section
- Other files use `default` or environment-specific config

This enables mixing Phlex views and Stimulus controllers in the same project, each transpiled with appropriate filters.

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
    PostgreSQL     IndexedDB/       SQLite/PG/
                   PGLite/sql.js      MySQL
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
