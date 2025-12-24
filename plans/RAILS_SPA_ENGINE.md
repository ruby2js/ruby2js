# Rails SPA Engine: Offline-Capable SPAs from Rails Subsets

## Status: Planning

Generate offline-capable Single Page Applications from a subset of an existing Rails application. The SPA runs entirely client-side with IndexedDB storage, syncing with the server when online.

## Problem Statement

Rails applications sometimes need specific views to work offline. Examples:
- **Judging/scoring interfaces** at events with unreliable connectivity
- **Field data collection** where network is unavailable
- **Kiosk displays** that must continue working during outages

Currently, this requires duplicating view logic:
- **Server:** ERB templates render with ActiveRecord objects
- **Client:** Hand-written JavaScript/Web Components render with JSON

When view logic changes, both implementations must be updated. This creates maintenance burden and risk of drift.

## Solution

A Rails Engine that:
1. Reads a manifest specifying which routes, models, views, and controllers to include
2. Transpiles the specified subset to JavaScript via Ruby2JS
3. Bundles into a standalone SPA with Dexie (IndexedDB) for storage
4. Mounts the SPA at a configurable path via Rack middleware
5. Integrates with Hotwire (Turbo + Stimulus) for navigation and interactivity

```
┌─────────────────────────────────────────────────────────────────┐
│  Rails Application                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  /scores/heats/123     →  Server-rendered (online)              │
│                                                                 │
│  /offline/scores/...   →  SPA (works offline)                   │
│       ↓                                                         │
│  Ruby2JS::Spa::Middleware serves transpiled SPA                 │
│       ↓                                                         │
│  SPA intercepts Turbo, renders from IndexedDB                   │
│       ↓                                                         │
│  On navigation: sync pending changes, fetch updates             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Target Use Case: Showcase Scoring

The showcase application's offline scoring requirements define the minimum viable scope:

### Routes Needed
```ruby
get 'heats/:id', to: 'scores#heat'
get 'heats/:id/card', to: 'scores#card'
get 'heats/:id/table', to: 'scores#table'
patch 'scores/:id', to: 'scores#update'
```

### Models Needed
```ruby
Heat, Entry, Score, Person, Dance, Age, Level, Studio, Solo
```

### Views Needed
```
scores/_table_heat.html.erb
scores/_cards_heat.html.erb
scores/_heat_header.html.erb
scores/_info_box.html.erb
# ... other scoring partials
```

### Stimulus Controllers Needed
```javascript
score_controller.js      # Uses turbo:before-visit
drop_controller.js       # Uses Turbo.renderStreamMessage()
open_feedback_controller.js
info_box_controller.js
```

## Architecture

### Rails Engine Structure

```
lib/ruby2js/
├── spa/
│   ├── engine.rb           # Rails::Engine with generators, middleware
│   ├── manifest.rb         # Parses config/ruby2js_spa.yml
│   ├── builder.rb          # Orchestrates transpilation
│   ├── middleware.rb       # Rack middleware to serve SPA
│   ├── transpilers/
│   │   ├── models.rb       # Transpile model subset
│   │   ├── views.rb        # Transpile ERB templates
│   │   ├── controllers.rb  # Transpile controller subset
│   │   └── routes.rb       # Transpile route subset
│   └── runtime/
│       ├── turbo_interceptor.js   # Intercept Turbo for offline
│       ├── sync.js                # Upload/download sync logic
│       └── dexie_adapter.js       # ActiveRecord over Dexie
└── generators/
    └── spa/
        ├── install_generator.rb
        └── templates/
            └── ruby2js_spa.yml.tt
```

### Generated SPA Structure

```
public/spa/{name}/
├── index.html              # Entry point, loads Turbo + app
├── app.js                  # Bundled transpiled code
├── models/                 # Transpiled model classes
├── views/                  # Transpiled render functions
├── controllers/            # Transpiled Rails controllers
├── stimulus/               # Copied Stimulus controllers (JS)
└── lib/
    ├── active_record.js    # Dexie-backed ActiveRecord
    ├── turbo_interceptor.js
    └── sync.js
```

### Manifest Format

```yaml
# config/ruby2js_spa.yml
name: scoring
mount_path: /offline/scores

# What to transpile
routes:
  only:
    - "get 'heats/:id', to: 'scores#heat'"
    - "get 'heats/:id/card', to: 'scores#card'"
    - "patch 'scores/:id', to: 'scores#update'"

models:
  include:
    - Heat
    - Entry
    - Score
    - Person
    - Dance
  # Associations outside the include list become pre-computed attributes

views:
  include:
    - scores/_table_heat.html.erb
    - scores/_cards_heat.html.erb
    - scores/_heat_header.html.erb

controllers:
  include:
    - ScoresController
  # Only actions referenced by routes are transpiled

stimulus:
  include:
    - score_controller.js
    - drop_controller.js

# Sync configuration
sync:
  endpoint: /api/spa/sync
  models:
    - Score  # Models that can be modified offline
```

## Turbo Integration

The key insight: `Turbo.renderStreamMessage()` accepts Turbo Stream HTML regardless of source. The SPA generates this HTML client-side from transpiled ERB.

### Navigation Flow (Offline)

```javascript
// turbo_interceptor.js
document.addEventListener('turbo:before-fetch-request', async (event) => {
  const url = new URL(event.detail.url);
  const path = url.pathname;

  // Check if this route is handled by SPA
  const match = SpaRouter.match(path);
  if (!match) return; // Let Turbo fetch from server

  event.preventDefault();

  // Try to sync first (if online)
  await Sync.attempt();

  // Render locally from IndexedDB
  const html = await match.controller[match.action](match.params);

  // Update DOM via Turbo
  Turbo.renderStreamMessage(`
    <turbo-stream action="replace" target="main">
      <template>${html}</template>
    </turbo-stream>
  `);

  // Update browser history
  history.pushState({}, '', path);
});
```

### Form Submission Flow (Offline)

```javascript
document.addEventListener('turbo:before-fetch-request', async (event) => {
  if (event.detail.fetchOptions.method === 'GET') return;

  const match = SpaRouter.match(path, method);
  if (!match) return;

  event.preventDefault();

  // Extract form data
  const formData = new FormData(event.target);
  const params = Object.fromEntries(formData);

  // Execute controller action locally
  const result = await match.controller[match.action](match.params, params);

  // Queue for sync
  await Sync.queue(match.model, match.action, params);

  // Render result
  if (result.turbo_stream) {
    Turbo.renderStreamMessage(result.turbo_stream);
  } else if (result.redirect) {
    SpaRouter.navigate(result.redirect);
  }
});
```

### Sync on Navigation

```javascript
// sync.js
document.addEventListener('turbo:before-visit', async (event) => {
  try {
    // 1. Upload pending changes
    await uploadPendingChanges();

    // 2. Download updates
    await downloadUpdates();
  } catch (e) {
    // Offline - proceed with local data
    console.log('Sync failed, using local data:', e.message);
  }
});
```

### Stimulus Compatibility

Existing Stimulus controllers work unchanged because:
1. They attach to DOM elements that Turbo Stream updates create
2. They use `Turbo.renderStreamMessage()` which works with locally-generated HTML
3. Events like `turbo:before-visit` fire regardless of navigation source

## Implementation Stages

### Stage 1: Engine Infrastructure

**Goal:** Rails Engine with generators and manifest parsing

#### Tasks

1. **Create Engine skeleton**
   ```ruby
   # lib/ruby2js/spa/engine.rb
   module Ruby2JS
     module Spa
       class Engine < ::Rails::Engine
         isolate_namespace Ruby2JS::Spa

         generators do
           require 'ruby2js/generators/spa/install_generator'
         end
       end
     end
   end
   ```

2. **Install generator**
   ```bash
   rails generate ruby2js:spa:install
   # Creates config/ruby2js_spa.yml
   # Adds middleware to config/application.rb
   # Adds .gitignore entry for public/spa/
   ```

3. **Manifest parser**
   ```ruby
   # lib/ruby2js/spa/manifest.rb
   module Ruby2JS
     module Spa
       class Manifest
         def initialize(path = 'config/ruby2js_spa.yml')
           @config = YAML.load_file(path)
         end

         def routes; @config['routes']; end
         def models; @config['models']; end
         def views; @config['views']; end
         def controllers; @config['controllers']; end
         def stimulus; @config['stimulus']; end
         def sync_config; @config['sync']; end
       end
     end
   end
   ```

4. **Rake task skeleton**
   ```ruby
   # lib/tasks/ruby2js_spa.rake
   namespace :ruby2js do
     namespace :spa do
       desc "Build offline SPA from manifest"
       task build: :environment do
         manifest = Ruby2JS::Spa::Manifest.new
         builder = Ruby2JS::Spa::Builder.new(manifest)
         builder.build
       end
     end
   end
   ```

#### Deliverables
- `rails generate ruby2js:spa:install` works
- `rake ruby2js:spa:build` runs (outputs placeholder)
- Manifest YAML parsed correctly

### Stage 2: Model Transpilation

**Goal:** Transpile model subset with Dexie backend

#### Tasks

1. **Model dependency resolution**
   - Parse `has_many`, `belongs_to` declarations
   - Build dependency graph
   - Warn about associations outside included models
   - Generate pre-computed attribute stubs for external associations

2. **Dexie schema generation**
   - Extract table structure from schema.rb or model introspection
   - Generate Dexie version/stores configuration
   - Handle indexes for queried fields

3. **Model class transpilation**
   - Use existing `rails/model` filter
   - Adapt for Dexie instead of sql.js
   - Handle scopes referenced by controllers

#### Example Output

```javascript
// models/heat.js
import { db } from '../lib/active_record.js';

export class Heat extends ApplicationRecord {
  static tableName = 'heats';

  // Associations (within SPA)
  get entry() { return Entry.find(this.entry_id); }
  get scores() { return Score.where({ heat_id: this.id }); }

  // Pre-computed (from server snapshot)
  // dance_string, scoring_type set during sync
}
```

#### Deliverables
- Models transpile to Dexie-backed classes
- Associations within SPA work
- External associations become pre-computed attributes

### Stage 3: View Transpilation

**Goal:** Transpile ERB templates to JavaScript render functions

#### Tasks

1. **ERB compilation**
   - Use existing ERB filter
   - Handle partials (`render partial:`)
   - Handle layouts (optional, may skip for SPA)

2. **View helper transpilation**
   - `dom_id` helper
   - `pluralize` helper
   - Path helpers for included routes
   - Form helpers (`form_with`, etc.)

3. **Turbo Stream generation**
   - Views can return Turbo Stream HTML
   - Support `turbo_stream.replace`, `append`, etc.

#### Example Output

```javascript
// views/scores/table_heat.js
export function table_heat({ heat, scores }) {
  return `
    <div id="${dom_id(heat)}" class="heat-table">
      <h2>${heat.dance_string}</h2>
      ${scores.map(score => score_row({ score })).join('')}
    </div>
  `;
}
```

#### Deliverables
- ERB templates transpile to render functions
- Partials work
- View helpers work

### Stage 4: Controller Transpilation

**Goal:** Transpile controller subset with action methods

#### Tasks

1. **Action extraction**
   - Only transpile actions referenced by routes
   - Handle `before_action` callbacks

2. **Params handling**
   - Route params from URL matching
   - Form params from Turbo interception

3. **Render/redirect**
   - `render` returns HTML string
   - `redirect_to` returns redirect instruction
   - `respond_to` with turbo_stream format

#### Example Output

```javascript
// controllers/scores_controller.js
export class ScoresController {
  async heat(params) {
    const heat = await Heat.find(params.id);
    const scores = await heat.scores;
    return table_heat({ heat, scores });
  }

  async update(params, formData) {
    const score = await Score.find(params.id);
    await score.update(formData);

    // Queue for sync
    Sync.queue('scores', 'update', { id: score.id, ...formData });

    return {
      turbo_stream: `
        <turbo-stream action="replace" target="${dom_id(score)}">
          <template>${score_row({ score })}</template>
        </turbo-stream>
      `
    };
  }
}
```

#### Deliverables
- Controllers transpile with action methods
- Actions return rendered HTML or Turbo Streams
- Mutations queue for sync

### Stage 5: Turbo Interceptor Runtime

**Goal:** Runtime that intercepts Turbo and renders locally

#### Tasks

1. **Route matching**
   - Parse transpiled routes
   - Match incoming paths
   - Extract params

2. **Turbo interception**
   - `turbo:before-fetch-request` handler
   - Prevent fetch, render locally
   - Update history

3. **Stimulus integration**
   - Copy specified Stimulus controllers
   - Ensure controllers connect after Turbo Stream updates

#### Deliverables
- Navigation works offline
- Turbo Streams update DOM
- Stimulus controllers work

### Stage 6: Sync Layer

**Goal:** Upload pending changes, download updates

#### Tasks

1. **Change tracking**
   - Queue model changes in IndexedDB
   - Track pending vs synced state

2. **Upload**
   - Batch pending changes
   - POST to sync endpoint
   - Mark as synced on success

3. **Download**
   - Fetch updates since last sync
   - Upsert into IndexedDB
   - Handle conflicts (last-write-wins initially)

4. **Server endpoint** (in showcase, not Ruby2JS)
   - `/api/spa/sync` accepts uploads, returns updates
   - Scoped to current user/event

#### Deliverables
- Changes persist locally
- Sync uploads when online
- Updates download on navigation

### Stage 7: Rack Middleware

**Goal:** Serve SPA at mount path

#### Tasks

1. **Middleware implementation**
   ```ruby
   # lib/ruby2js/spa/middleware.rb
   module Ruby2JS
     module Spa
       class Middleware
         def initialize(app, options = {})
           @app = app
           @mount_path = options[:mount_path]
           @spa_root = options[:spa_root]
         end

         def call(env)
           if env['PATH_INFO'].start_with?(@mount_path)
             serve_spa(env)
           else
             @app.call(env)
           end
         end
       end
     end
   end
   ```

2. **Static asset serving**
   - Serve `index.html` for SPA routes
   - Serve JS/CSS assets directly

3. **Auto-configuration**
   - Engine initializer reads manifest
   - Inserts middleware automatically

#### Deliverables
- `/offline/scores/heats/123` serves SPA
- Assets load correctly
- Non-SPA routes pass through

### Stage 8: Documentation & Testing

**Goal:** Production-ready with docs and tests

#### Tasks

1. **Documentation**
   - README with quick start
   - Manifest reference
   - Troubleshooting guide
   - Example project

2. **Testing**
   - Unit tests for manifest parsing
   - Integration tests for transpilation
   - End-to-end test with sample Rails app

3. **CI integration**
   - Add to Ruby2JS test suite
   - Test with ruby2js-on-rails demo

#### Deliverables
- Comprehensive documentation
- Test coverage
- CI passing

## Dependencies

```
Stage 1 (Engine Infrastructure)
    │
    ├── Stage 2 (Models)
    │       │
    ├── Stage 3 (Views)
    │       │
    └── Stage 4 (Controllers)
            │
            ▼
    Stage 5 (Turbo Interceptor)
            │
            ▼
    Stage 6 (Sync Layer)
            │
            ▼
    Stage 7 (Middleware)
            │
            ▼
    Stage 8 (Docs & Tests)
```

Stages 2-4 can proceed in parallel after Stage 1.

## Risks and Mitigations

### ActiveRecord Query Complexity

**Risk:** Showcase controllers may use complex queries not supported by Dexie.

**Mitigation:**
- Audit actual queries used in scoring views
- Support common patterns: `find`, `where`, `order`, `includes`
- Pre-compute complex queries server-side during sync

### Turbo Interception Edge Cases

**Risk:** Some Turbo features may not work with interception.

**Mitigation:**
- Test with actual showcase Stimulus controllers
- Document limitations
- Allow fallback to server for unsupported patterns

### Model Association Depth

**Risk:** Deep association chains may be hard to resolve offline.

**Mitigation:**
- Flatten associations during sync (pre-compute nested data)
- Limit SPA to specific view patterns
- Document association handling

### Sync Conflicts

**Risk:** Offline edits may conflict with server state.

**Mitigation:**
- Start with last-write-wins (simple)
- Add conflict detection in future iteration
- Scope to single-user-at-a-time use cases initially

## Success Criteria

### Minimum Viable (Showcase Scoring)

- [ ] Judge can view heat information offline
- [ ] Judge can enter scores offline
- [ ] Scores sync when connectivity returns
- [ ] Existing Stimulus controllers work
- [ ] No visible difference from online experience

### General Availability

- [ ] Works with any Rails 7+ application
- [ ] Manifest format documented
- [ ] Generator creates working configuration
- [ ] At least one example beyond showcase
- [ ] Published to RubyGems

## Open Questions

1. **Manifest validation:** How strict should validation be? Warn vs error on missing dependencies?

2. **Asset pipeline integration:** Should the build integrate with Propshaft/Sprockets, or be standalone?

3. **Service Worker:** Should the SPA register a service worker for true offline, or rely on Turbo interception?

4. **Versioning:** How to handle SPA version mismatches after server deploys?

5. **Authentication:** How to handle session/auth in the offline SPA?

## Future Possibilities

- **Service Worker:** Cache assets for true offline-first
- **Background Sync:** Use Background Sync API for reliable uploads
- **Conflict Resolution:** UI for resolving sync conflicts
- **Partial Sync:** Only sync data relevant to current user/context
- **Live Updates:** WebSocket/SSE for real-time sync while online

## References

- [Ruby2JS on Rails Demo](../demo/ruby2js-on-rails/) - Proves transpilation approach
- [RUBY2JS_SHARED_LOGIC.md](https://github.com/rubys/showcase/blob/main/plans/RUBY2JS_SHARED_LOGIC.md) - Showcase requirements
- [Hotwire Turbo](https://turbo.hotwired.dev/) - Navigation and streaming
- [Dexie.js](https://dexie.org/) - IndexedDB wrapper
- [Rails Engines](https://guides.rubyonrails.org/engines.html) - Engine patterns
