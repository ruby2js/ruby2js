---
order: 660
title: Chat Demo
top_section: Juntos
category: juntos/demos
hide_in_toc: true
---

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
bin/juntos db:prepare -d sqlite
bin/juntos up -d sqlite
```

Open multiple browser tabs. Messages broadcast via WebSocket to all connected clients.

## Deploy to Vercel

For Vercel deployment, you need a universal database and a real-time service. Juntos supports two approaches:

### Option 1: Supabase (Database + Real-time)

Supabase provides both PostgreSQL and real-time in one service:

```bash
bin/juntos db:prepare -d supabase
bin/juntos deploy -d supabase
```

Juntos automatically uses Supabase Realtime for Turbo Streams broadcasting.

**Setup:**
1. Create a [Supabase](https://supabase.com) project
2. Add environment variables to Vercel:
   - `SUPABASE_URL` — Project URL
   - `SUPABASE_ANON_KEY` — Anonymous key
   - `DATABASE_URL` — Direct Postgres connection (for migrations)

### Option 2: Any Database + Pusher

For other databases (Neon, Turso, PlanetScale), use Pusher for real-time:

```bash
bin/juntos db:prepare -d neon
bin/juntos deploy -d neon
```

Juntos detects Vercel + non-Supabase database and configures Pusher automatically.

**Setup:**
1. Create database ([Neon](https://neon.tech), [Turso](https://turso.tech), or [PlanetScale](https://planetscale.com))
2. Create a [Pusher](https://pusher.com) app (free tier: 200K messages/day)
3. Add environment variables to Vercel:
   - `DATABASE_URL` (or database-specific vars)
   - `PUSHER_APP_ID`, `PUSHER_KEY`, `PUSHER_SECRET`, `PUSHER_CLUSTER`

### Why Two Options?

Vercel's serverless functions can't maintain WebSocket connections. Both solutions use HTTP-based approaches:

- **Supabase Realtime** — Built into Supabase, uses their WebSocket infrastructure
- **Pusher** — Third-party service (Vercel's recommended approach for real-time)

## Deploy to Fly.io

Fly.io is ideal for the chat demo—it has **native WebSocket support**, so Turbo Streams broadcasting works without Pusher or other external services:

```bash
juntos db:create -d mpg
# Start proxy in separate terminal: fly mpg proxy chatapp_production
juntos db:prepare -d mpg
juntos deploy -t fly -d mpg
```

**Setup:**
1. Install [Fly CLI](https://fly.io/docs/flyctl/install/) and run `fly auth login`
2. The `db:create` command creates your app, database, and connects them automatically

No Pusher configuration needed. Messages broadcast via WebSocket to all connected clients, just like Rails with Action Cable.

## Deploy to Deno Deploy

```bash
juntos db:prepare -d neon
juntos deploy -t deno-deploy -d neon
```

Like Vercel, Deno Deploy requires Pusher for real-time (or Supabase Realtime if using Supabase).

**Setup:**
1. Install [deployctl](https://docs.deno.com/deploy/manual/deployctl)
2. Create a [Neon](https://neon.tech) database
3. Create a [Pusher](https://pusher.com) app
4. Set environment variables in Deno Deploy dashboard

## Deploy to Cloudflare

```bash
juntos db:prepare -d d1
juntos deploy -d d1
```

The `db:prepare` command creates the D1 database (if needed), runs migrations, and seeds if fresh.

Your model's `broadcast_append_to` calls route through Durable Objects. Subscribers on different edge instances receive the update. Real-time, globally distributed.

## The Code

### Message Model

**Try it** — edit the Ruby to see how the model transpiles:

<div data-controller="combo" data-selfhost="true" data-options='{
  "eslevel": 2022,
  "filters": ["model", "esm", "functions"]
}'></div>

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

**Try it** — edit the ERB to see how views transpile:

<div data-controller="combo" data-selfhost="true" data-erb="true" data-options='{
  "eslevel": 2022,
  "filters": ["rails/helpers", "erb", "esm", "functions"]
}'></div>

```ruby
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

**Try it** — partials transpile the same way:

<div data-controller="combo" data-selfhost="true" data-erb="true" data-options='{
  "eslevel": 2022,
  "filters": ["rails/helpers", "erb", "esm", "functions"]
}'></div>

```ruby
<%# app/views/messages/_message.html.erb %>
<div id="<%= dom_id(message) %>" data-chat-target="message">
  <span><%= message.username %></span>
  <span><%= message.body %></span>
</div>
```

The `data-chat-target="message"` attribute tells Stimulus to track this element. When new messages are appended, Stimulus calls `messageTargetConnected`.

### Stimulus Controller in Ruby

**Try it** — edit the Ruby code to see how it transpiles:

<div data-controller="combo" data-selfhost="true" data-options='{
  "eslevel": 2022,
  "filters": ["stimulus", "esm", "functions"]
}'></div>

```ruby
class ChatController < Stimulus::Controller
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
- `bodyTarget` usage auto-generates `static targets = ["body"]`
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
| **Fly.io** | Native WebSocket | All connected clients |
| **Vercel** | Pusher or Supabase Realtime | All connected clients |
| **Deno Deploy** | Pusher or Supabase Realtime | All connected clients |
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

**Try it** — see how `respond_to` transpiles:

<div data-controller="combo" data-selfhost="true" data-options='{
  "eslevel": 2022,
  "filters": ["controller", "esm", "functions"]
}'></div>

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
- See [Database Overview](/docs/juntos/databases) for database setup guides
- See [Fly.io Deployment](/docs/juntos/deploying/fly) for native WebSocket support
- See [Vercel Deployment](/docs/juntos/deploying/vercel) for edge deployment
- See [Deno Deploy](/docs/juntos/deploying/deno-deploy) for Deno-native edge
- See [Cloudflare Deployment](/docs/juntos/deploying/cloudflare) for Durable Objects
