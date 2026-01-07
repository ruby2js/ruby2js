# Rails SPA Engine: Offline-Capable SPAs from Rails Subsets

## Status: In Progress

Generate offline-capable Single Page Applications from a subset of an existing Rails application. The SPA runs entirely client-side with IndexedDB storage, syncing with the server when online.

## Validation Plan

This plan defines the **tooling**. Two applications validate it:

| Validation | Application | Purpose |
|------------|-------------|---------|
| First | [Calendar Demo](CALENDAR_DEMO.md) | New app built from scratch, proves the concept |
| Second | [Showcase Scoring](#target-use-case-showcase-scoring) | Production app, proves real-world viability |

The Calendar demo also extends SPA Engine with Electron and Capacitor targets for desktop/mobile.

## Current Progress

### Completed ✅

| Stage | Description                                                  | Commit  |
| ----- | ------------------------------------------------------------ | ------- |
| 1     | Engine infrastructure (generators, manifest DSL, rake tasks) | Initial |
| 2     | Model transpilation with AST-based dependency resolution     | d86afc7 |
| 3     | View transpilation (ERB to JS render functions)              | aa67a79 |
| 4     | Controller transpilation                                     | 2a89c8a |
| -     | Refactor: Builder generates ruby2js-rails compatible output  | 8243167 |
| -     | Update generator template for current syntax                 | a149b9f |

### What Works Now

The SPA builder generates a standalone directory that:
- Contains Ruby source files (models, controllers, views)
- Has `package.json` with `ruby2js-rails` dependency
- Has config files (`database.yml`, `ruby2js.yml`, `routes.rb`)
- Can be built with `npm install && npm run build && npm start`

```bash
# From a Rails app with ruby2js installed:
rails generate ruby2js:spa:install --name blog
# Edit config/ruby2js_spa.rb
rails ruby2js:spa:build
cd public/spa/blog
npm install && npm run build && npm start
```

## Revised Architecture

### Key Design Changes

1. **Dual Target Support**: Generate SPAs that can run either:
   - **Standalone**: `npm start` serves the SPA independently
   - **Rack-mounted**: Rails middleware serves the SPA at a mount path

2. **ruby2js-rails Handles Building**: The Ruby gem orchestrates (copies source, generates config), but `ruby2js-rails` npm package does actual transpilation. Enhancements go into ruby2js-rails, not a separate build process.

3. **Incremental Testing**: Test after each feature addition, not at the end.

### Build Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  Rails Application                                              │
│                                                                 │
│  config/ruby2js_spa.rb (manifest)                               │
│       │                                                         │
│       ▼                                                         │
│  rake ruby2js:spa:build                                         │
│       │                                                         │
│       ▼                                                         │
│  Ruby2JS::Spa::Builder                                          │
│  - Copies Ruby source (models, controllers, views)              │
│  - Generates package.json with ruby2js-rails                    │
│  - Generates config (database.yml, routes.rb, etc.)             │
│       │                                                         │
│       ▼                                                         │
│  public/spa/{name}/                                             │
│  ├── app/ (Ruby source)                                         │
│  ├── config/ (generated)                                        │
│  └── package.json                                               │
│       │                                                         │
│       ▼                                                         │
│  npm install && npm run build  (ruby2js-rails)                  │
│       │                                                         │
│       ▼                                                         │
│  dist/ (transpiled JavaScript)                                  │
│       │                                                         │
│       ├──► Standalone: npm start                                │
│       │                                                         │
│       └──► Rack: Middleware serves at mount_path                │
└─────────────────────────────────────────────────────────────────┘
```

### Generated SPA Structure

```
public/spa/{name}/
├── app/
│   ├── models/           # Ruby source (copied)
│   ├── controllers/      # Ruby source (copied)
│   └── views/            # ERB templates (copied)
├── config/
│   ├── database.yml      # Generated (dexie adapter)
│   ├── routes.rb         # Generated from manifest
│   ├── ruby2js.yml       # Generated (transpilation options)
│   └── schema.rb         # Copied from Rails app
├── package.json          # Generated (ruby2js-rails dependency)
├── index.html            # Generated entry point
└── README.md             # Generated instructions

# After npm run build:
├── dist/
│   ├── config/routes.js, paths.js, schema.js
│   ├── controllers/*.js
│   ├── models/*.js
│   ├── views/*.js
│   └── lib/rails.js, active_record.mjs
└── node_modules/
```

## Remaining Stages

### Next: End-to-End Testing

**Goal:** Verify the full workflow with a fresh Rails scaffold

```bash
rails new blog
cd blog
rails generate scaffold Article title:string body:text
rails db:migrate
# Add gem 'ruby2js' to Gemfile
bundle install
rails generate ruby2js:spa:install --name blog
# Edit config/ruby2js_spa.rb
rails ruby2js:spa:build
cd public/spa/blog
npm install && npm run build && npm start
```

**Success criteria:**
- SPA loads in browser
- Articles CRUD works with IndexedDB
- No Ruby/Rails runtime needed

### Stage 5: Rack Middleware

**Goal:** Serve SPA from within Rails app at mount path

```ruby
# config/ruby2js_spa.rb
Ruby2JS::Spa.configure do
  name :scoring
  mount_path '/offline'
  serve_from :rack  # New option
end
```

**Tasks:**
1. Middleware serves built SPA at mount_path
2. Falls through to Rails for non-SPA routes
3. Auto-configures via Engine initializer
4. Option in manifest to choose standalone vs rack

**Test:** Visit `/offline/articles` in Rails app, SPA loads and works

### Stage 6: Turbo Interceptor

**Goal:** Offline navigation with Turbo integration

**Tasks:**
1. Intercept `turbo:before-fetch-request`
2. Match against SPA routes
3. Render locally from IndexedDB
4. Update DOM via `Turbo.renderStreamMessage()`
5. Handle form submissions offline

**Test:** Navigate and submit forms while offline, works correctly

### Stage 7: Sync Layer

**Goal:** Bidirectional sync when online

**Tasks:**
1. Queue changes in IndexedDB
2. Upload pending changes on connectivity
3. Download updates since last sync
4. Handle conflicts (last-write-wins initially)

**Test:** Make offline changes, come online, changes sync to server

### Stage 8: Documentation & Polish

**Goal:** Production-ready with docs

**Tasks:**
1. README with quick start
2. Manifest reference docs
3. Troubleshooting guide
4. Integration with ruby2js.com docs

## Manifest Format

```ruby
# config/ruby2js_spa.rb
Ruby2JS::Spa.configure do
  name :scoring
  mount_path '/offline'

  # Models: auto-discovers associations
  models do
    include :Article
    include :Comment
  end

  # Controllers: optionally filter actions
  controllers do
    include :articles
    include :comments, only: [:create, :destroy]
  end

  # Views: glob patterns
  views do
    include 'articles/*.html.erb'
    include 'comments/_form.html.erb'
  end

  # Stimulus: copy JS controllers (not transpiled)
  stimulus do
    include 'article_controller.js'
  end
end
```

## ruby2js-rails Enhancements Needed

The `ruby2js-rails` npm package may need enhancements for SPA-specific features:

| Feature               | Config Option         | Description                    |
| --------------------- | --------------------- | ------------------------------ |
| Database adapter      | `config/database.yml` | Already supported              |
| Transpilation options | `config/ruby2js.yml`  | Already supported              |
| Turbo interceptor     | TBD                   | Runtime for offline navigation |
| Sync layer            | TBD                   | Change tracking and sync       |
| Middleware transpile  | TBD                   | Rack → Fetch API for edge deployment |

These would be added to `ruby2js-rails` as needed, keeping the Ruby gem lightweight.

### Middleware Transpilation (Edge Deployment)

For deploying the server to Cloudflare Workers, Rack middleware needs to transpile to Fetch API handlers:

| Rack Pattern | Fetch API Equivalent |
|--------------|---------------------|
| `def call(env)` | `async fetch(request, env)` |
| `env['PATH_INFO']` | `new URL(request.url).pathname` |
| `env['REQUEST_METHOD']` | `request.method` |
| `env['rack.input'].read` | `await request.text()` |
| `@app.call(env)` | `await this.app.fetch(request, env)` |
| `[200, headers, [body]]` | `new Response(body, { status: 200, headers })` |

This enables the "Ruby runtime optional" story - same sync API code runs on Rails or Cloudflare.

## Target Use Case: Showcase Scoring

**Second validation** after [Calendar Demo](CALENDAR_DEMO.md).

The [Showcase](https://github.com/rubys/showcase) application's offline scoring interface provides a production validation. Unlike Calendar (built from scratch), this extracts an SPA from an **existing** Rails application with real users (judges at ballroom dance competitions).

### Routes Needed
```ruby
get 'heats/:id', to: 'scores#heat'
get 'heats/:id/card', to: 'scores#card'
patch 'scores/:id', to: 'scores#update'
```

### Models Needed

| Model | Purpose | Writes? |
|-------|---------|---------|
| Event | Competition config | No |
| Judge | Judge assignment | No |
| Heat | Heat display data | No |
| Person | Participant names | No |
| Entry | Lead/follow pairs | No |
| Dance | Dance names | No |
| Score | **Judge scores** | **Yes** |
| Solo/Formation | Solo displays | No |
| Age, Level, Studio | Reference data | No |

Most models are read-only on the client. Only `Score` needs create/update.

### Architecture

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

**Key insight:** No hydration layer. The browser runs the same ActiveRecord-style queries against Dexie that Rails runs against SQLite. This replaces the existing JavaScript SPA (`heat_hydrator.js`, `heat_data_manager.js`, etc.) with transpiled Ruby.

### Success Criteria

- [ ] Judge can view heat information offline
- [ ] Judge can enter scores offline
- [ ] Scores sync when connectivity returns
- [ ] Existing Stimulus controllers work
- [ ] No visible difference from online experience

## Dependencies

```
Completed:
  ✅ Stage 1 (Engine Infrastructure)
  ✅ Stage 2 (Models)
  ✅ Stage 3 (Views)
  ✅ Stage 4 (Controllers)
  ✅ Refactor (ruby2js-rails compatible output)

Remaining:
  → End-to-End Testing (next)
      │
      ▼
  Stage 5 (Rack Middleware)
      │
      ▼
  Stage 6 (Turbo Interceptor)
      │
      ▼
  Stage 7 (Sync Layer)
      │
      ├──────────────────────────────┐
      ▼                              ▼
  Stage 8 (Documentation)    📱 Calendar Demo validates
      │                         (+ Electron/Capacitor)
      │                              │
      ▼                              ▼
  ════════════════════════════════════════
             Showcase Scoring
        (production validation)
```

## Open Questions

1. **Rack vs Standalone default:** Should manifest default to standalone (simpler) or rack-mounted (integrated)?

2. **ruby2js-rails versioning:** How to ensure SPA uses compatible ruby2js-rails version?

3. **Partial rebuilds:** Should `rake ruby2js:spa:build` detect changes and do incremental builds?

4. **Service Worker:** Add later for true offline-first, or integrate from the start?

## References

**Upstream (this depends on):**
- [AREL_QUERY_BUILDER.md](AREL_QUERY_BUILDER.md) - Query building and associations (foundational)

**Downstream (depends on this):**
- [Calendar Demo Plan](CALENDAR_DEMO.md) - First validation (new app + Electron/Capacitor)

**External:**
- [Ruby2JS on Rails Demo](../demo/ruby2js-on-rails/) - Proves transpilation approach
- [ruby2js-rails npm package](https://www.ruby2js.com/releases/ruby2js-rails-beta.tgz) - Build infrastructure
- [RUBY2JS_SHARED_LOGIC.md](https://github.com/rubys/showcase/blob/main/plans/RUBY2JS_SHARED_LOGIC.md) - Showcase requirements
- [Hotwire Turbo](https://turbo.hotwired.dev/) - Navigation and streaming
- [Dexie.js](https://dexie.org/) - IndexedDB wrapper
