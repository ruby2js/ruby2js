# Plan: ActiveRecord to Drizzle Transpilation

## Summary

Replace the current runtime adapter approach with build-time transpilation of ActiveRecord queries to Drizzle ORM syntax. A Drizzle-compatible IndexedDB helper provides browser support with the same API.

## Motivation

The current approach uses runtime adapters that implement ActiveRecord-like methods (`find`, `where`, `save`, etc.) for each database target. Analysis of the Dexie adapter revealed we're barely using Dexie's features - just basic CRUD while doing sorting, filtering, and associations ourselves.

**Current architecture:**
- Ruby models transpile to JS with ActiveRecord method calls
- Runtime adapters implement those methods for each database
- N adapters to maintain (Dexie, SQLite, Turso, D1, etc.)

**Proposed architecture:**
- Ruby models transpile directly to Drizzle query syntax
- Drizzle handles all SQL databases (one target, many drivers)
- Small IndexedDB helper implements Drizzle's API for browser offline

## Design

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

### Phase 5: Migration & Cleanup
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

## Dependencies

- Drizzle ORM (stable, well-maintained)
- Drizzle Kit (schema tooling)
- No Dexie dependency
- Smaller ruby2js-rails package

## Relationship to Other Plans

This plan can proceed after or in parallel with `sfc-triple-target.md`:
- SFC plan focuses on ERB→Astro view conversion
- This plan focuses on model/data layer
- Both contribute to "Rails app → deploy anywhere" vision
- Either can be implemented independently

## Open Questions

1. Should we support Drizzle's relational queries (`with`) or always use separate queries?
2. How do we handle `save` on new vs existing records at transpile time?
3. Schema migrations: leverage Drizzle Kit or custom solution?
4. What's the minimum Drizzle version we target?
