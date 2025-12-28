# Phlex Blog Demo

A complete blog application with full CRUD operations, built with Phlex views and Rails-style patterns. Demonstrates that Ruby2JS handles real applications, not just toy examples.

## Features

- **Full CRUD** - Create, read, update, delete posts
- **ActiveRecord-style models** - Validations, associations
- **Rails-style routing** - RESTful routes with path helpers
- **Phlex views** - Component-based UI with ApplicationView base class
- **Client-side navigation** - SPA-like experience with History API
- **Browser database** - sql.js (SQLite in WebAssembly)

## Quick Start

```bash
npm install
npm run dev
# Open http://localhost:3000
```

## Architecture

```
Ruby Source                    JavaScript Output
─────────────                  ─────────────────
app/models/*.rb        →       dist/models/*.js       (Rails Model filter)
app/controllers/*.rb   →       dist/controllers/*.js  (Rails Controller filter)
app/components/*.rb    →       dist/components/*.js   (Phlex filter)
app/views/*.rb         →       dist/views/*.js        (Phlex filter)
config/routes.rb       →       dist/config/routes.js  (Rails Routes filter)
```

## Phlex Patterns

### ApplicationView Base Class

Shared helpers available to all views:

```ruby
# app/views/application_view.rb
class ApplicationView < Phlex::HTML
  def truncate(text, length: 100)
    text.length > length ? "#{text[0...length]}..." : text
  end

  def time_ago(time)
    seconds = (Time.now - time).to_i
    case seconds
    when 0..59 then "#{seconds}s ago"
    when 60..3599 then "#{seconds / 60}m ago"
    else "#{seconds / 86400}d ago"
    end
  end
end
```

### View Components

Views extend ApplicationView and are automatically detected in `app/components/` and `app/views/`:

```ruby
# app/components/posts_index_view.rb
class PostsIndexView < ApplicationView
  def view_template
    div(class: "container") do
      render NavComponent.new

      header(class: "page-header") do
        h1 { "Blog Posts" }
        a(href: "/posts/new") { "New Post" }
      end

      @posts.each do |post|
        render PostCardComponent.new(post: post)
      end
    end
  end
end
```

### Component Composition

```ruby
# app/components/post_card_component.rb
class PostCardComponent < ApplicationView
  def view_template
    article(class: "post-card") do
      h2 { a(href: "/posts/#{@post.id}") { @post.title } }
      p { truncate(@post.body, length: 150) }
      span { time_ago(@post.created_at) }
    end
  end
end
```

## Project Structure

```
phlex-blog/
├── app/
│   ├── models/           # ActiveRecord-style models
│   │   └── post.rb
│   ├── controllers/      # Rails-style controllers
│   │   ├── application_controller.rb
│   │   └── posts_controller.rb
│   ├── components/       # Phlex view components
│   │   ├── nav_component.rb
│   │   ├── post_card_component.rb
│   │   ├── post_form_component.rb
│   │   ├── posts_index_view.rb
│   │   ├── posts_show_view.rb
│   │   ├── posts_new_view.rb
│   │   └── posts_edit_view.rb
│   └── views/            # Base views and helpers
│       ├── application_view.rb
│       └── posts.rb
├── config/
│   ├── database.yml      # Database configuration
│   ├── routes.rb         # RESTful routes
│   └── schema.rb         # Database schema
├── db/
│   └── seeds.rb          # Sample data
├── scripts/
│   ├── build.rb          # Ruby transpilation
│   └── smoke-test.mjs    # Verify Ruby/selfhost parity
├── dist/                 # Generated JavaScript
├── index.html            # Entry point
├── styles.css            # Application styles
└── package.json
```

## Database Targets

The same Ruby source can target different databases:

| Target  | Database             | Use Case                   |
| ------- | -------------------- | -------------------------- |
| Browser | sql.js (SQLite WASM) | Client-side SPA            |
| Browser | Dexie (IndexedDB)    | Persistent browser storage |
| Server  | better-sqlite3       | Node.js server             |
| Server  | PostgreSQL           | Production server          |

Configure via `config/database.yml` or `DATABASE` environment variable.

## Smoke Test

Verify Ruby and selfhost transpilation produce identical output:

```bash
node scripts/smoke-test.mjs
```

## See Also

- [Phlex Filter](/docs/filters/phlex) - Phlex DSL reference
- [Rails Filters](/docs/filters/rails) - Model, Controller, Routes filters
- [Ruby2JS-on-Rails Demo](../ruby2js-on-rails/) - Full Rails patterns with ERB
