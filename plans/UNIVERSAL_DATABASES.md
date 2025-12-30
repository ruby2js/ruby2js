# Universal Databases Plan

Extend the database adapter system to support HTTP-based "universal" databases that work across browser, Node.js, and edge runtimes, and rethink the target taxonomy to better reflect deployment realities.

## Context

The current architecture (see [MULTI_TARGET_ARCHITECTURE.md](./MULTI_TARGET_ARCHITECTURE.md) and [DEXIE_SUPPORT.md](./DEXIE_SUPPORT.md)) categorizes databases as either browser or server:

```ruby
# Current taxonomy in lib/ruby2js/rails/builder.rb
BROWSER_DATABASES = ['dexie', 'indexeddb', 'sqljs', 'sql.js', 'pglite'].freeze
SERVER_RUNTIMES = ['node', 'bun', 'deno', 'cloudflare'].freeze
```

This binary split doesn't account for a new class of databases that use HTTP/WebSocket protocols and work everywhere JavaScript runs.

## The Problem

### Current Limitations

1. **pglite is forced to browser** — Even though PGLite supports Node.js with file-based storage, the builder rejects `RUNTIME=node` for pglite.

2. **No support for edge databases** — Services like Neon, Turso, and PlanetScale use HTTP drivers that work across all environments, but there's no place for them in the current taxonomy.

3. **"Edge" is imprecise** — Lumping Cloudflare Workers with Vercel Edge or Deno Deploy ignores significant differences in their application models and platform capabilities.

4. **D1 advantages vs tradeoffs** — Cloudflare D1 offers integrated edge storage, but:
   - Writes go to a single primary region (latency for distant users)
   - Read replicas at edge help read-heavy workloads
   - Alternative databases might offer different tradeoffs

### Database Transport Types

| Transport | Databases | Environments |
|-----------|-----------|--------------|
| **Embedded** | sqljs, pglite (WASM), dexie (IndexedDB) | Browser |
| **Native bindings** | better-sqlite3, pg, mysql2 | Node.js, Bun, Deno |
| **Platform binding** | d1 | Cloudflare Workers only |
| **HTTP/WebSocket** | neon, turso, planetscale, supabase | Universal |

The HTTP-based databases are the key insight — they use `fetch` or `WebSocket`, which are available in browsers, Node.js 18+, Deno, Bun, and all edge runtimes.

## Proposed Taxonomy

### Three-Category Database Classification

```ruby
# Proposed taxonomy
BROWSER_ONLY_DATABASES = ['dexie', 'sqljs'].freeze
SERVER_ONLY_DATABASES = ['pg', 'mysql2', 'better_sqlite3'].freeze
UNIVERSAL_DATABASES = ['neon', 'turso', 'planetscale', 'pglite'].freeze
PLATFORM_DATABASES = { 'd1' => 'cloudflare' }.freeze
```

### Target Environments

Instead of binary browser/server, recognize distinct targets:

| Target | Application Model | Navigation | Key APIs |
|--------|-------------------|------------|----------|
| `browser` | SPA, client-side routing | History API, user-driven | DOM, IndexedDB |
| `node` | Server process | Express/router dispatch | fs, net, TCP |
| `bun` | Server process | Bun.serve | Bun APIs + Node compat |
| `deno` | Server process | Deno.serve | Deno APIs, fetch |
| `cloudflare` | Request/response handler | Worker fetch handler | D1, KV, Durable Objects |

### Database → Default Target Mapping

| Adapter | Default Target | Rationale |
|---------|----------------|-----------|
| `dexie` | browser | Browser-only (IndexedDB) |
| `sqljs` | browser | Browser-only (WASM SQLite) |
| `pglite` | browser | Primary value = PostgreSQL in browser |
| `better_sqlite3` | node | Native Node.js bindings |
| `pg` | node | TCP connections |
| `mysql2` | node | TCP connections |
| `d1` | cloudflare | Platform-specific binding |
| `neon` | node | Serverless Postgres, common with Vercel/Node |
| `turso` | cloudflare | Edge SQLite, D1 alternative |
| `planetscale` | node | Serverless MySQL, common with Vercel/Node |

### Configuration

Extend `config/database.yml` to allow explicit target override:

```yaml
development:
  adapter: pglite
  # target: browser (implied, default for pglite)

production:
  adapter: turso
  target: cloudflare  # explicit, could also be node/deno/bun
  url: <%= ENV['TURSO_DATABASE_URL'] %>
  auth_token: <%= ENV['TURSO_AUTH_TOKEN'] %>

# Override for embedded replica use case
local:
  adapter: turso
  target: node  # Use embedded replica mode
  sync_url: <%= ENV['TURSO_DATABASE_URL'] %>
```

## Dependencies

Each adapter requires its corresponding npm package as a peer dependency:

| Adapter | npm Package |
|---------|-------------|
| neon | `@neondatabase/serverless` |
| turso | `@libsql/client` |
| planetscale | `@planetscale/database` |

This mirrors how Rails handles database gems:

| Rails | Ruby2JS on Rails |
|-------|------------------|
| Default: `sqlite3` gem | Default: `dexie` or `better-sqlite3` |
| Want Postgres? `gem 'pg'` + update `database.yml` | Want Neon? `npm install @neondatabase/serverless` + update `database.yml` |

Familiar workflow for Rails developers. Explicit dependencies, no bundled drivers.

## Universal Database Adapters

### Turso (libSQL)

SQLite-compatible, closest to D1. HTTP-based with optional embedded replicas.

**Driver:** `@libsql/client`

**Why choose Turso over D1:**
- Works on any edge platform (Vercel, Deno Deploy, etc.)
- Embedded replicas for Node.js (local SQLite that syncs)
- Not locked to Cloudflare

**Adapter implementation (~130 lines):**

```javascript
// adapters/active_record_turso.mjs
import { createClient } from '@libsql/client';
import { ActiveRecordBase, attr_accessor, initTimePolyfill } from './active_record_base.mjs';

export { attr_accessor };

const DB_CONFIG = {};
let client = null;

export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };

  client = createClient({
    url: config.url || process.env.TURSO_DATABASE_URL,
    authToken: config.auth_token || process.env.TURSO_AUTH_TOKEN,
    // For embedded replicas (Node.js only)
    syncUrl: config.sync_url,
  });

  initTimePolyfill(globalThis);
  console.log('Connected to Turso');
  return client;
}

export async function execSQL(sql) {
  return await client.execute(sql);
}

// ... rest follows D1 pattern (SQLite dialect, ? placeholders)
```

### Neon (Serverless Postgres)

PostgreSQL-compatible, serverless. WebSocket/HTTP driver.

**Driver:** `@neondatabase/serverless`

**Why choose Neon:**
- Full PostgreSQL features (JSONB, arrays, CTEs, etc.)
- Serverless scaling (scales to zero)
- Branching for development/preview

**Adapter implementation:**

```javascript
// adapters/active_record_neon.mjs
import { neon } from '@neondatabase/serverless';
import { ActiveRecordBase, attr_accessor, initTimePolyfill } from './active_record_base.mjs';

export { attr_accessor };

const DB_CONFIG = {};
let sql = null;

export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };
  const connectionString = config.url || process.env.DATABASE_URL;

  sql = neon(connectionString);

  initTimePolyfill(globalThis);
  console.log('Connected to Neon');
  return sql;
}

// ... follows pg adapter pattern ($1, $2 placeholders, PostgreSQL dialect)
```

### PlanetScale (Serverless MySQL)

MySQL-compatible, serverless. HTTP driver.

**Driver:** `@planetscale/database`

**Why choose PlanetScale:**
- MySQL compatibility
- Serverless scaling
- Vitess-based (horizontal scaling)

**Adapter implementation:**

```javascript
// adapters/active_record_planetscale.mjs
import { connect } from '@planetscale/database';
import { ActiveRecordBase, attr_accessor, initTimePolyfill } from './active_record_base.mjs';

export { attr_accessor };

const DB_CONFIG = {};
let connection = null;

export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };

  connection = connect({
    url: config.url || process.env.DATABASE_URL,
  });

  initTimePolyfill(globalThis);
  console.log('Connected to PlanetScale');
  return connection;
}

// ... follows mysql2 pattern (? placeholders, MySQL dialect)
```

## Developer Experience

### Opinionated Defaults

When a developer selects an adapter, the target is chosen automatically based on the most common use case:

```bash
# Just specify the database, target is inferred
DATABASE=turso npm run build
# → target: cloudflare (Turso's primary use case is edge)

DATABASE=neon npm run build
# → target: node (Neon commonly used with serverless functions)

DATABASE=d1 npm run build
# → target: cloudflare (D1 only works on Cloudflare)
```

### Explicit Override

When the default doesn't match the use case:

```yaml
# config/database.yml
production:
  adapter: turso
  target: node  # Override: using embedded replica mode
```

Or via environment variable:

```bash
DATABASE=turso TARGET=node npm run build
```

### Validation

The builder validates that the adapter/target combination is valid:

```ruby
VALID_TARGETS = {
  'dexie' => ['browser'],
  'sqljs' => ['browser'],
  'pglite' => ['browser', 'node'],  # pglite supports both
  'better_sqlite3' => ['node', 'bun'],
  'pg' => ['node', 'bun', 'deno'],
  'mysql2' => ['node', 'bun'],
  'd1' => ['cloudflare'],
  'neon' => ['browser', 'node', 'bun', 'deno', 'cloudflare'],
  'turso' => ['browser', 'node', 'bun', 'deno', 'cloudflare'],
  'planetscale' => ['browser', 'node', 'bun', 'deno', 'cloudflare'],
}.freeze

def validate_target!
  valid = VALID_TARGETS[@database] || []
  unless valid.include?(@target)
    raise "Database '#{@database}' does not support target '#{@target}'.\n" \
          "Valid targets for #{@database}: #{valid.join(', ')}"
  end
end
```

### Error Messages

Clear, actionable error messages:

```
Error: Database 'd1' does not support target 'node'.
Valid targets for d1: cloudflare

Hint: D1 is Cloudflare's edge database and requires the Cloudflare Workers runtime.
For Node.js, consider: better_sqlite3 (SQLite), pg (PostgreSQL), or turso (edge-compatible SQLite).
```

## Implementation Phases

### Phase 1: Refactor Taxonomy

1. Update `lib/ruby2js/rails/builder.rb`:
   - Replace `BROWSER_DATABASES` with three-category system
   - Add `VALID_TARGETS` matrix
   - Add `DEFAULT_TARGET` mapping
   - Support `target:` in database.yml
   - Add validation with helpful error messages

2. Update `detect_runtime` to use new taxonomy

### Phase 2: Fix pglite for Node.js

1. Update pglite adapter to detect environment:
   ```javascript
   if (typeof window !== 'undefined' && window.indexedDB) {
     dataDir = `idb://${config.database}`;  // Browser
   } else {
     dataDir = `./${config.database}`;       // Node.js file-based
   }
   ```

2. Add 'pglite' to valid Node.js targets

### Phase 3: Add Universal Adapters

1. Create `adapters/active_record_turso.mjs`
   - SQLite dialect (like D1)
   - HTTP client via `@libsql/client`
   - Support for embedded replicas

2. Create `adapters/active_record_neon.mjs`
   - PostgreSQL dialect (like pg)
   - WebSocket/HTTP via `@neondatabase/serverless`

3. Create `adapters/active_record_planetscale.mjs`
   - MySQL dialect (like mysql2)
   - HTTP via `@planetscale/database`

### Phase 4: Cloudflare Target Refinement

1. Create `lib/targets/cloudflare/rails.js`
   - Fetch handler pattern (not http.createServer)
   - Request/Response API
   - Integration with D1 binding

2. Ensure universal adapters work with cloudflare target

### Phase 5: Documentation

1. Update database selection guide
2. Document target/adapter compatibility matrix
3. Add examples for each universal database
4. Explain when to choose each option

## Vercel Target

Universal HTTP-based databases enable Vercel as a deployment target. See [VERCEL_TARGET.md](./VERCEL_TARGET.md) for the full implementation plan.

**Key points:**
- `rails_server.js` already uses Fetch API, which Vercel expects
- Vercel requires HTTP-based databases (no TCP in Edge Functions)
- Two target variants: `vercel-edge` (fast) and `vercel-node` (more DB options)

### Target Selection (Updated)

| Target | Runtime | Entry Pattern | Use Case |
|--------|---------|---------------|----------|
| `browser` | Browser | SPA, client routing | Standalone browser apps |
| `node` | Node.js | `http.createServer` | Traditional servers |
| `bun` | Bun | `Bun.serve` | Bun servers |
| `deno` | Deno | `Deno.serve` | Deno servers |
| `cloudflare` | Workers | `export default { fetch }` | Cloudflare deployment |
| `vercel-edge` | V8 | `export default function` | Vercel Edge Functions |
| `vercel-node` | Node.js | `export default function` | Vercel Serverless |

## Open Questions

### Supabase

Supabase offers:
- PostgreSQL database (could use neon adapter pattern)
- Edge Functions (Deno-based)
- Client library with auth/realtime

**Question:** Is Supabase different enough to warrant its own adapter, or is it just "Postgres accessed via Neon-style driver"?

### Default for Universal Databases

Current thinking:
- `turso` → cloudflare (edge SQLite is primary use case)
- `neon` → node (serverless Postgres with functions is common)
- `planetscale` → node (same reasoning)

**Alternative:** Universal databases default to `node` since it's the broadest compatible target, and users override for edge.

## Success Criteria

1. pglite works on both browser and Node.js
2. Turso adapter works across browser, Node.js, and Cloudflare
3. Neon adapter works across browser, Node.js, and Cloudflare
4. Clear error messages when adapter/target mismatch
5. `config/database.yml` supports explicit `target:` field
6. Documentation explains all options and tradeoffs
7. Same Ruby source deploys to browser, Node.js, or Cloudflare by changing database.yml

## Compatibility Matrix (Goal State)

| Adapter | browser | node | bun | deno | cloudflare | vercel-edge | vercel-node |
|---------|:-------:|:----:|:---:|:----:|:----------:|:-----------:|:-----------:|
| dexie | ✓ | | | | | | |
| sqljs | ✓ | | | | | | |
| pglite | ✓ | ✓ | ✓ | | | | ✓ |
| better_sqlite3 | | ✓ | ✓ | | | | ✓ |
| pg | | ✓ | ✓ | ✓ | | | ✓ |
| mysql2 | | ✓ | ✓ | | | | ✓ |
| d1 | | | | | ✓ | | |
| neon | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| turso | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| planetscale | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

Notes:
- Browser usage of neon/turso/planetscale exposes credentials (demos/prototypes only)
- vercel-edge requires HTTP-based databases (no TCP)
- vercel-node can use TCP databases but HTTP-based are preferred for cold start performance
