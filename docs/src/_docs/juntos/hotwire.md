---
order: 645
title: Hotwire
top_section: Juntos
category: juntos
---

# Hotwire Support

Juntos includes full support for [Hotwire](https://hotwired.dev/)—the Rails-native approach to building interactive applications with minimal JavaScript.

{% toc %}

## Overview

Hotwire consists of two main components:

- **Turbo** — Fast navigation and real-time updates without writing JavaScript
- **Stimulus** — Lightweight JavaScript controllers for progressive enhancement

Juntos implements both, allowing you to write idiomatic Rails code that works across all targets.

## Turbo Streams Broadcasting

### Model Broadcasting

Add real-time updates to your models using familiar Rails callbacks:

```ruby
# app/models/message.rb
class Message < ApplicationRecord
  validates :body, presence: true

  # Broadcast new messages to all subscribers
  after_create_commit do
    broadcast_append_to "chat_room",
      target: "messages",
      partial: "messages/message",
      locals: { message: self }
  end

  # Broadcast removal when deleted
  after_destroy_commit do
    broadcast_remove_to "chat_room",
      target: "message_#{id}"
  end
end
```

**Available broadcasting methods:**

| Method | Action |
|--------|--------|
| `broadcast_append_to` | Append to target element |
| `broadcast_prepend_to` | Prepend to target element |
| `broadcast_replace_to` | Replace target element |
| `broadcast_remove_to` | Remove target element |
| `broadcast_update_to` | Update target content |
| `broadcast_before_to` | Insert before target |
| `broadcast_after_to` | Insert after target |
| `broadcast_json_to` | Send JSON event (for React/JS components) |

### View Subscription

Subscribe to broadcasts in your views:

```erb
<%# app/views/messages/index.html.erb %>
<div class="chat-room">
  <%# Subscribe to real-time updates %>
  <%= turbo_stream_from "chat_room" %>

  <%# Messages container - broadcasts append here %>
  <div id="messages">
    <%= render @messages %>
  </div>

  <%= form_with model: Message.new do |f| %>
    <%= f.text_field :body %>
    <%= f.submit "Send" %>
  <% end %>
</div>
```

The `turbo_stream_from` helper establishes the real-time connection. The element format varies by target:
- **Server targets** (Node/Bun/Deno): `<turbo-cable-stream-source>` for Action Cable
- **Cloudflare**: `<turbo-stream-source>` for simple WebSocket protocol
- **Browser**: Subscribes via BroadcastChannel API (no element needed)

### JSON Broadcasting for React Components

Turbo Streams broadcast HTML fragments, which works great for server-rendered views but conflicts with React's DOM management. Use `broadcast_json_to` to send JSON events that React components can use to update their state:

```ruby
# app/models/node.rb
class Node < ApplicationRecord
  belongs_to :workflow

  after_create_commit do
    broadcast_json_to "workflow_#{workflow_id}", "node_created"
  end

  after_update_commit do
    broadcast_json_to "workflow_#{workflow_id}", "node_updated"
  end

  after_destroy_commit do
    broadcast_json_to "workflow_#{workflow_id}", "node_destroyed"
  end
end
```

This broadcasts JSON events:

```json
{
  "type": "node_created",
  "model": "Node",
  "id": 42,
  "data": {"id": 42, "label": "New Node", "position_x": 100, "position_y": 200, ...}
}
```

**Subscribing with JsonStreamProvider:**

Use the `JsonStreamProvider` React context to handle subscriptions. It automatically uses WebSocket on server targets and BroadcastChannel on the browser target:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["react", "esm", "functions"]
}'></div>

```ruby
# app/views/workflows/Show.jsx.rb
import JsonStreamProvider from '../../../lib/JsonStreamProvider.js'
import WorkflowCanvas from 'components/WorkflowCanvas'

export default
def Show(workflow:)
  %x{
    <JsonStreamProvider stream={`workflow_${workflow.id}`}>
      <WorkflowCanvas ... />
    </JsonStreamProvider>
  }
end
```

**React component using the context:**

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["react", "esm", "functions"]
}'></div>

```ruby
# app/components/WorkflowCanvas.jsx.rb
import [useJsonStream], from: '../../lib/JsonStreamProvider.js'

export default
def WorkflowCanvas(...)
  stream = useJsonStream()

  useEffect(-> {
    return unless stream.lastMessage
    payload = stream.lastMessage

    case payload.type
    when 'node_created'
      setNodes(->(prev) { [*prev, to_flow_node(payload.data)] })
    when 'node_updated'
      setNodes(->(prev) { prev.map { |n| n.id == payload.id.to_s ? to_flow_node(payload.data) : n } })
    when 'node_destroyed'
      setNodes(->(prev) { prev.filter { |n| n.id != payload.id.to_s } })
    end
  }, [stream.lastMessage])
end
```

The provider handles the transport automatically:
- **Browser target**: Uses `BroadcastChannel` for same-origin tab sync
- **Server targets** (Node/Bun/Deno): Uses WebSocket with Action Cable protocol
- **Cloudflare**: Uses WebSocket with simple protocol (hibernation-friendly)

See the [Workflow Builder demo](/docs/juntos/demos/workflow-builder) for a complete example.

## Turbo Frames

Wrap content in frames for partial page updates:

```erb
<%# Clicking "Edit" loads just the form, not the whole page %>
<%= turbo_frame_tag dom_id(@article) do %>
  <h1><%= @article.title %></h1>
  <%= link_to "Edit", edit_article_path(@article) %>
<% end %>
```

```erb
<%# edit.html.erb - the frame replaces in-place %>
<%= turbo_frame_tag dom_id(@article) do %>
  <%= form_with model: @article do |f| %>
    <%= f.text_field :title %>
    <%= f.submit "Save" %>
  <% end %>
<% end %>
```

## Controller Format Negotiation

Handle both HTML and Turbo Stream responses:

```ruby
# app/controllers/messages_controller.rb
class MessagesController < ApplicationController
  def create
    @message = Message.new(message_params)
    if @message.save
      respond_to do |format|
        format.turbo_stream  # Renders create.turbo_stream.erb
        format.html { redirect_to messages_path }
      end
    end
  end
end
```

Juntos generates Accept header checks:

```javascript
// Generated JavaScript
if (context.request.headers.accept?.includes('text/vnd.turbo-stream.html')) {
  // Render turbo_stream response
} else {
  // Render HTML response
}
```

## Stimulus Controllers

Write Stimulus controllers in Ruby:

**Try it** — edit the Ruby code to see how it transpiles:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["stimulus", "esm", "functions"]
}'></div>

```ruby
class ChatController < Stimulus::Controller
  def connect()
    scroll_to_bottom()
  end

  def scroll_to_bottom()
    element.scrollTop = element.scrollHeight
  end

  def send_message(event)
    event.preventDefault()
    # Handle form submission
  end
end
```

### Rails Integration

In Rails development, the Stimulus middleware serves Ruby controllers as JavaScript on-the-fly:

1. Create `app/javascript/controllers/chat_controller.rb`
2. The middleware intercepts requests for `chat_controller.js`
3. Transpiles the Ruby source and returns JavaScript
4. Generates `controllers/index.js` manifest automatically

No build step required during development.

### Juntos Build

For Juntos targets, the builder:

1. Transpiles all `.rb` controllers to `.js`
2. Copies any existing `.js` controllers
3. Generates `controllers/index.js` manifest

## WebSocket Support by Target

| Target | Turbo Package | Transport | Protocol |
|--------|--------------|-----------|----------|
| **Browser** | `@hotwired/turbo` | `BroadcastChannel` | Local tabs only |
| **Node.js** | `@hotwired/turbo-rails` | `ws` package | Action Cable |
| **Bun** | `@hotwired/turbo-rails` | Native WebSocket | Action Cable |
| **Deno** | `@hotwired/turbo-rails` | Native WebSocket | Action Cable |
| **Cloudflare** | `@hotwired/turbo` | Durable Objects | Simple (hibernation-friendly) |
| **Vercel** | `@hotwired/turbo-rails` | Stubbed | Platform limitation |

### WebSocket Endpoint

All server targets expose a `/cable` endpoint for WebSocket connections. The protocol varies:

**Action Cable protocol (Node/Bun/Deno):**

```javascript
// Subscribe using Action Cable format
ws.send(JSON.stringify({
  command: 'subscribe',
  identifier: JSON.stringify({
    channel: 'Turbo::StreamsChannel',
    signed_stream_name: btoa(JSON.stringify('chat_room'))
  })
}));
```

**Simple protocol (Cloudflare):**

```javascript
// Subscribe using simple format
ws.send(JSON.stringify({
  type: 'subscribe',
  stream: 'chat_room'
}));

// Receive broadcasts as { stream, html }
ws.onmessage = (event) => {
  const { stream, html } = JSON.parse(event.data);
  Turbo.renderStreamMessage(html);
};
```

The simple protocol allows Cloudflare's Durable Object to truly hibernate between broadcasts, while Action Cable's ping requirements keep server processes active.

### Cloudflare Durable Objects

On Cloudflare, real-time features use Durable Objects with a simple protocol designed for hibernation:

```javascript
// wrangler.toml (auto-generated)
[[durable_objects.bindings]]
name = "TURBO_BROADCASTER"
class_name = "TurboBroadcaster"
```

**Why a simple protocol?**

Action Cable requires server-initiated pings every 3 seconds to keep connections alive. On Durable Objects, this would prevent hibernation and incur continuous billing. Instead, Cloudflare uses:

- **Base Turbo** (`@hotwired/turbo`) instead of turbo-rails
- **Simple WebSocket protocol**: `{ type: 'subscribe', stream }` / `{ stream, html }`
- **No server pings**: Cloudflare's edge maintains connections while the DO hibernates
- **True hibernation**: The Durable Object only wakes when broadcasts occur

The `TurboBroadcaster` class handles:
- WebSocket upgrade requests at `/cable`
- Stream subscriptions with hibernation-aware storage
- Broadcasting to subscribers (wakes DO briefly, then hibernates)
- Automatic cleanup on disconnect

## RPC and Real-Time Features

Juntos provides two complementary mechanisms for browser-server communication:

| Feature | RPC Transport | Broadcasting |
|---------|---------------|--------------|
| **Direction** | Browser → Server (request/response) | Server → Browser (push) |
| **Use case** | Model operations, data fetching | Real-time updates |
| **Endpoint** | `/__rpc` | `/cable` (WebSocket) |
| **Data flow** | Synchronous call, wait for result | Async event subscription |

### How They Work Together

A typical workflow:

1. **User action** → Path helper makes RPC call (e.g., `notes_path.post(...)`)
2. **Server processes** → Controller creates record, triggers `after_create_commit`
3. **Broadcast** → Turbo Stream or JSON event sent to all subscribers
4. **UI updates** → All connected clients receive the update

```ruby
# Model broadcasts on create
class Note < ApplicationRecord
  after_create_commit { broadcast_append_to "notes" }
end

# View fetches via path helper, subscribes to broadcasts
notes_path.get().then { |r| r.json.then { |data| setNotes(data) } }
turbo_stream_from "notes"  # Receives broadcasts from other users
```

This pattern enables:
- **Optimistic updates**: UI updates immediately via local state
- **Consistency**: Broadcasts sync all clients to server state
- **Offline support**: Browser target works without server, syncs when reconnected

## Demo

See the [Chat Demo](/docs/juntos/demos/chat) for Turbo Streams broadcasting and Stimulus controllers, or the [Notes Demo](/docs/juntos/demos/notes) for path helper RPC with JSON broadcasting.

## Limitations

### Vercel Edge

Vercel Edge Functions don't support persistent WebSocket connections. Broadcasting methods are stubbed (no-op). Consider using external pub/sub services (Pusher, Ably) for real-time features on Vercel.

### Browser Target

The browser target uses `BroadcastChannel` for same-origin communication between tabs. This doesn't provide cross-device real-time updates—it's for local development and offline-first apps where each browser instance has its own database.

For true real-time across devices, deploy to a server target (Node.js, Bun, Deno, Cloudflare).
