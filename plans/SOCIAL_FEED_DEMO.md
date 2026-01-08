# Social Feed Demo - Combined Offline-First App

The culmination demo: combining Blog, Chat, Photo Gallery, and Menu Bar Notes into an offline-capable social feed that syncs across all platforms.

## Overview

| Demo | What It Contributed |
|------|---------------------|
| Blog | CRUD, text content, forms |
| Chat | Real-time Turbo Streams, WebSockets |
| Photo Gallery | Capacitor camera, binary storage |
| Menu Bar Notes | Electron tray, global shortcuts |
| **Social Feed** | All of the above + sync |

### The Story

> Write a Rails app. Deploy the server to Cloudflare Workers. Deploy clients to browser, desktop, and mobile. All work offline. All sync when online. Real-time updates via WebSockets. Same Ruby codebase. No Ruby runtime anywhere.

## Architecture

```
                         Ruby on Rails Source
                                  │
                   ┌──────────────┴──────────────┐
                   ▼                              ▼
            Transpile (server)            Transpile (clients)
                   │                              │
                   ▼                              ▼
┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│     Cloudflare Workers          │  │         Client Apps              │
│  ┌───────────────────────────┐  │  │  ┌─────────────────────────┐    │
│  │  Sync API                 │  │  │  │  Browser (SPA)          │    │
│  │  POST /api/sync           │  │  │  │  └── IndexedDB          │    │
│  │  GET  /api/sync?since=    │  │  │  ├─────────────────────────┤    │
│  └───────────────────────────┘  │  │  │  Electron (Desktop)     │    │
│  ┌───────────────────────────┐  │  │  │  ├── SQLite             │    │
│  │  Durable Objects          │◀─┼──┼──│  └── Menu bar capture   │    │
│  │  (WebSocket hub)          │  │  │  ├─────────────────────────┤    │
│  │  broadcast_append_to      │  │  │  │  Capacitor (Mobile)     │    │
│  └───────────────────────────┘  │  │  │  ├── IndexedDB          │    │
│  ┌───────────────────────────┐  │  │  │  └── Native camera      │    │
│  │  D1 Database              │  │  │  └─────────────────────────┘    │
│  │  (SQLite at edge)         │  │  │                                 │
│  └───────────────────────────┘  │  └─────────────────────────────────┘
└─────────────────────────────────┘
            │                                      │
            └──────────────┬───────────────────────┘
                           │
                    All JavaScript
                    No Ruby Runtime
```

## Data Model

### Post

The unified content type. Text and/or photo, append-only.

```ruby
class Post < ApplicationRecord
  # Identity
  attribute :client_id, :string      # UUID generated on device

  # Content
  attribute :body, :text             # Text content (optional if image)
  attribute :image_data, :text       # Base64 image (optional if body)

  # Metadata
  attribute :author_name, :string    # Display name (no auth, just a name)
  attribute :device_type, :string    # 'browser', 'electron', 'capacitor'
  attribute :created_at, :datetime

  # Sync
  attribute :synced_at, :datetime    # When synced to server (null = pending)

  validates :client_id, presence: true, uniqueness: true
  validate :has_content

  before_create do
    self.client_id ||= SecureRandom.uuid
    self.created_at ||= Time.current
  end

  # Scopes for sync
  scope :since, ->(timestamp) { where('created_at > ?', timestamp) }
  scope :pending_sync, -> { where(synced_at: nil) }

  # Real-time broadcast
  after_create_commit do
    broadcast_append_to "feed",
      target: "posts",
      partial: "posts/post",
      locals: { post: self }
  end

  private

  def has_content
    errors.add(:base, "Post must have body or image") unless body.present? || image_data.present?
  end
end
```

### Why This Model Works

| Decision | Benefit |
|----------|---------|
| `client_id` (UUID) | Unique across devices, no server coordination |
| No `updated_at` | Append-only, no update conflicts |
| No `deleted_at` | No delete, no tombstones |
| No user auth | `author_name` is just display text |
| `synced_at` | Track what's been pushed to server |

## Sync Protocol

### Simple and Conflict-Free

Since posts are append-only with UUID client_ids:
- No conflicts possible (each post is unique)
- Sync = exchange new posts since last sync
- Order by `created_at` for display

### Client → Server (Push)

```ruby
# Client-side sync service
class SyncService
  def push
    pending = Post.pending_sync.to_a
    return if pending.empty?

    response = fetch('/api/sync', {
      method: 'POST',
      body: JSON.stringify({ posts: pending })
    })

    if response.ok
      # Mark as synced
      pending.each do |post|
        post.update(synced_at: Time.current)
      end
    end
  end
end
```

### Server → Client (Pull)

```ruby
# Client-side sync service
class SyncService
  def pull
    since = LocalStorage.get('last_sync_at') || '1970-01-01'

    response = fetch("/api/sync?since=#{since}")
    data = response.json

    data['posts'].each do |post_data|
      # Skip if we already have it (by client_id)
      next if Post.find_by(client_id: post_data['client_id'])
      Post.create(post_data.merge(synced_at: Time.current))
    end

    LocalStorage.set('last_sync_at', data['server_time'])
  end
end
```

### Server Sync Controller

```ruby
# app/controllers/api/sync_controller.rb
class Api::SyncController < ApplicationController
  # GET /api/sync?since=timestamp
  def index
    since = params[:since] ? Time.parse(params[:since]) : Time.at(0)

    render json: {
      posts: Post.since(since).order(:created_at),
      server_time: Time.current.iso8601
    }
  end

  # POST /api/sync
  def create
    posts = params[:posts] || []

    posts.each do |post_params|
      # Idempotent: skip if client_id exists
      next if Post.exists?(client_id: post_params[:client_id])

      Post.create!(
        client_id: post_params[:client_id],
        body: post_params[:body],
        image_data: post_params[:image_data],
        author_name: post_params[:author_name],
        device_type: post_params[:device_type],
        created_at: post_params[:created_at]
      )
    end

    render json: { success: true, server_time: Time.current.iso8601 }
  end
end
```

## Real-Time Updates

When online, new posts broadcast to all connected clients via WebSockets.

### Turbo Stream Subscription

```erb
<%# app/views/posts/index.html.erb %>
<%= turbo_stream_from "feed" %>

<div id="posts">
  <%= render @posts %>
</div>
```

### Cloudflare Durable Objects

For the edge deployment, Durable Objects manage WebSocket connections:

```javascript
// Transpiled from Ruby, runs on Cloudflare
export class FeedBroadcaster {
  constructor(state, env) {
    this.state = state;
    this.sessions = new Set();
  }

  async fetch(request) {
    if (request.headers.get('Upgrade') === 'websocket') {
      const pair = new WebSocketPair();
      this.sessions.add(pair[1]);
      pair[1].accept();

      pair[1].addEventListener('close', () => {
        this.sessions.delete(pair[1]);
      });

      return new Response(null, { status: 101, webSocket: pair[0] });
    }

    // Broadcast message to all sessions
    if (request.method === 'POST') {
      const message = await request.text();
      for (const session of this.sessions) {
        session.send(message);
      }
      return new Response('OK');
    }
  }
}
```

## Platform-Specific Features

### Browser (SPA)

Standard web experience:
- File input fallback for photos (no native camera)
- IndexedDB via Dexie
- Service Worker for offline

### Electron (Desktop)

Menu bar quick capture:
- Tray icon for quick access
- Global shortcut (Cmd+Shift+P) to post
- Native SQLite (better-sqlite3)
- Background sync

```ruby
# Electron-specific Stimulus controller
class TrayController < Stimulus::Controller
  def quickPost
    # Open quick capture popup
    window.electron.showQuickCapture
  end
end
```

### Capacitor (Mobile)

Native camera integration:
- Take photos with device camera
- Choose from photo library
- IndexedDB storage
- Background sync when app resumes

```ruby
# Capacitor-specific Stimulus controller
class CameraPostController < Stimulus::Controller
  def takePhoto
    result = await Camera.getPhoto(
      resultType: CameraResultType::Base64,
      source: CameraSource::Camera,
      quality: 80
    )
    imageDataTarget.value = result.base64String
  end
end
```

## User Interface

### Feed View

```erb
<%# app/views/posts/index.html.erb %>
<div class="social-feed" data-controller="feed sync">
  <header>
    <h1>Social Feed</h1>
    <span data-sync-target="status">●</span>
  </header>

  <!-- New post form -->
  <div class="new-post" data-controller="post-form camera">
    <%= form_with model: Post.new, data: { action: "submit->post-form#submit" } do |f| %>
      <%= f.hidden_field :image_data, data: { camera_target: "imageData" } %>
      <%= f.hidden_field :author_name, value: LocalStorage.get('author_name') %>

      <img data-camera-target="preview" class="hidden" />

      <%= f.text_area :body, placeholder: "What's happening?", rows: 2 %>

      <div class="actions">
        <button type="button" data-action="click->camera#takePhoto" class="camera-btn">
          📷
        </button>
        <%= f.submit "Post" %>
      </div>
    <% end %>
  </div>

  <!-- Real-time subscription -->
  <%= turbo_stream_from "feed" %>

  <!-- Posts list -->
  <div id="posts" class="posts-list">
    <%= render @posts %>
  </div>
</div>
```

### Post Partial

```erb
<%# app/views/posts/_post.html.erb %>
<article id="<%= dom_id(post) %>" class="post">
  <header>
    <strong><%= post.author_name || 'Anonymous' %></strong>
    <span class="device"><%= post.device_type %></span>
    <time><%= post.created_at.strftime('%b %d, %I:%M %p') %></time>
  </header>

  <% if post.image_data.present? %>
    <img src="data:image/jpeg;base64,<%= post.image_data %>" class="post-image" />
  <% end %>

  <% if post.body.present? %>
    <p><%= post.body %></p>
  <% end %>

  <% unless post.synced_at %>
    <span class="pending-badge">Pending sync</span>
  <% end %>
</article>
```

## Sync Controller (Stimulus)

```ruby
class SyncController < Stimulus::Controller
  targets [:status]

  def connect
    @syncService = SyncService.new

    # Sync on load
    sync if navigator.onLine

    # Sync on visibility change (tab becomes active)
    document.addEventListener('visibilitychange') do
      sync if document.visibilityState == 'visible' && navigator.onLine
    end

    # Sync on online event
    window.addEventListener('online') { sync }

    # Update status indicator
    updateStatus
    window.addEventListener('online') { updateStatus }
    window.addEventListener('offline') { updateStatus }
  end

  def sync
    statusTarget.textContent = '↻'
    statusTarget.classList.add('syncing')

    await @syncService.push
    await @syncService.pull

    statusTarget.textContent = '●'
    statusTarget.classList.remove('syncing')
  end

  def updateStatus
    if navigator.onLine
      statusTarget.classList.remove('offline')
      statusTarget.title = 'Online'
    else
      statusTarget.classList.add('offline')
      statusTarget.title = 'Offline - changes will sync when online'
    end
  end
end
```

## Build & Deploy

### Development

```bash
# Create app
curl -sL .../create-social-feed | bash -s social_feed
cd social_feed

# Run Rails server (traditional)
bin/rails db:prepare
bin/rails server
# Visit http://localhost:3000
```

### Deploy Server to Cloudflare

```bash
# Build for Cloudflare Workers
bin/juntos build -t cloudflare -d d1

# Deploy
cd dist
npx wrangler deploy
```

### Build Clients

```bash
# Browser (already deployed with server)
# Static assets served from Workers

# Electron
bin/juntos build -t electron -d better-sqlite3
cd dist-electron
npm install
npm run package  # Creates .dmg/.exe/.AppImage

# Capacitor
bin/juntos build -t capacitor -d dexie
cd dist-capacitor
npm install
npx cap add ios
npx cap add android
npx cap run ios      # Or submit to App Store
npx cap run android  # Or submit to Play Store
```

## Demo Flow

### 1. Multi-Device Setup

Open the app on:
- Browser (laptop)
- Electron (desktop menu bar)
- Capacitor (phone)

### 2. Online Posting

Post from browser → Appears instantly on all devices (WebSocket)

### 3. Offline Posting

1. Go offline on phone
2. Take photo, add caption, post
3. Shows "Pending sync" badge
4. Come online → Syncs automatically
5. Appears on all other devices

### 4. Menu Bar Quick Capture

1. Press Cmd+Shift+P from any app
2. Type quick note in popup
3. Hit Enter → Syncs to all devices

### 5. Photo from Phone

1. Tap camera button
2. Take photo with native camera
3. Add caption, post
4. Syncs to browser and desktop

## What This Proves

| Capability | Demonstrated |
|------------|--------------|
| Offline-first | Works without network |
| Cross-platform sync | All clients stay in sync |
| Real-time updates | WebSocket broadcasting |
| Native APIs | Camera (Capacitor), Tray (Electron) |
| Edge deployment | Cloudflare Workers + D1 |
| No Ruby runtime | Everything is JavaScript |
| Single codebase | Ruby source, JS everywhere |

## File Structure

```
social_feed/
├── app/
│   ├── models/
│   │   └── post.rb
│   ├── controllers/
│   │   ├── posts_controller.rb
│   │   └── api/
│   │       └── sync_controller.rb
│   ├── views/
│   │   ├── posts/
│   │   │   ├── index.html.erb
│   │   │   ├── _post.html.erb
│   │   │   └── create.turbo_stream.erb
│   │   └── layouts/
│   │       └── application.html.erb
│   └── javascript/
│       └── controllers/
│           ├── feed_controller.rb
│           ├── sync_controller.rb
│           ├── post_form_controller.rb
│           ├── camera_controller.rb      # Capacitor
│           └── tray_controller.rb        # Electron
├── config/
│   ├── routes.rb
│   └── database.yml
├── db/
│   ├── schema.rb
│   └── seeds.rb
└── package.json
```

## Implementation Phases

### Phase 1: Core Feed (Browser Only)

- [ ] Post model with client_id
- [ ] Posts controller (index, create)
- [ ] Feed view with Turbo Streams
- [ ] Basic sync service (push/pull)
- [ ] Test in browser with IndexedDB

### Phase 2: Cloudflare Deployment

- [ ] Transpile server to Workers
- [ ] Set up D1 database
- [ ] Set up Durable Objects for WebSocket
- [ ] Deploy and test

### Phase 3: Electron Client

- [ ] Build for Electron target
- [ ] Add tray icon and popup
- [ ] Add global shortcut
- [ ] Native SQLite storage
- [ ] Test sync with server

### Phase 4: Capacitor Client

- [ ] Build for Capacitor target
- [ ] Add camera integration
- [ ] IndexedDB storage
- [ ] Test on iOS and Android
- [ ] Test sync with server

### Phase 5: Polish

- [ ] Offline indicators
- [ ] Sync progress feedback
- [ ] Error handling
- [ ] Loading states
- [ ] Responsive design

### Phase 6: Documentation

- [ ] Create docs/src/_docs/juntos/demos/social-feed.md
- [ ] Architecture overview
- [ ] Deployment guide
- [ ] Create test/social_feed/create-social-feed script

## Success Criteria

1. **Offline works** - All clients function without network
2. **Sync works** - Posts appear on all devices
3. **Real-time works** - Instant updates when online
4. **Native APIs work** - Camera on mobile, tray on desktop
5. **No Ruby server** - Cloudflare Workers only
6. **Single codebase** - All from Ruby source

## Dependencies

This demo depends on:

- [AREL_QUERY_BUILDER.md](AREL_QUERY_BUILDER.md) - Query building, `since` scope
- [Blog Demo](../docs/src/_docs/juntos/demos/blog.md) - CRUD patterns
- [Chat Demo](../docs/src/_docs/juntos/demos/chat.md) - Real-time patterns
- [PHOTO_GALLERY_DEMO.md](PHOTO_GALLERY_DEMO.md) - Capacitor camera
- [MENU_BAR_NOTES_DEMO.md](MENU_BAR_NOTES_DEMO.md) - Electron tray

## References

- [Cloudflare Workers](https://developers.cloudflare.com/workers/)
- [Cloudflare D1](https://developers.cloudflare.com/d1/)
- [Cloudflare Durable Objects](https://developers.cloudflare.com/durable-objects/)
- [Capacitor](https://capacitorjs.com/)
- [Electron](https://www.electronjs.org/)
- [Dexie.js](https://dexie.org/)
