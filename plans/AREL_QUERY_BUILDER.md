# Arel-Style Query Builder Plan

Add deferred query building to Juntos ActiveRecord, enabling Rails-like method chaining with lazy evaluation.

## Dependency Role

This plan is **foundational** for offline-first applications:

```
AREL_QUERY_BUILDER (this plan)
        ↓
RAILS_SPA_ENGINE (tooling that uses queries)
        ↓
CALENDAR_DEMO (first validation)
        ↓
Showcase Scoring (production validation)
```

Both Calendar and Showcase require ActiveRecord-style queries against Dexie:

```ruby
# Calendar needs
Event.where(user_id: 1).includes(:user).modified_since(timestamp)

# Showcase needs
Heat.where(number: 42).includes(:dance, entry: [:lead, :follow])
```

Without this working, the "same models everywhere" vision can't be realized.

## Context

The current Juntos ActiveRecord implementation executes queries immediately:

```javascript
// Current: each method returns Promise<Model[]>
const users = await User.where({active: true});
// Can't chain - users is already an array
```

In Rails/Arel, queries build up through chaining and execute only when needed:

```ruby
# Rails: builds query, executes on iteration/await
User.where(active: true).order(:name).limit(10)
```

This plan introduces a `Relation` class that accumulates query constraints and executes lazily.

## Goals

1. **Enable method chaining** — `User.where({active: true}).order('name').limit(10)`
2. **Deferred execution** — Query runs on `await`, iteration, or terminal methods
3. **Adapter-agnostic** — Same API for SQL adapters and Dexie
4. **Incremental adoption** — Existing code continues to work
5. **Extensible** — Architecture supports adding more Arel features over time

## The 80/20 Approach

Rather than implementing Arel's full AST node system, use a simpler pattern:

| Arel (Full) | 80/20 Version |
|-------------|---------------|
| Complex node tree | Plain object state |
| Database-agnostic SQL generation | Adapter-specific execution |
| Arbitrary query composition | Fixed set of chainable methods |
| ~10,000 lines | ~200 lines |

This gets 80% of the developer experience with 20% of the complexity.

## Architecture

### Relation Class

The `Relation` class accumulates query state and is "thenable" (has `.then()`), so `await` triggers execution:

```javascript
class Relation {
  constructor(modelClass) {
    this.model = modelClass;
    this._conditions = [];
    this._notConditions = [];
    this._orConditions = [];
    this._order = null;
    this._limit = null;
    this._offset = null;
    this._select = null;
    this._distinct = false;
  }

  // --- Chainable methods (return new Relation) ---

  where(conditions) {
    const rel = this._clone();
    rel._conditions.push(conditions);
    return rel;
  }

  order(options) {
    const rel = this._clone();
    rel._order = options;
    return rel;
  }

  limit(n) {
    const rel = this._clone();
    rel._limit = n;
    return rel;
  }

  offset(n) {
    const rel = this._clone();
    rel._offset = n;
    return rel;
  }

  // --- Terminal methods (execute query) ---

  async first() {
    return (await this.limit(1).toArray())[0] || null;
  }

  async last() {
    const rel = this._clone();
    rel._order = rel._order ? this._reverseOrder(rel._order) : { id: 'desc' };
    return (await rel.limit(1).toArray())[0] || null;
  }

  async count() {
    return this.model._executeCount(this);
  }

  async toArray() {
    return this.model._executeRelation(this);
  }

  // --- Thenable interface (enables await) ---

  then(resolve, reject) {
    return this.toArray().then(resolve, reject);
  }

  // --- Internal ---

  _clone() {
    const rel = new Relation(this.model);
    rel._conditions = [...this._conditions];
    rel._notConditions = [...this._notConditions];
    rel._orConditions = [...this._orConditions];
    rel._order = this._order;
    rel._limit = this._limit;
    rel._offset = this._offset;
    rel._select = this._select;
    rel._distinct = this._distinct;
    return rel;
  }

  _reverseOrder(order) {
    if (typeof order === 'string') {
      return { [order]: 'desc' };
    }
    const [col, dir] = Object.entries(order)[0];
    return { [col]: dir === 'desc' ? 'asc' : 'desc' };
  }
}
```

### ActiveRecord Integration

Static methods return Relations instead of executing directly:

```javascript
class ActiveRecord extends ActiveRecordBase {
  // Returns Relation, not Promise
  static where(conditions) {
    return new Relation(this).where(conditions);
  }

  static order(options) {
    return new Relation(this).order(options);
  }

  static limit(n) {
    return new Relation(this).limit(n);
  }

  static all() {
    return new Relation(this);
  }

  // Adapter-specific: execute a Relation
  static async _executeRelation(relation) {
    // Implemented by each adapter
  }

  static async _executeCount(relation) {
    // Implemented by each adapter
  }
}
```

### SQL Adapter Execution

For SQL-based adapters (better-sqlite3, pg, mysql2, etc.):

```javascript
static async _executeRelation(rel) {
  const { sql, values } = this._buildSQL(rel);
  const stmt = db.prepare(sql);
  const rows = stmt.all(...values);
  return rows.map(row => new this(row));
}

static _buildSQL(rel) {
  let sql = `SELECT * FROM ${this.tableName}`;
  const values = [];

  // WHERE clause
  if (rel._conditions.length > 0) {
    const whereParts = [];
    for (const cond of rel._conditions) {
      for (const [key, value] of Object.entries(cond)) {
        if (Array.isArray(value)) {
          // IN clause: where({id: [1, 2, 3]})
          const placeholders = value.map(() => '?').join(', ');
          whereParts.push(`${key} IN (${placeholders})`);
          values.push(...value);
        } else if (value === null) {
          whereParts.push(`${key} IS NULL`);
        } else {
          whereParts.push(`${key} = ?`);
          values.push(value);
        }
      }
    }
    sql += ` WHERE ${whereParts.join(' AND ')}`;
  }

  // ORDER BY
  if (rel._order) {
    const [col, dir] = typeof rel._order === 'string'
      ? [rel._order, 'ASC']
      : [Object.keys(rel._order)[0], rel._order[Object.keys(rel._order)[0]].toUpperCase()];
    sql += ` ORDER BY ${col} ${dir === 'DESC' ? 'DESC' : 'ASC'}`;
  }

  // LIMIT / OFFSET
  if (rel._limit) sql += ` LIMIT ${rel._limit}`;
  if (rel._offset) sql += ` OFFSET ${rel._offset}`;

  return { sql, values };
}
```

### Dexie Adapter Execution

For Dexie (IndexedDB), build a Collection instead of SQL:

```javascript
static async _executeRelation(rel) {
  let collection = this.table;

  // Apply where conditions
  if (rel._conditions.length > 0) {
    // Dexie's where() only supports one indexed field
    // Use first condition for indexed lookup, rest for filter
    const [first, ...rest] = rel._conditions;
    collection = this.table.where(first);

    // Additional conditions become JavaScript filters
    for (const cond of rest) {
      collection = collection.filter(row =>
        Object.entries(cond).every(([k, v]) => {
          if (Array.isArray(v)) return v.includes(row[k]);
          if (v === null) return row[k] == null;
          return row[k] === v;
        })
      );
    }
  }

  // Apply order
  if (rel._order) {
    const [col, dir] = typeof rel._order === 'string'
      ? [rel._order, 'asc']
      : Object.entries(rel._order)[0];
    collection = collection.orderBy ? collection.orderBy(col) : this.table.orderBy(col);
    if (dir === 'desc') collection = collection.reverse();
  }

  // Apply offset/limit
  if (rel._offset) collection = collection.offset(rel._offset);
  if (rel._limit) collection = collection.limit(rel._limit);

  const rows = await collection.toArray();
  return rows.map(row => new this(row));
}
```

## Dexie Limitations

The Relation API is identical across adapters, but Dexie has constraints:

| Feature | SQL Adapters | Dexie |
|---------|--------------|-------|
| Multi-column WHERE | SQL handles efficiently | First uses index, rest filter in JS |
| Complex ORDER BY | `ORDER BY a, b DESC` | Single column only |
| OR conditions | `WHERE a=1 OR b=2` | Filter in JS |
| COUNT with WHERE | `SELECT COUNT(*)` | Counts filtered collection |

These differences are hidden from the developer. Performance may vary.

## Progress

| Phase | Status | Notes |
|-------|--------|-------|
| Cleanup | ✅ Done | `demo/ruby2js-on-rails/` removed |
| Phase 0 | ✅ Done | `active_record_sql.mjs`, dialects, all SQL adapters refactored |
| Phase 0.5 | ✅ Done | `dialects/mysql.mjs` created |
| Phase 1 | ✅ Done | `relation.mjs` with 56 passing tests |
| Phase 2 | ✅ Done | `not()` and `or()` methods, 72 passing tests |
| Phase 3 | ✅ Done | `select()`, `distinct()`, `exists()`, `pluck()`, 98 passing tests |
| Phase 4 | 🔲 TODO | Associations with `includes()` - **critical for Calendar/Showcase** |
| Phase 5 | 🔲 TODO | Scopes (documentation pattern) |
| Phase 6 | 🔲 TODO | Batching (`find_each`, `find_in_batches`) |
| Phase 7 | ⏸️ Optional | Aggregations |

## ~~Cleanup: Remove Obsolete Prototype~~ ✅ Done

~~Before implementation, remove `demo/ruby2js-on-rails/` which contains an outdated standalone ActiveRecord prototype.~~

Removed in earlier session. The blog and chat demos under `demo/` now use smoke tests to validate Ruby vs selfhost transpilation.

## Phased Implementation

### Phase 0: Adapter Refactoring (Prerequisite)

**Goal:** Consolidate duplicated code across SQL adapters using inheritance, enabling shared Relation execution logic.

**Problem:** Currently, each SQL adapter (~300 lines) duplicates nearly identical finder methods (`all`, `find`, `where`, `first`, `last`, `order`, `count`), mutation methods (`_insert`, `_update`, `destroy`), and DDL functions. This means implementing `_executeRelation` would require changes in 6+ places.

**Solution:** Introduce a three-tier inheritance hierarchy:

```
ActiveRecordBase (existing)
    │
    └── ActiveRecordSQL (NEW - shared SQL logic)
            │
            ├── SQLiteDialect (?, 1/0 booleans, AUTOINCREMENT)
            │     ├── BetterSqlite3Adapter
            │     ├── TursoAdapter
            │     ├── D1Adapter
            │     └── SqlJsAdapter
            │
            ├── PostgresDialect ($N, TRUE/FALSE, SERIAL)
            │     ├── PgAdapter
            │     ├── NeonAdapter
            │     └── PgliteAdapter
            │
            └── MySQLDialect (?, TRUE/FALSE, AUTO_INCREMENT)
                  ├── MySQL2Adapter
                  └── PlanetScaleAdapter

ActiveRecordDexie (separate - non-SQL)
```

**New Files:**

```
packages/ruby2js-rails/adapters/
├── active_record_sql.mjs      # Shared SQL finder/mutation logic
├── dialects/
│   ├── sqlite.mjs             # SQLite placeholder, types, booleans
│   ├── postgres.mjs           # PostgreSQL placeholder, types, booleans
│   └── mysql.mjs              # MySQL placeholder, types, booleans
```

**ActiveRecordSQL Base Class:**

```javascript
// active_record_sql.mjs
import { ActiveRecordBase } from './active_record_base.mjs';

export class ActiveRecordSQL extends ActiveRecordBase {
  // --- Dialect hooks (override in subclass) ---
  static get useNumberedParams() { return false; }  // true for Postgres
  static get returningId() { return false; }        // true for Postgres

  // --- Driver hooks (each adapter implements) ---
  static async _execute(sql, params) {
    throw new Error('Subclass must implement _execute');
  }

  static _getRows(result) {
    throw new Error('Subclass must implement _getRows');
  }

  static _getLastInsertId(result) {
    throw new Error('Subclass must implement _getLastInsertId');
  }

  // --- Shared finder implementations ---

  static async all() {
    const result = await this._execute(`SELECT * FROM ${this.tableName}`);
    return this._getRows(result).map(row => new this(row));
  }

  static async find(id) {
    const sql = `SELECT * FROM ${this.tableName} WHERE id = ${this._param(1)}`;
    const result = await this._execute(sql, [id]);
    const rows = this._getRows(result);
    if (rows.length === 0) throw new Error(`${this.name} not found with id=${id}`);
    return new this(rows[0]);
  }

  static async findBy(conditions) {
    const { sql, values } = this._buildWhere(conditions);
    const result = await this._execute(
      `SELECT * FROM ${this.tableName} WHERE ${sql} LIMIT 1`,
      values
    );
    const rows = this._getRows(result);
    return rows.length > 0 ? new this(rows[0]) : null;
  }

  static async where(conditions) {
    const { sql, values } = this._buildWhere(conditions);
    const result = await this._execute(
      `SELECT * FROM ${this.tableName} WHERE ${sql}`,
      values
    );
    return this._getRows(result).map(row => new this(row));
  }

  static async count() {
    const result = await this._execute(
      `SELECT COUNT(*) as count FROM ${this.tableName}`
    );
    return parseInt(this._getRows(result)[0].count);
  }

  static async first() {
    const result = await this._execute(
      `SELECT * FROM ${this.tableName} ORDER BY id ASC LIMIT 1`
    );
    const rows = this._getRows(result);
    return rows.length > 0 ? new this(rows[0]) : null;
  }

  static async last() {
    const result = await this._execute(
      `SELECT * FROM ${this.tableName} ORDER BY id DESC LIMIT 1`
    );
    const rows = this._getRows(result);
    return rows.length > 0 ? new this(rows[0]) : null;
  }

  static async order(options) {
    let column, direction;
    if (typeof options === 'string') {
      column = options;
      direction = 'ASC';
    } else {
      column = Object.keys(options)[0];
      direction = (options[column] === 'desc' || options[column] === ':desc') ? 'DESC' : 'ASC';
    }
    const result = await this._execute(
      `SELECT * FROM ${this.tableName} ORDER BY ${column} ${direction}`
    );
    return this._getRows(result).map(row => new this(row));
  }

  // --- Shared mutation implementations ---

  async destroy() {
    if (!this._persisted) return false;
    await this.constructor._execute(
      `DELETE FROM ${this.constructor.tableName} WHERE id = ${this.constructor._param(1)}`,
      [this.id]
    );
    this._persisted = false;
    console.log(`  ${this.constructor.name} Destroy (id: ${this.id})`);
    await this._runCallbacks('after_destroy_commit');
    return true;
  }

  async _insert() {
    const cols = [];
    const placeholders = [];
    const values = [];
    let i = 1;

    for (const [key, value] of Object.entries(this.attributes)) {
      if (key === 'id') continue;
      cols.push(key);
      placeholders.push(this.constructor._param(i++));
      values.push(value);
    }

    let sql = `INSERT INTO ${this.constructor.tableName} (${cols.join(', ')}) VALUES (${placeholders.join(', ')})`;
    if (this.constructor.returningId) sql += ' RETURNING id';

    const result = await this.constructor._execute(sql, values);
    this.id = this.constructor._getLastInsertId(result);
    this.attributes.id = this.id;
    this._persisted = true;
    console.log(`  ${this.constructor.name} Create (id: ${this.id})`);
    return true;
  }

  async _update() {
    const sets = [];
    const values = [];
    let i = 1;

    for (const [key, value] of Object.entries(this.attributes)) {
      if (key === 'id') continue;
      sets.push(`${key} = ${this.constructor._param(i++)}`);
      values.push(value);
    }
    values.push(this.id);

    const sql = `UPDATE ${this.constructor.tableName} SET ${sets.join(', ')} WHERE id = ${this.constructor._param(i)}`;
    await this.constructor._execute(sql, values);
    console.log(`  ${this.constructor.name} Update (id: ${this.id})`);
    return true;
  }

  // --- Shared helpers ---

  static _param(n) {
    return this.useNumberedParams ? `$${n}` : '?';
  }

  static _buildWhere(conditions) {
    const clauses = [];
    const values = [];
    let i = 1;
    for (const [key, value] of Object.entries(conditions)) {
      clauses.push(`${key} = ${this._param(i++)}`);
      values.push(value);
    }
    return { sql: clauses.join(' AND '), values };
  }
}
```

**Dialect Classes:**

```javascript
// dialects/sqlite.mjs
import { ActiveRecordSQL } from '../active_record_sql.mjs';

export const SQLITE_TYPE_MAP = {
  string: 'TEXT', text: 'TEXT', integer: 'INTEGER', bigint: 'INTEGER',
  float: 'REAL', decimal: 'REAL', boolean: 'INTEGER', date: 'TEXT',
  datetime: 'TEXT', time: 'TEXT', timestamp: 'TEXT', binary: 'BLOB',
  json: 'TEXT', jsonb: 'TEXT'
};

export class SQLiteDialect extends ActiveRecordSQL {
  static get useNumberedParams() { return false; }
  static get returningId() { return false; }
  static get typeMap() { return SQLITE_TYPE_MAP; }

  static formatBoolean(val) { return val ? 1 : 0; }
  static formatDefault(value) {
    if (value === null) return 'NULL';
    if (typeof value === 'string') return `'${value.replace(/'/g, "''")}'`;
    if (typeof value === 'boolean') return value ? '1' : '0';
    return String(value);
  }
}

// dialects/postgres.mjs
import { ActiveRecordSQL } from '../active_record_sql.mjs';

export const PG_TYPE_MAP = {
  string: 'VARCHAR(255)', text: 'TEXT', integer: 'INTEGER', bigint: 'BIGINT',
  float: 'DOUBLE PRECISION', decimal: 'DECIMAL', boolean: 'BOOLEAN',
  date: 'DATE', datetime: 'TIMESTAMP', time: 'TIME', timestamp: 'TIMESTAMP',
  binary: 'BYTEA', json: 'JSON', jsonb: 'JSONB'
};

export class PostgresDialect extends ActiveRecordSQL {
  static get useNumberedParams() { return true; }
  static get returningId() { return true; }
  static get typeMap() { return PG_TYPE_MAP; }

  static formatBoolean(val) { return val ? 'TRUE' : 'FALSE'; }
  static formatDefault(value) {
    if (value === null) return 'NULL';
    if (typeof value === 'string') return `'${value.replace(/'/g, "''")}'`;
    if (typeof value === 'boolean') return value ? 'TRUE' : 'FALSE';
    return String(value);
  }
}
```

**Thin Adapter Example (Turso):**

```javascript
// active_record_turso.mjs
import { createClient } from '@libsql/client';
import { SQLiteDialect } from './dialects/sqlite.mjs';
import { attr_accessor, initTimePolyfill } from './active_record_base.mjs';

export { attr_accessor };

let client = null;

// ... initDatabase, DDL functions (can also be shared) ...

export class ActiveRecord extends SQLiteDialect {
  static async _execute(sql, params = []) {
    return client.execute({ sql, args: params });
  }

  static _getRows(result) {
    return result.rows.map(row => ({ ...row }));
  }

  static _getLastInsertId(result) {
    return result.rows[0]?.id ?? Number(result.lastInsertRowid);
  }
}
```

**Benefits:**

| Metric | Before | After |
|--------|--------|-------|
| Lines per SQL adapter | ~300 | ~50 |
| Total SQL adapter code | ~1800 | ~500 |
| Adding `_executeRelation` | 6 places | 1 place |
| Bug fix propagation | 6 places | 1 place |
| Adding new adapter | Copy 300 lines | Implement 3 methods |

**Testing:** No new tests required.

The existing demo applications (`demo/blog/`, `demo/chat/`) serve as integration tests. Run them after each adapter refactor to verify functionality. This refactoring changes internal structure, not external behavior, so existing code coverage is sufficient.

**Files Modified:**

- New: `active_record_sql.mjs`, `dialects/sqlite.mjs`, `dialects/postgres.mjs`
- Modified: SQLite adapters (better-sqlite3, turso, d1, sqljs), PostgreSQL adapters (pg, neon, pglite)
- Unchanged: `active_record_base.mjs`

**Intentionally Standalone Adapters:**

| Adapter | Reason |
|---------|--------|
| **dexie** | Non-SQL (IndexedDB) — uses Collection API, not SQL queries |
| **supabase** | Non-SQL (PostgREST API) — uses `.from().select().eq()`, not raw SQL |

These adapters implement the same ActiveRecord interface but have fundamentally different query mechanisms that don't fit the SQL inheritance hierarchy.

---

### Phase 0.5: MySQL Dialect

**Goal:** Extend the SQL inheritance hierarchy to MySQL-compatible databases.

**Adapters to refactor:**
- `mysql2` — Standard MySQL driver for Node.js
- `planetscale` — MySQL-compatible serverless database

**New File:** `dialects/mysql.mjs`

```javascript
// dialects/mysql.mjs
import { ActiveRecordSQL } from '../active_record_sql.mjs';

export const MYSQL_TYPE_MAP = {
  string: 'VARCHAR(255)',
  text: 'TEXT',
  integer: 'INT',
  bigint: 'BIGINT',
  float: 'DOUBLE',
  decimal: 'DECIMAL',
  boolean: 'TINYINT(1)',
  date: 'DATE',
  datetime: 'DATETIME',
  time: 'TIME',
  timestamp: 'TIMESTAMP',
  binary: 'BLOB',
  json: 'JSON',
  jsonb: 'JSON'
};

export class MySQLDialect extends ActiveRecordSQL {
  // MySQL uses ? placeholders (like SQLite)
  static get useNumberedParams() { return false; }

  // MySQL doesn't support RETURNING, uses insertId
  static get returningId() { return false; }

  static get typeMap() { return MYSQL_TYPE_MAP; }

  // MySQL accepts native booleans but stores as TINYINT(1)
  static _formatValue(val) {
    if (typeof val === 'boolean') return val ? 1 : 0;
    return val;
  }

  static formatDefaultValue(value) {
    if (value === null) return 'NULL';
    if (typeof value === 'string') return `'${value.replace(/'/g, "''")}'`;
    if (typeof value === 'boolean') return value ? '1' : '0';
    return String(value);
  }
}
```

**Thin Adapter Example (mysql2):**

```javascript
// active_record_mysql2.mjs
import mysql from 'mysql2/promise';
import { MySQLDialect } from './dialects/mysql.mjs';
import { attr_accessor, initTimePolyfill } from './active_record_base.mjs';

export { attr_accessor };

let pool = null;

// ... initDatabase, DDL functions ...

export class ActiveRecord extends MySQLDialect {
  static async _execute(sql, params = []) {
    const [rows, fields] = await pool.execute(sql, params);
    return { rows, fields };
  }

  static _getRows(result) {
    return result.rows || [];
  }

  static _getLastInsertId(result) {
    return result.rows?.insertId;
  }
}
```

**Testing:** No new tests required.

MySQL adapters can be tested manually via demos. The adapter refactoring doesn't change external behavior. Docker setup for integration testing: `docker run -d -p 3306:3306 -e MYSQL_ROOT_PASSWORD=test mysql:8`

**Files Modified:**

- New: `dialects/mysql.mjs`
- Modified: `active_record_mysql2.mjs`, `active_record_planetscale.mjs`
- Updated: `lib/ruby2js/rails/builder.rb` (copy mysql dialect)

---

### Phase 1: Core Relation (MVP)

**Goal:** Basic chaining with deferred execution.

**Features:**
- `where(conditions)` — equality conditions
- `order(column)` / `order({column: 'desc'})`
- `limit(n)` / `offset(n)`
- `first()` / `last()` / `count()`
- `all()` returns Relation
- `await` triggers execution

**Files:**
- New: `packages/ruby2js-rails/adapters/relation.mjs`
- Modified: All `active_record_*.mjs` adapters

**Testing:** Tests required in `packages/ruby2js-rails/test/`.

This phase introduces new functionality with significant complexity. Tests should cover:
- Method chaining (`where().order().limit()`)
- Deferred execution (Relation is thenable)
- Terminal methods (`first()`, `last()`, `count()`, `toArray()`)
- SQL building (`_buildRelationSQL()` produces correct SQL)
- Edge cases (empty results, null conditions, IN clauses)

**Estimated size:** ~150 lines for Relation, ~50 lines per adapter

### Phase 2: Enhanced Conditions

**Goal:** More expressive WHERE clauses.

**Features:**
- Array values: `where({id: [1, 2, 3]})` → `IN` clause
- Null handling: `where({deleted_at: null})` → `IS NULL`
- `not(conditions)` — negation
- `or(relation)` — OR composition

```javascript
// Phase 2 examples
User.where({role: ['admin', 'moderator']})
User.where({deleted_at: null})
User.where({active: true}).not({role: 'guest'})
User.where({admin: true}).or(User.where({moderator: true}))
```

**Implementation:**

```javascript
not(conditions) {
  const rel = this._clone();
  rel._notConditions = rel._notConditions || [];
  rel._notConditions.push(conditions);
  return rel;
}

or(otherRelation) {
  const rel = this._clone();
  rel._orConditions.push(otherRelation._conditions);
  return rel;
}
```

**Testing:** Tests required in `packages/ruby2js-rails/test/`.

New query patterns need verification:
- IN clause: `where({id: [1, 2, 3]})` generates correct SQL
- NULL handling: `where({deleted_at: null})` produces `IS NULL`
- NOT conditions: `not({role: 'guest'})` negates correctly
- OR composition: `where({admin: true}).or(...)` combines properly

### Phase 3: Query Refinement

**Goal:** Column selection, distinct, exists.

**Features:**
- `select(...columns)` — limit returned columns
- `distinct()` — unique results
- `exists()` — boolean check
- `pluck(...columns)` — return values, not models

```javascript
// Phase 3 examples
User.select('id', 'name').where({active: true})
User.distinct().pluck('role')
User.where({email: 'test@example.com'}).exists()
```

**Implementation:**

```javascript
select(...columns) {
  const rel = this._clone();
  rel._select = columns;
  return rel;
}

distinct() {
  const rel = this._clone();
  rel._distinct = true;
  return rel;
}

async exists() {
  return (await this.limit(1).count()) > 0;
}

async pluck(...columns) {
  const rel = this._clone();
  rel._select = columns;
  rel._pluck = true;
  const rows = await this.model._executePluck(rel);
  return columns.length === 1
    ? rows.map(r => r[columns[0]])
    : rows.map(r => columns.map(c => r[c]));
}
```

**Testing:** Tests required in `packages/ruby2js-rails/test/`.

New functionality needs verification:
- `select()` limits columns returned
- `distinct()` produces unique results
- `exists()` returns boolean correctly (edge cases: empty table, matching/non-matching)
- `pluck()` returns values (single column as flat array, multiple as nested arrays)

### Phase 4: Associations

**Goal:** Define and load related models, enabling `includes()` for eager loading.

This phase is **critical** for Calendar and Showcase demos where queries span multiple tables.

**Features:**
- `belongs_to` / `has_many` / `has_many :through` declarations
- `includes(...associations)` — eager loading
- Nested includes: `includes(entry: [:lead, :follow])`
- Association accessors: `heat.dance`, `entry.lead`

**Model Declarations:**

```javascript
// Model with associations
class Heat extends ActiveRecord {
  static associations = {
    dance: { type: 'belongs_to', model: 'Dance', foreignKey: 'dance_id' },
    entry: { type: 'belongs_to', model: 'Entry', foreignKey: 'entry_id' },
    scores: { type: 'has_many', model: 'Score', foreignKey: 'heat_id' }
  };
}

class Entry extends ActiveRecord {
  static associations = {
    lead: { type: 'belongs_to', model: 'Person', foreignKey: 'lead_id' },
    follow: { type: 'belongs_to', model: 'Person', foreignKey: 'follow_id' },
    instructor: { type: 'belongs_to', model: 'Person', foreignKey: 'instructor_id' }
  };
}

class Event extends ActiveRecord {
  static associations = {
    user: { type: 'belongs_to', model: 'User', foreignKey: 'user_id' },
    meeting_requests: { type: 'has_many', model: 'MeetingRequest', foreignKey: 'event_id' }
  };
}
```

**Relation Enhancement:**

```javascript
class Relation {
  includes(...associations) {
    const rel = this._clone();
    rel._includes = rel._includes || [];
    rel._includes.push(...associations);
    return rel;
  }
}
```

**SQL Adapter Implementation:**

For SQL adapters, use separate queries (not JOINs) to load associations:

```javascript
static async _executeRelation(rel) {
  // 1. Execute main query
  const rows = await this._executeMainQuery(rel);
  const records = rows.map(row => new this(row));

  // 2. Load included associations
  if (rel._includes && rel._includes.length > 0) {
    await this._loadAssociations(records, rel._includes);
  }

  return records;
}

static async _loadAssociations(records, includes) {
  for (const include of includes) {
    if (typeof include === 'string') {
      // Simple include: 'dance'
      await this._loadAssociation(records, include);
    } else if (typeof include === 'object') {
      // Nested include: { entry: ['lead', 'follow'] }
      for (const [assocName, nested] of Object.entries(include)) {
        await this._loadAssociation(records, assocName);
        // Recursively load nested associations
        const assocRecords = records.map(r => r[assocName]).filter(Boolean);
        const assocModel = this._getAssociationModel(assocName);
        await assocModel._loadAssociations(assocRecords, nested);
      }
    }
  }
}

static async _loadAssociation(records, assocName) {
  const assoc = this.associations[assocName];
  if (!assoc) return;

  const AssocModel = this._resolveModel(assoc.model);

  if (assoc.type === 'belongs_to') {
    // Collect foreign key values
    const fkValues = [...new Set(records.map(r => r[assoc.foreignKey]).filter(Boolean))];
    if (fkValues.length === 0) return;

    // Single query for all related records
    const related = await AssocModel.where({ id: fkValues });
    const relatedById = Object.fromEntries(related.map(r => [r.id, r]));

    // Attach to parent records
    for (const record of records) {
      record[assocName] = relatedById[record[assoc.foreignKey]] || null;
    }
  } else if (assoc.type === 'has_many') {
    // Collect primary key values
    const pkValues = records.map(r => r.id);

    // Single query for all related records
    const related = await AssocModel.where({ [assoc.foreignKey]: pkValues });

    // Group by foreign key
    const relatedByFk = {};
    for (const r of related) {
      const fk = r[assoc.foreignKey];
      if (!relatedByFk[fk]) relatedByFk[fk] = [];
      relatedByFk[fk].push(r);
    }

    // Attach to parent records
    for (const record of records) {
      record[assocName] = relatedByFk[record.id] || [];
    }
  }
}
```

**Dexie Adapter Implementation:**

Same pattern, but using Dexie's `where().anyOf()` for batch loading:

```javascript
static async _loadAssociation(records, assocName) {
  const assoc = this.associations[assocName];
  if (!assoc) return;

  const AssocModel = this._resolveModel(assoc.model);

  if (assoc.type === 'belongs_to') {
    const fkValues = [...new Set(records.map(r => r[assoc.foreignKey]).filter(Boolean))];
    if (fkValues.length === 0) return;

    // Dexie batch lookup
    const related = await AssocModel.table.where('id').anyOf(fkValues).toArray();
    const relatedById = Object.fromEntries(related.map(r => [r.id, new AssocModel(r)]));

    for (const record of records) {
      record[assocName] = relatedById[record[assoc.foreignKey]] || null;
    }
  } else if (assoc.type === 'has_many') {
    const pkValues = records.map(r => r.id);

    // Dexie batch lookup on foreign key (requires index)
    const related = await AssocModel.table.where(assoc.foreignKey).anyOf(pkValues).toArray();

    const relatedByFk = {};
    for (const r of related) {
      const fk = r[assoc.foreignKey];
      if (!relatedByFk[fk]) relatedByFk[fk] = [];
      relatedByFk[fk].push(new AssocModel(r));
    }

    for (const record of records) {
      record[assocName] = relatedByFk[record.id] || [];
    }
  }
}
```

**N+1 Prevention:**

The key insight is that `includes()` triggers batch loading, not per-record queries:

```javascript
// BAD: N+1 queries (without includes)
const heats = await Heat.where({number: 42});
for (const heat of heats) {
  console.log(heat.dance);  // Separate query for each heat!
}

// GOOD: 2 queries total (with includes)
const heats = await Heat.where({number: 42}).includes('dance');
for (const heat of heats) {
  console.log(heat.dance);  // Already loaded
}
```

**Dexie Index Requirements:**

For efficient `has_many` loading, foreign keys need indexes:

```javascript
// Dexie schema must include foreign key indexes
const db = new Dexie('calendar');
db.version(1).stores({
  events: '++id, user_id',           // user_id indexed for has_many
  meeting_requests: '++id, event_id', // event_id indexed for has_many
  scores: '++id, heat_id, judge_id'   // heat_id indexed for has_many
});
```

**Testing:** Tests required in `packages/ruby2js-rails/test/`.

Complex feature requires comprehensive tests:
- `belongs_to` associations load correctly
- `has_many` associations load correctly
- Nested associations: `includes({ entry: ['lead', 'follow'] })`
- N+1 prevention: batch loading verifies query count
- Edge cases: missing associations, null foreign keys

Example test structure:

```javascript
describe('Associations', () => {
  it('loads belongs_to association', async () => {
    const heats = await Heat.where({number: 1}).includes('dance');
    expect(heats[0].dance).toBeInstanceOf(Dance);
    expect(heats[0].dance.name).toBeDefined();
  });

  it('loads nested associations', async () => {
    const heats = await Heat.where({number: 1}).includes({ entry: ['lead', 'follow'] });
    expect(heats[0].entry).toBeInstanceOf(Entry);
    expect(heats[0].entry.lead).toBeInstanceOf(Person);
    expect(heats[0].entry.follow).toBeInstanceOf(Person);
  });

  it('prevents N+1 queries', async () => {
    const queryCount = trackQueries();
    const heats = await Heat.limit(100).includes('dance', 'entry');
    // Should be 3 queries: heats, dances, entries (not 201)
    expect(queryCount()).toBe(3);
  });
});
```

### Phase 5: Scopes

**Goal:** Named, reusable query fragments.

**Features:**
- Define scopes as static methods
- Scopes return Relations, enabling chaining
- Default scope support

```javascript
// Model definition
class Article extends ActiveRecord {
  static published() {
    return this.where({published: true});
  }

  static recent() {
    return this.order({created_at: 'desc'}).limit(10);
  }

  static byAuthor(authorId) {
    return this.where({author_id: authorId});
  }

  // Default scope
  static get defaultScope() {
    return this.where({deleted: false});
  }
}

// Usage
Article.published().recent()
Article.byAuthor(123).order('title')
```

**Implementation:**

Scopes are just methods that return Relations. The framework provides:
- Documentation pattern
- Optional default scope handling in `all()`

```javascript
static all() {
  const base = new Relation(this);
  if (this.defaultScope) {
    return this.defaultScope.merge(base);
  }
  return base;
}
```

**Testing:** No new tests required.

Scopes are simply methods that return Relations. Phase 1 tests cover Relation functionality. Default scope behavior can be verified through existing integration tests in demos.

### Phase 6: Batching

**Goal:** Memory-efficient iteration over large datasets.

**Features:**
- `find_each(callback, {batch_size: 1000})`
- `find_in_batches(callback, {batch_size: 1000})`
- `in_batches({batch_size: 1000})` — returns iterator

```javascript
// Process millions of records without loading all into memory
await User.where({active: true}).find_each(async (user) => {
  await sendEmail(user);
}, { batch_size: 500 });

// Get batches for parallel processing
await User.in_batches({ batch_size: 1000 }).forEach(async (batch) => {
  await processBatch(batch);
});
```

**Implementation:**

```javascript
async find_each(callback, { batch_size = 1000 } = {}) {
  let offset = 0;
  while (true) {
    const batch = await this.limit(batch_size).offset(offset).toArray();
    if (batch.length === 0) break;
    for (const record of batch) {
      await callback(record);
    }
    if (batch.length < batch_size) break;
    offset += batch_size;
  }
}

async find_in_batches(callback, { batch_size = 1000 } = {}) {
  let offset = 0;
  while (true) {
    const batch = await this.limit(batch_size).offset(offset).toArray();
    if (batch.length === 0) break;
    await callback(batch);
    if (batch.length < batch_size) break;
    offset += batch_size;
  }
}
```

**Testing:** Tests required in `packages/ruby2js-rails/test/`.

Batching has subtle edge cases:
- Empty dataset (zero iterations)
- Dataset smaller than batch size (single iteration)
- Dataset exactly divisible by batch size (boundary condition)
- `find_each` vs `find_in_batches` callback signatures
- Error handling mid-batch

### Phase 7: Aggregations (Optional)

**Goal:** SQL aggregation without loading records.

**Features:**
- `sum(column)`
- `average(column)`
- `minimum(column)` / `maximum(column)`
- `group(...columns)` with aggregations

```javascript
// Aggregate queries
await Order.where({status: 'completed'}).sum('total')
await Product.average('price')
await User.group('role').count()
```

**Testing:** Tests if implemented.

This phase is optional. If implemented, tests should cover:
- `sum()`, `average()`, `minimum()`, `maximum()` with various data types
- `group()` with aggregations
- Aggregations combined with `where()` conditions

**Note:** This phase is optional. Many apps don't need aggregations in JavaScript — they use database views or reporting tools. Implement only if there's clear demand.

## File Structure

```
packages/ruby2js-rails/
├── adapters/
│   ├── active_record_base.mjs          # Validation, callbacks, save/update
│   ├── active_record_sql.mjs           # Shared SQL finders, _executeRelation
│   ├── relation.mjs                    # Relation class (chainable queries)
│   ├── dialects/
│   │   ├── sqlite.mjs                  # SQLite: ?, 1/0, AUTOINCREMENT
│   │   ├── postgres.mjs                # Postgres: $N, TRUE/FALSE, SERIAL
│   │   └── mysql.mjs                   # MySQL: ?, TRUE/FALSE, AUTO_INCREMENT
│   ├── active_record_better_sqlite3.mjs  # Thin: extends SQLiteDialect
│   ├── active_record_turso.mjs           # Thin: extends SQLiteDialect
│   ├── active_record_d1.mjs              # Thin: extends SQLiteDialect
│   ├── active_record_sqljs.mjs           # Thin: extends SQLiteDialect
│   ├── active_record_pg.mjs              # Thin: extends PostgresDialect
│   ├── active_record_neon.mjs            # Thin: extends PostgresDialect
│   ├── active_record_pglite.mjs          # Thin: extends PostgresDialect
│   ├── active_record_mysql2.mjs          # Thin: extends MySQLDialect
│   ├── active_record_planetscale.mjs     # Thin: extends MySQLDialect
│   └── active_record_dexie.mjs           # Separate: non-SQL, Collection API
```

## Backward Compatibility

Existing code continues to work:

```javascript
// Old style - still works, returns Promise
const articles = await Article.where({published: true});

// New style - returns Relation, await executes
const articles = await Article.where({published: true}).order('title').limit(10);
```

The key is that `await` on a Relation calls its `then()` method, which executes the query.

## Testing Strategy

### Test Location

All Relation and adapter tests go in `packages/ruby2js-rails/test/`. This directory should contain:

```
packages/ruby2js-rails/test/
├── relation_test.mjs           # Core Relation class tests
├── active_record_sql_test.mjs  # SQL building and execution tests
└── fixtures/                   # Test data setup
```

### Testing by Phase

| Phase | Tests Required | Rationale |
|-------|---------------|-----------|
| 0 (Adapter Refactoring) | No | Internal refactoring; demos provide integration coverage |
| 0.5 (MySQL Dialect) | No | Internal refactoring; demos provide integration coverage |
| 1 (Core Relation) | **Yes** | New functionality with significant complexity |
| 2 (Enhanced Conditions) | **Yes** | New query patterns |
| 3 (Query Refinement) | **Yes** | New functionality (select, distinct, exists, pluck) |
| 4 (Associations) | **Yes** | Complex feature with N+1 prevention |
| 5 (Scopes) | No | Just methods returning Relations; Phase 1 covers this |
| 6 (Batching) | **Yes** | Edge cases around batch boundaries |
| 7 (Aggregations) | If implemented | Optional phase |

### Unit Tests (Phase 1+)

```javascript
describe('Relation', () => {
  it('chains where conditions', async () => {
    const rel = User.where({active: true}).where({role: 'admin'});
    expect(rel._conditions).toEqual([{active: true}, {role: 'admin'}]);
  });

  it('executes on await', async () => {
    const users = await User.where({active: true});
    expect(Array.isArray(users)).toBe(true);
  });

  it('supports limit and offset', async () => {
    const users = await User.order('id').limit(5).offset(10);
    expect(users.length).toBeLessThanOrEqual(5);
  });
});
```

### Integration Tests

Existing demos (`demo/blog/`, `demo/chat/`) serve as integration tests. Run them after significant changes to verify end-to-end functionality.

For adapter-specific testing, create minimal test cases that exercise each adapter's unique behavior (e.g., placeholder syntax, boolean formatting).

## Success Criteria

1. **Phase 0 complete:** SQL adapters refactored to use inheritance hierarchy
2. **Phase 1 complete:** Basic chaining works across all adapters
3. **Phase 4 complete:** Associations with includes() work across all adapters
4. **API compatibility:** `await User.where(...).order(...).limit(...)` works
5. **Association loading:** `await Heat.includes(:dance, entry: [:lead, :follow])` works
6. **No regressions:** Existing immediate-execution code still works
7. **Code reduction:** SQL adapter code reduced from ~1800 to ~500 lines
8. **Performance:** No significant overhead for simple queries
9. **N+1 prevention:** includes() batch-loads associations efficiently
10. **Documentation:** Examples in Juntos docs show chaining and association patterns

## What We Skip (The Other 80%)

Features intentionally omitted to keep the implementation simple:

| Feature | Why Skipped |
|---------|-------------|
| Joins | Complex, use raw SQL or eager loading |
| Subqueries | Rarely needed in app code |
| HAVING clause | Use `group()` with post-filtering |
| Arel node system | Over-engineered for most apps |
| Query caching | Let the database handle it |
| Prepared statements | Adapter handles this |
| Complex locking | `FOR UPDATE` etc. — use raw SQL |

If any of these become necessary, the Relation architecture supports adding them incrementally.

## Related Plans

**Downstream (depends on this):**
- [RAILS_SPA_ENGINE.md](./RAILS_SPA_ENGINE.md) — SPA generation tooling (uses query builder)
- [CALENDAR_DEMO.md](./CALENDAR_DEMO.md) — First validation of offline-first queries

**Parallel (same layer):**
- [DEXIE_SUPPORT.md](./DEXIE_SUPPORT.md) — Multiple adapter architecture
- [UNIVERSAL_DATABASES.md](./UNIVERSAL_DATABASES.md) — HTTP-based adapters
- [MULTI_TARGET_ARCHITECTURE.md](./MULTI_TARGET_ARCHITECTURE.md) — Target environments
