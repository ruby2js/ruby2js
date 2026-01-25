# Plan: Rust Rewrite of Ruby2JS

## Summary

Rewrite the Ruby2JS transpiler core in Rust, producing a single codebase that compiles to native binaries, WASM (for browser/Node.js), and potentially native Vite/Rolldown plugins. This is a strategic investment as the JavaScript tooling ecosystem has consolidated around Rust.

**Estimated effort:** 4-12 weeks (weeks 1-4 are mechanical translation; week 5+ depends on edge cases encountered during parity testing).

**Key insight:** This is translation, not invention—two reference implementations exist with comprehensive tests.

**Current hesitation:** Dual maintenance burden until cutover. Start only when prepared to commit to full transition.

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

## Key Insight: This Is Translation, Not Invention

This is **not** greenfield development. We have:

1. **Two reference implementations** — Ruby (canonical) and JS (selfhost)
2. **Comprehensive test suite** — defines expected behavior exactly
3. **Proven architecture** — handler-per-node, filter chain, visitor pattern
4. **Comparison tooling** — `bin/compare` already exists

The work is mechanical translation:
```
1. Read Ruby implementation
2. Read JS implementation
3. Write Rust equivalent
4. Run tests
5. Fix until output matches
```

"Correct" is defined as "produces identical output to existing implementations." There's no architectural exploration, edge case discovery, or "what should this do?" questions.

---

## Project Structure

```
ruby2js/crates/
├── Cargo.toml              # Workspace manifest
├── ruby2js/                # Core library
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs          # pub fn convert(source, options) -> String
│       ├── main.rs         # CLI (until split out)
│       ├── converter/
│       │   ├── mod.rs      # Visitor dispatch
│       │   ├── literals.rs
│       │   ├── variables.rs
│       │   ├── control.rs
│       │   ├── methods.rs
│       │   └── classes.rs
│       ├── filters/
│       │   ├── mod.rs      # Filter trait, chain
│       │   ├── functions.rs
│       │   ├── esm.rs
│       │   └── camel_case.rs
│       ├── serializer.rs
│       └── options.rs
├── ruby2js-cli/            # CLI (when split from core)
│   ├── Cargo.toml
│   └── src/main.rs
├── ruby2js-wasm/           # WASM bindings for npm
│   ├── Cargo.toml
│   └── src/lib.rs
└── ruby2js-sys/            # CRuby FFI bindings
    ├── Cargo.toml
    └── src/lib.rs
```

**Naming convention:** Directory names match crate names (what gets published to crates.io).

**Initial structure:** Start with just `ruby2js/` containing both library and CLI. Split when complexity warrants it.

---

## Implementation Approach

### Week 1: Full Converter

**Days 1-2: PoC**
- Project setup, Cargo workspace, dependencies
- Learn Prism Rust API (`ruby-prism` crate)
- Establish patterns (visitor, output building)
- 5-10 handlers working

**Days 3-5: Remaining Handlers**
- Patterns established, mostly copy-adapt-test
- Similar handlers come in clusters (all assignments, all literals, all control flow)
- LLM assists with drafting implementations from Ruby/JS reference

**Deliverable:** CLI that converts Ruby to JS (no filters), ~60 handlers.

### Week 2: WASM + FFI Proof of Concept

**Goal:** Prove the integration story before investing in filters.

**WASM binding:**
```javascript
import { convert } from 'ruby2js-wasm';
console.log(convert('x = 1'));  // "let x = 1"
```

**CRuby FFI binding:**
```ruby
require 'ruby2js_sys'
puts Ruby2JS.convert('x = 1')  # "let x = 1"
```

**Why early:** De-risks integration. Any surprises surface before writing 23 filters.

**Tools:** `wasm-bindgen` + `wasm-pack` (WASM), `magnus` or `rb-sys` (CRuby FFI). Both well-trodden paths.

### Weeks 3-4: Filters

**Same translation pattern as converters:**
1. Filter architecture (chain, options, state)
2. `functions` filter — Ruby method → JS equivalent mappings
3. `esm` filter — ES6 module imports/exports
4. `camelCase` filter — Naming convention conversion
5. `return` filter — Implicit return handling
6. Remaining filters as needed for Juntos (~23 total)

**Deliverable:** Full filter chain matching Ruby/JS implementation behavior.

### Week 5+: Parity and Polish

**This is where uncertainty lives.**

Optimistic scenario:
- Tests pass, edge cases are minor
- Ready for cutover decision

Pessimistic scenario:
- Subtle semantic mismatches surface
- Obscure Ruby syntax needs investigation
- Output formatting differences require iteration

**Scope:**
1. Run full test suite against Rust implementation
2. Fix edge cases and discrepancies
3. Benchmark performance comparison
4. Document any intentional differences

### Future: Rolldown Native Plugin

**Goal:** Native Rust plugin for Vite's Rolldown bundler.

**Status (Jan 2026):** Rolldown is in RC, internal Vite plugins have been converted to native Rust, but external Rust plugin API documentation is not yet available. The Rollup-compatible JS plugin API works now.

**Timing:** Begin when Rust plugin documentation is available for external developers. WASM approach provides a working solution in the interim.

---

## Effort Estimate

### Revised Timeline (January 2026)

| Week | Milestone | Confidence |
|------|-----------|------------|
| 1 | Full converter (60 handlers), CLI works | High |
| 2 | WASM + FFI proof of concept | High |
| 3-4 | Filters (23 filters) | High |
| 5+ | Parity testing, edge cases, polish | Variable |

**Weeks 1-4** are mechanical translation work with reference implementations. These should go quickly—the patterns are established, the work is bounded, and LLMs accelerate the repetitive parts.

**Week 5+** is where outcomes diverge:
- **Best case:** Tests pass, minor edge cases, ready for cutover decision
- **Worst case:** Subtle semantic issues, output formatting differences, extended iteration

### Conservative Estimate

| Scenario | Total Effort |
|----------|--------------|
| Optimistic | 4-5 weeks |
| Realistic | 6-8 weeks |
| Pessimistic | 10-12 weeks |

This is significantly tighter than the original 3-6 month estimate, based on the insight that this is translation (two reference implementations exist) rather than invention.

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

## Key Hesitation: Dual Maintenance

**The primary reason not to start now:** Until the decision is made to fully cut over to Rust, there will be dual maintenance burden.

| Scenario | Maintenance Load |
|----------|------------------|
| Ruby/JS only (current) | Single implementation |
| During Rust development | Three implementations (Ruby, JS, Rust) |
| After Rust cutover | Single implementation (Rust) |

**Implications:**
- Bug fixes need to be applied to multiple implementations during transition
- New features should wait until cutover, or be implemented in all versions
- The transition period should be as short as practical

**Mitigation strategies:**
1. **Feature freeze during transition** — No new features until Rust is ready
2. **Fast iteration** — Compress weeks 1-4, make cutover decision quickly
3. **Clear cutover criteria** — Define exactly what "ready" means (test pass rate, performance benchmarks)
4. **Deprecation timeline** — Once Rust is primary, set sunset date for Ruby/JS

**When to commit:** Start only when prepared to see the transition through to cutover. The 4-5 week timeline makes this more tractable than a 3-6 month timeline would.

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

### Risk: Dual maintenance during transition

**Mitigation:**
- Compressed timeline (4-5 weeks realistic) minimizes dual maintenance window
- Feature freeze during transition—no new features until cutover
- Same test suite for all implementations
- Clear cutover criteria defined upfront
- Once Rust passes all tests, Ruby/JS versions become reference-only

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

### 2026-01-25: Revised Timeline Analysis

**Context:** Deeper analysis of implementation approach revealed this is translation work, not greenfield development.

**Key insight:** Two reference implementations (Ruby, JS) exist with comprehensive tests. The work is mechanical: read existing code, write Rust equivalent, verify output matches. No architectural decisions or edge case discovery needed.

**Revised timeline:**
- Weeks 1-4: Full converter + filters (high confidence)
- Week 5+: Parity testing (variable, could go either way)
- Total: 4-12 weeks depending on edge cases

**Hesitation:** Dual maintenance burden during transition. Starting means committing to see it through to cutover.

**Decision:** Plan documented with revised timeline. Start when prepared to commit to full transition.

### 2026-01-24: Initial Analysis

**Context:** Discussed feasibility and timing of Rust rewrite.

**Decision:** Document plan but do not start implementation. Current JS selfhost is sufficient. Rust rewrite is strategic investment.

**Rationale:**
- No immediate forcing function
- Current implementation delivers value
- Ecosystem direction (Vite → Rolldown) validates long-term strategy
- Bounded effort is acceptable when timing is right

**Ecosystem status update:** Discovered Rolldown is further along than expected—RC status, powering Vite 8 Beta (Dec 2025). Re-evaluate when Vite 8 stable releases and Rust plugin documentation is available (likely mid-2026).

---

## References

### Internal
- `crates/` — Rust implementation (to be created)
- `demo/selfhost/` — Current JavaScript selfhost implementation
- `lib/ruby2js/converter/` — Converter handlers to port (~60 files)
- `lib/ruby2js/filter/` — Filters to port (~23 files)
- `spec/` — Test suite (becomes specification for Rust implementation)
- `bin/compare` — Comparison tool for verifying output matches

### External
- [ruby-prism crate](https://crates.io/crates/ruby-prism) — Rust bindings for Prism parser
- [Rolldown](https://rolldown.rs/) — Vite's Rust-based bundler
- [Rolldown GitHub](https://github.com/rolldown/rolldown) — Source and issue tracker
- [Vite 8 Beta Announcement](https://vite.dev/blog/announcing-vite8-beta) — Dec 2025, Rolldown integration
- [Vite Rolldown Integration Guide](https://vite.dev/guide/rolldown) — Migration and compatibility
- [VoidZero Rolldown Announcement](https://voidzero.dev/posts/announcing-rolldown-vite) — Background and vision
