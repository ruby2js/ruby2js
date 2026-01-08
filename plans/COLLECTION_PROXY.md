# CollectionProxy Implementation

Implement a proper `CollectionProxy` class that mirrors Rails' `ActiveRecord::Associations::CollectionProxy`, enabling idiomatic Rails code like `article.comments.size` to work in Juntos.

## Background

In Rails, `article.comments` returns a `CollectionProxy`, not a plain array. This proxy:
- Supports counting (`.size`, `.length`, `.count`)
- Supports building/creating (`.build`, `.create`)
- Supports querying (`.where`, `.find`, `.first`, `.last`)
- Is enumerable (`.each`, `.map`, `[0]`)
- Enables chaining (`article.comments.where(active: true).order(:created_at)`)

Currently, our model filter generates an inline object with `build`, `create`, `find`, and `then` methods. This works for basic use but lacks `.size` and chaining.

## Current State

The blog demo temporarily uses `.length` instead of `.size`:
```erb
<%= pluralize(article.comments.length, "comment") %>
```

This works because:
- Rails: `CollectionProxy#length` loads records and returns count
- Juntos: Eager-loaded `_comments` is an array with `.length`

## Goal

Restore the blog demo to idiomatic Rails:
```erb
<%= pluralize(article.comments.size, "comment") %>
```

## Implementation

### 1. Create CollectionProxy Class

File: `packages/ruby2js-rails/adapters/collection_proxy.mjs`

```javascript
export class CollectionProxy {
  constructor(owner, association, AssocModel) {
    this._owner = owner;
    this._association = association;  // { name, type, foreignKey }
    this._model = AssocModel;
    this._loaded = false;
    this._records = null;
  }

  // --- Counting ---

  get size() {
    if (this._records) return this._records.length;
    // If not loaded, could do async count - for now require load
    return this._records?.length ?? 0;
  }

  get length() {
    return this.size;
  }

  async count() {
    const fk = this._association.foreignKey;
    return this._model.where({ [fk]: this._owner.id }).count();
  }

  get empty() {
    return this.size === 0;
  }

  // --- Building ---

  build(params = {}) {
    const fk = this._association.foreignKey;
    return new this._model({ ...params, [fk]: this._owner.id });
  }

  async create(params = {}) {
    const record = this.build(params);
    await record.save();
    if (this._records) this._records.push(record);
    return record;
  }

  // --- Finding ---

  async find(id) {
    return this._model.find(id);
  }

  async first() {
    if (this._records) return this._records[0] || null;
    return this.toRelation().first();
  }

  async last() {
    if (this._records) return this._records[this._records.length - 1] || null;
    return this.toRelation().last();
  }

  // --- Chaining ---

  where(conditions) {
    return this.toRelation().where(conditions);
  }

  order(options) {
    return this.toRelation().order(options);
  }

  limit(n) {
    return this.toRelation().limit(n);
  }

  // Convert to a scoped Relation for chaining
  toRelation() {
    const fk = this._association.foreignKey;
    return this._model.where({ [fk]: this._owner.id });
  }

  // --- Enumerable ---

  [Symbol.iterator]() {
    return (this._records || [])[Symbol.iterator]();
  }

  forEach(fn) {
    return (this._records || []).forEach(fn);
  }

  map(fn) {
    return (this._records || []).map(fn);
  }

  filter(fn) {
    return (this._records || []).filter(fn);
  }

  // Array indexing
  at(index) {
    return (this._records || [])[index];
  }

  // --- Thenable ---

  then(resolve, reject) {
    if (this._records) {
      return Promise.resolve(this._records).then(resolve, reject);
    }
    return this.toRelation().then(records => {
      this._records = records;
      this._loaded = true;
      return records;
    }).then(resolve, reject);
  }

  // --- Loading ---

  load(records) {
    this._records = records;
    this._loaded = true;
    return this;
  }

  get loaded() {
    return this._loaded;
  }
}
```

### 2. Update Model Filter

In `lib/ruby2js/filter/rails/model.rb`, update `generate_has_many_method` to return a CollectionProxy:

```ruby
def generate_has_many_method(assoc)
  # has_many :comments -> get comments() {
  #   if (this._comments) return this._comments;
  #   return new CollectionProxy(this, this.constructor.associations.comments, Comment);
  # }

  # ... generate getter that returns CollectionProxy
end
```

The getter returns `_comments` if set (for eager-loaded data), otherwise creates a new CollectionProxy.

### 3. Update Eager Loading

In `active_record_dexie.mjs` and `active_record_sql.mjs`, update `_loadHasMany` to set a loaded CollectionProxy instead of a plain array:

```javascript
static async _loadHasMany(records, assocName, assoc, AssocModel) {
  // ... fetch related records ...

  for (const record of records) {
    const related = relatedByFk.get(record.id) || [];
    // Create a loaded CollectionProxy
    const proxy = new CollectionProxy(record, assoc, AssocModel);
    proxy.load(related);
    record[`_${assocName}`] = proxy;
  }
}
```

### 4. Add Import to Adapters

Both Dexie and SQL adapters need to import CollectionProxy:

```javascript
import { CollectionProxy } from 'ruby2js-rails/adapters/collection_proxy.mjs';
```

### 5. Restore Blog Demo

Change back to idiomatic Rails:
```erb
<%= pluralize(article.comments.size, "comment") %>
```

## Testing

1. **Blog demo on Dexie**: Verify comment counts display correctly
2. **Blog demo on SQLite**: Verify same behavior on SQL adapter
3. **Chaining**: Test `article.comments.where(...).first`
4. **Building**: Test `article.comments.build(...)` and `article.comments.create(...)`
5. **Enumeration**: Test `article.comments.each { |c| ... }`

## Files to Change

| File | Change |
|------|--------|
| `packages/ruby2js-rails/adapters/collection_proxy.mjs` | New file |
| `packages/ruby2js-rails/adapters/active_record_dexie.mjs` | Import CollectionProxy, update `_loadHasMany` |
| `packages/ruby2js-rails/adapters/active_record_sql.mjs` | Import CollectionProxy, update `_loadHasMany` |
| `lib/ruby2js/filter/rails/model.rb` | Update `generate_has_many_method` |
| `demo/blog/app/views/articles/_article.html.erb` | Restore `.size` |
| `test/blog/create-blog` | Restore `.size` in sed command |

## Estimated Effort

| Task | Time |
|------|------|
| Create CollectionProxy class | 2-3 hours |
| Update model filter | 1 hour |
| Update adapter eager loading | 1 hour |
| Testing and edge cases | 1-2 hours |
| **Total** | **~1 day** |

## Success Criteria

1. `article.comments.size` returns correct count
2. `article.comments.where(...)` returns scoped Relation
3. `article.comments.build(...)` creates record with FK set
4. `for (const c of article.comments)` iterates loaded records
5. Blog demo displays "(3 comments)" correctly with `.size`
