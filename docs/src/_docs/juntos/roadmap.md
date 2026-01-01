---
order: 60
title: Roadmap
top_section: Juntos
category: juntos
---

# Roadmap

Juntos currently supports the core Rails patterns: models, controllers, views, routes, migrations, and helpers. The architecture is designed to expand—each Rails subsystem can become a filter that transforms familiar APIs into platform-appropriate implementations.

{% toc %}

## Planned

### Action Mailer

Transform Rails mailer syntax into email service API calls:

```ruby
# What you write
UserMailer.welcome(@user).deliver_later

# Browser target: queue for server sync
# Node target: Resend/SendGrid API call
# Edge target: Resend/SendGrid API call
```

Email services under consideration: [Resend](https://resend.com/), [SendGrid](https://sendgrid.com/), [Postmark](https://postmarkapp.com/).

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

### Background Jobs

Active Job-style interface for async processing:

```ruby
# What you write
ProcessOrderJob.perform_later(@order)

# Browser: Web Worker or deferred execution
# Node: Bull/BullMQ with Redis
# Edge: Not supported (platform limitation)
```

## Under Consideration

### Stimulus Reflex / Hotwire

Server-side DOM updates over WebSocket. Depends on Action Cable.

### Active Record Encryption

Encrypted attributes for sensitive data. Platform-specific crypto APIs.

### Action Text

Rich text content with Trix editor. Requires Active Storage for attachments.

## Contributing

Juntos is open source. If you're interested in implementing any of these features or have ideas for others, see the [Ruby2JS repository](https://github.com/ruby2js/ruby2js).

The filter architecture makes contributions approachable—each feature is a self-contained transformation from Rails patterns to JavaScript implementations.
