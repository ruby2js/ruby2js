# Plan: ActiveRecord to Drizzle Transpilation

## Summary

Replace the current runtime adapter approach with build-time transpilation of ActiveRecord queries to Drizzle ORM syntax. For `juntos eject`, models transpile to framework-specific reactive stores (Alpine.store, Pinia, Zustand) that use Drizzle for persistence. A Drizzle-compatible IndexedDB helper provides browser-only support.

## Motivation

The current approach uses runtime adapters that implement ActiveRecord-like methods (`find`, `where`, `save`, etc.) for each database target. Analysis of the Dexie adapter revealed we're barely using Dexie's features - just basic CRUD while doing sorting, filtering, and associations ourselves.

**Current architecture:**
- Ruby models transpile to JS with ActiveRecord method calls
- Runtime adapters implement those methods for each database
- N adapters to maintain (Dexie, SQLite, Turso, D1, etc.)

**Proposed architecture:**
- Ruby models transpile to Drizzle query syntax for persistence
- Framework stores provide local reactivity (Alpine.store, Pinia, etc.)
- Broadcasts remain orthogonal - sync across tabs/clients/users
- Drizzle handles all SQL databases (one target, many drivers)
- Small IndexedDB helper implements Drizzle's API for browser offline

## Design

### Three Concerns, Separately Addressed

ActiveRecord in Rails conflates three concerns that should be addressed separately:

| Concern | Rails | Ejected App |
|---------|-------|-------------|
| **Persistence** | ActiveRecord + database | Drizzle + database |
| **Local Reactivity** | Turbo (DOM replacement) | Framework store (Alpine.store, Pinia, Zustand) |
| **Broadcast/Sync** | Turbo Streams over WebSocket | BroadcastChannel (tabs) / WebSocket (users) |

```
┌─────────────────────────────────────────────────────────────────┐
│  Browser Tab A                    Browser Tab B / Other User    │
│                                                                 │
│  ┌─────────────────────┐         ┌─────────────────────┐       │
│  │ Framework Store     │         │ Framework Store     │       │
│  │ (local reactivity)  │         │ (local reactivity)  │       │
│  └──────────┬──────────┘         └──────────▲──────────┘       │
│             │                               │                   │
│             ▼                               │                   │
│  ┌─────────────────────┐                   │                   │
│  │ Drizzle             │───────────────────┘                   │
│  │ (persistence)       │    Broadcast (BroadcastChannel/WS)    │
│  └─────────────────────┘                                       │
└─────────────────────────────────────────────────────────────────┘
```

**Key insight:** `broadcasts_to` stays largely unchanged - it emits to a channel. The *receiver* integrates with the framework store. This plan focuses on persistence (Drizzle); broadcast is orthogonal.

### One Transpilation Pattern, Two Backends

```ruby
Article.where(status: 'published').order(:created_at).limit(10)
```

**Transpiles to (both targets):**
```javascript
db.select().from(articles).where(eq(articles.status, 'published')).orderBy(articles.created_at).limit(10)
```

**Imports differ by target:**
```javascript
// SQL targets (Astro DB, Turso, D1, Postgres, MySQL, SQLite)
import { db } from './db';
import { eq } from 'drizzle-orm';

// Browser/IndexedDB target
import { db } from './db';
import { eq } from 'ruby2js-rails/idb';
```

### Query Mapping

| ActiveRecord | Drizzle Output |
|--------------|----------------|
| `Model.find(id)` | `db.select().from(model).where(eq(model.id, id)).get()` |
| `Model.find_by(name: 'x')` | `db.select().from(model).where(eq(model.name, 'x')).get()` |
| `Model.where(status: 'a')` | `db.select().from(model).where(eq(model.status, 'a'))` |
| `Model.where('age > ?', 21)` | `db.select().from(model).where(gt(model.age, 21))` |
| `Model.order(:created_at)` | `...orderBy(model.created_at)` |
| `Model.order(created_at: :desc)` | `...orderBy(desc(model.created_at))` |
| `Model.limit(10)` | `...limit(10)` |
| `Model.offset(20)` | `...offset(20)` |
| `Model.first` | `...limit(1).get()` |
| `Model.last` | `...orderBy(desc(model.id)).limit(1).get()` |
| `Model.count` | `db.select({ count: count() }).from(model)` |
| `Model.create(attrs)` | `db.insert(model).values(attrs)` |
| `record.save` | `db.insert(model).values(attrs)` or `db.update(model).set(attrs).where(eq(model.id, id))` |
| `record.update(attrs)` | `db.update(model).set(attrs).where(eq(model.id, id))` |
| `record.destroy` | `db.delete(model).where(eq(model.id, id))` |

### Schema Transpilation

```ruby
# db/schema.rb
create_table :articles do |t|
  t.string :title, null: false
  t.text :body
  t.string :status, default: 'draft'
  t.timestamps
end
```

**Drizzle output:**
```javascript
// db/schema.ts
import { sqliteTable, text, integer } from 'drizzle-orm/sqlite-core';

export const articles = sqliteTable('articles', {
  id: integer('id').primaryKey({ autoIncrement: true }),
  title: text('title').notNull(),
  body: text('body'),
  status: text('status').default('draft'),
  created_at: integer('created_at', { mode: 'timestamp' }),
  updated_at: integer('updated_at', { mode: 'timestamp' }),
});
```

### IndexedDB Helper

A small (~2-3KB) library implementing Drizzle's query builder API over IndexedDB:

```javascript
// ruby2js-rails/idb.mjs
export function eq(column, value) { return { type: 'eq', column, value }; }
export function gt(column, value) { return { type: 'gt', column, value }; }
// ... other operators

class IDBQueryBuilder {
  select() { return this; }
  from(table) { this._table = table; return this; }
  where(condition) { this._conditions.push(condition); return this; }
  orderBy(column) { this._order = column; return this; }
  limit(n) { this._limit = n; return this; }

  async then(resolve) {
    // Execute against IndexedDB
    const tx = this._db.transaction([this._table], 'readonly');
    const store = tx.objectStore(this._table);
    let results = await store.getAll();
    results = this._applyConditions(results);
    results = this._applyOrder(results);
    results = this._applyLimit(results);
    resolve(results);
  }
}
```

The helper only implements what the transpiler emits - not full Drizzle compatibility.

### Associations

**has_many:**
```ruby
Article.includes(:comments).where(status: 'published')
```

**Option A - Drizzle relational queries (SQL targets):**
```javascript
db.query.articles.findMany({
  where: eq(articles.status, 'published'),
  with: { comments: true }
});
```

**Option B - Separate queries (IndexedDB or simpler SQL):**
```javascript
const arts = await db.select().from(articles).where(eq(articles.status, 'published'));
const artIds = arts.map(a => a.id);
const cmts = await db.select().from(comments).where(inArray(comments.article_id, artIds));
// Attach comments to articles
```

Design decision: likely Option B for consistency across targets, with Option A as optimization for SQL.

### Framework Store Output (for `juntos eject`)

When ejecting to a specific framework, models become store definitions:

**Ruby source:**
```ruby
class Article < ApplicationRecord
  has_many :comments
  validates :title, presence: true
  broadcasts_to ->(_article) { "articles" }
end
```

**Ejected to Alpine (`--framework alpine`):**
```javascript
import { db, eq } from './db.js';
import { articles } from './schema.js';

Alpine.store('articles', {
  items: [],

  async all() {
    this.items = await db.select().from(articles);
    return this.items;
  },

  async find(id) {
    return await db.select().from(articles).where(eq(articles.id, id)).get();
  },

  async where(conditions) {
    // Build Drizzle query from conditions
    this.items = await db.select().from(articles).where(...);
    return this.items;
  },

  async create(attrs) {
    const record = await db.insert(articles).values(attrs).returning();
    this.items.unshift(record);  // Local reactivity
    BroadcastChannel.broadcast('articles', ...);  // Cross-tab/user sync
    return record;
  },

  // Broadcast receiver - called by subscriber
  handleBroadcast(action, data) {
    if (action === 'append') this.items.unshift(data);
    if (action === 'remove') this.items = this.items.filter(i => i.id !== data.id);
    // Alpine reactivity automatically updates UI
  }
});
```

**Ejected to Vue (`--framework vue`):**
```javascript
import { defineStore } from 'pinia';
import { db, eq } from './db.js';
import { articles } from './schema.js';

export const useArticlesStore = defineStore('articles', {
  state: () => ({ items: [] }),

  actions: {
    async all() {
      this.items = await db.select().from(articles);
      return this.items;
    },
    async create(attrs) {
      const record = await db.insert(articles).values(attrs).returning();
      this.items.unshift(record);
      BroadcastChannel.broadcast('articles', ...);
      return record;
    },
    // ...
  }
});
```

The Drizzle queries are identical across frameworks - only the store wrapper differs.

## Implementation Phases

### Phase 1: Basic CRUD Transpilation
- Create `drizzle` filter in `lib/ruby2js/filter/`
- Handle: `find`, `find_by`, `where`, `create`, `save`, `update`, `destroy`
- Schema transpilation: `db/schema.rb` → Drizzle `defineTable`
- Test against existing blog demo

### Phase 2: Query Chaining
- Handle method chains: `.where().order().limit()`
- AST walking for chained calls
- Operators: `eq`, `ne`, `gt`, `lt`, `gte`, `lte`, `and`, `or`, `inArray`

### Phase 3: IndexedDB Helper
- Implement Drizzle-compatible API subset
- Query execution against IndexedDB
- Transaction handling
- In-memory sort/filter (IndexedDB limitation)

### Phase 4: Associations
- `has_many` / `belongs_to` declarations
- `includes` for eager loading
- Foreign key handling in schema

### Phase 5: Framework Store Output
- Add `--framework` option to model transpilation
- Alpine.store output generator
- Pinia (Vue) output generator
- Zustand (React) output generator (optional)
- Broadcast receiver integration per framework
- Test `juntos eject --framework alpine` produces idiomatic code

### Phase 6: Migration & Cleanup
- Deprecate runtime adapters
- Update demos to use new approach
- Documentation

## Target Coverage

| Target | Backend |
|--------|---------|
| Astro DB | Drizzle (libSQL) |
| Turso | Drizzle (libSQL) |
| Cloudflare D1 | Drizzle (D1) |
| PlanetScale | Drizzle (MySQL) |
| Neon | Drizzle (Postgres) |
| SQLite (Node) | Drizzle (better-sqlite3) |
| Postgres | Drizzle (pg) |
| MySQL | Drizzle (mysql2) |
| Browser/Offline | IndexedDB helper |

One transpilation target (Drizzle syntax) covers all SQL databases. One additional helper covers browser offline.

## Risk Assessment

**Low risk:**
- Transpilation patterns are well understood
- Drizzle API is stable and documented
- IndexedDB is a browser standard
- Incremental implementation path
- Existing demos provide test cases

**Medium risk (schedule, not viability):**
- Association eager loading design needs iteration
- Complex WHERE clauses (OR, nested conditions)
- Migration story for existing apps

**Not risky:**
- Fundamental approach is proven (transpilation works)
- Dependencies are stable
- Scope is bounded (support what we emit)

## Success Criteria

1. Blog demo works with Drizzle transpilation (SQL target)
2. Blog demo works with IndexedDB helper (browser target)
3. Same Ruby model code, different build targets
4. No runtime ActiveRecord adapter needed
5. Bundle size reduced (no Dexie, no adapter layer)
6. Existing integration tests pass
7. `juntos eject --framework alpine` produces idiomatic Alpine code
8. Ejected app has working cross-tab broadcast sync
9. An Alpine developer would recognize the output as "normal Alpine"

## Dependencies

- Drizzle ORM (stable, well-maintained)
- Drizzle Kit (schema tooling)
- No Dexie dependency
- Smaller ruby2js-rails package

## Relationship to Other Plans

This plan works together with `sfc-triple-target.md` to enable `juntos eject`:

| Plan | Converts | Output |
|------|----------|--------|
| `sfc-triple-target.md` | Views, Controllers, Routes | Framework components (Astro, Vue, React, Svelte) |
| This plan | Models | Framework stores + Drizzle persistence |

Both share the `--framework` option concept:
- SFC plan: `--framework astro` → Astro components
- This plan: `--framework alpine` → Alpine.store definitions

Together they enable: `juntos eject --framework alpine` takes a Rails blog and produces an idiomatic Alpine.js application with:
- Alpine components (from ERB views)
- Alpine.store (from ActiveRecord models)
- Drizzle persistence (from schema.rb)
- BroadcastChannel sync (from broadcasts_to)

Implementation can proceed in parallel - views and models are independent concerns.

## Open Questions

1. Should we support Drizzle's relational queries (`with`) or always use separate queries?
2. How do we handle `save` on new vs existing records at transpile time?
3. Schema migrations: leverage Drizzle Kit or custom solution?
4. What's the minimum Drizzle version we target?
5. Which frameworks to support initially? Alpine seems natural for Rails developers; Vue/React for broader reach.
6. Should ejected stores be one-per-model or a single unified store?
7. How should associations work in stores? Separate store references or nested data?
8. Should broadcast receiver setup be auto-generated or require user wiring?
