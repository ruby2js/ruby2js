---
order: 670
title: Roadmap
top_section: Juntos
category: juntos
---

# Roadmap

Juntos currently supports the core Rails patterns: models, controllers, views, routes, migrations, and helpers. The architecture is designed to expand—each Rails subsystem can become a filter that transforms familiar APIs into platform-appropriate implementations.

{% toc %}

## Recently Implemented

### Astro Blog Demo with ISR

The [Astro Blog demo](/docs/juntos/demos/astro-blog) showcases Ruby2JS integration with Astro:

- **`.astro.rb` pages** — Ruby frontmatter with `__END__` template separator
- **Preact islands** — `.jsx.rb` components with `client:load` hydration
- **ActiveRecord patterns** — `Post.all`, `Post.find`, `post.save` with IndexedDB
- **ISR caching** — In-memory stale-while-revalidate via `withRevalidate`
- **Full CRUD** — Create, edit, delete with cross-component events

See the [ISR documentation](/docs/juntos/isr) for the caching API.

### Capacitor, Electron & Tauri Targets

Native app support is now available. See the [Photo Gallery demo](/docs/juntos/demos/photo-gallery) for a complete example.

**Capacitor (iOS/Android):**

- **Mobile apps** — Same codebase runs in native WebView
- **Native APIs** — Camera, filesystem, push notifications via Capacitor plugins
- **Distribution** — App Store, Google Play
- **Database** — Dexie (IndexedDB), sql.js, or HTTP-based adapters

**Electron (Desktop):**

- **Desktop apps** — macOS, Windows, Linux
- **System integration** — Tray icons, global shortcuts, IPC
- **Distribution** — DMG, NSIS installer, AppImage
- **Database** — SQLite (better-sqlite3), sql.js, or HTTP-based adapters

**Tauri (Lightweight Desktop):**

- **Desktop apps** — macOS, Windows, Linux with ~3-10MB bundles (vs Electron's ~150MB)
- **System WebView** — Uses native OS WebView instead of bundled Chromium
- **Native features** — Rust backend for OS integration
- **Distribution** — DMG, NSIS installer, AppImage
- **Database** — sql.js, PGlite, or HTTP-based adapters

### Hotwire (Turbo + Stimulus)

[Hotwire](https://hotwired.dev/) integration is now available. See the [Hotwire documentation](/docs/juntos/hotwire) for details.

**What's included:**

- **Turbo Streams Broadcasting** — Real-time DOM updates via WebSocket
  - `broadcast_append_to`, `broadcast_prepend_to`, `broadcast_replace_to`, `broadcast_remove_to`
  - `broadcast_json_to` for React/JavaScript component integration (sends JSON instead of HTML)
  - WebSocket support on Node.js, Bun, Deno, and Cloudflare (Durable Objects)
  - Browser-side `BroadcastChannel` for same-origin tabs

- **View Helpers** — `turbo_stream_from`, `turbo_frame_tag`

- **Stimulus Controllers** — Write controllers in Ruby, transpile to JavaScript
  - Rails middleware serves `.rb` controllers as `.js` on-the-fly
  - Juntos builder generates `controllers/index.js` manifest

See the [Workflow Builder demo](/docs/juntos/demos/workflow-builder) for React integration with JSON broadcasting.

### Active Storage

File attachments work across all deployment targets:

```ruby
# What you write
class Clip < ApplicationRecord
  has_one_attached :audio
end

clip.audio.attach(file)
clip.audio.url
```

**Storage adapters by target:**

- **Browser** — IndexedDB blob storage via Dexie
- **Node.js** — Local filesystem with database-backed metadata
- **Edge (Fly, Cloudflare, Vercel Edge, Deno)** — S3-compatible storage (AWS S3, Cloudflare R2, MinIO)

See the [Dictaphone demo](/docs/juntos/demos/dictaphone) for Active Storage with audio files and AI transcription.

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

### Action Cable

Full Action Cable abstraction for custom channels:

```ruby
# What you write
class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "chat_#{params[:room]}"
  end
end

# Node/Bun/Deno: Native WebSocket server
# Browser: WebSocket client
# Cloudflare: Durable Objects
# Vercel: Not supported (platform limitation)
```

**Note:** Basic real-time features already work via [Turbo Streams broadcasting](/docs/juntos/hotwire)—`broadcast_append_to`, `broadcast_remove_to`, etc. Action Cable would add support for custom channels beyond Turbo Streams.

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

### StimulusReflex

[StimulusReflex](https://docs.stimulusreflex.com/) enables server-side DOM updates over WebSocket—reactive UIs without writing JavaScript. Depends on Action Cable.

### Active Record Encryption

Encrypted attributes for sensitive data. Platform-specific crypto APIs.

### Action Text

Rich text content with Trix editor. Requires Active Storage for attachments.

## Contributing

Juntos is open source. If you're interested in implementing any of these features or have ideas for others, see the [Ruby2JS repository](https://github.com/ruby2js/ruby2js).

The filter architecture makes contributions approachable—each feature is a self-contained transformation from Rails patterns to JavaScript implementations.
