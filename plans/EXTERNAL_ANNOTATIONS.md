# External Annotations: Types and Directives for Unmodified Rails Apps

Companion plan to [FIZZY_BENCHMARK.md](./FIZZY_BENCHMARK.md). That plan covers transpilation correctness and runtime adapters. This plan covers the annotation layer needed to transpile **unmodified** Rails applications — no inline `# Pragma:` comments in source files.

---

## Problem

The pragma filter handles ambiguous Ruby operations (e.g., `x << y` could be array push, set add, or string concat) by inferring types from literals and constructors. This works when types are visible from local assignment, but fails for:

- Method parameters (no type info at all)
- Method return values (`x = foo()` — what type is x?)
- Instance variables assigned outside the current file
- Values flowing through association proxies or Rails helpers

Today, the escape hatch is `# Pragma: array` comments in the source file. For the "clone and eject" workflow, we need those annotations to live **outside** the source.

## Design

Two complementary mechanisms, both external to the application source:

### 1. RBS Files — Type Information (Layer 2)

Standard Ruby type format. Consumed by the pragma filter to populate `@var_types` / `@ivar_types`.

```
overlay/
  sig/
    app/
      models/
        card.rbs
        account.rbs
```

Example content:

```rbs
class Card
  @tags: Array[Tag]
  @assignments: Array[Assignment]

  def accessible_user_ids: () -> Array[Integer]
end
```

**Why RBS:**
- Standard format (ships with Ruby 3.0+)
- Tooling exists to generate them (`rbs_rails`, `typeprof`)
- Gems increasingly ship their own RBS definitions
- The `rbs` gem provides a proper parser — no need to roll our own
- Sorbet `T.let` is already supported; RBS is the other major type system

**What it replaces:** Inline `# Pragma: array`, `# Pragma: hash`, `# Pragma: set`, `# Pragma: entries` comments. These account for roughly a third of all pragmas in the selfhost codebase.

### 2. Directives in ruby2js.yml — Everything Else (Layer 3)

Method-level and file-level directives that don't fit a type system: skip, semantic overrides, deployment targets.

```yaml
# config/ruby2js.yml (extends existing format)
eject:
  output: ejected
  exclude:
    - app/models/ssrf_protection.rb
    - app/jobs/**/*.rb

directives:
  # Method-level skip (server-only methods in otherwise transpilable classes)
  Account.create_with_owner:
    skip: true
  Card#move_to_archive:
    skip: true

  # Semantic overrides
  Event::Description#card:
    nullish: true           # use ?? not || for memoization
  Card#accessible?:
    entries: true           # iterate hash with Object.entries()
```

**What it replaces:** Inline `# Pragma: skip`, `# Pragma: ??`, `# Pragma: entries`, etc. Addressed by `ClassName#method` or `ClassName.class_method`, which is stable across source edits (unlike line numbers).

### What Stays Inline

Expression-level pragmas within a method that mixes behaviors (e.g., a method with both logical-or and nullish-coalescing `||` usage). Expected to be very rare — perhaps 2-3 per large application. When encountered, options include:

- A single inline `# Pragma:` comment (minimal source modification)
- Refactoring the method to separate concerns (often a code quality win)
- A method-level blanket directive if one behavior dominates

---

## Implementation

### Phase 1: RBS Consumption

**Where it plugs in:** The pragma filter's `on_class` / `on_module` handlers already set up `@ivar_types` scopes. RBS consumption adds a step at class entry that pre-populates types from `.rbs` files.

1. Add an `rbs_dir` option (default: `sig/`) to Ruby2JS configuration
2. At startup, parse `.rbs` files using the `rbs` gem and build a type map:
   - `{ "Card" => { ivars: { "@tags" => :array }, methods: { "accessible_user_ids" => :array } } }`
3. In the pragma filter's `on_class`, merge RBS types into `@ivar_types`
4. For method return types, track in a new `@method_return_types` hash; use at call sites to infer variable types from assignment (`x = foo()`)
5. Map RBS types to pragma filter's internal symbols:
   - `Array[X]` → `:array`, `Hash[K,V]` → `:hash`, `Set[X]` → `:set`
   - `String` → `:string`, `Integer`/`Float` → `:number`
   - `Map[K,V]` → `:map`, `Proc` → `:proc`

**Testing:** Add specs that verify RBS-provided types produce the same disambiguation as inline pragmas.

### Phase 2: Method-Level Directives

**Where it plugs in:** The pragma filter's `scan_pragmas()` currently only reads `@comments[:_raw]`. Add a second source.

1. Add a `directives` key to the options hash, loaded from `ruby2js.yml`
2. In `scan_pragmas()`, also check `options[:directives]` keyed by method identifier
3. When entering `on_def` / `on_defs`, look up `"ClassName#method"` or `"ClassName.method"` in directives
4. Apply matching directives as if they were inline pragmas on the method body
5. `skip: true` → wrap method in `:hide` node (already supported by the skip pragma)

**Key detail:** The pragma filter needs to know the current class name. It already tracks this via scope management for `@ivar_types`. Reuse that context for directive lookup.

### Phase 3: Overlay Generation Tooling

A command that bootstraps an overlay for an existing Rails app:

```bash
npx juntos overlay --generate
```

Steps:
1. Run `rbs_rails` (if available) to generate RBS for models
2. Run `typeprof` (if available) on key files for additional type info
3. Scan for server-only patterns (files requiring non-transpilable gems, jobs, mailers)
4. Output a starter `sig/` directory and `directives:` section
5. Report what was auto-generated vs what needs manual review

This phase is optional — overlays can be hand-written. But generation dramatically lowers the barrier.

---

## Overlay for Fizzy

When the runtime work in FIZZY_BENCHMARK.md is far enough along that type/directive gaps are the bottleneck, the Fizzy overlay would look approximately like:

```
fizzy-overlay/
  ruby2js.yml            # directives + eject config
  sig/
    app/models/
      card.rbs            # ~24 ivars from concerns
      account.rbs
      board.rbs
      event.rbs
      filter/
        params.rbs        # tracks hash vs array in filter logic
      search/
        highlighter.rbs   # string mutation patterns
```

**Estimated scale** (speculative, based on current Fizzy code survey):
- ~20 RBS files, mostly generated, some hand-edited
- ~10-20 method directives (server-only methods, semantic overrides)
- ~0-5 inline pragmas for truly expression-level edge cases

The user experience: clone Fizzy, download the overlay, run `npx juntos eject`, get working JavaScript.

---

## Sequencing

This work depends on the FIZZY_BENCHMARK.md runtime phase being substantially complete. The order:

1. **Now:** Continue runtime adapter work (StandardError, has_rich_text, CurrentAttributes)
2. **When tests start passing:** Identify which failures are type-disambiguation issues vs missing adapters
3. **Phase 1:** Implement RBS consumption — likely the highest-value single change
4. **Phase 2:** Implement method-level directives — addresses skip and semantic overrides
5. **Phase 3:** Build overlay generation tooling — improves adoption UX
6. **Validate:** Create the Fizzy overlay and measure: how many files need inline pragmas?

---

## Open Questions

- **RBS for associations?** `rbs_rails` generates types for associations (`has_many :cards` → `cards: ActiveRecord::Relation[Card]`). Should we map `ActiveRecord::Relation[X]` to `:array` for disambiguation, or is that too lossy?
- **Gem-shipped RBS?** Ruby standard library and some gems ship RBS. Should we consume those automatically, or only project-local `sig/` files? (Automatic gives more coverage but adds complexity.)
- **Self-hosted converter?** RBS consumption requires the `rbs` gem (Ruby-side). The self-hosted JS converter can't use it. Options: pre-resolve RBS to a JSON type map at build time, or accept that the JS converter won't have RBS support.
- **Directive inheritance?** If `Card` includes `Taggable` concern, and `Taggable` has RBS types, should `Card` inherit them? This mirrors how the concern filter already composes behavior.
