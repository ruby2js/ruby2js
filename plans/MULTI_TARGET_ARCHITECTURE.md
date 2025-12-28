# Multi-Target Architecture Plan

Transpile the same Rails-structured Ruby source to different JavaScript runtime targets: browser SPA, Node.js server, or hybrid configurations.

## Vision

One codebase:
```
app/
├── models/article.rb
├── controllers/articles_controller.rb
├── views/articles/index.html.erb
└── config/routes.rb
```

Multiple deployment targets:
- **Browser** — SPA with client-side routing, IndexedDB storage
- **Node.js** — Traditional HTTP server, PostgreSQL/MySQL storage
- **Hybrid** — Server-side rendering with client-side hydration (future)

## Key Insight: Transpilation-Time Selection

All target-specific decisions are made at build time, not runtime:

```
Build Time                           Runtime
──────────                           ───────
TARGET=browser                       No target switching
DATABASE=dexie                       No adapter abstraction
        ↓                            No unused code paths
   Build process                             ↓
        ↓                            Just the generated
   Filters receive options           JavaScript running
        ↓
   Target-appropriate code
```

**Benefits:**
- Zero runtime overhead for target selection
- No unused code shipped (browser doesn't get http.createServer)
- Each target is optimized for its environment
- Simpler debugging (you know exactly what code runs)

## Configuration

### config/database.yml (Primary)

The adapter in `config/database.yml` determines both database and target:

```yaml
development:
  adapter: dexie
  database: my_app_dev

test:
  adapter: sqljs
  database: my_app_test

production:
  adapter: pg
  host: localhost
  port: 5432
  database: my_app_production
  pool: 5
```

| Adapter          | Target  | Use Case                       |
| ---------------- | ------- | ------------------------------ |
| `dexie`          | browser | IndexedDB wrapper (~50KB)      |
| `sqljs`          | browser | Full SQL support (~2.7MB WASM) |
| `better_sqlite3` | node    | Development, sync API          |
| `sqlite3`        | node    | Development, async API         |
| `pg`             | node    | Production PostgreSQL          |
| `mysql2`         | node    | Production MySQL               |

### Environment Variables

`RAILS_ENV` or `NODE_ENV` selects which config to use:

```bash
# Development (default) → reads development.adapter → dexie → browser
npm run dev

# Production → reads production.adapter → pg → node
RAILS_ENV=production npm run build
# or
NODE_ENV=production npm run build
```

Priority: `RAILS_ENV` > `NODE_ENV` > `'development'`

**Optional overrides:**

```bash
# Override adapter for quick testing (without editing yaml)
DATABASE=sqljs npm run dev

# Production with DATABASE_URL (standard 12-factor pattern)
DATABASE_URL=postgres://user:pass@host:5432/myapp npm run build
```

### Build Script Logic

```javascript
const env = process.env.RAILS_ENV || process.env.NODE_ENV || 'development';
const dbConfig = yaml.load(fs.readFileSync('config/database.yml', 'utf8'));
const database = process.env.DATABASE || dbConfig[env]?.adapter || 'dexie';
const target = ['dexie', 'sqljs'].includes(database) ? 'browser' : 'node';
```

`DATABASE_URL` can be used at build time or runtime:

**Build time:** Extracts adapter to select which implementation to copy:
```bash
DATABASE_URL=postgres://... npm run build  # → copies active_record_pg.mjs
```

**Runtime:** Connection details read from environment:
```javascript
// In active_record_pg.mjs
const dbConfig = process.env.DATABASE_URL
  ? parseDatabaseUrl(process.env.DATABASE_URL)
  : DB_CONFIG;  // Fallback to build-time config
```

This separation means:
- **Adapter selection** happens at build time (which driver code to include)
- **Connection details** can come from runtime environment (12-factor friendly)

```
postgres://user:pass@localhost:5432/myapp?pool=5
   │        │    │       │       │    │      └── options
   │        │    │       │       │    └── database
   │        │    │       │       └── port
   │        │    │       └── host
   │        │    └── password
   │        └── username
   └── adapter (postgres → pg)
```

### config/database.yml

Database connection details (adapter-specific options):

```yaml
development:
  adapter: dexie
  database: my_app_dev

production:
  adapter: pg
  host: localhost
  port: 5432
  database: my_app_production
  pool: 5
```

The `adapter` field can be overridden by `DATABASE` environment variable, allowing the same `database.yml` to work across environments:

```bash
# Use pg adapter with production connection settings
DATABASE=pg NODE_ENV=production npm run build
```

### Build Process

```javascript
// build-selfhost.mjs
import yaml from 'js-yaml';

const target = process.env.TARGET || 'browser';
const env = process.env.NODE_ENV || 'development';

// Read database config
const dbConfig = yaml.load(fs.readFileSync('config/database.yml', 'utf8'));
const database = process.env.DATABASE || dbConfig[env]?.adapter || 'dexie';

// Pass to transpiler
await build({
  target,           // 'browser' | 'node'
  database,         // 'dexie' | 'sqljs' | 'pg' | 'mysql2' | 'better_sqlite3'
  dbConfig: dbConfig[env]
});
```

## Target Differences

### Routes

**Browser target (`rails/routes` filter):**
```javascript
// Generated routes.js
import { router } from './lib/router.js';

router.resources('articles');
router.root('articles#index');

// Client-side routing via History API
window.addEventListener('popstate', () => router.dispatch(location.pathname));
document.addEventListener('click', (e) => {
  if (e.target.matches('a[data-turbo]')) {
    e.preventDefault();
    history.pushState({}, '', e.target.href);
    router.dispatch(e.target.pathname);
  }
});
```

**Node.js target:**
```javascript
// Generated server.js
import http from 'http';
import { router } from './lib/router.js';

router.resources('articles');
router.root('articles#index');

// HTTP server
const server = http.createServer(async (req, res) => {
  await router.dispatch(req, res);
});

server.listen(process.env.PORT || 3000);
```

### Views (ERB filter)

**Browser target:**
```ruby
# Ruby ERB
<%= link_to article.title, article_path(article) %>
```
```javascript
// Generated (browser)
`<a data-turbo="true" href="/articles/${article.id}"
    onClick="event.preventDefault(); navigate('/articles/${article.id}')">${article.title}</a>`
```

**Node.js target:**
```javascript
// Generated (node)
`<a href="/articles/${article.id}">${article.title}</a>`
```

### Controllers

**Browser target:**
```javascript
// redirect_to becomes pushState
redirect_to(article_path(this.article));
// → history.pushState({}, '', `/articles/${this.article.id}`); router.dispatch();

// render updates DOM
this.render('articles/show');
// → document.getElementById('main').innerHTML = await this.view();
```

**Node.js target:**
```javascript
// redirect_to sends HTTP redirect
redirect_to(article_path(this.article));
// → res.writeHead(302, { Location: `/articles/${this.article.id}` }); res.end();

// render sends HTTP response
this.render('articles/show');
// → res.writeHead(200, { 'Content-Type': 'text/html' }); res.end(await this.view());
```

### Active Record

See [DEXIE_SUPPORT.md](./DEXIE_SUPPORT.md) for database adapter details. The database adapter determines the target environment — see the Configuration section above for the full mapping.

## Architecture

### File Structure

```
demo/ruby2js-on-rails/
├── app/                          # Ruby source (unchanged)
│   ├── models/
│   ├── controllers/
│   └── views/
├── config/
│   ├── routes.rb
│   └── database.yml
├── lib/
│   ├── adapters/                 # Database adapters
│   │   ├── active_record_dexie.mjs
│   │   ├── active_record_sqljs.mjs
│   │   ├── active_record_pg.mjs
│   │   └── active_record_better_sqlite3.mjs
│   ├── targets/                  # Target-specific runtime
│   │   ├── browser/
│   │   │   ├── router.mjs
│   │   │   ├── application_controller.mjs
│   │   │   └── boot.mjs
│   │   └── node/
│   │       ├── router.mjs
│   │       ├── application_controller.mjs
│   │       └── server.mjs
│   └── shared/                   # Shared across targets
│       └── application_record.mjs  # Base class (minimal)
├── build/
│   └── build-selfhost.mjs
└── dist/                         # Generated output
    ├── active_record.mjs         # Copied from adapters/
    ├── router.mjs                # Copied from targets/
    ├── application_controller.mjs
    ├── models/
    ├── controllers/
    └── views/
```

### Filter Integration

Filters receive database option (from config/database.yml) and derive target:

```ruby
# Ruby2JS.convert options (database read from config/database.yml)
Ruby2JS.convert(source, {
  filters: [:rails_routes, :rails_controller, :erb],
  database: 'dexie',      # from database.yml[env].adapter
  dbConfig: { ... }       # from database.yml[env]
})
```

Each filter derives target from database to generate appropriate code:

```ruby
# lib/ruby2js/filter/rails/routes.rb
BROWSER_DATABASES = %w[dexie sqljs]

def on_send(node)
  target = BROWSER_DATABASES.include?(@options[:database]) ? 'browser' : 'node'
  if target == 'node'
    generate_http_server(node)
  else
    generate_history_api(node)
  end
end
```

## Implementation Phases

### Phase 1: Database Adapters ✅ COMPLETE

See [DEXIE_SUPPORT.md](./DEXIE_SUPPORT.md).

**Completed:**
1. ✅ Extract sql.js to `lib/adapters/active_record_sqljs.mjs`
2. ✅ Build process copies selected adapter to `dist/lib/active_record.mjs`
3. ✅ Generate `ApplicationRecord` wrapper at build time (deleted `app/models/application_record.rb`)
4. ✅ Add validation helpers to adapter (validates_presence_of, validates_length_of)
5. ✅ Make all controller actions async with await for database operations
6. ✅ Make seeds filter async with await for Article.all, Article.create, etc.
7. ✅ Add association preloading for show/edit actions (article.comments = await...)
8. ✅ Fix circular dependency by extracting path helpers to `config/paths.js`
9. ✅ Add `:await` to GROUP_OPERATORS for proper parenthesization
10. ✅ Make routes dispatch handlers async
11. ✅ Handle `:asyncs` nodes in IIFE module converter

12. ✅ Create `lib/adapters/active_record_dexie.mjs` (IndexedDB alternative ~50KB vs sql.js ~2.7MB)
13. ✅ Add DATABASE environment variable selection in build scripts
14. ✅ Test with Dexie adapter

**Phase 1 Complete!** Both sql.js and Dexie adapters work with identical ActiveRecord API.

### Phase 2: Target Infrastructure ✅ COMPLETE

1. ✅ Create `lib/targets/browser/` and `lib/targets/node/` directories
2. ✅ Extract browser-specific router to `lib/targets/browser/rails.js`
3. ✅ Create Node.js router with http.createServer in `lib/targets/node/rails.js`
4. ✅ Build process derives target from DATABASE and copies appropriate files
5. ✅ Update build script to use derived target (browser for dexie/sqljs, node otherwise)

**Phase 2 Complete!** Target-specific runtime files are copied based on database adapter.

### Phase 3: Filter Updates ✅ COMPLETE

1. ✅ `rails/routes` filter - Already target-agnostic
   - Imports from `../lib/rails.js` which is target-specific (copied at build time)
   - No filter changes needed - runtime handles differences

2. ✅ `rails/controller` filter - Already target-agnostic
   - Returns `{ redirect: path }` objects
   - Runtime handles redirects differently per target
   - No filter changes needed

3. ✅ `erb` filter updated with `database` option support
   - Added `BROWSER_DATABASES` constant
   - Added `browser_target?` helper method
   - `build_nav_link`: Browser generates onclick handlers, Node generates plain hrefs
   - `build_delete_link`: Browser uses JS confirm, Node uses form-based delete
   - `build.rb` updated to pass database option to ERB filter

**Phase 3 Complete!** ERB filter generates target-appropriate HTML based on database option.

### Phase 4: Node.js Adapters ✅ COMPLETE

1. ✅ Create `lib/adapters/active_record_better_sqlite3.mjs`
   - Synchronous SQLite via better-sqlite3 package
   - WAL mode enabled for better concurrency
   - Uses `globalThis.Time` instead of `window.Time`

2. ✅ Create `lib/adapters/active_record_pg.mjs`
   - PostgreSQL via node-postgres (pg) package
   - Connection pooling with configurable pool size
   - Supports `DATABASE_URL` environment variable (12-factor apps)
   - Parameterized queries with `$1, $2, ...` placeholders

3. ⏸️ `active_record_mysql2.mjs` (deferred - same pattern as pg)

4. ✅ Update `build.rb` ADAPTER_FILES mapping:
   - `better_sqlite3`, `sqlite3` → `active_record_better_sqlite3.mjs`
   - `pg`, `postgres`, `postgresql` → `active_record_pg.mjs`

**Note:** Real database testing deferred to Phase 5 integration. Adapters follow same API pattern as browser adapters.

### Phase 5: Integration & Polish ✅ COMPLETE

1. ✅ Server entry point: `server.mjs` for Node.js target
2. ✅ npm scripts for all targets:
   - `dev` / `dev:node` - Development with hot reload
   - `build` / `build:node` / `build:pg` - Build for different targets
   - `start` / `start:node` - Run production builds
3. ✅ Optional dependencies: `better-sqlite3`, `pg` in package.json
4. ✅ README updated with:
   - Multi-target quick start
   - Target platform comparison table
   - Updated command reference
   - Updated project structure

**All phases complete!** The same Ruby source can now be transpiled to browser SPA or Node.js server.

## Usage Examples

### Browser SPA (Default)

```bash
npm run dev
# → NODE_ENV=development → database.yml[development].adapter=dexie → browser
# → Serves SPA at localhost:3000
# → Client-side routing, IndexedDB storage
```

### Node.js Development

```bash
# With database.yml configured for better_sqlite3 in development:
npm run dev
# → Runs HTTP server at localhost:3000
# → Traditional request/response, SQLite file storage
```

### Node.js Production

```bash
RAILS_ENV=production npm run build
# → database.yml[production].adapter=pg → node target
# → Generates server.mjs with PostgreSQL adapter
# → Deploy to any Node.js host
```

### Docker Deployment

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY . .
RUN npm install
RUN RAILS_ENV=production npm run build
CMD ["node", "dist/server.mjs"]
```

At runtime, the platform provides `DATABASE_URL`:

```bash
# Heroku, Railway, Render, etc.
docker run -e DATABASE_URL=postgres://... myapp

# Or docker-compose
services:
  web:
    environment:
      - DATABASE_URL=postgres://user:pass@db:5432/myapp
```

## Success Criteria

1. Same Ruby source deploys to browser and Node.js
2. Database adapter read from `config/database.yml` (target derived automatically)
3. No target-switching code in generated output
4. Browser bundle excludes all Node.js code
5. Node.js bundle excludes browser-specific code
6. Both targets pass identical functional tests

## Timeline

- **Phase 1:** Database adapters (~2 days) — see DEXIE_SUPPORT.md
- **Phase 2:** Target infrastructure (~1 day)
- **Phase 3:** Filter updates (~2 days)
- **Phase 4:** Node.js adapters (~1 day)
- **Phase 5:** Integration & polish (~1 day)

**Total: ~7 days**

## Future Possibilities

### Hybrid/SSR Target

Server-side rendering with client-side hydration:
- Initial render on Node.js (SEO, performance)
- Client takes over after load
- Shared view templates

### Edge Runtime Target

Cloudflare Workers, Deno Deploy, Vercel Edge:
- Minimal runtime (~50KB budget)
- D1 or Turso for SQLite-compatible edge database
- Different routing model (fetch handler)

### React Native Target

Mobile apps:
- AsyncStorage instead of IndexedDB
- React Native navigation
- Same models and business logic
