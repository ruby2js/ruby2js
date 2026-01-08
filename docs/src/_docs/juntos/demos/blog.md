---
order: 655
title: Blog Demo
top_section: Juntos
category: juntos/demos
hide_in_toc: true
---

A classic Rails blog with articles and comments. The same code runs on Rails, in browsers with IndexedDB, on Node.js with SQLite, and on edge platforms.

{% toc %}

## Create the App

```bash
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/blog/create-blog | bash -s blog
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

## Run with Rails

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

### Debugging in DevTools

Open DevTools. In the Sources panel, find your Ruby files—`app/models/article.rb`, `app/controllers/articles_controller.rb`. Set breakpoints on Ruby lines. Step through Ruby code. Inspect variables with Ruby names.

The Console shows Rails-style logging:

```
Article Create {title: "Hello", body: "World", created_at: "..."}
Article Update {id: 1, title: "Updated", updated_at: "..."}
```

## Run on Node.js

```bash
bin/juntos db:prepare -d sqlite
bin/juntos up -d sqlite
```

Open http://localhost:3000. Same blog—but now Node.js serves requests, and [better-sqlite3](https://github.com/WiseLibs/better-sqlite3) provides the database.

The `db:prepare` command runs migrations and seeds if the database is fresh. The `up` command builds and starts the server.

Other runtimes work too:

```bash
bin/juntos up -t bun -d sqlite    # Bun runtime
bin/juntos up -t deno -d postgres  # Deno with PostgreSQL
```

## Deploy to Vercel

```bash
bin/juntos db:prepare -d neon
bin/juntos deploy -d neon
```

**Prerequisites:**

1. [Vercel CLI](https://vercel.com/docs/cli) — `npm i -g vercel` and `vercel login`
2. [Create a Vercel project](https://vercel.com/docs/projects/overview) — run `vercel` once to link
3. [Create a Neon database](https://neon.tech/docs/get-started-with-neon/signing-up)
4. Connect database — add `DATABASE_URL` as a Vercel environment variable
5. Local environment — copy credentials to `.env.local` for migrations

Like Rails, migrations run separately from deployment. The `db:prepare` command applies migrations and seeds if fresh. The `deploy` command builds and deploys.

## Deploy to Cloudflare

```bash
bin/juntos db:prepare -d d1
bin/juntos deploy -d d1
```

**Prerequisites:**

1. [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/) — `npm i -g wrangler` and `wrangler login`

The `db:prepare` command creates the D1 database (if not already set up), runs migrations, and seeds if fresh. The database ID is saved to `.env.local` automatically as `D1_DATABASE_ID` (for development) or `D1_DATABASE_ID_PRODUCTION` (for production).

## The Code

The code is idiomatic Rails. **Try it** — edit the Ruby to see how models transpile:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["model", "esm", "functions"]
}'></div>

```ruby
class Article < ApplicationRecord
  has_many :comments, dependent: :destroy
  validates :title, presence: true
  validates :body, presence: true, length: { minimum: 10 }
end
```

**Try it** — controllers also transpile directly:

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

  def show
  end

  def create
    @article = Article.new(article_params)
    if @article.save
      redirect_to @article
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_article
    @article = Article.find(params[:id])
  end
end
```

Nothing special. Nothing modified for transpilation. Standard Rails conventions work.

## What This Demo Shows

### Model Layer

- `has_many` and `belongs_to` associations
- `dependent: :destroy` for cascading deletes
- `validates` with `presence` and `length`

### Controller Layer

- `before_action` callbacks
- Instance variable assignment (`@article`)
- Standard CRUD actions
- `redirect_to` and `render`
- Strong parameters (`article_params`)

### View Layer

- ERB templates with `<%= %>` and `<% %>`
- `link_to`, `button_to`, `form_with`
- Nested forms for comments
- Partials (`_article.html.erb`, `_comment.html.erb`)
- Layouts with `yield`

### Routes

- `resources :articles`
- Nested `resources :comments`
- `root "articles#index"`
- Generated path helpers (`article_path`, `new_article_path`)

## What Works Differently

- **Migrations** — In browsers, migrations run automatically on startup
- **Database** — IndexedDB in browsers, SQLite/PostgreSQL on servers
- **ActiveRecord queries** — Use `where`, `find`, `all`, chainable queries, and basic raw SQL conditions

## What Doesn't Work

- **Complex associations** — `has_many :through` is limited
- **Callbacks** — `after_save` works; `around_*` callbacks don't
- **Scopes** — Lambda scopes need explicit conversion

## Next Steps

- Try the [Chat Demo](/docs/juntos/demos/chat) for real-time features
- Read the [Architecture](/docs/juntos/architecture) to understand what gets generated
- Check [Deployment Guides](/docs/juntos/deploying/) for detailed platform setup
