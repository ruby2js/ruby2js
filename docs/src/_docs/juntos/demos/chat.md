---
order: 660
title: Chat Demo
top_section: Juntos
category: juntos-demos
hide_in_toc: true
---

# Chat Demo

A real-time chat room demonstrating Hotwire patterns—Turbo Streams broadcasting and Stimulus controllers written in Ruby.

{% toc %}

## Create the App

```bash
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/chat/create-chat | bash -s chat
cd chat
```

This creates a Rails app with:

- **Message model** — username, body, timestamps
- **Real-time broadcasting** — messages appear instantly for all users
- **Stimulus controller** — auto-scroll written in Ruby
- **Turbo Streams** — `broadcast_append_to`, `broadcast_remove_to`

## Run with Rails

```bash
bin/rails db:prepare
bin/dev
```

Open http://localhost:3000 in multiple browser tabs. Send messages. Watch them appear everywhere.

The Ruby Stimulus controller transpiles automatically at boot. Edit the `.rb` file, refresh, and see your changes—no restart needed.

## Run in the Browser

```bash
bin/juntos dev -d dexie
```

Same chat interface, running entirely in your browser. The browser target uses `BroadcastChannel`—messages sync between tabs on the same device.

## Run on Node.js

```bash
bin/juntos migrate -d sqlite
bin/juntos server -d sqlite
```

Open multiple browser tabs. Messages broadcast via WebSocket to all connected clients.

## Deploy to Cloudflare

```bash
wrangler d1 create chat
echo "D1_DATABASE_ID=your-id-here" >> .env.local
bin/juntos migrate -d d1
bin/juntos deploy -d d1
```

Your model's `broadcast_append_to` calls route through Durable Objects. Subscribers on different edge instances receive the update. Real-time, globally distributed.

## The Code

### Message Model

```ruby
# app/models/message.rb
class Message < ApplicationRecord
  validates :username, presence: true
  validates :body, presence: true

  after_create_commit do
    broadcast_append_to "chat_room",
      target: "messages",
      partial: "messages/message",
      locals: { message: self }
  end

  after_destroy_commit do
    broadcast_remove_to "chat_room",
      target: "message_#{id}"
  end
end
```

The `after_create_commit` callback broadcasts new messages to all subscribers. The `after_destroy_commit` removes deleted messages from everyone's view.

### View Subscription

```erb
<%# app/views/messages/index.html.erb %>
<div data-controller="chat">
  <%= turbo_stream_from "chat_room" %>

  <div id="messages">
    <%= render @messages %>
  </div>

  <%= form_with model: Message.new,
      data: { action: "turbo:submit-end->chat#clearInput" } do |f| %>
    <%= f.text_field :username, placeholder: "Name" %>
    <%= f.text_field :body, placeholder: "Message",
        data: { chat_target: "body" } %>
    <%= f.submit "Send" %>
  <% end %>
</div>
```

The `turbo_stream_from` helper establishes the WebSocket subscription. New messages append to `#messages` automatically. The `turbo:submit-end` action clears the input field after each message is sent.

### Message Partial

```erb
<%# app/views/messages/_message.html.erb %>
<div id="<%= dom_id(message) %>" data-chat-target="message">
  <span><%= message.username %></span>
  <span><%= message.body %></span>
</div>
```

The `data-chat-target="message"` attribute tells Stimulus to track this element. When new messages are appended, Stimulus calls `messageTargetConnected`.

### Stimulus Controller in Ruby

**Try it** — edit the Ruby code to see how it transpiles:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["stimulus", "esm", "functions"]
}'></div>

```ruby
class ChatController < Stimulus::Controller
  self.targets = %w(body)

  # Auto-scroll to show the new message
  def messageTargetConnected(element)
    element.scrollIntoView()
  end

  # Clear the message input after form submission
  def clearInput
    bodyTarget.value = ""
    bodyTarget.focus()
  end
end
```

The controller auto-scrolls the chat when new messages arrive and clears the input after each message is sent. The `messageTargetConnected` callback is called by Stimulus whenever a new element with `data-chat-target="message"` is added to the DOM—this is the idiomatic Stimulus pattern for reacting to dynamic content.

**Key transpilations:**
- `self.targets = [...]` becomes `static targets = [...]`
- `messageTargetConnected` stays as-is (Stimulus convention)
- `bodyTarget` becomes `this.bodyTarget` (Stimulus target accessor)
- `self.element` becomes `this.element`

## WebSocket Implementation by Platform

| Platform | Implementation | Scope |
|----------|---------------|-------|
| **Rails** | Action Cable | Server-managed connections |
| **Browser** | `BroadcastChannel` | Same-origin tabs only |
| **Node.js** | `ws` package | All connected clients |
| **Bun** | Native WebSocket | All connected clients |
| **Deno** | Native WebSocket | All connected clients |
| **Cloudflare** | Durable Objects | Global edge distribution |

### Browser Limitations

The browser target uses `BroadcastChannel`, which only works between tabs on the same device. This is ideal for:

- Local development
- Offline-first apps
- Single-user scenarios

For cross-device real-time, deploy to a server target.

### Cloudflare Durable Objects

Cloudflare Workers are stateless—each request might hit a different instance. WebSockets need state to track subscriptions.

Juntos uses Durable Objects as coordinators:

1. Client connects to `/cable`
2. Worker routes to the `TurboBroadcaster` Durable Object
3. Durable Object manages WebSocket connections
4. Broadcasts fan out to all subscribers

The Durable Object uses hibernation for cost efficiency—connections stay open but don't consume CPU while idle.

## What This Demo Shows

### Turbo Streams Broadcasting

- `broadcast_append_to` — add content to a target
- `broadcast_remove_to` — remove content from a target
- `turbo_stream_from` — subscribe to a channel

### Stimulus in Ruby

- `Stimulus::Controller` base class
- `self.targets` for target definitions
- `connect` lifecycle method
- `targetConnected` callbacks for dynamic content
- Direct JavaScript object access (`self.element`)

### Format Negotiation

```ruby
# app/controllers/messages_controller.rb
def create
  @message = Message.new(message_params)
  if @message.save
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to messages_path }
    end
  end
end
```

The controller responds differently based on the request's Accept header.

## Extending the Demo

Ideas for building on this foundation:

- **User presence** — show who's online
- **Typing indicators** — broadcast "user is typing"
- **Message editing** — use `broadcast_replace_to`
- **Rooms** — multiple chat channels
- **Private messages** — user-scoped streams

The Hotwire patterns scale from this simple demo to complex real-time applications.

## Next Steps

- Read [Hotwire](/docs/juntos/hotwire) for the full reference
- Try the [Blog Demo](/docs/juntos/demos/blog) for CRUD patterns
- See [Cloudflare Deployment](/docs/juntos/deploying/cloudflare) for edge details
