# Pragma-Based Self-Hosting Plan

## Status: In Progress

This document describes a new approach to self-hosting Ruby2JS that replaces the current
heuristic-based `filter/selfhost.rb` with a pragma-based system.

## Background

### Current Approach Problems

The current `filter/selfhost.rb` is **1,249 lines** of heuristic code that tries to infer
intent from context:

```ruby
# Example: Guessing if << is for arrays or strings based on variable name
if method == :<< && args.length == 1 && target
  var_name = case target.type
    when :ivar then target.children[0].to_s.sub('@', '')
    when :lvar then target.children[0].to_s
  end
  if var_name == 'vars'  # Guess: "vars" is a Hash
    # ... one behavior
  else  # Guess: everything else is an Array
    # ... different behavior
  end
end
```

**Problems with this approach:**
- Each fix risks breaking other things (heuristics interact unpredictably)
- Hard to debug (why did this variable get treated as X?)
- Fragile (rename a variable and behavior changes)
- Large codebase (~1,250 lines filter + ~440 lines hand-written JS preamble)
- Slow progress (~52% tests passing after significant effort)

### Pragma Approach Benefits

Instead of inferring, **declare intent explicitly**:

```ruby
# In source file
result = []  # Pragma: array
result << child  # Now unambiguous: becomes result.push(child)
```

**Benefits:**
- **Linear progress** - each pragma fixes one thing
- **No regressions** - fixes don't break other fixes
- **Clear debugging** - see the pragma, know the behavior
- **Smaller codebase** - ~250 lines of filter code total
- **Fast progress** - estimated 3-5x faster to completion

## Architecture

### Filter Split

Instead of one monolithic filter, use focused filters for each context:

```
lib/ruby2js/filter/
├── pragma.rb              # Universal pragma handling ✓ IMPLEMENTED
├── combiner.rb            # Merges reopened modules/classes ✓ IMPLEMENTED
├── selfhost.rb            # Orchestrator (loads all modules) ✓ IMPLEMENTED
└── selfhost/
    ├── core.rb            # Universal rules ✓ IMPLEMENTED (~150 lines)
    ├── walker.rb          # Prism::Visitor patterns ✓ IMPLEMENTED (~180 lines)
    ├── converter.rb       # Converter handler patterns (STUB)
    └── spec.rb            # Minitest → JS test framework (STUB)
```

### Current Implementation Status

| Component | Status | Lines | Notes |
|-----------|--------|-------|-------|
| `pragma.rb` | ✓ Complete | ~280 | Type disambiguation, behavior pragmas |
| `combiner.rb` | ✓ Complete | ~150 | Merges reopened modules/classes |
| `selfhost/core.rb` | ✓ Complete | ~150 | Reserved words, sym→str conversion |
| `selfhost/walker.rb` | ✓ Complete | ~180 | Walker-specific transforms |
| `selfhost/converter.rb` | Stub | ~25 | To be implemented |
| `selfhost/spec.rb` | Stub | ~25 | To be implemented |

### Filter Responsibilities

#### `pragma.rb` ✓ IMPLEMENTED
Line-level control via comments:
- `# Pragma: ??` - nullish coalescing
- `# Pragma: function` - force traditional function syntax
- `# Pragma: guard` - null-guard splat arrays
- `# Pragma: array/hash/string` - type disambiguation
- `# Pragma: method/self/proto/entries` - behavior control
- `# Pragma: skip` - skip require statements

#### `selfhost/core.rb` ✓ IMPLEMENTED
Universal transformations for all selfhost targets:
- `s(:sym, ...)` → `s('sym', ...)` (symbols to strings in AST construction)
- `node.type == :sym` → `node.type === 'sym'` (type comparisons)
- `%i[...].include?(x)` → `['...'].includes(x)` (symbol arrays)
- Reserved word renaming (`var` → `var_`)
- Remove `private/protected/public` declarations

#### `selfhost/walker.rb` ✓ IMPLEMENTED
For the Prism walker transpilation:
- `arr[-1] = x` → `arr[arr.length - 1] = x` (negative indexing)
- `str[i, len]` → `str.slice(i, i + len)` (2-arg slice)
- `.to_sym`, `.freeze` → removed (no-op in JS)
- `.empty?` → `.length == 0`
- `.reject {}` → `.filter {}` with negated condition
- Remove Ruby-specific methods (respond_to?, is_a?, etc.)
- Skip external requires (prism, node)

#### `selfhost/converter.rb` (STUB)
For converter handler files (to be implemented):
- `handle :type do ... end` → method definitions
- Class reopening → merged class definitions
- Serializer ivar access (`@sep`, `@nl`, etc.)

#### `selfhost/spec.rb` (STUB)
For test specs (to be implemented):
- `describe X do ... end` → `describe('X', () => {...})`
- `it 'text' do ... end` → `it('text', () => {...})`
- `_(x).must_equal(y)` → assertion

## Pragmas

### Existing (PR #257)

| Pragma | Effect |
|--------|--------|
| `??` / `nullish` | `\|\|` → `??`, `\|\|=` → `??=` |
| `noes2015` / `function` | Arrow functions → traditional `function` |
| `guard` | `[*a]` → `a ?? []` (null-safe splat) |

### New for Selfhost

#### Type Disambiguation

| Pragma | Example | Output |
|--------|---------|--------|
| `array` | `arr << x # Pragma: array` | `arr.push(x)` |
| `hash` | `h.dup # Pragma: hash` | `Object.assign({}, h)` |
| `string` | `s << x # Pragma: string` | `s + x` |

#### Method Call Control

| Pragma | Example | Output |
|--------|---------|--------|
| `method` | `foo # Pragma: method` | `foo()` (not getter) |
| `self` | `put(x) # Pragma: self` | `this.put(x)` |

#### Structure

| Pragma | Example | Output |
|--------|---------|--------|
| `proto` | `class Foo # Pragma: proto` | Methods → prototype assignments |
| `entries` | `hash.each {...} # Pragma: entries` | `Object.entries(hash).forEach(...)` |

### Pragma Density

Estimated pragma annotations needed:
- **File-level**: ~45 (one `# Pragma: proto` per handler file)
- **Line-level**: ~25-30 (ambiguous `<<`, `.dup`, hash iteration)
- **Total**: ~70-75 pragmas across ~4,867 lines (~1.5%)

Most files will have 1-3 pragmas. Source files will **not** be dominated by pragmas.

## Implementation Plan

### Phase 0: Prerequisites ✓ COMPLETE
- [x] PR #257 merged (pragma infrastructure)

### Phase 1: Create Filter Structure ✓ COMPLETE
- [x] Create `lib/ruby2js/filter/selfhost/` directory
- [x] Create `core.rb` with universal rules
- [x] Create `walker.rb` with walker-specific transforms
- [x] Create stub `converter.rb`, `spec.rb` shells
- [x] Update `selfhost.rb` as orchestrator

### Phase 2: Walker Transpilation ✓ COMPLETE
- [x] Add pragma handlers (array, hash, string, method, self, proto, entries, skip)
- [x] Implement walker-specific transforms (negative indexing, 2-arg slice, etc.)
- [x] Create smoke tests (`spec/selfhost_walker_spec.rb`)
- [x] Walker transpiles to valid JavaScript (31 tests pass)

### Phase 3: Converter Transpilation (NEXT)
1. Implement `selfhost/converter.rb`:
   - `handle :type do...end` pattern
   - Class reopening handling
   - Serializer ivar access
2. Add pragmas to converter source files as needed
3. Create smoke tests for transpiled converter

### Phase 4: Spec Transpilation (FUTURE)
1. Implement `selfhost/spec.rb`:
   - Minitest describe/it blocks
   - Assertion helpers
2. Transpile test suite to JavaScript
3. Run tests in Node.js

### Phase 5: Integration (FUTURE)
1. Create browser demo with full converter
2. Document the self-hosting approach
3. Size comparison with Opal-based demo

## Migration Strategy

### What We Keep
- PR #257 pragma infrastructure
- Test suite (unchanged)
- Transpilation pipeline (`selfhost.rb` orchestration)
- Knowledge of patterns from current implementation

### What We Discard
- Most of `filter/selfhost.rb` (~1,200 lines)
- Hand-written JS preamble (~400 lines) - regenerate as needed

### What We Build
- ~150 lines of pragma handlers
- ~50 lines per specialized filter (4 filters = ~200 lines)
- ~70-75 pragma annotations in source files

## Size Comparison

| Component | Current | With Pragmas |
|-----------|---------|--------------|
| `filter/selfhost.rb` | 1,249 lines | ~100 lines |
| Specialized filters | 0 | ~200 lines |
| JS preamble | 440 lines | ~50 lines |
| Pragma handlers | 0 | ~150 lines |
| **Total filter code** | **~1,700 lines** | **~500 lines** |
| Source annotations | 0 | ~75 pragmas |

**~70% reduction** in filter code complexity.

## Timeline Estimate

| Phase | Estimated Time |
|-------|---------------|
| Phase 1: Filter structure | 2-4 hours |
| Phase 2: Pragma handlers | 4-6 hours |
| Phase 3: Strip heuristics | 2-3 hours |
| Phase 4: Annotate sources | 4-8 hours |
| Phase 5: Complete tests | 4-8 hours |
| **Total** | **16-29 hours** |

Compare to continuing current approach: **40+ hours** estimated to reach 100%.

## Success Criteria

- [ ] All converter tests pass (248/248)
- [ ] All filter tests pass
- [ ] `filter/selfhost.rb` < 100 lines
- [ ] Total selfhost filter code < 500 lines
- [ ] Each source file has < 5 pragmas on average
- [ ] No hand-written JS classes (Token, Line, Serializer transpile cleanly)

## Risks and Mitigations

### Risk: Pragmas become cluttered
**Mitigation:** Most patterns have universal rules. Only truly ambiguous cases need pragmas.
Analysis shows ~1.5% pragma density.

### Risk: New pragma types needed
**Mitigation:** Pragma infrastructure is extensible. Adding a new pragma is ~10-20 lines.

### Risk: Pragmas affect Ruby behavior
**Mitigation:** Pragmas are comments - zero impact on Ruby execution. Only affect JS output.

## Generalization: Dual-Target Ruby Development

While developed for self-hosting Ruby2JS, this pragma-based approach is **generalizable** to any
project that wants to maintain a single Ruby codebase that runs in both Ruby and JavaScript.

### The Dual-Target Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│                    Single Ruby Source                           │
│    (with pragma annotations for JS-incompatible patterns)       │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
    ┌─────────────────┐             ┌─────────────────┐
    │  Ruby Runtime   │             │  Ruby2JS with   │
    │  (pragmas are   │             │  pragma filter  │
    │   just comments)│             │                 │
    └─────────────────┘             └─────────────────┘
              │                               │
              ▼                               ▼
    ┌─────────────────┐             ┌─────────────────┐
    │  Ruby Behavior  │             │  JS Behavior    │
    │  (server-side)  │             │  (browser/node) │
    └─────────────────┘             └─────────────────┘
```

### Use Cases

1. **Shared business logic** - Validation rules, calculations, data transformations
2. **Universal libraries** - Date handling, formatting, parsing utilities
3. **Isomorphic applications** - Same code on server (Ruby) and client (JS)
4. **Gradual migration** - Move from Ruby to JS incrementally
5. **Cross-platform tools** - CLI (Ruby) and browser (JS) versions

### Why Pragmas Work for Dual-Targeting

- **Zero Ruby impact** - Pragmas are comments; Ruby behavior unchanged
- **Explicit over implicit** - No guessing about types or intent
- **Incremental** - Add pragmas only where needed
- **Documented** - Pragmas serve as inline documentation of JS behavior
- **Testable** - Same tests run against both Ruby and transpiled JS

### Pragma Applicability Analysis

All proposed pragmas have general utility beyond self-hosting:

| Pragma | Selfhost Use | General Use Case |
|--------|--------------|------------------|
| `array` | Mark `<<` target as array | Any code with ambiguous `<<` |
| `hash` | Mark `.dup` target as hash | Rails apps, data processing |
| `string` | Mark `<<` target as string | Template building, logging |
| `entries` | Hash iteration | Any hash `.each` in shared code |
| `method` | Force `()` on call | Side-effect methods as properties |
| `self` | Add `this.` prefix | Class methods calling siblings |
| `proto` | Class reopening → prototype | Monkey-patching shared classes |
| `nullish` | `\|\|` → `??` | Form defaults, API responses |
| `function` | Arrow → function | DOM callbacks, jQuery handlers |
| `guard` | Null-safe splat | External API data handling |

**None of these pragmas are truly selfhost-specific.** Each addresses a fundamental
Ruby-to-JavaScript semantic gap that any dual-target project would encounter.

### Documentation Opportunity

The pragma system could be documented as a general methodology:

1. **"Dual-Target Ruby Development Guide"** - Patterns, anti-patterns, migration steps
2. **Pragma Reference** - When to use each pragma, with examples
3. **Project Templates** - Starter repos showing dual-target setup
4. **Lint Rules** - Catch non-transpilable patterns early

### Incompatible Patterns (No Pragma Solution)

Some Ruby patterns cannot be dual-targeted:

| Pattern | Why Not |
|---------|---------|
| `method_missing` | No JS equivalent for runtime method synthesis |
| `define_method` at runtime | Static transpilation can't capture dynamic definitions |
| `eval` with dynamic strings | Security and static analysis concerns |
| File I/O | Platform-specific APIs |
| Threading | Different concurrency models |
| C extensions | No JS equivalent |

Projects wanting dual-target support should avoid these patterns in shared code.

## References

- [PR #257: Pragma Filter](https://github.com/ruby2js/ruby2js/pull/257)
- [SELF_HOSTING.md](./SELF_HOSTING.md) - Original self-hosting plan
- [PRISM_WALKER.md](./PRISM_WALKER.md) - Prism AST translation
