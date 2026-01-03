---
order: 60
title: Roadmap
top_section: Juntos
category: juntos
---

# Roadmap

Juntos currently supports the core Rails patterns: models, controllers, views, routes, migrations, and helpers. The architecture is designed to expand—each Rails subsystem can become a filter that transforms familiar APIs into platform-appropriate implementations.

{% toc %}

## Recently Implemented

### Hotwire (Turbo + Stimulus)

[Hotwire](https://hotwired.dev/) integration is now available. See the [Hotwire documentation](/docs/juntos/hotwire) for details.

**What's included:**

- **Turbo Streams Broadcasting** — Real-time DOM updates via WebSocket
  - `broadcast_append_to`, `broadcast_prepend_to`, `broadcast_replace_to`, `broadcast_remove_to`
  - WebSocket support on Node.js, Bun, Deno, and Cloudflare (Durable Objects)
  - Browser-side `BroadcastChannel` for same-origin tabs

- **View Helpers** — `turbo_stream_from`, `turbo_frame_tag`

- **Stimulus Controllers** — Write controllers in Ruby, transpile to JavaScript
  - Rails middleware serves `.rb` controllers as `.js` on-the-fly
  - Juntos builder generates `controllers/index.js` manifest

## Planned

### Vite Integration

A [Vite](https://vitejs.dev/) plugin ecosystem that makes Ruby a first-class frontend language:

```javascript
// vite.config.js
import { defineConfig } from 'vite';
import { rails } from 'vite-plugin-ruby2js';

export default defineConfig({
  plugins: [rails()]
});
```

**Benefits over current dev server:**

| Feature | Current | With Vite |
|---------|---------|-----------|
| Hot reload | Full page refresh | HMR — state preserved |
| Rebuild speed | Full project | Module-level |
| CSS handling | Separate Tailwind CLI | Built-in PostCSS |
| Production | No optimization | Tree shaking, code splitting |

Hot Module Replacement means editing a view re-renders without losing your current article, form inputs, or scroll position.

**Beyond Juntos:** The same plugin architecture supports Ruby inside [Vue](https://vuejs.org/), [Svelte](https://svelte.dev/), and [Astro](https://astro.build/) components. Write a Juntos backend with Vue or Svelte for interactive parts—all in Ruby. Phlex components become portable across frameworks via ES module imports.

### Active Storage

Transform attachment APIs into cloud storage operations:

```ruby
# What you write
@article.image.attach(params[:image])
@article.image.url

# Browser target: IndexedDB blob storage
# Node target: Local filesystem or S3
# Vercel target: Vercel Blob
# Cloudflare target: R2
```

### Action Cable

WebSocket support for real-time features:

```ruby
# What you write
class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "chat_#{params[:room]}"
  end
end

# Node/Bun/Deno: Native WebSocket server
# Browser: WebSocket client
# Edge: Not supported (platform limitation)
```

### Active Job

Async processing with the Rails Active Job interface:

```ruby
# What you write
ProcessOrderJob.perform_later(@order)

# Browser: Web Worker or deferred execution
# Node: Bull/BullMQ with Redis
# Edge: Not supported (platform limitation)
```

## Under Consideration

### Action Mailer

Transform Rails mailer syntax into email service API calls ([Resend](https://resend.com/), [SendGrid](https://sendgrid.com/), [Postmark](https://postmarkapp.com/)).

### Stimulus Reflex / Hotwire

Server-side DOM updates over WebSocket. Depends on Action Cable.

### Active Record Encryption

Encrypted attributes for sensitive data. Platform-specific crypto APIs.

### Action Text

Rich text content with Trix editor. Requires Active Storage for attachments.

## Contributing

Juntos is open source. If you're interested in implementing any of these features or have ideas for others, see the [Ruby2JS repository](https://github.com/ruby2js/ruby2js).

The filter architecture makes contributions approachable—each feature is a self-contained transformation from Rails patterns to JavaScript implementations.
