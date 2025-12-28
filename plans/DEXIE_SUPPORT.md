# Dexie.js Support Plan

Add Dexie.js as an alternative ActiveRecord backend alongside sql.js, demonstrating that the architecture supports multiple storage adapters.

> **Note:** This plan is part of the broader [Multi-Target Architecture](./MULTI_TARGET_ARCHITECTURE.md) which extends the same transpilation-time selection pattern to support different runtime targets (browser vs Node.js) beyond just database adapters.

## Goals

1. **Support both sql.js and Dexie.js** — User chooses via configuration
2. **Rails-like configuration** — Use `config/database.yml` pattern
3. **Demonstrate extensibility** — Clear path to adding more backends (e.g., PostgreSQL via Node.js driver)
4. **Improve first impressions** — Dexie.js (~50KB) vs sql.js (~2.7MB WASM)
5. **Zero runtime overhead** — Adapter selection at transpilation time, not runtime

## Key Insight: Transpilation-Time Selection

Instead of runtime adapter switching with abstract interfaces, the database adapter is selected at **build time**:

```
Build Time (Node.js)                 Runtime (Browser)
────────────────────                 ─────────────────
config/database.yml                  No YAML parser
        ↓                            No config loading
   js-yaml parses                    No adapter switching
        ↓                            No abstract interface
 adapter: dexie                              ↓
 database: my_app_dev                Just the chosen
        ↓                            active_record.mjs
 Copy active_record_dexie.mjs            running
 Inject database name/options
 to dist/active_record.mjs
```

**Benefits:**
- No runtime adapter abstraction layer
- No YAML parser in browser bundle
- No dynamic adapter loading
- No config file fetching at startup
- Each implementation is simple and direct
- Better tree-shaking and dead code elimination

## Configuration

### config/database.yml

```yaml
development:
  adapter: dexie
  database: ruby2js_rails_dev

production:
  adapter: dexie
  database: ruby2js_rails

# Alternative: sql.js for full SQL support
# development:
#   adapter: sql_js
#   database: ruby2js_rails_dev
```

The YAML file can include any adapter-specific options:

```yaml
development:
  adapter: dexie
  database: my_app_dev
  # Dexie-specific options
  auto_open: true

production:
  adapter: pg
  host: localhost
  port: 5432
  database: my_app_production
  username: <%= ENV['DB_USER'] %>
  password: <%= ENV['DB_PASS'] %>
```

### Environment Variable Override

The adapter can be overridden via environment variables:

```bash
# Simple adapter selection
DATABASE=dexie npm run build
DATABASE=sqljs npm run dev

# Full connection URL (standard 12-factor pattern)
DATABASE_URL=postgres://user:pass@localhost:5432/myapp npm run build
DATABASE_URL=mysql2://user:pass@localhost:3306/myapp npm run build
DATABASE_URL=sqlite3:///db/production.sqlite3 npm run build
```

`DATABASE_URL` takes precedence and is parsed to extract adapter, credentials, host, port, and database name:

```javascript
// build-selfhost.mjs
function parseDatabaseUrl(url) {
  const parsed = new URL(url);
  return {
    adapter: parsed.protocol.replace(':', '').replace('postgres', 'pg'),
    host: parsed.hostname,
    port: parsed.port,
    database: parsed.pathname.slice(1),
    username: parsed.username,
    password: parsed.password,
    ...Object.fromEntries(parsed.searchParams)
  };
}

const dbConfig = process.env.DATABASE_URL
  ? parseDatabaseUrl(process.env.DATABASE_URL)
  : { adapter: process.env.DATABASE, ...yamlConfig };
```

**Build time vs runtime:**

For Node.js adapters, connection details can also be read at **runtime**:

```javascript
// In active_record_pg.mjs (generated)
const dbConfig = process.env.DATABASE_URL
  ? parseDatabaseUrl(process.env.DATABASE_URL)
  : DB_CONFIG;  // Fallback to build-time injected config
```

This separation means:
- **Adapter selection** (which implementation to copy) — build time
- **Connection details** (host, password, etc.) — can be runtime

This is 12-factor friendly: build once, deploy anywhere with `DATABASE_URL` provided by the platform.

### YAML Parser

`js-yaml` is installed as a **dev dependency** only:

```bash
npm install --save-dev js-yaml
```

It's used by:
- `dev-server.mjs` when starting the dev server
- `build-selfhost.mjs` when building for production

Never imported by any code that runs in the browser.

## Architecture

### Multiple Active Record Implementations

Instead of an abstract adapter interface, maintain separate complete implementations:

```
demo/ruby2js-on-rails/
├── lib/
│   └── adapters/
│       ├── active_record_dexie.mjs      # Complete Dexie.js implementation
│       ├── active_record_sqljs.mjs      # Complete sql.js implementation
│       └── active_record_better_sqlite3.mjs  # Node.js native SQLite
└── dist/
    └── active_record.mjs                # Copied from adapters/ at build time
```

Each implementation is self-contained (~200-300 lines) with no shared abstract base class.

### Build Process

```javascript
// build-selfhost.mjs (simplified)
import yaml from 'js-yaml';
import fs from 'fs';

// Read config
const configText = fs.readFileSync('config/database.yml', 'utf8');
const config = yaml.load(configText);
const env = process.env.NODE_ENV || 'development';
const dbConfig = config[env];

// Copy appropriate implementation
const adapterFile = `lib/adapters/active_record_${dbConfig.adapter}.mjs`;
let adapterCode = fs.readFileSync(adapterFile, 'utf8');

// Inject configuration
adapterCode = adapterCode.replace(
  'const DB_CONFIG = {};',
  `const DB_CONFIG = ${JSON.stringify(dbConfig)};`
);

fs.writeFileSync('dist/active_record.mjs', adapterCode);
```

### dev-server.mjs Integration

```javascript
// dev-server.mjs
import yaml from 'js-yaml';

// Query environment, read config
const config = yaml.load(fs.readFileSync('config/database.yml', 'utf8'));
const dbConfig = config[process.env.NODE_ENV || 'development'];

// Pass to build
await buildSelfhost({
  database: dbConfig  // { adapter: 'dexie', database: 'my_app_dev', ... }
});
```

### Schema Filter Integration

The `rails/schema` filter receives the target adapter as a convert option:

```ruby
# Ruby2JS.convert options
Ruby2JS.convert(source, {
  database: { adapter: 'dexie', database: 'my_app' }
})
```

The filter generates adapter-appropriate schema:

**For sql.js:**
```javascript
DB.exec(`
  CREATE TABLE IF NOT EXISTS articles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT,
    body TEXT,
    created_at TEXT,
    updated_at TEXT
  )
`);
```

**For Dexie.js:**
```javascript
const db = new Dexie('my_app');
db.version(1).stores({
  articles: '++id, title, created_at, updated_at',
  comments: '++id, article_id, created_at, updated_at'
});
```

## Implementation Steps

### Phase 1: Extract Current sql.js Implementation

1. Move current `active_record.mjs` to `lib/adapters/active_record_sqljs.mjs`
2. Add config injection point: `const DB_CONFIG = {};`
3. Update to use `DB_CONFIG.database` for database name
4. Verify existing functionality still works

**Files changed:**
- New: `lib/adapters/active_record_sqljs.mjs`
- Modified: `build-selfhost.mjs` (copy logic)

### Phase 2: Create Dexie.js Implementation

1. Create `lib/adapters/active_record_dexie.mjs`
2. Implement same public API as sql.js version
3. Use Dexie.js for all database operations

**Dexie.js method mapping:**

| ActiveRecord Method         | Dexie.js Implementation                 |
| --------------------------- | --------------------------------------- |
| `Model.all()`               | `db[table].toArray()`                   |
| `Model.find(id)`            | `db[table].get(id)`                     |
| `Model.find_by(conditions)` | `db[table].where(conditions).first()`   |
| `Model.where(conditions)`   | `db[table].where(conditions).toArray()` |
| `Model.count()`             | `db[table].count()`                     |
| `Model.first`               | `db[table].orderBy('id').first()`       |
| `Model.last`                | `db[table].orderBy('id').last()`        |
| `record.save()`             | `db[table].put(attrs)`                  |
| `record.destroy()`          | `db[table].delete(id)`                  |

### Phase 3: Build Process Updates

1. Add `js-yaml` as dev dependency
2. Update `build-selfhost.mjs` to:
   - Read `config/database.yml`
   - Copy appropriate adapter implementation
   - Inject database configuration
3. Update `dev-server.mjs` to pass config to build

### Phase 4: Schema Filter Updates

1. Add `database` option to convert
2. Update `rails/schema` filter to check adapter type
3. Generate appropriate schema format per adapter

### Phase 5: Testing & Validation

1. Run full demo with sql.js adapter — verify no regressions
2. Run full demo with Dexie.js adapter — verify all features work
3. Test switching between adapters via config change + rebuild
4. Compare bundle sizes and load times
5. Update documentation

## File Structure After Implementation

```
demo/ruby2js-on-rails/
├── config/
│   └── database.yml              # Adapter configuration (read at build time)
├── lib/
│   └── adapters/
│       ├── active_record_dexie.mjs
│       ├── active_record_sqljs.mjs
│       └── active_record_better_sqlite3.mjs  # Future: Node.js
├── dist/
│   └── active_record.mjs         # Copied from adapters/ with config injected
├── build/
│   └── build-selfhost.mjs        # Reads YAML, copies adapter
└── package.json                  # js-yaml as devDependency, dexie as dependency
```

## Bundle Size Comparison

| Backend  | Runtime Size | Notes           |
| -------- | ------------ | --------------- |
| sql.js   | ~2.7MB       | WASM binary     |
| Dexie.js | ~50KB        | Pure JavaScript |

**With Dexie.js:** ~50KB (no YAML parser in bundle!)
**With sql.js:** ~2.7MB

**Improvement:** 98% smaller bundle with Dexie.js backend

Note: `js-yaml` (~50KB) is only used at build time, never shipped to browser.

## Backend Matrix

This architecture enables environment-appropriate adapters:

**Browser:**
| Adapter    | Use Case                           | Size   |
| ---------- | ---------------------------------- | ------ |
| **dexie**  | Default for browser apps           | ~50KB  |
| **sql_js** | Full SQL needed in browser (niche) | ~2.7MB |

**Node.js:**
| Adapter            | Use Case                     | Notes                       |
| ------------------ | ---------------------------- | --------------------------- |
| **better_sqlite3** | Development, simple apps     | Native bindings, sync, fast |
| **sqlite3**        | Development, async preferred | Native bindings, async      |
| **pg**             | Production PostgreSQL        | Real database               |
| **mysql2**         | Production MySQL             | Real database               |

**The insight:** sql.js (WASM) is only needed for the niche case of "full SQL in browser." Most browser apps use Dexie.js. Node.js apps use native SQLite or production databases — no WASM overhead.

**Typical configurations:**

```yaml
# Browser app (default)
development:
  adapter: dexie
  database: my_app_dev
production:
  adapter: dexie
  database: my_app

# Node.js app
development:
  adapter: better_sqlite3
  database: db/development.sqlite3
production:
  adapter: pg
  host: localhost
  database: myapp_production
  username: deploy
  password: secret

# Browser app needing full SQL (rare)
development:
  adapter: sql_js
  database: my_app_dev
```

## Success Criteria

1. Demo works identically with either adapter
2. Switching adapters requires only `config/database.yml` change + rebuild
3. Bundle size with Dexie.js is under 100KB (excluding app code)
4. No YAML parser or adapter switching code in browser bundle
5. All existing tests pass with both adapters
6. Documentation explains both options and tradeoffs

## Timeline

- **Phase 1-2:** Extract sql.js, create Dexie.js implementation (~1 day)
- **Phase 3-4:** Build process + schema filter updates (~0.5 day)
- **Phase 5:** Testing, validation, documentation (~0.5 day)

**Total: ~2 days**
