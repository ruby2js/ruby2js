# Vercel Target Plan

Add Vercel as a deployment target for Ruby2JS on Rails, enabling Rails-style applications to run as serverless functions on Vercel's platform.

## Prerequisites

This plan depends on [UNIVERSAL_DATABASES.md](./UNIVERSAL_DATABASES.md) — Vercel requires HTTP-based databases (Neon, Turso, PlanetScale) since Edge Functions cannot use TCP connections.

## Proof of Concept: test/blog

The `test/blog/create-blog` script generates a standard Rails blog application that demonstrates Vercel compatibility. The generated app includes:

```ruby
# Standard Rails model with validations and associations
class Article < ApplicationRecord
  has_many :comments, dependent: :destroy
  validates :title, presence: true
  validates :body, presence: true, length: { minimum: 10 }
end

# Standard nested routes
Rails.application.routes.draw do
  root "articles#index"
  resources :articles do
    resources :comments, only: [:create, :destroy]
  end
end

# Standard controller with redirects and flash messages
def create
  @comment = @article.comments.build(comment_params)
  if @comment.save
    redirect_to @article, notice: "Comment was successfully created."
  else
    redirect_to @article, alert: "Could not create comment."
  end
end
```

**Currently works with:**
- `adapter: dexie` → Browser with IndexedDB
- `adapter: better-sqlite3` → Node.js with SQLite

**For Vercel, only config changes needed:**

```yaml
# config/database.yml
production:
  adapter: neon        # or turso, planetscale
  target: vercel-edge
```

No Ruby code changes required. The app deploys to Vercel as-is.

### Why This Works

| Rails Pattern | Vercel Compatibility |
|---------------|---------------------|
| Stateless controllers | ✓ Standard Rails pattern |
| Model validations | ✓ Run per-request |
| Associations (has_many, belongs_to) | ✓ Resolved via DB queries |
| Nested routes | ✓ Just URL patterns |
| Flash messages | ✓ Cookie-based |
| Redirects | ✓ HTTP 302 responses |
| ERB views | ✓ Rendered per-request |
| No background jobs | ✓ None used |
| No file uploads | ✓ None used |
| No WebSockets | ✓ None used |

This demonstrates that **standard Rails applications** — the kind developers write every day — are Vercel-compatible without modification.

## Background

### What is Vercel?

Vercel is a deployment platform optimized for frontend frameworks, offering:

- **Static hosting** — Files served from global CDN
- **Serverless Functions** — Node.js functions, on-demand execution
- **Edge Functions** — V8 isolates at CDN edge, faster cold starts

### Why Vercel?

| Benefit | Description |
|---------|-------------|
| Git-based deploys | Push to deploy, preview URLs per PR |
| No lock-in | HTTP databases work anywhere |
| Familiar model | Similar to Heroku's simplicity |
| Large ecosystem | Popular platform, good docs |

### Constraints (Serverless Model)

Ruby2JS on Rails is already designed for these constraints:

| Constraint | Ruby2JS Status |
|------------|----------------|
| Stateless requests | ✓ Already assumed |
| No persistent connections | ✓ HTTP-based DB adapters |
| No background jobs | ✓ Not supported |
| No WebSockets | ✓ Not supported |
| Request-scoped state | ✓ Context object per request |

### Rails Features That Don't Translate

Some Rails features depend on capabilities that don't exist in serverless/edge environments. These are fundamental constraints of the deployment model, not Ruby2JS limitations:

| Rails Feature | Why It Doesn't Work | Workaround |
|---------------|---------------------|------------|
| **File uploads** | No persistent filesystem | Presigned URLs to S3, R2, Cloudflare Images |
| **Active Job** | No background processes; functions terminate after response | External queues (Inngest, Trigger.dev, Cloudflare Queues) |
| **Action Cable** | No persistent WebSocket connections | External services (Pusher, Ably) or Durable Objects |
| **Action Mailer** | No SMTP access | External APIs (SendGrid, Resend, Postmark) |
| **Active Storage** | Depends on filesystem + background jobs | External storage APIs directly |
| **Session stores** (Redis, DB) | No persistent connections on edge | Cookie-based sessions, or JWTs |
| **Cron jobs** | No long-running processes | Vercel Cron, external schedulers |

**Note:** Next.js has identical constraints. These are inherent to serverless, not specific to Ruby2JS.

### What Works Well

The serverless model excels at stateless request/response patterns—which is most CRUD applications:

- Database queries (via HTTP-based adapters)
- Form submissions with validation
- Redirects and flash messages
- Cookie-based authentication
- API endpoints
- Server-side rendering
- Static page generation with ISR

The `test/blog` demo (articles + comments with validations and nested routes) represents the sweet spot: a standard Rails application that deploys without modification.

## Architecture

### Existing Foundation

The runtime architecture already supports Vercel:

```
rails_base.js          → Shared: RouterBase, ApplicationBase, helpers
    ↓
rails_server.js        → Shared: Fetch API dispatch (Request/Response)
    ↓
targets/cloudflare/    → Worker fetch handler (~60 lines)
targets/vercel-edge/   → Edge Function handler (NEW)
targets/vercel-node/   → Serverless Function handler (NEW)
```

The key insight: `rails_server.js` uses the Fetch API (Request/Response), which Vercel Edge Functions use natively.

### Target Variants

| Target | Runtime | Use Case |
|--------|---------|----------|
| `vercel-edge` | V8 isolates | Fast, HTTP-only databases |
| `vercel-node` | Node.js | TCP databases OK, slower cold starts |

## Implementation

### Phase 1: Edge Function Target

Create `targets/vercel-edge/rails.js`:

```javascript
// Ruby2JS-on-Rails - Vercel Edge Functions Target
import {
  Router as RouterServer,
  Application as ApplicationServer,
  createContext,
  createFlash,
  truncate,
  pluralize,
  dom_id
} from './rails_server.js';

export { createContext, createFlash, truncate, pluralize, dom_id };
export { Router } from './rails_server.js';

export class Application extends ApplicationServer {
  static _initialized = false;

  static async initDatabase() {
    if (this._initialized) return;

    const adapter = await import('./active_record.mjs');
    this.activeRecordModule = adapter;

    // Initialize with environment variables (Vercel convention)
    await adapter.initDatabase({
      url: process.env.DATABASE_URL,
    });

    if (this.schema?.create_tables) {
      await this.schema.create_tables();
    }

    this._initialized = true;
  }

  // Create the Edge Function handler
  static handler() {
    const app = this;
    return async function(request) {
      try {
        await app.initDatabase();
        return await Router.dispatch(request);
      } catch (e) {
        console.error('Edge Function error:', e);
        return new Response(
          `<h1>500 Internal Server Error</h1><pre>${e.stack}</pre>`,
          { status: 500, headers: { 'Content-Type': 'text/html' } }
        );
      }
    };
  }
}
```

### Phase 2: Serverless Function Target

Create `targets/vercel-node/rails.js`:

```javascript
// Ruby2JS-on-Rails - Vercel Serverless Functions Target (Node.js)
import {
  Router,
  Application as ApplicationServer,
  createContext
} from './rails_server.js';

export { Router, createContext };

export class Application extends ApplicationServer {
  static _initialized = false;

  static async initDatabase() {
    if (this._initialized) return;

    const adapter = await import('./active_record.mjs');
    this.activeRecordModule = adapter;

    await adapter.initDatabase({
      url: process.env.DATABASE_URL,
    });

    if (this.schema?.create_tables) {
      await this.schema.create_tables();
    }

    this._initialized = true;
  }

  // Create the Serverless Function handler
  // Vercel's Node.js runtime supports Web API Request/Response
  static handler() {
    const app = this;
    return async function(request) {
      try {
        await app.initDatabase();
        return await Router.dispatch(request);
      } catch (e) {
        console.error('Serverless Function error:', e);
        return new Response(
          `<h1>500 Internal Server Error</h1><pre>${e.stack}</pre>`,
          { status: 500, headers: { 'Content-Type': 'text/html' } }
        );
      }
    };
  }
}
```

### Phase 3: Build Output Structure

The build process generates Vercel-compatible output:

```
dist/
├── api/
│   └── [[...path]].js      # Catch-all route handler
├── lib/
│   ├── rails.js            # Target-specific runtime
│   ├── rails_base.js       # Shared base
│   ├── rails_server.js     # Shared server logic
│   └── active_record.mjs   # Database adapter
├── config/
│   ├── routes.js
│   ├── schema.js
│   └── paths.js
├── controllers/
│   └── *.js
├── models/
│   └── *.js
├── views/
│   └── **/*.js
├── public/
│   └── (static assets)
└── vercel.json
```

### Phase 4: Entry Point Generation

Generate `api/[[...path]].js`:

```javascript
// Vercel catch-all route handler
// Generated by Ruby2JS on Rails

import { Application, Router } from '../lib/rails.js';
import '../config/routes.js';

// Configure application
Application.configure({
  schema: (await import('../config/schema.js')).Schema,
  seeds: null,  // Seeds typically not run in production
  layout: (await import('../views/layouts/application.js')).layout
});

// Export handler for Vercel
export default Application.handler();

// Edge runtime configuration (for vercel-edge target)
export const config = {
  runtime: 'edge',  // or 'nodejs' for vercel-node
};
```

### Phase 5: Vercel Configuration

Generate `vercel.json`:

```json
{
  "version": 2,
  "buildCommand": "npm run build",
  "outputDirectory": "dist",
  "routes": [
    {
      "src": "/public/(.*)",
      "dest": "/public/$1"
    },
    {
      "src": "/(.*)",
      "dest": "/api/[[...path]]"
    }
  ],
  "functions": {
    "api/[[...path]].js": {
      "runtime": "edge"
    }
  }
}
```

## Configuration

### database.yml

```yaml
production:
  adapter: neon          # or turso, planetscale
  target: vercel-edge    # or vercel-node
```

### Environment Variables

Vercel uses environment variables for configuration:

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | Database connection string |
| `NODE_ENV` | Environment (production) |

Set via Vercel dashboard or CLI:
```bash
vercel env add DATABASE_URL
```

## Database Compatibility

| Target | Compatible Adapters |
|--------|---------------------|
| `vercel-edge` | neon, turso, planetscale |
| `vercel-node` | neon, turso, planetscale, pg, mysql2, pglite |

Edge Functions cannot use TCP, so only HTTP-based databases work.

## Deployment Workflow

### Initial Setup

```bash
# Install Vercel CLI
npm install -g vercel

# Link project
vercel link

# Set environment variables
vercel env add DATABASE_URL

# Deploy
vercel deploy
```

### Git Integration

Once linked, every push triggers a deploy:
- `main` branch → Production
- Other branches → Preview URL

### Local Development

```bash
# Use Vercel's local dev server
vercel dev

# Or use Ruby2JS dev server (same code, different runtime)
npm run dev
```

## Builder Updates

### lib/ruby2js/rails/builder.rb

```ruby
VERCEL_TARGETS = ['vercel-edge', 'vercel-node'].freeze

def build
  # ... existing code ...

  if VERCEL_TARGETS.include?(@target)
    generate_vercel_config
    generate_vercel_entry_point
  end
end

def generate_vercel_config
  config = {
    version: 2,
    buildCommand: 'npm run build',
    outputDirectory: 'dist',
    routes: [
      { src: '/public/(.*)', dest: '/public/$1' },
      { src: '/(.*)', dest: '/api/[[...path]]' }
    ]
  }

  if @target == 'vercel-edge'
    config[:functions] = {
      'api/[[...path]].js' => { runtime: 'edge' }
    }
  end

  write_json('dist/vercel.json', config)
end

def generate_vercel_entry_point
  entry = <<~JS
    import { Application, Router } from '../lib/rails.js';
    import '../config/routes.js';

    Application.configure({
      schema: (await import('../config/schema.js')).Schema,
      layout: (await import('../views/layouts/application.js')).layout
    });

    export default Application.handler();

    export const config = {
      runtime: '#{@target == 'vercel-edge' ? 'edge' : 'nodejs'}'
    };
  JS

  FileUtils.mkdir_p('dist/api')
  File.write('dist/api/[[...path]].js', entry)
end
```

## Comparison with Cloudflare

| Aspect | Cloudflare Workers | Vercel |
|--------|-------------------|--------|
| Entry pattern | `export default { fetch }` | `export default function` |
| Database | D1 binding (`env.DB`) | Environment variable |
| Config file | `wrangler.toml` | `vercel.json` |
| Integrated storage | D1, KV, R2, Durable Objects | None |
| Edge locations | 300+ | ~20 regions |
| Cold starts | Near-zero | Variable |

## Implementation Phases

### Phase 1: Target Files
- [ ] Create `targets/vercel-edge/rails.js`
- [ ] Create `targets/vercel-node/rails.js`
- [ ] Test with existing `rails_server.js` dispatch

### Phase 2: Build Integration
- [ ] Add `vercel-edge` and `vercel-node` to valid targets
- [ ] Generate `vercel.json` configuration
- [ ] Generate API entry point

### Phase 3: Documentation
- [ ] Deployment guide for Vercel
- [ ] Database setup instructions (Neon, Turso, PlanetScale)
- [ ] Environment variable configuration

### Phase 4: Testing
- [ ] Deploy sample app to Vercel
- [ ] Test with each compatible database adapter
- [ ] Verify preview deployments work

## Success Criteria

1. `target: vercel-edge` deploys and runs on Vercel Edge Functions
2. `target: vercel-node` deploys and runs on Vercel Serverless Functions
3. Database connectivity works via environment variables
4. Static assets served from CDN
5. Preview deployments work for PRs
6. Same Ruby source deploys to Vercel, Cloudflare, or Node.js

## Caching Filter

A new `caching` filter for cache control features. Target-aware: generates appropriate output for each platform.

### Supported Features

```ruby
class ArticlesController < ApplicationController
  # Time-based revalidation (ISR on Vercel, Cache-Control elsewhere)
  revalidate 60  # seconds

  # Tag-based caching for on-demand invalidation
  cache_tag "articles"

  # Per-action caching
  caches_action :index, :show

  def index
    @articles = Article.all
  end

  def show(id)
    @article = Article.find(id)
    cache_tag "article-#{id}"  # Dynamic tag
  end

  def create
    @article = Article.new(article_params)
    if @article.save
      revalidate_tag "articles"  # Bust cache on mutation
      redirect_to @article
    end
  end
end
```

### Target-Aware Behavior

| Feature | Vercel | Cloudflare | Node | Browser |
|---------|--------|------------|------|---------|
| `revalidate 60` | `s-maxage=60, stale-while-revalidate` | Cache-Control + Cache API | Cache-Control header | Ignored |
| `cache_tag "x"` | Next.js cache tags | Cache API with tag | Memory/Redis cache | Ignored |
| `revalidate_tag "x"` | Next.js `revalidateTag()` | Cache API purge | Cache invalidation | Ignored |
| `caches_action` | Static + revalidate | Cache API | Memory cache | Ignored |

### Filter Implementation

```ruby
# lib/ruby2js/filter/caching.rb
module Ruby2JS
  module Filter
    module Caching
      include SEXP

      def on_class(node)
        @revalidate = nil
        @cache_tags = []
        @cached_actions = []

        result = super

        # Inject caching metadata into class if needed
        if @revalidate || @cache_tags.any?
          result = inject_cache_config(result)
        end

        result
      end

      def on_send(node)
        target, method, *args = node.children

        case method
        when :revalidate
          return handle_revalidate(args) if target.nil?
        when :cache_tag
          return handle_cache_tag(args) if target.nil?
        when :revalidate_tag
          return handle_revalidate_tag(args) if target.nil?
        when :caches_action
          return handle_caches_action(args) if target.nil?
        end

        super
      end

      private

      def handle_revalidate(args)
        @revalidate = args.first.children.first
        # Store for runtime; removed from output
        s(:nil)
      end

      def handle_cache_tag(args)
        @cache_tags << process(args.first)
        s(:nil)
      end

      def handle_revalidate_tag(args)
        tag = process(args.first)
        # Generate target-appropriate invalidation call
        s(:send, nil, :__revalidate_tag__, tag)
      end
    end

    DEFAULTS.push Caching
  end
end
```

## React Filter Extension

Extend the existing `react` filter to support React Server Components:

### use_client Directive

```ruby
# Pragma style (magic comment)
# use client
class Counter < React
  def initialize
    @count = 0
  end
end

# Or class-level declaration
class InteractiveWidget < React
  use_client

  def initialize
    @active = false
  end
end
```

### Target-Aware Behavior

| Feature | Vercel/Next.js | Other Targets |
|---------|----------------|---------------|
| `use_client` | Prepends `'use client'` directive | Ignored (all code is client) |
| `use_server` | Prepends `'use server'` directive | Ignored |

### Implementation (extend react.rb)

```ruby
# In lib/ruby2js/filter/react.rb

def on_class(node)
  @use_client = false
  @use_server = false

  # ... existing code ...

  result = super

  # Prepend directive for React Server Components
  if @use_client && nextjs_target?
    result = prepend_directive(result, "'use client'")
  elsif @use_server && nextjs_target?
    result = prepend_directive(result, "'use server'")
  end

  result
end

def on_send(node)
  target, method, *args = node.children

  if target.nil?
    case method
    when :use_client
      @use_client = true
      return s(:nil)
    when :use_server
      @use_server = true
      return s(:nil)
    end
  end

  # ... existing code ...
  super
end

private

def nextjs_target?
  @options[:target]&.start_with?('vercel') ||
    @options[:framework] == 'nextjs'
end
```

## Other Vercel Features

These don't require filters—they're handled by the build process or runtime:

### Static Generation

```ruby
class ArticlesController < ApplicationController
  # Class method detected by builder, generates generateStaticParams()
  def self.static_params
    Article.all.map { |a| { id: a.id } }
  end
end
```

### Metadata / SEO

```ruby
class ArticlesController < ApplicationController
  # Class-level metadata becomes generateMetadata() export
  metadata title: "Blog Articles",
           description: "Read our latest posts"

  def show(id)
    @article = Article.find(id)
    # Instance-level metadata for dynamic pages
    metadata title: @article.title,
             og_image: @article.image_url
  end
end
```

### Not Found

```ruby
def show(id)
  @article = Article.find(id)
  not_found if @article.nil?  # Handled by base ApplicationController
end
```

### Response Header Integration

For ISR to work, the target runtime must include cache headers in responses:

```javascript
// targets/vercel-edge/rails.js
static async dispatch(request) {
  const response = await super.dispatch(request);

  // Add revalidate header if set by controller
  if (this._revalidate) {
    const headers = new Headers(response.headers);
    headers.set('Cache-Control', `s-maxage=${this._revalidate}, stale-while-revalidate`);
    return new Response(response.body, {
      status: response.status,
      headers
    });
  }

  return response;
}
```

## Blog Demonstration Path

The `test/blog` app serves as a progressive demonstration of Vercel capabilities:

### Step 1: Baseline (Works Today)

```bash
cd test/blog
./create-blog my-blog
cd my-blog

# Run with browser + IndexedDB
bundle exec ruby2js dev
```

**Config:**
```yaml
# config/database.yml
development:
  adapter: dexie
  database: my_blog_dev
```

### Step 2: Vercel Deployment

Change only the database config:

```yaml
# config/database.yml
production:
  adapter: neon
  target: vercel-edge
```

```bash
# Deploy
vercel link
vercel env add DATABASE_URL  # Neon connection string
vercel deploy
```

**No Ruby code changes.** The same blog runs on Vercel.

### Step 3: Add ISR Caching

Enhance the articles controller:

```ruby
# app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  revalidate 60  # Cache for 60 seconds
  cache_tag "articles"

  def index
    @articles = Article.all
  end

  def show(id)
    @article = Article.find(id)
    cache_tag "article-#{id}"
  end

  def create
    @article = Article.new(article_params)
    if @article.save
      revalidate_tag "articles"  # Bust cache on create
      redirect_to @article, notice: "Article created."
    else
      render :new
    end
  end
end
```

### Step 4: Add React Components (Optional)

Enhance views with Material UI:

```ruby
# app/views/articles/index.rb
import [Card, CardContent, Typography, Button], from: "@mui/material"

class ArticlesIndex < ApplicationView
  def render
    _div class: "articles" do
      @articles.each do |article|
        render Card.new(key: article.id, sx: { mb: 2 }) do
          render CardContent.new do
            render Typography.new(variant: "h5") { article.title }
            render Typography.new(variant: "body2", color: "text.secondary") do
              truncate(article.body, 100)
            end
          end
          render Button.new(
            onClick: -> { navigate("/articles/#{article.id}") }
          ) { "Read More" }
        end
      end
    end
  end
end
```

### Step 5: Static Generation (Advanced)

Pre-render article pages at build time:

```ruby
# app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  # Generate static pages for all articles
  def self.static_params
    Article.all.map { |a| { id: a.id } }
  end

  revalidate 3600  # Revalidate hourly

  def show(id)
    @article = Article.find(id)
    not_found if @article.nil?
  end
end
```

### Demonstration Summary

| Step | Feature | Code Changes | Config Changes |
|------|---------|--------------|----------------|
| 1 | Browser dev | None | dexie adapter |
| 2 | Vercel deploy | None | neon + vercel-edge |
| 3 | ISR caching | Add `revalidate`, `cache_tag` | None |
| 4 | React UI | Replace views with MUI | Add npm deps |
| 5 | Static gen | Add `static_params` | None |

Each step builds on the previous. The blog remains a standard Rails CRUD application throughout—no architectural rewrites required.

## Open Questions

1. **Middleware**: Should `before_action` generate Vercel Edge Middleware for auth/geo?
2. **Monorepo**: How to handle Vercel's monorepo detection?
3. **Preview mode**: Support for draft/preview content workflows?

## References

- [Vercel Edge Functions](https://vercel.com/docs/functions/edge-functions)
- [Vercel Serverless Functions](https://vercel.com/docs/functions/serverless-functions)
- [Vercel Configuration](https://vercel.com/docs/projects/project-configuration)
