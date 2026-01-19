---
order: 650
title: Demo Applications
top_section: Juntos
category: juntos-demos
---

# Demo Applications

**Start anywhere. Go anywhere. Same patterns throughout.**

Whether you're publishing content or building an application, the same ActiveRecord patterns work everywhere. Pick your entry point. Move when your needs change. No rewrite required.

{% toc %}

## Starting from Content

When your starting point is markdown files, documentation, or a blog.

| Demo | What It Shows |
|------|---------------|
| **[SSG Blog](/docs/juntos/demos/ssg-blog)** | Pure static. Markdown → HTML. Zero JavaScript. |
| **[Astro Blog](/docs/juntos/demos/astro-blog)** | Add interactivity with islands. Client-side CRUD when needed. |

**The path:** content → static site → interactive islands → client-side app

### SSG Blog

The simplest entry point - a static blog with no JavaScript:

- **Markdown content** — Posts and authors as `.md` files with front matter
- **Content adapter** — ActiveRecord-like queries over markdown
- **Liquid templates** — Standard 11ty templating
- **Zero JavaScript** — Pure static HTML output

Best for understanding the content adapter. When you need interactivity, add islands.

### Astro Blog

Content meets application - static pages with interactive islands:

- **Astro pages** — `.astro.rb` format with Ruby frontmatter
- **Preact islands** — `.jsx.rb` interactive components with `client:load`
- **ActiveRecord patterns** — `Post.all`, `Post.find`, `post.save` with IndexedDB
- **ISR caching** — `withRevalidate` for stale-while-revalidate
- **Full CRUD** — Create, edit, delete posts

Best for understanding how content and application coexist. Static shell, interactive islands.

## Starting from Application

When your starting point is a Rails app with runtime data.

| Demo | What It Shows |
|------|---------------|
| **[Blog](/docs/juntos/demos/blog)** | Full CRUD. Deploy to browser, Node, or Edge. |
| **[Chat](/docs/juntos/demos/chat)** | Add real-time with Turbo Streams. |
| **[Notes](/docs/juntos/demos/notes)** | JSON API patterns, path helper RPC. |

**The path:** Rails → browser (Dexie) → Node (SQLite) → Edge (D1) → add ISR

### Blog

The "hello world" of web frameworks - articles with comments:

- **Model associations** — `has_many`, `belongs_to`, `dependent: :destroy`
- **Validations** — `presence`, `length`
- **Nested routes** — `resources :articles { resources :comments }`
- **CRUD operations** — All seven RESTful actions
- **Multi-platform** — Same app runs on Rails, browser, Node, Edge

Best for understanding how Rails patterns translate to JavaScript across all deployment targets.

### Chat

Real-time capabilities with Hotwire:

- **Turbo Streams** — `broadcast_append_to`, `broadcast_remove_to`
- **Stimulus controllers** — Written in Ruby, transpiled to JavaScript
- **WebSocket subscription** — `turbo_stream_from` helper
- **Format negotiation** — `respond_to` with turbo_stream format

Best for understanding real-time features. Add this capability to any app.

### Notes

JSON API patterns for React data fetching:

- **Path helper RPC** — `notes_path.get()`, `note_path(id).patch()` return Response objects
- **JSON by default** — Path helpers default to JSON format
- **RBX components** — React components written in Ruby syntax
- **Unified API** — Same code works on browser and server

Best for understanding Server Functions-style data fetching with React.

## Adding Capabilities

Focused demos showing specific integrations you can add to any app.

| Demo | Capability |
|------|------------|
| **[Photo Gallery](/docs/juntos/demos/photo-gallery)** | Device APIs (camera, Capacitor, Electron) |
| **[Workflow Builder](/docs/juntos/demos/workflow-builder)** | Third-party React libraries |

### Photo Gallery

Native device integration across platforms:

- **Browser camera** — `getUserMedia()` for webcam access
- **Capacitor camera** — Native iOS/Android camera plugin
- **Electron desktop** — System tray, global shortcuts, background app
- **Binary storage** — Base64 images in any database

Best for understanding Capacitor and Electron targets.

### Workflow Builder

Complex third-party library integration:

- **React Flow** — Third-party React library for node-based editors
- **JSON broadcasting** — `broadcast_json_to` for React state updates
- **React Context** — `JsonStreamProvider` for subscription management
- **Multi-target** — BroadcastChannel (browser) or WebSocket (server)

Best for understanding React component integration and JSON broadcasting patterns.

## Running the Demos

### Content Demos (11ty, Astro)

```bash
# SSG Blog
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/ssg-blog/create-ssg-blog | bash -s myapp
cd myapp
npm run dev

# Astro Blog
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/astro-blog/create-astro-blog | bash -s myapp
cd myapp
npm run dev
```

### Application Demos (Rails)

```bash
# Create any Rails demo (blog, chat, notes, photo_gallery, workflow)
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/DEMO/create-DEMO | bash -s myapp
cd myapp
```

Then deploy anywhere:

```bash
# Run with Rails (baseline)
RAILS_ENV=production bin/rails db:prepare
bin/rails server -e production

# Run in browser (no server)
bin/juntos dev -d dexie

# Run on Node.js
bin/juntos db:prepare -d sqlite
bin/juntos up -d sqlite

# Deploy to Edge (Cloudflare D1)
bin/juntos db:prepare -d d1
bin/juntos deploy -d d1
```

## Creating Your Own

Use any Rails app as a starting point:

```bash
rails new myapp
cd myapp
# Add your models, controllers, views...
bin/juntos dev -d dexie
```

Or start from content:

```bash
# Create content directory with markdown files
# Add @ruby2js/content-adapter
# Query with Post.where(...).order(...)
```

Same patterns, any entry point, any destination.
