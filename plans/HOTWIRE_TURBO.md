# Hotwire Turbo Integration Plan

This plan covers full Hotwire Turbo support for Juntos, enabling real-time updates across browser windows. Real-time broadcasting works on Browser (BroadcastChannel), Node/Bun/Deno (WebSocket), and Cloudflare (Durable Objects). Vercel lacks native WebSocket support and will have broadcasting stubbed out.

## Blog Post Series Context

This is **Post 2** in a four-part series demonstrating Ruby2JS/Juntos capabilities:

| Post | Plan | Theme | Key Proof |
|------|------|-------|-----------|
| 1 | — | Patterns | Rails conventions transpile to JS |
| **2** | **HOTWIRE_TURBO.md** | **Frameworks** | **Ruby becomes valid Stimulus/Turbo JS** |
| 3 | [VITE_RUBY2JS.md](./VITE_RUBY2JS.md) | Tooling | Ruby as first-class frontend language |
| 4 | [PHLEX_UNIFICATION.md](./PHLEX_UNIFICATION.md) | Portability | Same Ruby → Phlex JS or React |

**This post proves:** Ruby transpiles to valid framework code that Stimulus accepts—not just "Rails-like" patterns, but actual JavaScript that tools recognize.

**Teaser for next post:** "If Ruby works for Stimulus, why stop there?"

## Current Status (January 2026)

### Completed

| Phase | Component | Status | Notes |
|-------|-----------|--------|-------|
| 1 | Turbo Drive | ✅ Complete | Navigation via Turbo, no custom handlers |
| 2 | Turbo Frames | ✅ Complete | `turbo_frame_tag` helper works |
| 3a | Turbo Stream Helpers | ✅ Complete | All 7 actions implemented |
| 3b | Server Format Negotiation | ✅ Complete | `respond_to` with Accept header checking |
| 4 | Model Broadcasting | ✅ Complete | All broadcast_*_to methods |
| 5 | turbo_stream_from | ✅ Complete | View subscriptions work |
| 6 | Stimulus Controllers | ✅ Complete | Ruby transpilation + JS copy |

### Platform Support

| Platform | Turbo Drive | Turbo Streams | Broadcasting | Status |
|----------|-------------|---------------|--------------|--------|
| Browser | ✅ | ✅ | ✅ BroadcastChannel | **Tested** |
| Node.js | ✅ | ✅ | ✅ WebSocket (`ws`) | **Tested** |
| Bun | ✅ | ✅ | ✅ Native WebSocket | Untested |
| Deno | ✅ | ✅ | ✅ Native WebSocket | Untested |
| Cloudflare | ✅ | ✅ | ⚠️ Durable Objects | **Needs fixes** |
| Vercel | ✅ | ✅ | ❌ Stubbed | By design |

### What Works Now

- **Blog demo**: Browser (dexie) and Node (sqlite) targets tested and working
- **Chat demo**: Created with `test/chat/create-chat`, Turbo Streams broadcasting functional
- **Stimulus controllers**: Ruby controllers transpile correctly (fixed 2026-01-04)
  - Builder now uses dedicated STIMULUS_OPTIONS with Stimulus filter
  - Uses `autoexports: :default` for Rails-convention `export default class`
  - `@hotwired/stimulus` added to browser importmap
  - Controllers imported via `/app/javascript/controllers/index.js`
- **422 status for validation errors**: All targets return proper status for Turbo Drive

### Remaining Work: Cloudflare Durable Objects

The Cloudflare target has all the code but the deployment configuration is incomplete:

| Component | Location | Status | Issue |
|-----------|----------|--------|-------|
| D1 adapter | `packages/ruby2js-rails/adapters/active_record_d1.mjs` | ✅ Complete | — |
| Cloudflare target | `packages/ruby2js-rails/targets/cloudflare/rails.js` | ✅ Complete | — |
| TurboBroadcaster DO | Lines 170-290 in cloudflare target | ✅ Complete | — |
| wrangler.toml (builder) | `lib/ruby2js/rails/builder.rb:1485` | ⚠️ Incomplete | Missing DO binding |
| wrangler.toml (deploy) | `lib/ruby2js/cli/deploy.rb:234` | ⚠️ Incomplete | Missing DO binding |
| Entry point (builder) | `lib/ruby2js/rails/builder.rb:1509` | ⚠️ Incomplete | Missing DO export |
| Entry point (deploy) | `lib/ruby2js/cli/deploy.rb:260` | ⚠️ Incomplete | Missing DO export |
| CLI migrate -d d1 | `lib/ruby2js/cli/migrate.rb` | ✅ Complete | Uses wrangler d1 execute |
| CLI deploy -t cloudflare | `lib/ruby2js/cli/deploy.rb` | ✅ Complete | Runs wrangler deploy |

### Fixes Required

**1. Add Durable Objects to wrangler.toml generation** (two locations):

```toml
# Add after [[d1_databases]] section:
[[durable_objects.bindings]]
name = "TURBO_BROADCASTER"
class_name = "TurboBroadcaster"

[[migrations]]
tag = "v1"
new_classes = ["TurboBroadcaster"]
```

**2. Export TurboBroadcaster from entry point** (two locations):

```javascript
import { Application, Router, TurboBroadcaster } from '../lib/rails.js';
// ... existing code ...
export default Application.worker();
export { TurboBroadcaster };  // ADD THIS LINE
```

### Files to Modify

1. `lib/ruby2js/rails/builder.rb`
   - Line ~1485: `generate_cloudflare_config()` - add DO binding to wrangler.toml
   - Line ~1509: `generate_cloudflare_entry_point()` - add TurboBroadcaster export

2. `lib/ruby2js/cli/deploy.rb`
   - Line ~234: `generate_cloudflare_config()` - add DO binding to wrangler.toml
   - Line ~260: worker entry point generation - add TurboBroadcaster export

### Testing Plan

After fixes:
1. Create chat demo: `curl ... | bash -s chat`
2. `cd chat`
3. Create D1 database: `wrangler d1 create chat`
4. Add D1_DATABASE_ID to `.env.local`
5. Migrate: `bin/juntos migrate -d d1`
6. Deploy: `bin/juntos deploy -d d1` (builds automatically)
7. Test real-time: Open two browser windows, send messages

---

## Architecture Overview

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                            TURBO INTEGRATION                                   │
├───────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Browser   │  │ Node/Bun/   │  │ Cloudflare  │  │       Vercel        │  │
│  │             │  │   Deno      │  │             │  │                     │  │
│  ├─────────────┤  ├─────────────┤  ├─────────────┤  ├─────────────────────┤  │
│  │ Turbo Drive │  │ Turbo Drive │  │ Turbo Drive │  │ Turbo Drive         │  │
│  │ Turbo Stream│  │ Turbo Stream│  │ Turbo Stream│  │ Turbo Streams       │  │
│  │ Turbo Frame │  │ Turbo Frame │  │ Turbo Frame │  │ Turbo Frames        │  │
│  ├─────────────┤  ├─────────────┤  ├─────────────┤  ├─────────────────────┤  │
│  │Broadcast-   │  │ WebSocket   │  │ Durable     │  │ ❌ No real-time     │  │
│  │Channel API  │  │ Server      │  │ Objects     │  │   (stubbed)         │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│                                                                                │
│  ┌───────────────────────────────────────────────────────────────────────────┐│
│  │                         Stimulus Controllers                              ││
│  │              .js files → copy       .rb files → transpile                 ││
│  └───────────────────────────────────────────────────────────────────────────┘│
└───────────────────────────────────────────────────────────────────────────────┘
```

## Current State

### Existing Turbo Filter
`lib/ruby2js/filter/turbo.rb` only handles custom Turbo Stream actions:
```ruby
Turbo.stream_action :log do
  console.log targetElements
end
# → Turbo.StreamActions.log = function() { console.log(this.targetElements) }
```

### Current Navigation System
- Custom `navigate(event, path)` function with History API
- Every `link_to` generates: `<a href="/path" onclick="return navigate(event, '/path')">`
- Forms use custom `routes.model.method(event, id)` handlers
- Defined in `packages/ruby2js-rails/targets/browser/rails.js`

## Implementation Phases

### Phase 1: Turbo Drive (Navigation)

**Goal**: Remove custom `navigate()` handlers, let Turbo intercept links/forms automatically.

| Component | Current | After |
|-----------|---------|-------|
| Links | `<a onclick="return navigate(...)">` | `<a href="/path">` |
| Forms | `<form onsubmit="return routes.x.post(event)">` | `<form action="/path" method="post">` |
| Delete | Custom onclick with confirm | `data-turbo-method="delete" data-turbo-confirm="..."` |

**Files to modify**:
- `lib/ruby2js/filter/rails/helpers.rb` - Remove onclick/onsubmit handlers (~10 locations in lines 380-520)
- `lib/ruby2js/rails/builder.rb` - Add Turbo to index.html importmap and server layouts
- `packages/ruby2js-rails/targets/browser/rails.js` - Remove custom Router/navigate code

**New data attribute handling**:
```ruby
link_to "Delete", article, method: :delete, data: { turbo_confirm: "Sure?" }
# → <a href="/articles/1" data-turbo-method="delete" data-turbo-confirm="Sure?">
```

**Turbo inclusion**:
- Browser: Add to importmap in `generate_index_html()`
- Server: Add `<script type="module" src="...turbo...">` to layout

---

### Phase 2: Turbo Frames (Partial Updates)

**Goal**: Support `<turbo-frame>` for scoped navigation.

**New helper in `lib/ruby2js/filter/turbo.rb`**:
```ruby
turbo_frame_tag "comments" do
  render @article.comments
end
# → <turbo-frame id="comments">...</turbo-frame>

turbo_frame_tag "edit", src: edit_article_path(@article)
# → <turbo-frame id="edit" src="/articles/1/edit"></turbo-frame>
```

**Attributes to support**:
- `id` (required)
- `src` (lazy loading)
- `target` (_top, _self, frame-id)
- `loading` (eager, lazy)

---

### Phase 3: Turbo Streams (Controller Responses)

**Goal**: Support `turbo_stream.replace/append/prepend/remove/update` in controllers.

**Controller pattern** (from showcase app):
```ruby
respond_to do |format|
  format.turbo_stream {
    render turbo_stream: turbo_stream.replace('list', partial: 'items')
  }
  format.html { redirect_to items_path }
end
```

**Stream actions to implement**:
| Action | Description |
|--------|-------------|
| `append` | Add to end of target |
| `prepend` | Add to beginning of target |
| `replace` | Replace entire target element |
| `update` | Replace target's innerHTML |
| `remove` | Remove target element |
| `before` | Insert before target |
| `after` | Insert after target |

**Output format**:
```html
<turbo-stream action="replace" target="list">
  <template><!-- rendered partial --></template>
</turbo-stream>
```

**Files to modify**:
- `lib/ruby2js/filter/turbo.rb` - Add stream action helpers ✅ (done)
- `lib/ruby2js/filter/rails/controller.rb` - Add `respond_to` format.turbo_stream handling (server targets)
- Server runtime - Check Accept header for `text/vnd.turbo-stream.html` (server targets)

**Server-side format negotiation** (for Node/Cloudflare/etc, not browser):
The controller filter currently extracts only `format.html` bodies. For full Turbo Stream support on server targets:
1. Transform `respond_to` blocks to check `request.headers.accept` at runtime
2. If Accept includes `text/vnd.turbo-stream.html`, execute `format.turbo_stream` block
3. Otherwise execute `format.html` block
4. Set appropriate `Content-Type` header in response

This is not needed for browser SPAs (we intercept all requests client-side).

**Multiple streams**:
```ruby
render turbo_stream: [
  turbo_stream.replace('package-select', partial: 'package'),
  turbo_stream.replace('options-select', partial: 'options')
]
```

---

### Phase 4: Model Broadcasting (Real-time)

**Goal**: Support `broadcast_replace_to`, `broadcast_replace_later_to` in models.

**Pattern from showcase app** (`app/models/score.rb`):
```ruby
after_save do |score|
  broadcast_replace_later_to "live-scores-#{ENV['RAILS_APP_DB']}",
    partial: 'scores/last_update',
    target: 'last-score-update',
    locals: { action: false, timestamp: score.updated_at }
end
```

**Broadcast methods to implement**:
| Method | Description |
|--------|-------------|
| `broadcast_replace_to` | Immediate replace |
| `broadcast_replace_later_to` | Deferred (setTimeout/Promise) |
| `broadcast_append_to` | Immediate append |
| `broadcast_append_later_to` | Deferred append |
| `broadcast_prepend_to` | Immediate prepend |
| `broadcast_remove_to` | Immediate remove |

**Implementation by platform**:

| Platform | Pub/Sub Mechanism | Implementation |
|----------|-------------------|----------------|
| Browser | `BroadcastChannel` API | Same-origin tabs communicate directly |
| Node/Bun/Deno | WebSocket server | Simple custom protocol (see below) |
| Cloudflare | Durable Objects | Native WebSocket with hibernation |
| Vercel | Stubbed (no-op) | No persistent connections possible |

**WebSocket Protocol** (simple, not Action Cable compatible initially):
```javascript
// Client → Server
{ type: "subscribe", stream: "article_1_comments" }
{ type: "unsubscribe", stream: "article_1_comments" }

// Server → Client
{ type: "message", stream: "article_1_comments", html: "<turbo-stream ...>" }
```

This is intentionally minimal. A full Action Cable-compatible implementation can be added later for Rails interop. For now, we control both ends and can use the simplest thing that works.

**Cloudflare Durable Objects Implementation**:

Cloudflare provides native WebSocket support via Durable Objects with hibernation (no idle costs).

*Generated Durable Object class* (`TurboBroadcaster`):
```javascript
import { DurableObject } from "cloudflare:workers";

export class TurboBroadcaster extends DurableObject {
  async fetch(request) {
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws, message) {
    // Handle protocol messages if needed
    const data = JSON.parse(message);
    if (data.type === "ping") {
      ws.send(JSON.stringify({ type: "pong" }));
    }
  }

  webSocketClose(ws, code, reason, wasClean) {
    // Connection cleanup handled automatically
  }

  // Called by model broadcast methods
  broadcast(html) {
    for (const ws of this.ctx.getWebSockets()) {
      ws.send(html);
    }
  }
}
```

*Worker routing* (added to existing Cloudflare entry point):
```javascript
// Handle WebSocket upgrade for Turbo Streams
if (url.pathname === "/cable") {
  const upgradeHeader = request.headers.get("Upgrade");
  if (upgradeHeader === "websocket") {
    const stream = url.searchParams.get("stream");
    const broadcaster = env.TURBO_BROADCASTER.getByName(stream);
    return broadcaster.fetch(request);
  }
}
```

*wrangler.toml configuration*:
```toml
[[durable_objects.bindings]]
name = "TURBO_BROADCASTER"
class_name = "TurboBroadcaster"

[[migrations]]
tag = "v1"
new_classes = ["TurboBroadcaster"]
```

*Model broadcast call*:
```javascript
// broadcast_replace_to "article_1_comments", partial: "...", target: "..."
const html = `<turbo-stream action="replace" target="comments">...</turbo-stream>`;
await env.TURBO_BROADCASTER.getByName("article_1_comments").broadcast(html);
```

Benefits of Durable Objects:
- **Hibernation**: WebSocket stays open but Durable Object evicted when idle (no duration charges)
- **Built-in connection management**: `ctx.getWebSockets()` tracks all connections
- **Per-stream isolation**: Each stream name gets its own Durable Object instance
- **Global distribution**: Runs close to users automatically

**`_later` handling**:
Since this is JavaScript, no Active Job needed:
```javascript
// broadcast_replace_later_to becomes:
setTimeout(() => this.broadcast_replace_to(...), 0);
// or
Promise.resolve().then(() => this.broadcast_replace_to(...));
```

**Files to create/modify**:
- `lib/ruby2js/filter/rails/model.rb` - Add broadcast_* method transformations
- `packages/ruby2js-rails/targets/browser/rails.js` - Add BroadcastChannel wrapper
- New: `packages/ruby2js-rails/targets/node/action_cable.js` - WebSocket server

---

### Phase 5: turbo_stream_from (View Subscriptions)

**Goal**: Support view helper for subscribing to broadcast channels.

**Usage** (from showcase `app/views/scores/by_age.html.erb`):
```erb
<%= turbo_stream_from "live-scores-#{ENV['RAILS_APP_DB']}" %>
```

**Browser implementation**:
```javascript
// Generated code registers a BroadcastChannel listener
const channel = new BroadcastChannel("live-scores-mydb");
channel.onmessage = (event) => {
  Turbo.renderStreamMessage(event.data);
};
```

**Server implementation** (Node/Bun/Deno):
```html
<turbo-cable-stream-source
  channel="live-scores-mydb"
  signed-stream-name="...">
</turbo-cable-stream-source>
```

**Files to modify**:
- `lib/ruby2js/filter/turbo.rb` - Add `turbo_stream_from` helper
- `lib/ruby2js/filter/erb.rb` - Handle the helper in ERB context

---

### Phase 6: Stimulus Controller Handling

**Goal**: Copy `.js` files directly, transpile `.rb` files.

**Current behavior** (`lib/ruby2js/rails/builder.rb` lines 584-595):
```ruby
stimulus_dir = File.join(DEMO_ROOT, 'app/javascript/controllers')
if File.exist?(stimulus_dir)
  self.transpile_directory(stimulus_dir, ...)
end
```

**Enhancement needed**:
1. For `.js` files: Copy directly to dist (no transpilation)
2. For `.rb` files: Transpile with stimulus filter
3. Generate `controllers/index.js` that registers all controllers

**Example Stimulus controller** (from showcase):
```javascript
// app/javascript/controllers/live_scores_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.token = document.querySelector('meta[name="csrf-token"]').content;
    const observer = new MutationObserver(this.reload);
    observer.observe(this.element, { attributes: true, childList: true, subtree: true });
  }

  reload = _event => {
    fetch(this.element.getAttribute("action"), {
      method: "POST",
      headers: { "X-CSRF-Token": this.token, "Content-Type": "application/json" },
      credentials: "same-origin",
      body: ""
    }).then(response => response.text())
      .then(html => Turbo.renderStreamMessage(html));
  };
}
```

---

## Implementation Order & Dependencies

```
Phase 1: Turbo Drive ──────────────────────────────────────────┐
   │ (No real-time, just navigation)                          │
   ▼                                                           │
Phase 2: Turbo Frames                                          │
   │ (Partial page updates)                                    │ Can demo
   ▼                                                           │ at each
Phase 3a: Turbo Stream Helpers                                 │ phase
   │ (turbo_stream.replace/append/etc)                         │
   ▼                                                           │
Phase 3b: Server Format Negotiation                            │
   │ (respond_to with format.turbo_stream for server targets)  │
   ▼                                                           │
Phase 4: Model Broadcasting ────────────────────────────────────┘
   │ (broadcast_replace_to)
   ▼
Phase 5: turbo_stream_from
   │ (View subscriptions)
   ▼
Phase 6: Stimulus refinements
   (Copy .js, transpile .rb)
```

---

## Blog Demo Adaptation

For the `test/blog` demo, add live comments:

**Model** (`app/models/comment.rb`):
```ruby
class Comment < ApplicationRecord
  belongs_to :article

  after_create_commit do
    broadcast_append_to "article_#{article_id}_comments",
      partial: "comments/comment",
      target: "comments"
  end

  after_destroy_commit do
    broadcast_remove_to "article_#{article_id}_comments",
      target: dom_id(self)
  end
end
```

**View** (`app/views/articles/show.html.erb`):
```erb
<%= turbo_stream_from "article_#{@article.id}_comments" %>

<div id="comments">
  <%= render @article.comments %>
</div>

<%= form_with model: [@article, Comment.new] do |form| %>
  <%= form.text_field :commenter %>
  <%= form.text_area :body %>
  <%= form.submit "Add Comment" %>
<% end %>
```

---

## Estimated Effort

| Phase | Complexity | Effort | Status |
|-------|------------|--------|--------|
| Phase 1: Turbo Drive | Medium | 2 days | ✅ Complete |
| Phase 2: Turbo Frames | Low | 1 day | ✅ Complete |
| Phase 3a: Turbo Stream Helpers | Low | 0.5 days | ✅ Complete |
| Phase 3b: Server Format Negotiation | Medium | 1 day | ✅ Complete |
| Phase 4: Model Broadcasting | Medium | 2 days | ✅ Complete |
| Phase 5: turbo_stream_from | Low | 1 day | ✅ Complete |
| Phase 6: Stimulus refinements | Low | 0.5 days | ✅ Complete |
| **Cloudflare DO fixes** | Low | 0.5 days | ⏳ Remaining |
| **Total** | | **8-9 days** | ~95% done |

Risk was substantially reduced by:
- Simple custom WebSocket protocol (not Action Cable compatible)
- In-memory pub/sub only (no Redis)
- Cloudflare Durable Objects provide native WebSocket (no custom server needed)
- Deferred: signed streams, two-way comms, horizontal scaling

---

## Success Criteria

| Criterion | Status | Notes |
|-----------|--------|-------|
| Two browser windows open to same article | ✅ Achieved | Tested on browser + Node |
| Add comment in window A → appears in B | ✅ Achieved | Chat demo working |
| Browser (BroadcastChannel) | ✅ Achieved | Tested with dexie |
| Node/Bun/Deno (WebSocket) | ✅ Achieved | Node tested, Bun/Deno untested |
| Cloudflare (Durable Objects) | ⏳ Pending | Code complete, config fixes needed |
| Vercel (stubbed) | ✅ Achieved | By design, no WebSocket |
| Stimulus controllers (.js and .rb) | ✅ Achieved | Both copy and transpile work |
| No backwards compatibility concerns | ✅ Achieved | Turbo replaces custom navigation |

---

## Deferred for Follow-on Work

These items are explicitly out of scope for this implementation:

- **Full Action Cable compatibility** - Custom simple WebSocket protocol is sufficient
- **Signed stream names** - Not needed when we control both ends
- **Two-way WebSocket communication** - Server→client only; client→server uses HTTP
- **Cross-process pub/sub** - In-memory is sufficient; Redis/etc can be added later
- **Horizontal scaling** - Single-process model matches TurboCable approach

## Blog Post Context

This work is part of a trilogy of blog posts introducing Juntos:

| Post | Title | Theme | Status |
|------|-------|-------|--------|
| 1 | Rails to the Edge and Beyond | Same CRUD, five runtimes | ✅ Published 2026-01-02 |
| 2 | Hotwire on the Edge | Real-time + Stimulus | 📝 Draft, target 2026-01-05 |
| 3 | (Vite integration) | Ruby as frontend language | 📋 Planned |

**Post 2 narrative arc:**
- Post 1 proved Rails patterns work in JavaScript (CRUD)
- Post 2 proves Ruby can do frontend JavaScript (Stimulus controllers)
- This sets up Post 3: "if Ruby works for Stimulus, why not Vue/Svelte/Astro?"

**Post 2 key claims to verify:**
1. Chat demo with `broadcast_append_to`/`broadcast_remove_to` works
2. Stimulus controllers in Ruby transpile to valid Stimulus JS
3. `turbo_stream_from` establishes WebSocket subscriptions
4. Cloudflare with D1 and Durable Objects provides real-time at the edge

**Before publishing Post 2:**
- [ ] Fix Cloudflare Durable Objects configuration (wrangler.toml + entry point)
- [ ] Test chat demo on Cloudflare deployment
- [ ] Update blog post with tested Cloudflare instructions
- [ ] Add hint about Post 3 (Vite/Vue/Svelte) at the end

See also: `plans/VITE_RUBY2JS.md` for Post 3 planning.

---

## References

- [Turbo Handbook - Streams](https://turbo.hotwired.dev/handbook/streams)
- [Turbo Rails GitHub](https://github.com/hotwired/turbo-rails)
- [Stimulus Handbook](https://stimulus.hotwired.dev/handbook/introduction)
- [TurboCable](https://intertwingly.net/blog/2025/11/04/TurboCable.html) - Minimal WebSocket approach
- [Cloudflare Durable Objects WebSocket Server](https://developers.cloudflare.com/durable-objects/examples/websocket-hibernation-server/) - Native WebSocket with hibernation
- [Cloudflare Durable Objects Overview](https://developers.cloudflare.com/durable-objects/)
- Showcase app patterns: `~/git/showcase/app/`
