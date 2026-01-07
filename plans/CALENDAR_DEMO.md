# Group Calendar Demo - Offline-First Multi-Platform

A third demo application showcasing offline-first capabilities across browser, Electron (desktop), and Capacitor (mobile) targets, with a Rails server acting as sync coordinator.

## Relationship to Other Plans

This demo sits at the top of the dependency chain:

```
AREL_QUERY_BUILDER (foundational - query building, associations)
        ↓
RAILS_SPA_ENGINE (tooling - manifest, builder, middleware)
        ↓
CALENDAR_DEMO (this plan - first validation)
        ↓
Showcase Scoring (production validation)
```

| Plan | Purpose |
|------|---------|
| **[AREL_QUERY_BUILDER.md](AREL_QUERY_BUILDER.md)** | Query building, associations, includes() |
| **[RAILS_SPA_ENGINE.md](RAILS_SPA_ENGINE.md)** | The tooling (manifest DSL, builder, middleware, sync layer) |
| **CALENDAR_DEMO.md** | First validation: new demo app built from scratch |
| Showcase scoring | Second validation: production app (existing Rails subset) |

The Calendar demo is a Rails app that **uses** the SPA Engine to generate offline-capable browser/Electron/Capacitor apps. Implementation details for middleware (Stage 5), Turbo interceptor (Stage 6), and sync layer (Stage 7) are in the SPA Engine plan.

## Overview

| Demo | Pattern | What It Shows |
|------|---------|---------------|
| Blog | CRUD | Table stakes, Rails conventions |
| Chat | Real-time | Turbo Streams, WebSockets, broadcasting |
| **Calendar** | Offline + Sync | Device ↔ Server, same models, local-first |

### The Story

> Write a Rails app. Deploy it anywhere - traditional server, edge, browser, desktop, or mobile. Works offline. Syncs when online. Same codebase. Ruby runtime optional.

This is something Rails genuinely can't do on its own.

## Architecture

Two server options - same offline clients:

### Option A: Rails Server (Traditional)

```
┌──────────────────────────────────────────────────────┐
│                    Rails App                          │
│  ┌─────────────────────────────────────────────────┐ │
│  │  Rack Middleware                                │ │
│  │  ├── /offline → Browser app (Juntos/IndexedDB) │ │
│  │  └── /* → Normal Rails (server-rendered)       │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  • Primary web app (server-rendered Rails)          │
│  • Serves offline-capable browser app via middleware │
│  • Sync API endpoints for all offline clients       │
│  • Requires Ruby runtime                            │
└──────────────────────────────────────────────────────┘
              ▲                ▲                ▲
              │ sync           │ sync           │ sync
        ┌─────┴─────┐    ┌─────┴─────┐    ┌─────┴─────┐
        │  Browser  │    │ Electron  │    │ Capacitor │
        │ (offline) │    │ (desktop) │    │ (mobile)  │
        │ IndexedDB │    │  SQLite   │    │ IndexedDB │
        └───────────┘    └───────────┘    └───────────┘
```

### Option B: Edge Server (Serverless)

```
┌──────────────────────────────────────────────────────┐
│              Cloudflare Workers (Transpiled)          │
│  ┌─────────────────────────────────────────────────┐ │
│  │  Middleware (transpiled Rack → Fetch API)       │ │
│  │  ├── /offline → Static assets (KV/R2)          │ │
│  │  └── /* → Transpiled controllers               │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  • Same codebase, transpiled to JavaScript          │
│  • D1 database (SQLite-compatible)                  │
│  • Sync API endpoints (same code, different runtime)│
│  • No Ruby runtime needed anywhere                  │
└──────────────────────────────────────────────────────┘
              ▲                ▲                ▲
              │ sync           │ sync           │ sync
        ┌─────┴─────┐    ┌─────┴─────┐    ┌─────┴─────┐
        │  Browser  │    │ Electron  │    │ Capacitor │
        │ (offline) │    │ (desktop) │    │ (mobile)  │
        │ IndexedDB │    │  SQLite   │    │ IndexedDB │
        └───────────┘    └───────────┘    └───────────┘
```

### Key Points

1. **Same codebase** - Write once, deploy to Rails OR edge
2. **Middleware transpiles** - Rack middleware → Fetch API handlers
3. **Sync API everywhere** - Same sync controller on Rails or Cloudflare
4. **Same models everywhere** - `Event`, `MeetingRequest` work on all platforms
5. **Ruby optional** - Edge deployment needs no Ruby runtime

## Data Model

### Event

User's own calendar events. Fully editable offline.

```ruby
class Event < ApplicationRecord
  belongs_to :user

  validates :title, presence: true
  validates :starts_at, presence: true
  validates :ends_at, presence: true

  # For sync
  attribute :client_id, :string      # UUID generated on device
  attribute :synced_at, :datetime    # Last sync timestamp
  attribute :deleted_at, :datetime   # Soft delete for sync

  scope :for_user, ->(user) { where(user: user) }
  scope :visible_to, ->(user) { where(user: user).or(where(visibility: :public)) }
  scope :modified_since, ->(timestamp) { where('updated_at > ?', timestamp) }
end
```

### MeetingRequest

Requests between users. Queued offline, processed when online.

```ruby
class MeetingRequest < ApplicationRecord
  belongs_to :organizer, class_name: 'User'
  belongs_to :invitee, class_name: 'User'

  enum :status, { pending: 0, confirmed: 1, rejected: 2 }

  validates :title, presence: true
  validates :proposed_time, presence: true

  # For sync
  attribute :client_id, :string
  attribute :synced_at, :datetime

  after_create_commit :notify_invitee, if: :persisted_to_server?
end
```

### User

Simplified for demo purposes.

```ruby
class User < ApplicationRecord
  has_many :events, dependent: :destroy
  has_many :organized_meetings, class_name: 'MeetingRequest', foreign_key: :organizer_id
  has_many :received_meetings, class_name: 'MeetingRequest', foreign_key: :invitee_id

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
end
```

## Sync Strategy

### Client-Side (Offline App)

Each offline client maintains:

1. **Local events** - User's own events (full CRUD offline)
2. **Cached events** - Other users' public events (read-only cache)
3. **Pending queue** - Changes waiting to sync
4. **Last sync timestamp** - For delta sync

```javascript
// Sync service (runs on all offline targets)
class SyncService {
  async sync() {
    if (!navigator.onLine) return;

    // 1. Push local changes
    await this.pushPendingChanges();

    // 2. Pull remote changes
    await this.pullChanges();

    // 3. Update last sync timestamp
    this.lastSyncAt = new Date();
  }

  async pushPendingChanges() {
    const pending = await LocalDB.getPendingChanges();
    for (const change of pending) {
      await this.pushChange(change);
    }
  }

  async pullChanges() {
    const response = await fetch(`/api/sync?since=${this.lastSyncAt}`);
    const { events, meeting_requests } = await response.json();
    await LocalDB.mergeRemoteChanges(events, meeting_requests);
  }
}
```

### Server-Side (Rails API)

```ruby
# app/controllers/api/sync_controller.rb
class Api::SyncController < ApplicationController
  # GET /api/sync?since=timestamp
  def index
    since = params[:since] ? Time.parse(params[:since]) : Time.at(0)

    render json: {
      events: current_user.events.modified_since(since) +
              Event.visible_to(current_user).modified_since(since),
      meeting_requests: current_user.all_meeting_requests.modified_since(since),
      server_time: Time.current
    }
  end

  # POST /api/sync
  def create
    changes = params[:changes]

    changes[:events]&.each { |e| sync_event(e) }
    changes[:meeting_requests]&.each { |mr| sync_meeting_request(mr) }

    render json: { success: true, server_time: Time.current }
  end

  private

  def sync_event(event_params)
    event = Event.find_by(client_id: event_params[:client_id])

    if event
      event.update(event_params) if event_params[:updated_at] > event.updated_at
    else
      current_user.events.create(event_params)
    end
  end
end
```

### Conflict Resolution

Simple last-write-wins based on `updated_at`:

1. Each change has a timestamp
2. Server compares timestamps
3. Most recent change wins
4. Client receives authoritative state after sync

For meeting requests (state machine), server is authoritative:

1. Client sends state change request
2. Server validates transition
3. Server broadcasts new state to all parties

## Rack Middleware

The Rails app serves the offline-capable browser app via middleware:

```ruby
# lib/juntos/offline_middleware.rb
module Juntos
  class OfflineMiddleware
    def initialize(app, options = {})
      @app = app
      @offline_path = options[:path] || '/offline'
      @static_server = Rack::Static.new(
        -> (env) { [404, {}, []] },
        urls: [''],
        root: Rails.root.join('public/offline'),
        index: 'index.html'
      )
    end

    def call(env)
      if env['PATH_INFO'].start_with?(@offline_path)
        # Rewrite path and serve from public/offline
        env['PATH_INFO'] = env['PATH_INFO'].sub(@offline_path, '')
        env['PATH_INFO'] = '/index.html' if env['PATH_INFO'].empty? || env['PATH_INFO'] == '/'
        @static_server.call(env)
      else
        @app.call(env)
      end
    end
  end
end

# config/application.rb
config.middleware.use Juntos::OfflineMiddleware, path: '/offline'
```

### Build Integration

```ruby
# lib/tasks/juntos.rake
namespace :juntos do
  desc "Build offline app for embedding"
  task build_offline: :environment do
    system('bin/juntos', 'build', '-t', 'browser', '-d', 'dexie', '-o', 'public/offline')
  end
end

# Hook into assets:precompile for production
Rake::Task['assets:precompile'].enhance(['juntos:build_offline'])
```

## Target-Specific Implementation

### Browser Target

Served via middleware from `/offline`. Uses existing browser target infrastructure.

```
Storage: IndexedDB (Dexie)
Sync: Fetch API to /api/sync
Service Worker: For true offline capability
```

**Service Worker Addition:**

```javascript
// public/offline/sw.js
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open('calendar-v1').then((cache) => {
      return cache.addAll([
        '/offline/',
        '/offline/app.js',
        '/offline/styles.css',
        // ... other assets
      ]);
    })
  );
});

self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request).then((response) => {
      return response || fetch(event.request);
    })
  );
});
```

### Electron Target (Desktop)

New target that wraps the Node.js server in an Electron shell.

```
Storage: SQLite (better-sqlite3)
Sync: Same API, different storage backend
Run: npm start (developer use)
```

**Generated Files:**

```
dist/
├── main.js              # Electron main process
├── preload.js           # Context bridge
├── package.json         # Electron dependencies
├── lib/                 # Rails.js framework (node target)
├── app/                 # Transpiled app
└── config/              # Routes, database config
```

**main.js:**

```javascript
const { app, BrowserWindow } = require('electron');
const { spawn } = require('child_process');
const path = require('path');

let mainWindow;
let server;

async function startServer() {
  // Start the Node.js server
  const serverPath = path.join(__dirname, 'server.js');
  server = spawn('node', [serverPath], {
    env: { ...process.env, PORT: '3456' }
  });

  // Wait for server to be ready
  await new Promise(resolve => setTimeout(resolve, 1000));
}

async function createWindow() {
  await startServer();

  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true
    }
  });

  mainWindow.loadURL('http://localhost:3456');
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (server) server.kill();
  app.quit();
});
```

### Capacitor Target (Mobile)

New target that wraps the browser app in a native container.

```
Storage: IndexedDB (same as browser, persists in WebView)
Sync: Same API
Run: npx cap run ios/android (developer use)
Native APIs: Camera, push notifications (future)
```

**Generated Files:**

```
dist/
├── capacitor.config.ts  # Capacitor configuration
├── package.json         # Capacitor dependencies
├── www/                 # Browser app output
│   ├── index.html
│   ├── app.js
│   └── ...
├── ios/                 # Generated by cap add ios
└── android/             # Generated by cap add android
```

**capacitor.config.ts:**

```typescript
import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.example.calendar',
  appName: 'Calendar',
  webDir: 'www',
  server: {
    // For development, proxy to Rails server
    url: 'http://localhost:3000/offline',
    cleartext: true
  },
  plugins: {
    // Future: push notifications, camera, etc.
  }
};

export default config;
```

## Implementation Plan

The Calendar demo builds on the [SPA Engine](RAILS_SPA_ENGINE.md) infrastructure. Phases are sequenced to validate SPA Engine stages as they're completed.

### Phase 1: Rails App + SPA Engine Integration

**Goal:** Working calendar that uses SPA Engine to generate offline browser app.

**Depends on:** SPA Engine Stages 1-4 (complete), Stage 5 (Rack Middleware)

1. **Create Rails app structure**
   - [ ] Generate models (User, Event, MeetingRequest)
   - [ ] Create migrations with sync fields (client_id, synced_at, deleted_at)
   - [ ] Add validations and associations
   - [ ] Seed data (demo users)

2. **Build Rails UI**
   - [ ] Calendar view (week/month)
   - [ ] Event CRUD
   - [ ] Meeting request workflow
   - [ ] User switching (for demo purposes)

3. **Add SPA Engine manifest**
   - [ ] `rails generate ruby2js:spa:install --name calendar`
   - [ ] Configure models, controllers, views in manifest
   - [ ] `rails ruby2js:spa:build` generates browser app

4. **Add Sync API** (server-side only)
   - [ ] GET /api/sync endpoint
   - [ ] POST /api/sync endpoint
   - [ ] Authentication (simple token for demo)

5. **Validate SPA Engine Stage 5**
   - [ ] Rack middleware serves SPA at `/offline`
   - [ ] Test offline functionality

**Depends on:** SPA Engine Stage 6 (Turbo Interceptor), Stage 7 (Sync Layer)

6. **Validate SPA Engine Stages 6-7**
   - [ ] Turbo interceptor handles offline navigation
   - [ ] Sync layer pushes/pulls changes
   - [ ] Conflict resolution works

### Phase 2: Edge Server Option

**Goal:** Deploy the server to Cloudflare Workers - no Ruby runtime needed anywhere.

This transforms the architecture from "Rails server + offline clients" to "Edge server + offline clients" where everything is transpiled JavaScript.

```
┌─────────────────┐         ┌─────────────────┐
│  Rails Server   │         │  Edge Server    │
│  (Ruby)         │   OR    │  (Transpiled)   │
│  SQLite/Postgres│         │  D1 database    │
└────────┬────────┘         └────────┬────────┘
         │ sync                      │ sync
    ┌────┴────┐                 ┌────┴────┐
    ▼         ▼                 ▼         ▼
 Browser   Desktop           Browser   Desktop
 (Dexie)   (SQLite)          (Dexie)   (SQLite)
```

**Story upgrade:** "Write a Rails app. Deploy everywhere. No Ruby server needed."

1. **Middleware transpilation**
   - [ ] Rack `call(env)` → Fetch API `fetch(request, env)`
   - [ ] Rack env hash → Request/URL properties
   - [ ] Rack response tuple → Response object
   - [ ] Middleware chaining (`@app.call`)

2. **Sync API on edge**
   - [ ] Same sync controller, transpiled
   - [ ] D1 as server database
   - [ ] Authentication (edge-compatible)

3. **Build integration**
   - [ ] `juntos deploy -t cloudflare` includes sync API
   - [ ] Generates worker with middleware + routes + sync
   - [ ] D1 migrations from schema.rb

4. **Validate full serverless story**
   - [ ] No Ruby runtime anywhere
   - [ ] Same models on edge (D1) and client (Dexie)
   - [ ] Sync works between edge and offline clients

### Phase 3: Electron Target

**Goal:** Same app as desktop application (developer use).

1. **Create Electron target in builder.rb**
   - [ ] Add 'electron' to targets
   - [ ] Generate main.js, preload.js
   - [ ] Generate Electron package.json

2. **Implement generate_electron_config()**
   - [ ] Electron main process template
   - [ ] Preload script for context isolation
   - [ ] Build integration

3. **Add to CLI**
   - [ ] `juntos build -t electron`

4. **Documentation**
   - [ ] Electron setup guide
   - [ ] Development workflow (npm start)

### Phase 3: Capacitor Target

**Goal:** Same app as mobile application (developer use).

1. **Create Capacitor target in builder.rb**
   - [ ] Add 'capacitor' to targets
   - [ ] Generate capacitor.config.ts
   - [ ] Generate appropriate package.json

2. **Implement generate_capacitor_config()**
   - [ ] Capacitor config template
   - [ ] Instructions for iOS/Android project initialization

3. **Add to CLI**
   - [ ] `juntos build -t capacitor`

4. **Documentation**
   - [ ] Capacitor setup guide
   - [ ] Running on own devices (npx cap run ios/android)
   - [ ] Xcode/Android Studio requirements

### Phase 4: Documentation & Polish

1. **Demo documentation**
   - [ ] Create docs/src/_docs/juntos/demos/calendar.md
   - [ ] Update demos index
   - [ ] Add to deployment overview

2. **Target documentation**
   - [ ] Create docs/src/_docs/juntos/deploying/electron.md
   - [ ] Create docs/src/_docs/juntos/deploying/capacitor.md
   - [ ] Update deployment overview with new targets

3. **Create script**
   - [ ] test/calendar/create-calendar script
   - [ ] Include all three target examples

## User Experience

### Demo Flow

1. **Start with Rails**
   ```bash
   curl -sL .../create-calendar | bash -s calendar
   cd calendar
   bin/rails db:prepare
   bin/rails server
   ```
   Open http://localhost:3000 - full Rails app

2. **Try offline browser**

   Open http://localhost:3000/offline
   - Add some events
   - Go offline (DevTools → Network → Offline)
   - Events still work!
   - Go online → syncs automatically

3. **Run as desktop app**
   ```bash
   juntos build -t electron
   cd dist
   npm install && npm start
   ```
   Same app, runs as desktop window on your Mac/Windows/Linux

4. **Run on your phone**
   ```bash
   juntos build -t capacitor
   cd dist
   npm install
   npx cap add ios      # or android
   npx cap run ios      # runs on your connected device
   ```
   Same app, runs on your own iPhone/iPad/Android (no App Store needed)

5. **Deploy server to edge (no Ruby needed)**
   ```bash
   juntos deploy -t cloudflare -d d1
   ```
   Same sync API, running on Cloudflare Workers with D1 database.
   No Ruby runtime anywhere - everything is transpiled JavaScript.

### Key Demonstrations

| Feature | Rails Server | Edge Server | Browser | Electron | Capacitor |
|---------|--------------|-------------|---------|----------|-----------|
| View calendar | ✅ | ✅ | ✅ | ✅ | ✅ |
| Create events | ✅ | ✅ | ✅ offline | ✅ offline | ✅ offline |
| See others' events | ✅ | ✅ | ✅ cached | ✅ cached | ✅ cached |
| Meeting requests | ✅ | ✅ | ✅ queued | ✅ queued | ✅ queued |
| Works offline | N/A | N/A | ✅ | ✅ | ✅ |
| Syncs when online | N/A | N/A | ✅ | ✅ | ✅ |
| Ruby runtime | Required | **None** | None | None | None |

## Open Questions

1. **Authentication** - How to handle user identity across offline clients?
   - Option A: Simple token-based (good for demo)
   - Option B: OAuth flow (more realistic)
   - Option C: Device-specific users (simplest)

2. **Conflict resolution** - Last-write-wins is simple but lossy
   - Acceptable for demo?
   - Or show CRDT-style merging?

3. **Real-time updates** - When online, should changes push immediately?
   - Polling (simple)
   - WebSocket (better UX, more complex)
   - Only sync on demand (simplest)

4. **Multi-device same user** - User has phone AND desktop
   - Both should stay in sync
   - Need to handle this in sync logic

## Success Criteria

1. **Same codebase** - One set of models/views works everywhere
2. **True offline** - App fully functional without network
3. **Seamless sync** - Changes merge automatically when online
4. **Easy setup** - Each target buildable with single command
5. **Clear documentation** - Users can follow along and build their own

## Future Enhancements

- **Distribution/Packaging** - electron-builder, App Store submission, code signing
- Push notifications (Capacitor)
- Background sync (Service Worker)
- Native calendar integration
- Recurring events
- Time zone handling
- Attachments (files, images)

## Follow-On: Showcase Scoring Interface

After Calendar validates the SPA Engine with a new demo app, the next step is validating with a **production application**: the offline scoring interface in [Showcase](https://github.com/rubys/showcase).

See [RAILS_SPA_ENGINE.md](RAILS_SPA_ENGINE.md#target-use-case-showcase-scoring) for detailed requirements.

### Target Architecture

Replace the existing JavaScript SPA with SPA Engine-generated Ruby:

```
Server (Rails + SQLite)          Browser (SPA Engine + Dexie)
┌─────────────────────┐          ┌─────────────────────┐
│  Heat.where(...)    │  ──sync→ │  Heat.where(...)    │
│  Score.create(...)  │  ←sync── │  Score.create(...)  │
│                     │          │                     │
│  Same Ruby models   │          │  Same Ruby models   │
│  SQLite database    │          │  Dexie/IndexedDB    │
└─────────────────────┘          └─────────────────────┘
```

**Key insight:** No hydration layer. The browser runs the same ActiveRecord-style queries against Dexie that Rails runs against SQLite.

### Why This Matters

- **Real production app** with actual users (judges at competitions)
- **Complex associations** (Heat → Entry → Lead/Follow → Studio)
- **Offline-critical** (venues often have poor connectivity)
- **Same codebase** proving the "Rails everywhere" vision

## Future Demos

Once Calendar proves the offline-first patterns, additional demos could showcase different domains:

### Offline Kanban (Inspired by Fizzy)

An offline-capable task/issue tracker demonstrating:
- **Board/Column/Card** model with drag-and-drop
- **Personal workflow** - edit your tasks offline, sync when online
- **Conflict resolution** - last-write-wins for card movements
- **Append-only comments** - easy merge strategy

**Use cases:**
- Field workers updating task status
- Construction sites with poor connectivity
- Mobile-first teams
- Personal kanban that syncs across devices

**Scope:** ~500-1000 LOC, 5-6 models (Board, Column, Card, Tag, User)

**Why it's different from Calendar:**
- More complex drag-and-drop interactions
- Card state machine (triage → column → closed)
- Demonstrates sync patterns for ordered lists

**Inspired by [Fizzy](https://github.com/basecamp/fizzy)** (37signals' kanban app) but purpose-built for offline-first rather than real-time collaboration.
