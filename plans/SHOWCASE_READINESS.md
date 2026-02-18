# Showcase Readiness: Ruby2JS Fixes Before Pilot

Preparation work in ruby2js needed before starting the showcase scoring pilot.
See `plans/SHOWCASE_SCORING_PILOT.md` for the pilot itself.

Based on analysis of the 12 in-scope showcase models: Heat, Score, Entry, Person,
Dance, Category, Judge, Solo, Event, Age, Level, Studio.

---

## 1. Bugs (incorrect transpilation)

### 1a. `to_h` with block produces wrong output ✅

Fixed. Added `on_block` handler for `to_h` in `lib/ruby2js/filter/functions.rb`.
Now generates `Object.fromEntries(arr.map(k => [k, 1]))`.

### 1b. `group_by { }.map { }` chain produces Object, then calls `.map` on it

```ruby
scores.group_by { |s| s.heat_id }.map { |k, v| [k, v.count] }
```
`group_by` transpiles to `.reduce(...)` which returns a plain Object. The chained
`.map` then calls `Object.prototype.map` which is `undefined`.

**Used in:** Heat (`rank_placement`, `rank_summaries`), Dance (`scrutineering`)

**Fix in:** `lib/ruby2js/filter/functions.rb` — when `map`, `select`, `each`, etc.
are chained after `group_by`, wrap the receiver in `Object.entries()`. Alternatively,
make `group_by` return `Object.entries` format when it detects a chained enumerable.

**Status:** ✅ Fixed. Added `group_by` to `infer_type` in `lib/ruby2js/filter/pragma.rb`
(returns `:hash`). The pragma filter's existing hash-iteration handler now wraps
`group_by` results with `Object.entries()` automatically when chained with
`.map { |k, v| }`, `.select { |k, v| }`, `.each { |k, v| }`, etc.

---

## 2. Missing Method Mappings (easy)

### 2a. `uniq` — no mapping, passes through silently

```ruby
items.uniq        # → [...new Set(items)]
items.uniq!       # → items = [...new Set(items)]  (or splice-based)
```

**Used in:** Heat (`partners`), Person (`active`), Dance (`scrutineering`)

**Fix in:** `lib/ruby2js/filter/functions.rb`

### 2b. `unshift` — already exists in JS with the same name

```ruby
arr.unshift(x)    # → arr.unshift(x)  — already valid JS!
```

Currently passes through untouched, which happens to be correct. **No fix needed** —
but confirm it works when chained.

**Used in:** Solo (`instructors`)

### 2c. `rotate` — no mapping

```ruby
arr.rotate         # → [...arr.slice(1), arr[0]]
arr.rotate(n)      # → [...arr.slice(n), ...arr.slice(0, n)]
```

**Used in:** Person (`display_name`) — `name.split(/,\s*/).rotate.join(' ')`

**Fix in:** `lib/ruby2js/filter/functions.rb`

---

## 3. Lint Enhancements

### 3a. Detect methods with no JS equivalent

Add structural lint rules for Ruby methods that pass through silently but will
fail at runtime:

- `uniq` (until 2a is fixed)
- `rotate` (until 2c is fixed)
- `sort_by` without a block (Ruby sorts ascending by default; JS `.sort()` is lexicographic)

These are more valuable than the ambiguous-method warnings because the failure
is guaranteed, not type-dependent.

### 3b. Detect incorrect `to_h` with block

Until bug 1a is fixed, lint should flag `to_h` calls that have a block argument.

### 3c. Detect `.map`/`.select`/`.each` chained after `group_by`

Until bug 1b is fixed, lint should flag enumerable methods called on the result
of `group_by`.

---

## 4. Adapter Gaps

### 4a. `arel_table` in scopes

Four models use `arel_table` for ordering:
```ruby
scope :ordered, -> { order(arel_table[:order]) }
scope :by_name, -> { order(arel_table[:name]) }
```

The adapters don't support Arel. Options:
- **Rewrite in showcase** to `order(:order)` / `order(:name)` — simplest
- **Transpiler fix**: detect `arel_table[:col]` pattern and simplify to column name
- **Adapter support**: teach the SQL adapter to handle `{column: 'asc'}` objects

**Recommendation:** Transpiler fix — `arel_table[:col]` is a common Rails idiom
for avoiding SQL keyword conflicts (e.g., `order` is both a column and SQL keyword).
Detect in the model filter and emit the column name as a string.

### 4b. Nested `includes`

```ruby
heats.includes(entry: [:lead, :follow])
```

The adapter currently supports flat `includes(:scores, :entry)` but not nested
hash syntax for eager-loading through associations.

**Used in:** Dance (`scrutineering`), various query chains

**Fix in:** `packages/ruby2js-rails/adapters/relation.mjs` — extend `includes()`
to accept hash arguments and resolve nested associations.

### 4c. Raw SQL in `where` / scopes

```ruby
scope :category_scores, -> { where('heat_id < 0') }
Score.where(heat: heats)  # association-based where
```

String-based `where` conditions need the SQL adapter to parse simple expressions.
Association-based `where` (passing an ActiveRecord relation or collection) needs
adapter support for `IN` clause generation.

**Used in:** Score (scopes), Dance (`scrutineering`), Category (`is_spacer?`)

### 4d. `where.not` with ranges

```ruby
.where.not(number: ..0)
```

The `where.not` chain transpiles correctly. The adapter's `not()` method exists.
But beginless ranges as condition values need adapter-level handling to generate
`number > 0` SQL.

---

## 5. Model Filter Gaps (lower priority for read path)

These matter for writes or validation but not for the pilot's read-heavy scoring path:

| Gap | Models | Priority |
|-----|--------|----------|
| `normalizes` | Person, Dance, Category, Studio | Low — read path only |
| `validates_associated` | Heat | Low — no validation in browser |
| `accepts_nested_attributes_for` | Person | Low — admin write path |
| `has_one_attached` (Active Storage) | Solo, Event | Low — files stay on server |
| Callback conditions (`if: -> { ... }`) | Event, Solo | Medium — may need for write-back |

---

## 6. Edge Cases (likely OK but need testing)

### 6a. Recursive lambdas

```ruby
runoff = lambda do |entries, examining, focused = false|
  # ... complex logic ...
  runoff.call(entries, examining + 1, true)
end
```

Should transpile to `let runoff = (entries, examining, focused=false) => { ... runoff(...) }`.
JS closures capture `let` bindings correctly, so the recursion should work.
**Needs integration test with real data.**

**Used in:** Heat `rank_placement`, `rank_summaries` (the core scoring algorithms)

### 6b. `super` in column accessor overrides

```ruby
def number
  value = super  # reads the raw column value
  value.to_i == value ? value.to_i : value
end
```

In the adapter, column values come from the instance attribute hash, not a
superclass method. The transpiled `super.number` may not resolve correctly.

**Fix:** May need adapter to provide `getAttribute(name)` or ensure `super`
property access works on the base model class.

### 6c. `value.to_i == value` type check

Ruby distinguishes `1` (Integer) from `1.0` (Float). JS doesn't.
`value.to_i == value` is used to decide whether to display "1" vs "1.5".
JS equivalent: `Number.isInteger(value)`.

The functions filter maps `to_i` to `parseInt()`, so this becomes
`parseInt(value) == value` which happens to work for this case. **Probably OK.**

### 6d. `association(:extensions).loaded?`

```ruby
cat.association(:extensions).loaded?
```

Rails introspection API for checking if an association is eager-loaded.
No adapter equivalent. Used in Heat `dance_category` to avoid N+1.

**Workaround:** In the browser, all data is local (SQLite WASM), so there's no
N+1 problem. Could stub `association().loaded?` to always return `false` and let
the query execute.

---

## Suggested Order of Work

**Phase A — Fix bugs (blocks correctness):**
1. `to_h` with block (1a)
2. `group_by` + chained enumerable (1b)

**Phase B — Add missing methods (blocks compilation):**
3. `uniq` mapping (2a)
4. `rotate` mapping (2c)

**Phase C — Adapter gaps (blocks queries):**
5. `arel_table` simplification (4a)
6. Nested `includes` (4b)
7. Raw SQL in `where` (4c)

**Phase D — Lint improvements (prevents regressions):**
8. Missing-method detection (3a)
9. Incorrect `to_h` detection (3b)

**Phase E — Integration testing:**
10. Transpile all 12 models, syntax-check output
11. Test recursive lambda scoring algorithms with real event data
12. Test `super` in column accessors against adapter

Phase A and B are prerequisites. Phase C may be partially worked around by
rewriting a few scopes in the showcase app. Phase D improves the developer
experience for all future Juntos users, not just this pilot.
