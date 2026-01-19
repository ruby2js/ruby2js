---
order: 650
title: Demo Applications
top_section: Juntos
category: juntos-demos
---

## Starting from Content

| Demo | What It Shows |
|------|---------------|
| **[SSG Blog](/docs/juntos/demos/ssg-blog)** | Pure static. Markdown → HTML. Zero JavaScript. |
| **[Astro Blog](/docs/juntos/demos/astro-blog)** | Static pages with interactive islands. Client-side CRUD. |

## Starting from Application

| Demo | What It Shows |
|------|---------------|
| **[Blog](/docs/juntos/demos/blog)** | Full CRUD. Deploy to browser, Node, or Edge. |
| **[Chat](/docs/juntos/demos/chat)** | Real-time Turbo Streams without a Rails server. |
| **[Notes](/docs/juntos/demos/notes)** | JSON API with path helpers as RPC calls. |

## Adding Capabilities

| Demo | What It Shows |
|------|---------------|
| **[Photo Gallery](/docs/juntos/demos/photo-gallery)** | Device APIs via Capacitor and Electron. |
| **[Workflow Builder](/docs/juntos/demos/workflow-builder)** | Third-party React libraries with JSON broadcasting. |

## Try Them

Each demo runs live - click to try without installing anything.

To run locally:

```bash
# Content demos
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/ssg-blog/create-ssg-blog | bash -s myapp

# Application demos (blog, chat, notes, photo_gallery, workflow)
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/blog/create-blog | bash -s myapp
```

---

## What You Just Saw

The conventional wisdom is: pick your stack, stay in your lane. Rails for CRUD, Astro for content, different patterns for each deployment target.

These demos include:

- A Rails app running in a browser with IndexedDB
- The same Rails app deploying to Cloudflare Edge with D1
- The same app packaged for mobile (Capacitor) and desktop (Electron)
- Turbo Streams and Action Cable working without a Rails server
- ActiveRecord queries over markdown files
- Path helpers that work as RPC calls

Same models. Same validations. Same routes. Same controllers. Different runtimes.
