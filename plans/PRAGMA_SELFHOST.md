# Pragma-Based Self-Hosting Plan

## Status: Proposed

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
├── pragma.rb              # Universal pragma handling (PR #257)
├── selfhost/
│   ├── core.rb            # Universal rules (~50 lines)
│   ├── converter.rb       # Converter handler patterns (~100 lines)
│   ├── walker.rb          # Prism::Visitor patterns (~50 lines)
│   └── spec.rb            # Minitest → JS test framework (~50 lines)
```

### Filter Responsibilities

#### `pragma.rb` (from PR #257)
Line-level control via comments:
- `# Pragma: ??` - nullish coalescing
- `# Pragma: function` - force traditional function syntax
- `# Pragma: guard` - null-guard splat arrays
- Plus new selfhost pragmas (see below)

#### `selfhost/core.rb` (~50 lines)
Universal transformations, always loaded:
- `s(:sym, ...)` → `s('sym', ...)` (symbols to strings in AST construction)
- `node.type == :sym` → `node.type === 'sym'` (type comparisons)
- Reserved word renaming (`var` → `var_`)
- `respond_to?(:type)` → type guard

#### `selfhost/converter.rb` (~100 lines)
For converter handler files:
- `handle :type do ... end` → `on_type = function() {...}`
- Class reopening → prototype assignments
- Serializer ivar access (`@sep`, `@nl`, etc.)

#### `selfhost/walker.rb` (~50 lines)
For the Prism walker:
- `class X < Prism::Visitor` → class with visit dispatch
- `visit_*_node` → `visitCamelCase` naming
- Remove `super` calls in visitor

#### `selfhost/spec.rb` (~50 lines)
For test specs:
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

### Phase 0: Prerequisites
- [x] PR #257 merged (pragma infrastructure)

### Phase 1: Create Filter Structure
1. Create `lib/ruby2js/filter/selfhost/` directory
2. Create `core.rb` with universal rules (extracted from current selfhost.rb)
3. Create empty `converter.rb`, `walker.rb`, `spec.rb` shells
4. Update `selfhost.rb` orchestration to use new filters

### Phase 2: Add Pragma Handlers
1. Add selfhost pragmas to `pragma.rb`:
   - `array`, `hash`, `string`
   - `method`, `self`
   - `proto`, `entries`
2. Each pragma: ~10-20 lines of handler code

### Phase 3: Strip Old Heuristics
1. Remove heuristic code from old `filter/selfhost.rb`
2. Keep only code that doesn't have a pragma equivalent
3. Target: <100 lines remaining

### Phase 4: Annotate Source Files
1. Run tests, identify failures
2. For each failure:
   - Find the source line
   - Add appropriate pragma
   - Verify fix
3. Track progress (should be fast - ~1 pragma per minute)

### Phase 5: Complete Test Suite
1. Converter tests (currently 130/248 = 52%)
2. Filter tests
3. Integration tests

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
