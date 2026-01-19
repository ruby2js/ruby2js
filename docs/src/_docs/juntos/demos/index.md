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
| **[Astro Blog](/docs/juntos/demos/astro-blog)** | Astro islands, `.astro.rb` pages, Preact components, ISR caching, IndexedDB |
| **[Chat](/docs/juntos/demos/chat)** | Real-time Turbo Streams, Stimulus controllers in Ruby, WebSocket broadcasting |
| **[Photo Gallery](/docs/juntos/demos/photo-gallery)** | Camera integration, Capacitor mobile apps, Electron desktop apps |
| **[Workflow Builder](/docs/juntos/demos/workflow-builder)** | React Flow integration, real-time collaboration, JSON broadcasting |
| **[Notes](/docs/juntos/demos/notes)** | Path helper RPC, JSON API, Server Functions-style data fetching, React components |

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

### Astro Blog Demo

A static blog demonstrating Astro integration with Ruby2JS:

- **Astro pages** — `.astro.rb` format with Ruby frontmatter and `__END__` template
- **Preact islands** — `.jsx.rb` interactive components with `client:load`
- **ActiveRecord patterns** — Familiar `Post.all`, `Post.find`, `post.save` with IndexedDB
- **ISR caching** — `withRevalidate` for stale-while-revalidate data fetching
- **Full CRUD** — Create, edit, delete posts with cross-component events

Best for understanding Astro integration and static site patterns with Ruby.

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

### Photo Gallery Demo

A camera-enabled gallery demonstrating native device integration:

- **Browser camera** — `getUserMedia()` for webcam access
- **Capacitor camera** — Native iOS/Android camera plugin
- **Electron desktop** — System tray, global shortcuts, background app
- **Binary storage** — Base64 images in any database

Best for understanding Capacitor and Electron targets.

### Workflow Builder Demo

A visual workflow editor demonstrating React integration and real-time collaboration:

- **React Flow** — Third-party React library for node-based editors
- **JSON broadcasting** — `broadcast_json_to` for React state updates
- **React Context** — `JsonStreamProvider` for subscription management
- **Multi-target** — BroadcastChannel (browser) or WebSocket (server)

Best for understanding React component integration and JSON broadcasting patterns.

### Notes Demo

A notes app demonstrating Server Functions-style path helpers and JSON API patterns:

- **Path helper RPC** — `notes_path.get()`, `note_path(id).patch()` return Response objects
- **JSON by default** — Path helpers default to JSON format for React data fetching
- **RBX components** — React components written in Ruby syntax
- **Unified API** — Same code works on browser (direct invocation) and server (HTTP fetch)

Best for understanding Server Functions-style data fetching and JSON API patterns with React.

## Creating Your Own

Use any Rails app as a starting point:

```bash
rails new myapp
cd myapp
# Add your models, controllers, views...
bin/juntos dev -d dexie
```

If something doesn't transpile correctly, check the [Architecture](/docs/juntos/architecture) docs or open an issue.
