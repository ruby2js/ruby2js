---
order: 54
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

The `turbo_stream_from` helper generates a `<turbo-cable-stream-source>` element that establishes the WebSocket connection.

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

```ruby
# app/javascript/controllers/chat_controller.rb
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

**Transpiles to:**

```javascript
class ChatController extends Stimulus.Controller {
  connect() {
    this.scroll_to_bottom()
  }

  scroll_to_bottom() {
    this.element.scrollTop = this.element.scrollHeight
  }

  send_message(event) {
    event.preventDefault()
    // Handle form submission
  }
}
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

| Target | Implementation | Notes |
|--------|---------------|-------|
| **Browser** | `BroadcastChannel` | Same-origin tabs only |
| **Node.js** | `ws` package | Full WebSocket server |
| **Bun** | Native WebSocket | Built into `Bun.serve` |
| **Deno** | Native WebSocket | `Deno.upgradeWebSocket` |
| **Cloudflare** | Durable Objects | Hibernation-aware |
| **Vercel** | Stubbed | Platform limitation |

### WebSocket Endpoint

Server targets expose a `/cable` endpoint for WebSocket connections:

```javascript
// Client connection
const ws = new WebSocket('ws://localhost:3000/cable');

// Subscribe to a channel
ws.send(JSON.stringify({
  command: 'subscribe',
  channel: 'chat_room'
}));

// Receive broadcasts
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  if (data.type === 'turbo-stream') {
    Turbo.renderStreamMessage(data.html);
  }
};
```

### Cloudflare Durable Objects

On Cloudflare, real-time features use Durable Objects for WebSocket coordination:

```javascript
// wrangler.toml (auto-generated)
[[durable_objects.bindings]]
name = "BROADCASTER"
class_name = "TurboBroadcaster"
```

The `TurboBroadcaster` class handles:
- WebSocket upgrade requests
- Channel subscriptions
- Broadcasting to subscribers
- Hibernation for cost efficiency

## Chat Demo

A complete chat room demo showcases real-time Turbo Streams broadcasting:

```bash
# Create the app
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/chat/create-chat | bash -s chat
cd chat
```

Run in the browser with IndexedDB:

```bash
bin/juntos dev -d dexie
```

Run on Node.js with SQLite:

```bash
bin/juntos migrate -d sqlite
bin/juntos server -d sqlite
```

Deploy to Cloudflare with D1:

```bash
wrangler d1 create chat
echo "D1_DATABASE_ID=your-id-here" >> .env.local
bin/juntos migrate -d d1
bin/juntos deploy -d d1
```

Open multiple browser tabs, send messages, and watch them appear everywhere.

The demo showcases:
- Turbo Streams broadcasting (`broadcast_append_to`, `broadcast_remove_to`)
- Stimulus controller for auto-scroll (written in Ruby)
- `turbo_stream_from` subscription
- `respond_to` with format negotiation

## Limitations

### Vercel Edge

Vercel Edge Functions don't support persistent WebSocket connections. Broadcasting methods are stubbed (no-op). Consider using external pub/sub services (Pusher, Ably) for real-time features on Vercel.

### Browser Target

The browser target uses `BroadcastChannel` for same-origin communication between tabs. This doesn't provide cross-device real-time updates—it's for local development and offline-first apps where each browser instance has its own database.

For true real-time across devices, deploy to a server target (Node.js, Bun, Deno, Cloudflare).
