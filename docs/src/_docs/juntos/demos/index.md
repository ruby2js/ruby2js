---
order: 650
title: Demo Applications
top_section: Juntos
category: juntos-demos
---

# Demo Applications

Hands-on examples showcasing Juntos capabilities. Each demo is a complete Rails application that runs across all supported platforms.

{% toc %}

## Available Demos

| Demo | What It Demonstrates |
|------|---------------------|
| **[Blog](/docs/juntos/demos/blog)** | CRUD operations, nested resources, validations, multi-platform deployment |
| **[Chat](/docs/juntos/demos/chat)** | Real-time Turbo Streams, Stimulus controllers in Ruby, WebSocket broadcasting |

## Running Any Demo

All demos follow the same pattern:

### 1. Create the App

```bash
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/DEMO/create-DEMO | bash -s myapp
cd myapp
```

Replace `DEMO` with `blog` or `chat`.

### 2. Run with Rails (Baseline)

Verify it works as standard Rails:

```bash
RAILS_ENV=production bin/rails db:prepare
bin/rails server -e production
```

### 3. Run in Browser

Same app, no Ruby runtime:

```bash
bin/juntos dev -d dexie
```

### 4. Run on Node.js

Full server with SQLite:

```bash
bin/juntos db:prepare -d sqlite
bin/juntos up -d sqlite
```

### 5. Deploy to Edge

Cloudflare Workers with D1:

```bash
bin/juntos db:prepare -d d1
bin/juntos deploy -d d1
```

The `db:prepare` command creates the D1 database (if needed), runs migrations, and seeds if fresh.

## What Each Demo Teaches

### Blog Demo

The blog is the "hello world" of web frameworks—articles with comments. It covers:

- **Model associations** — `has_many`, `belongs_to`, `dependent: :destroy`
- **Validations** — `presence`, `length`
- **Nested routes** — `resources :articles { resources :comments }`
- **CRUD operations** — All seven RESTful actions
- **Form helpers** — `form_with`, nested forms

Best for understanding how Rails patterns translate to JavaScript.

### Chat Demo

A real-time chat room demonstrating Hotwire patterns:

- **Turbo Streams** — `broadcast_append_to`, `broadcast_remove_to`
- **Stimulus controllers** — Written in Ruby, transpiled to JavaScript
- **WebSocket subscription** — `turbo_stream_from` helper
- **Format negotiation** — `respond_to` with turbo_stream format

Best for understanding real-time features and Hotwire integration.

## Creating Your Own

Use any Rails app as a starting point:

```bash
rails new myapp
cd myapp
# Add your models, controllers, views...
bin/juntos dev -d dexie
```

If something doesn't transpile correctly, check the [Architecture](/docs/juntos/architecture) docs or open an issue.
