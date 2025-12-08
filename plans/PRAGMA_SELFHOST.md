# Pragma-Based Self-Hosting Plan

## Status: Phase 2 Complete (Walker Transpilation Working)

This document describes the pragma-based approach to self-hosting Ruby2JS.

## Philosophy

### Get It Working, Then Refactor

When implementing self-hosting, it's acceptable to:
1. Add functionality to selfhost filters to get things working
2. Identify patterns that apply beyond self-hosting
3. Refactor those patterns into general Ruby2JS functionality

**The selfhost filters should contain only transformations that are truly unique to self-hosting.** If a transformation would benefit other codebases, it belongs in a general-purpose filter.

### What Belongs in Selfhost Filters

Selfhost filters are for Ruby2JS-specific code patterns that wouldn't appear in normal user code:

- **walker.rb**: `private`/`protected`/`public` removal (walker uses these but Ruby2JS core errors on them in classes)
- **spec.rb**: `_()` wrapper removal (minitest expectation syntax)

### What Belongs in General Filters

Patterns that could appear in any Ruby codebase belong in general filters:

| Pattern | General Filter | Notes |
|---------|---------------|-------|
| `.freeze` removal | functions | No-op in JS |
| `.to_sym` removal | functions | Symbols are strings in JS |
| `.reject(&:method)` | functions | Common Ruby idiom |
| Negative index assignment | functions | `arr[-1] = x` |
| 2-argument slice | functions | `str[i, len]` |
| `.empty?` | functions | Already existed |
| Autoreturn for methods | return | Default filter |
| Skip statements | pragma | `# Pragma: skip` |

## Current Architecture

### Filter Structure

```
lib/ruby2js/filter/
├── pragma.rb              # Universal pragma handling (skip, etc.)
├── combiner.rb            # Merges reopened modules/classes
├── functions.rb           # Ruby method → JS equivalents
├── return.rb              # Autoreturn for methods
├── require.rb             # require/require_relative handling
├── selfhost.rb            # Orchestrator (loads all modules)
└── selfhost/
    ├── core.rb            # Empty shell (all moved to other filters)
    ├── walker.rb          # private/protected/public removal (~39 lines)
    ├── converter.rb       # handle :type do...end patterns (STUB)
    └── spec.rb            # _() wrapper removal (~39 lines)
```

### Implementation Status

| Component | Status | Lines | Purpose |
|-----------|--------|-------|---------|
| `pragma.rb` | Complete | ~280 | Type hints, skip statements |
| `combiner.rb` | Complete | ~150 | Module/class merging |
| `functions.rb` | Extended | ~800 | Ruby→JS method mapping |
| `return.rb` | Complete | ~50 | Method autoreturn |
| `require.rb` | Complete | ~200 | require→import |
| `selfhost/core.rb` | Empty | ~32 | Entry point only |
| `selfhost/walker.rb` | Complete | ~39 | Visibility removal |
| `selfhost/spec.rb` | Complete | ~39 | _() wrapper removal |
| `selfhost/converter.rb` | Stub | ~25 | To be implemented |

### Pragmas in Source Files

The walker source files (`lib/ruby2js/prism_walker.rb`, `lib/ruby2js/node.rb`) use minimal pragmas:

| Pragma | Usage | Purpose |
|--------|-------|---------|
| `# Pragma: skip` | `require` statements | Don't transpile external requires |
| `# Pragma: skip` | `def` statements | Skip methods not needed in JS |
| `# Pragma: skip` | `alias` statements | Skip Ruby-only aliases |

**Total pragmas in source: ~10-15** (not the 70-75 originally estimated)

## Walker Transpilation

### What Works

- Walker transpiles to valid JavaScript
- All 31 walker spec tests pass
- Node.js can parse and instantiate the transpiled code
- Core functionality (Node class, visitor methods) works

### Filter Chain for Walker

```ruby
filters: [
  Ruby2JS::Filter::Pragma,           # Handle # Pragma: skip
  Ruby2JS::Filter::Require,          # require → import
  Ruby2JS::Filter::Combiner,         # Merge reopened classes
  Ruby2JS::Filter::Selfhost::Core,   # (empty)
  Ruby2JS::Filter::Selfhost::Walker, # Remove private/protected/public
  Ruby2JS::Filter::Functions,        # Ruby methods → JS
  Ruby2JS::Filter::Return,           # Autoreturn for methods
  Ruby2JS::Filter::ESM               # ES module exports
]
```

### Options Used

```ruby
eslevel: 2022,
comparison: :identity,      # == → ===
underscored_private: true   # @foo → _foo
```

## Refactoring History

During walker implementation, several transformations were moved from selfhost filters to general filters:

1. **functions filter additions**:
   - `.freeze` → removed (no-op)
   - `.to_sym` → removed (symbols are strings)
   - `.reject(&:method)` → `.filter(x => !x.method)`
   - `arr[-1] = x` → `arr[arr.length - 1] = x`
   - `str[i, len]` → `str.slice(i, i + len)`

2. **pragma filter additions**:
   - `# Pragma: skip` now works on `def`, `defs`, `alias`

3. **Removed from selfhost**:
   - Autoreturn logic (use Return filter instead)
   - Symbol→string conversion (use core `comparison: :identity`)
   - `gem()` removal (removed `gem 'minitest'` from all specs)
   - `_()` wrapper moved to spec.rb

## Next Steps

### Phase 3: Converter Transpilation

1. Implement `selfhost/converter.rb`:
   - `handle :type do...end` pattern
   - Class reopening handling
2. Add pragmas to converter source files as needed
3. Create smoke tests for transpiled converter

### Phase 4: Spec Transpilation

1. Extend `selfhost/spec.rb`:
   - Minitest describe/it blocks → JS test framework
   - Assertion helpers
2. Transpile test suite to JavaScript
3. Run tests in Node.js

### Phase 5: Integration

1. Create browser demo with full converter
2. Document the self-hosting approach
3. Size comparison with Opal-based demo

## Success Criteria

- [x] Walker transpiles to valid JavaScript
- [x] Selfhost filters are minimal (<100 lines each)
- [x] Most transformations in general filters
- [x] Source files have minimal pragmas (<5 per file average)
- [ ] Converter transpiles to valid JavaScript
- [ ] Specs transpile and pass in Node.js
- [ ] Browser demo works

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

### Documentation Opportunity

Once self-hosting is complete, document this as a general methodology:

1. **"Dual-Target Ruby Development Guide"** - Patterns, anti-patterns, migration steps
2. **Pragma Reference** - When to use each pragma, with examples
3. **Project Templates** - Starter repos showing dual-target setup
4. **Lint Rules** - Catch non-transpilable patterns early

## References

- [PR #257: Pragma Filter](https://github.com/ruby2js/ruby2js/pull/257)
- [SELF_HOSTING.md](./SELF_HOSTING.md) - Original self-hosting plan
- [PRISM_WALKER.md](./PRISM_WALKER.md) - Prism AST translation
