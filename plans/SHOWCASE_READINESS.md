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

### 2a. `uniq` — no mapping, passes through silently ✅

Fixed. `uniq` → `[...new Set(a)]`, `uniq!` → `a.splice(0, a.length, ...new Set(a))`.

### 2b. `unshift` — already exists in JS with the same name

```ruby
arr.unshift(x)    # → arr.unshift(x)  — already valid JS!
```

Currently passes through untouched, which happens to be correct. **No fix needed** —
but confirm it works when chained.

**Used in:** Solo (`instructors`)

### 2c. `rotate` — no mapping ✅

Fixed. `rotate` → `[...a.slice(1), a[0]]`, `rotate(n)` → `[...a.slice(n), ...a.slice(0, n)]`.

---

## 3. Lint Enhancements ✅

### 3a. Detect methods with no JS equivalent ✅

No longer needed — `uniq` (2a) and `rotate` (2c) are now mapped. `sort_by`
without a block is already handled by the functions filter (uses `slice().sort()`
or `toSorted()` depending on ES level).

The `juntos lint` command already provides structural anti-pattern detection
(lint.mjs) and ambiguous-method warnings (pragma.rb).

### 3b. Detect incorrect `to_h` with block ✅

No longer needed — `to_h` with block is now correctly transpiled (1a).

### 3c. Detect `.map`/`.select`/`.each` chained after `group_by` ✅

No longer needed — `group_by` result is now type-inferred as `:hash`, which
triggers automatic `Object.entries()` wrapping (1b).

---

## 4. Adapter Gaps

### 4a. `arel_table` in scopes ✅

Fixed. Added `arel_table[:column]` detection in `transform_scope_body` in
`lib/ruby2js/filter/rails/model.rb`. The pattern `arel_table[:col]` is simplified
to the column name string `"col"`. E.g., `order(arel_table[:order])` → `this.order("order")`.

### 4b. Nested `includes` ✅

Already works. The adapter's `_loadAssociations` in `active_record_sql.mjs` handles
both flat strings and nested hash objects (`{ posts: ['comments', 'tags'] }`).
The transpiler correctly converts `includes(entry: [:lead, :follow])` to
`includes({entry: ["lead", "follow"]})`. **No fix needed.**

### 4c. Raw SQL in `where` / scopes ✅

Already works. The adapter's `where()` accepts raw SQL strings, and the SQL adapter
inserts them directly into the WHERE clause. `where('heat_id < 0')` works as-is.
**No fix needed.**

### 4d. `where.not` with ranges ✅

Already works. The adapter's `_buildRangeSQL` handles all range types including
beginless ranges. `where.not(number: ..0)` correctly generates `number > 0`.
**No fix needed.**

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

**Phase A — Fix bugs (blocks correctness): ✅ COMPLETE**
1. `to_h` with block (1a) ✅
2. `group_by` + chained enumerable (1b) ✅

**Phase B — Add missing methods (blocks compilation): ✅ COMPLETE**
3. `uniq` mapping (2a) ✅
4. `rotate` mapping (2c) ✅

**Phase C — Adapter gaps (blocks queries): ✅ COMPLETE**
5. `arel_table` simplification (4a) ✅ — transpiler fix in model filter
6. Nested `includes` (4b) ✅ — already supported
7. Raw SQL in `where` (4c) ✅ — already supported
8. `where.not` with ranges (4d) ✅ — already supported

**Phase D — Lint improvements (prevents regressions): ✅ COMPLETE**
9. Missing-method detection (3a) ✅ — resolved by Phase B fixes
10. Incorrect `to_h` / `group_by` detection (3b, 3c) ✅ — resolved by Phase A fixes

**Phase E — Integration testing:**
11. Transpile all 12 models, syntax-check output
12. Test recursive lambda scoring algorithms with real event data
13. Test `super` in column accessors against adapter

Phases A–C are complete. Phase D improves the developer experience for all
future Juntos users, not just this pilot.
