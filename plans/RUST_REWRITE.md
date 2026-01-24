# Plan: Rust Rewrite of Ruby2JS

## Summary

Rewrite the Ruby2JS transpiler core in Rust, producing a single codebase that compiles to native binaries, WASM (for browser/Node.js), and potentially native Vite/Rolldown plugins. This is a strategic investment as the JavaScript tooling ecosystem has consolidated around Rust.

**Timeline:** Re-evaluate when Vite 8 reaches stable and Rust plugin documentation is available (likely mid-2026). Rolldown is already in RC and powers Vite 8 Beta.

## Status

**Planning** — Not yet started. This document captures analysis and framing for future execution.

---

## Ecosystem Status (January 2026)

The Rust tooling transition is further along than anticipated:

| Component | Status | Notes |
|-----------|--------|-------|
| **Rolldown** | RC (Release Candidate) | Powers Vite 8 Beta |
| **Vite 8** | Beta (Dec 2025) | First Rolldown-powered release |
| **Oxc** | Integrated | Compiler toolchain, native plugins enabled by default |
| **Native Vite plugins** | In production | Internal plugins converted to Rust |

### Performance Results

Early adopters report significant gains:
- Linear: Build time reduced from 46s → 6s
- Rolldown is 10-30x faster than Rollup
- Memory usage reduced up to 100x in some cases

### Plugin API Status

- Rolldown has a Rollup-compatible JavaScript plugin API
- Several internal Vite plugins have been converted to native Rust
- Native plugins are enabled by default in Vite 8
- Custom Rust plugin API for external developers: documentation pending

### Implications

The "Rolldown 1.0" trigger point is closer than initially assumed. Vite 8 stable release (expected early-mid 2026) would be a natural evaluation point for this work.

---

## Strategic Rationale

### Why Rust?

The JavaScript tooling ecosystem has moved to Rust:

| Tool | Legacy | Current |
|------|--------|---------|
| Vite bundler | Rollup (JS) | Rolldown (Rust) — in Vite 8 |
| Transpilation | Babel (JS) | SWC/oxc (Rust) |
| Linting | ESLint (JS) | Biome/oxc (Rust) |
| Parsing | Various | Prism (C), oxc (Rust) |

Ruby2JS's goal is to make Rails a first-class citizen in the JavaScript ecosystem. Being implemented in Rust aligns with where that ecosystem now is.

### Why Not Now?

The current implementation works:
- JavaScript selfhost is functional and integrated with Vite
- Juntos delivers value today
- No immediate performance bottleneck
- Vite 8 is still in beta; Rust plugin API not yet documented for external developers

This is a "when, not if" decision—documented and ready to execute when the time is right. The ecosystem is moving faster than expected; re-evaluate when Vite 8 stabilizes.

### Single Codebase, Multiple Targets

A Rust implementation eliminates the need for multiple codebases:

| Current | With Rust |
|---------|-----------|
| Ruby implementation (canonical) | Single Rust codebase |
| JavaScript selfhost (transpiled from Ruby) | Compiles to WASM for JS environments |
| — | Compiles to native for CLI |
| — | Potential native Rolldown plugin |

The "selfhost" concept becomes unnecessary—you just compile to WASM for JavaScript environments.

---

## Feasibility Analysis

### Key Enabler: Prism Has Rust Bindings

The hardest part of any transpiler—parsing—is already solved:

- **Prism** is written in C with official bindings for Rust (`ruby-prism` crate)
- Ruby2JS already uses Prism for parsing
- The Rust implementation would use the same parser, ensuring AST compatibility

### What Needs to Be Implemented in Rust

1. **Converter handlers** (~60 handlers in `lib/ruby2js/converter/`)
   - Each Ruby AST node type → JavaScript output
   - Pattern: `match` arms or trait implementations

2. **Filters** (~23 filters in `lib/ruby2js/filter/`)
   - AST transformations before conversion
   - Pattern: Visitor pattern, well-established in Rust

3. **Serializer** (`lib/ruby2js/serializer.rb`)
   - Output formatting, indentation
   - Straightforward string building

4. **Configuration and options**
   - ES level selection
   - Filter chain configuration
   - Output options

### What Carries Forward

- **Test suite** — Input/output pairs are language-agnostic; same tests verify Rust implementation
- **Design** — Handler-per-node, filter chain, visitor patterns all translate cleanly to Rust
- **Documentation** — User-facing behavior unchanged

### Rust Advantages

- **Type system** catches errors that Ruby/JS discover at runtime
- **Pattern matching** is more expressive than Ruby's `case` or JS's `switch`
- **Explicit ownership** makes data flow clearer
- **Performance** is predictable and fast

---

## Implementation Approach

### Phase 0: Proof of Concept

**Goal:** Validate that Prism Rust bindings work and basic conversion is tractable.

**Scope:**
- Parse Ruby source using `ruby-prism` crate
- Convert minimal subset: literals, assignments, binary operations
- Output: `x = 1 + 2` → `let x = 1 + 2`

**Deliverable:** Working Rust binary that transpiles basic expressions.

**Effort:** 1-2 days

### Phase 1: Core Converter

**Goal:** Implement the most common AST node handlers.

**Scope (priority order):**
1. `send` — Method calls, operators (highest frequency)
2. `lvasgn`, `ivasgn`, `cvasgn`, `gvasgn` — Variable assignments
3. `def`, `defs` — Method definitions
4. `class`, `module` — Class/module definitions
5. `if`, `case`, `while`, `for` — Control flow
6. `array`, `hash` — Data structures
7. `block`, `lambda` — Blocks and lambdas
8. `str`, `dstr`, `sym`, `dsym` — Strings and symbols
9. `const`, `casgn` — Constants
10. Remaining handlers

**Deliverable:** Rust converter that handles ~80% of real-world Ruby code.

**Effort:** 1-2 months

### Phase 2: Filters

**Goal:** Implement the filter system and key filters.

**Scope (priority order):**
1. Filter architecture (chain, options, state)
2. `functions` filter — Ruby method → JS equivalent mappings
3. `esm` filter — ES6 module imports/exports
4. `camelCase` filter — Naming convention conversion
5. `return` filter — Implicit return handling
6. Remaining filters as needed for Juntos

**Deliverable:** Filter chain matching Ruby implementation behavior.

**Effort:** 1-2 months

### Phase 3: Bindings and Integration

**Goal:** Make the Rust implementation usable from JavaScript and as a CLI.

**Scope:**
1. **WASM compilation** — `wasm-pack` build for browser/Node.js
2. **JavaScript wrapper** — Thin JS API matching current selfhost
3. **CLI binary** — Native `ruby2js` command
4. **Vite plugin compatibility** — Drop-in replacement for selfhost

**Deliverable:** `ruby2js.wasm` + JS wrapper that passes existing integration tests.

**Effort:** 2-4 weeks

### Phase 4: Parity and Validation

**Goal:** Achieve full compatibility with Ruby implementation.

**Scope:**
1. Run full test suite against Rust implementation
2. Fix edge cases and discrepancies
3. Benchmark performance comparison
4. Document any intentional differences

**Deliverable:** Rust implementation passes all tests, documented performance characteristics.

**Effort:** 1 month

### Phase 5: Rolldown Native Plugin

**Goal:** Native Rust plugin for Vite's Rolldown bundler.

**Scope:**
- Implement Rolldown's Rust plugin API
- Direct Rust-to-Rust integration, no WASM overhead
- Benchmark vs WASM approach

**Status (Jan 2026):** Rolldown is in RC, internal Vite plugins have been converted to native Rust, but external Rust plugin API documentation is not yet available. The Rollup-compatible JS plugin API works now.

**Timing:** Begin when Rust plugin documentation is available for external developers. WASM approach (Phase 3) provides a working solution in the interim.

---

## Effort Estimate

| Phase | Effort | Cumulative |
|-------|--------|------------|
| Phase 0: PoC | 1-2 days | 1-2 days |
| Phase 1: Core converter | 1-2 months | 1-2 months |
| Phase 2: Filters | 1-2 months | 2-4 months |
| Phase 3: Bindings | 2-4 weeks | 3-5 months |
| Phase 4: Parity | 1 month | 4-6 months |

**Total: 3-6 months** focused effort, or **6-9 months** part-time.

This is bounded: "more than a week, less than a year."

---

## Trigger Points

Consider starting this work when any of these occur:

1. **Vite 8 Stable + Rust Plugin Docs** — When Vite 8 reaches stable and documentation exists for writing custom Rust plugins (not just JS-compatible plugins). Currently in beta as of Dec 2025.
2. **Performance bottleneck** — Large Juntos projects hit transpilation speed limits
3. **Major refactor needed** — Combine efforts with other significant changes
4. **Natural pause** — Between major Juntos milestones
5. **Contributor interest** — Someone with Rust expertise wants to contribute

**Timeline note:** Given Vite 8 beta released Dec 2025, stable release likely early-mid 2026. This could accelerate the timeline from "2-3 year horizon" to "evaluate in 2026."

The current JS selfhost implementation continues to work regardless—Rolldown's Rollup-compatible plugin API means existing Vite integration is unaffected.

---

## Risks and Mitigations

### Risk: Rust learning curve limits contributions

**Mitigation:**
- LLMs significantly lower the barrier to Rust contribution
- Rust is growing in popularity; more developers will know it over time
- The Ruby2JS audience (Ruby developers) increasingly overlaps with systems programming interest

### Risk: Rewrite takes longer than estimated

**Mitigation:**
- Comprehensive test suite defines expected behavior
- Phase 0 PoC validates feasibility before committing
- Can ship incrementally (Phase 1 alone is useful)

### Risk: Two implementations drift during transition

**Mitigation:**
- Same test suite for both implementations
- Can run comparison tool during development
- Once Rust passes all tests, Ruby version becomes reference-only

### Risk: Rolldown Rust plugin API not available or changes

**Mitigation:**
- Phase 5 (native Rolldown integration) is optional
- WASM approach works regardless of Rolldown API—Rolldown supports Rollup-compatible JS plugins
- Internal Vite plugins already use native Rust, so the capability exists
- Wait for external developer documentation before Phase 5

---

## What Doesn't Change

- **User-facing behavior** — Same Ruby input produces same JavaScript output
- **Juntos architecture** — Filters, adapters, targets remain conceptually identical
- **Documentation** — User guides still apply
- **Test cases** — Same expected inputs/outputs

---

## Preparatory Steps (Do Anytime)

These low-effort tasks make the future transition easier:

1. **Test suite completeness** — Ensure edge cases are covered; tests become the specification
2. **AST transformation documentation** — Capture the "why" of tricky conversions while context is fresh
3. **Monitor Vite 8 / Rolldown** — Track stable release and Rust plugin API documentation
4. **Prism Rust bindings familiarity** — Experiment with `ruby-prism` crate when convenient
5. **Watch Rolldown GitHub** — [github.com/rolldown/rolldown](https://github.com/rolldown/rolldown) for plugin API discussions

---

## Decision Record

### 2026-01-24: Initial Analysis

**Context:** Discussed feasibility and timing of Rust rewrite.

**Decision:** Document plan but do not start implementation. Current JS selfhost is sufficient. Rust rewrite is strategic investment.

**Rationale:**
- No immediate forcing function
- Current implementation delivers value
- Ecosystem direction (Vite → Rolldown) validates long-term strategy
- Bounded effort (3-6 months) is acceptable when timing is right

**Ecosystem status update:** Discovered Rolldown is further along than expected—RC status, powering Vite 8 Beta (Dec 2025). This shortens the timeline from "2-3 year horizon" to "re-evaluate when Vite 8 stable releases and Rust plugin documentation is available" (likely mid-2026).

---

## References

### Internal
- `demo/selfhost/` — Current JavaScript selfhost implementation
- `lib/ruby2js/converter/` — Converter handlers to port
- `lib/ruby2js/filter/` — Filters to port
- `spec/` — Test suite (becomes specification for Rust implementation)

### External
- [ruby-prism crate](https://crates.io/crates/ruby-prism) — Rust bindings for Prism parser
- [Rolldown](https://rolldown.rs/) — Vite's Rust-based bundler
- [Rolldown GitHub](https://github.com/rolldown/rolldown) — Source and issue tracker
- [Vite 8 Beta Announcement](https://vite.dev/blog/announcing-vite8-beta) — Dec 2025, Rolldown integration
- [Vite Rolldown Integration Guide](https://vite.dev/guide/rolldown) — Migration and compatibility
- [VoidZero Rolldown Announcement](https://voidzero.dev/posts/announcing-rolldown-vite) — Background and vision
