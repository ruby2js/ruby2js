# Ruby2JS Self-Hosting Refactoring Plan

This document outlines a phased approach to refactoring the Ruby2JS self-hosting infrastructure. The goal is not just to make self-hosting work, but to make it an **exemplar** of how to use Ruby2JS effectively for dual-target Ruby development.

## Current State Assessment

### What Works
- Converter transpiles to ~11,700 lines of JavaScript
- 225/249 tests passing (90% pass rate), 12 skipped
- Browser demo functional
- CI integration with spec manifest system

### Scope and Philosophy

This plan focuses on **refactoring existing working code**, not adding new functionality.

**In Scope:**
- Eliminating code duplication
- Extracting general-purpose code from selfhost filters
- Reducing pragma burden in source files
- Documenting patterns in a user's guide
- Cleaning up the build pipeline

**Out of Scope (for now):**
- Fixing the 12 skipped tests (address opportunistically if encountered)
- Transpiling filters to JavaScript (functions filter is substantial; defer to future work)
- Adding new Ruby language features

**Rationale:** Significant effort went into getting self-hosting working. The conscious choice was made to accumulate some technical debt to reach a working state with a passing test suite. Now that we have tests to verify refactoring doesn't break anything, we can clean up systematically.

### Technical Debt Identified
- **86 pragmas** scattered across source files (converter: 10, node: 8, prism_walker: 5, serializer: 19, plus ~44 in converter handlers)
- Selfhost filters contain code that may benefit others
- Preambles/postambles duplicate functionality that could be transpiled
- Build pipeline has redundancy
- Documentation focuses on reference; lacks user's guide

---

## Phase 1: User's Guide - Foundation

**Goal:** Document recommended patterns for dual-target Ruby development before refactoring, so we have a target to work toward.

### 1.1 Create User's Guide Structure
Create `docs/src/_docs/users-guide/` with:

1. **introduction.md** - Why dual-target Ruby, who benefits, core philosophy
2. **getting-started.md** - Minimal working example, first transpilation
3. **pragmas.md** - Complete pragma reference with when/why to use each
4. **patterns.md** - Recommended patterns for dual-target code:
   - Dual-method pattern (Ruby vs JS implementations)
   - When to use skip vs. alternative implementations
   - Array/Hash iteration patterns that work in both
   - Class and module patterns
5. **polyfills.md** - Available polyfills, how to add custom ones
6. **filters.md** - Guide to relevant filters (functions, return, esm, etc.)
7. **anti-patterns.md** - What to avoid (method_missing, eval, etc.)
8. **build-setup.md** - How to set up a build pipeline

### 1.2 Extract Patterns from Self-Hosting Experience
Document patterns discovered during self-hosting:
- `# Pragma: hash` vs `# Pragma: entries` - when to use each
- `# Pragma: array` - why `.push()` sometimes needs explicit syntax
- `# Pragma: method` - when Ruby's call semantics differ from JS
- `# Pragma: skip` - removing Ruby-only code paths
- `# Pragma: logical` - forcing `||` instead of `??`

### 1.3 Deliverables
- New documentation section in `docs/src/_docs/users-guide/`
- Updated `conversion-details.md` as gateway to user's guide
- Examples from actual self-hosting code

---

## Phase 2: Converter Audit

**Goal:** Review every converter change since e15b9777 and simplify where possible using pragmas and polyfills.

### 2.1 Files to Audit (22 files, 371 lines changed)

| File | Changes | Audit Focus |
|------|---------|-------------|
| class.rb | 42 lines | Hash iteration patterns |
| class2.rb | 16 lines | Array dup, respond_to patterns |
| def.rb | 12 lines | ast_node? checks, array dup |
| dstr.rb | 4 lines | Empty interpolation handling |
| for.rb | 2 lines | Range step patterns |
| hash.rb | 11 lines | Hash literal handling |
| if.rb | 2 lines | Condition patterns |
| import.rb | 2 lines | Import syntax |
| ivar.rb | 10 lines | Instance variable patterns |
| kwbegin.rb | 43 lines | Exception handling, IIFE wrapping |
| logical.rb | 64 lines | Nullish coalescing vs OR |
| logical_or.rb | 58 lines | NEW FILE - needs review |
| masgn.rb | 16 lines | Multiple assignment patterns |
| module.rb | 8 lines | Module patterns |
| opasgn.rb | 5 lines | Operator assignment |
| regexp.rb | 10 lines | Rest parameter position |
| return.rb | 8 lines | Return statement patterns |
| send.rb | 50 lines | Method call patterns |
| vasgn.rb | 8 lines | Variable assignment |

### 2.2 Audit Questions for Each File
1. **Can this be simplified with a pragma?** If code was added to handle JS-specific behavior, could a pragma on the Ruby source achieve the same result?
2. **Can this be simplified with a polyfill?** If code handles a Ruby method not in JS, should it be a polyfill instead of converter logic?
3. **Is this truly converter-level?** Or should it be in a filter?
4. **Does this benefit all users?** If so, is it properly generalized?
5. **Is the change well-documented?** In code comments and/or docs?

### 2.3 Specific Areas to Investigate

**Pragma Reduction Opportunities:**
- Can `# Pragma: hash` cases be handled by a filter instead?
- Can `# Pragma: entries` become default behavior for Hash iteration?
- Can `# Pragma: array` cases be eliminated with smarter converter logic?

**Polyfill Candidates:**
- Any converter logic that adds Ruby method → JS method mapping should potentially be a polyfill or filter instead

### 2.4 Deliverables
- Audit report for each changed file
- List of pragmas that could be eliminated
- List of converter changes that should move to filters
- PRs for simplifications identified

---

## Phase 3: Selfhost Filter Audit

**Goal:** Ensure selfhost filters contain ONLY transformations unique to self-hosting. Move general-purpose code elsewhere.

### 3.1 Files to Audit

| Filter | Lines | Current Purpose |
|--------|-------|-----------------|
| selfhost/core.rb | 33 | Empty shell (entry point only) |
| selfhost/walker.rb | 187 | Prism API name mapping, private/protected removal |
| selfhost/converter.rb | 323 | handle :type pattern, method name conversion |
| selfhost/spec.rb | 74 | _() wrapper removal, globalThis ivars |

### 3.2 Audit Questions
1. **Is this truly selfhost-specific?** Would other users benefit?
2. **Is this Prism-specific?** Does it only apply to Prism walker transpilation?
3. **Could this be a general filter option?** E.g., "remove private/protected" as an option?
4. **Is there dead code?** Code that was needed during development but isn't anymore?

### 3.3 Candidates for Extraction

**walker.rb - Potentially General:**
- `PRISM_PROPERTY_MAP` / `PRISM_METHOD_MAP` - Prism-specific, should stay
- `private/protected/public removal` - Could be a general filter option
- `visit_*_node` → `visit*Node` conversion - Prism-specific, should stay

**converter.rb - Potentially General:**
- `ALWAYS_METHODS` - Force parentheses on certain methods (general utility)
- `GETTER_METHODS` - Mark methods as getters (general utility)
- `CONVERTER_INSTANCE_METHODS` - Selfhost-specific
- `respond_to?` transformation - Could be a general filter for safe `in` checks
- `handle :type` pattern - Selfhost-specific (Ruby2JS DSL)
- Array slice comparison - Could be a general pattern

**spec.rb - Potentially General:**
- `_()` wrapper removal - Minitest-specific, could be a testing filter
- `globalThis` ivar handling - Arrow function specific, somewhat general

### 3.4 Deliverables
- Audit report for each selfhost filter
- List of code to extract to general filters
- PRs for extractions
- Updated selfhost filters (smaller, focused)

---

## Phase 4: Build Pipeline Audit

**Goal:** Eliminate duplication, create single source of truth, evaluate what could be filters.

### 4.1 Current Build Pipeline Components

**Transpilation Scripts:**
- `scripts/transpile_walker.rb`
- `scripts/transpile_converter.rb`
- `scripts/transpile_spec.rb`

**Preamble/Support Files:**
- `preamble.mjs` - NotImplementedError class
- `test_harness.mjs` - Test framework, polyfills, Ruby2JS.convert wrapper

### 4.2 Audit Questions

**Preambles:**
1. Could `NotImplementedError` be transpiled from Ruby source?
2. Are there other Ruby built-ins that should be polyfills?
3. Could the export statement handling move into ESM filter?

**Test Harness:**
1. Could `Namespace` class be transpiled from Ruby source?
2. Could minitest compatibility be a transpilable Ruby module?
3. Should polyfills be auto-generated and injected?

**Build Scripts:**
1. Is filter ordering consistent across all scripts?
2. Could there be a shared configuration?
3. Should source manipulation (adding pragmas) move to a pre-filter?

### 4.3 Candidates for Improvement

**Single Source of Truth:**
- `NotImplementedError` - Could be defined in Ruby, transpiled
- `Namespace` - Already in Ruby (`lib/ruby2js/namespace.rb`), just needs transpiling
- Test assertions (`must_equal`, etc.) - Could be a transpilable Ruby module

**Filter Opportunities:**
- Export statement handling in build scripts → ESM filter enhancement
- Polyfill injection → Already in polyfill filter, ensure it's comprehensive
- Source pre-processing (adding pragmas) → Could be a pre-filter hook

### 4.4 Deliverables
- Build pipeline analysis document
- List of components to transpile vs hand-write
- Unified build configuration proposal
- PRs for improvements

---

## Phase 5: Pragma Usage Review

**Goal:** Minimize pragmas needed in source files while maintaining compatibility.

### 5.1 Current Pragma Distribution

| File | Count | Pragma Types |
|------|-------|--------------|
| converter.rb | 10 | hash, entries, method, skip |
| node.rb | 8 | skip (Ruby-only methods) |
| prism_walker.rb | 5 | skip (require, respond_to?, visit) |
| serializer.rb | 19 | skip ([], []=, <<), array |
| converter/*.rb | ~44 | Various |

**Total: ~86 pragmas**

### 5.2 Pragma Reduction Strategies

**Strategy 1: Smarter Defaults**
- If most Hash iterations need `# Pragma: entries`, make that the default behavior
- If `.dup` on arrays commonly needs `# Pragma: array`, handle automatically

**Strategy 2: Filter-Based Handling**
- Move pragma-like behavior into filters that can be enabled/disabled
- E.g., "strict array operations" filter

**Strategy 3: Alternative APIs**
- Where pragmas mark incompatible patterns, provide alternative Ruby APIs
- E.g., Instead of `arr.dup # Pragma: array`, use `arr.clone()` which transpiles cleanly

**Strategy 4: Convention Over Annotation**
- Establish conventions that eliminate need for pragmas
- Document these conventions in user's guide

### 5.3 Audit Process
For each pragma in source files:
1. Why is it needed?
2. Could the converter/filter handle this automatically?
3. Is there an alternative Ruby idiom that works without pragma?
4. If pragma must stay, is it documented?

### 5.4 Deliverables
- Complete pragma audit spreadsheet
- List of pragmas that can be eliminated
- Filter/converter changes to reduce pragmas
- Updated documentation for remaining pragmas
- Target: Reduce pragmas by 50% or more

---

## Phase 6: User's Guide Update

**Goal:** Update documentation based on learnings from phases 2-5.

### 6.1 Updates Based on Findings
- Add new patterns discovered
- Document new filters/options added
- Update anti-patterns based on audit findings
- Add troubleshooting section based on common issues

### 6.2 Real-World Examples
- Use actual self-hosting code as examples
- Before/after comparisons showing improvements
- Performance considerations

### 6.3 Migration Guide
If changes from phases 2-5 affect existing users:
- Document breaking changes
- Provide migration steps
- Show before/after code examples

### 6.4 Deliverables
- Updated user's guide sections
- Migration guide if needed
- Changelog entries for all changes

---

## Success Criteria

### Quantitative Goals
- [ ] Pragmas reduced from ~86 to <40
- [ ] Selfhost filters total <200 lines (currently ~617)
- [ ] All 249 tests passing (currently 237, 12 skipped)
- [ ] Build pipeline reduced duplication by 50%

### Qualitative Goals
- [ ] User's guide complete and reviewed
- [ ] Self-hosting code exemplifies best practices
- [ ] No selfhost-specific code in general filters (only options)
- [ ] Build pipeline has single source of truth for shared code
- [ ] Documentation covers all pragmas and when to use them

### Documentation Goals
- [ ] User's guide has 8+ pages
- [ ] Each pragma type documented with examples
- [ ] Anti-patterns section prevents common mistakes
- [ ] Build setup guide enables new projects

---

## Timeline Considerations

This is a **deliberate, phased approach**. Each phase builds on the previous:

1. **Phase 1 (User's Guide Foundation)** - Sets the target for what "good" looks like
2. **Phase 2 (Converter Audit)** - Identifies what can be simplified
3. **Phase 3 (Selfhost Filter Audit)** - Extracts general-purpose code
4. **Phase 4 (Build Pipeline Audit)** - Unifies and simplifies
5. **Phase 5 (Pragma Review)** - Reduces annotation burden
6. **Phase 6 (Guide Update)** - Documents learnings

Each phase may inform changes to earlier phases' work - this is expected and encouraged.

---

## Appendix: File Inventory

### Source Files with Pragmas (to audit in Phase 5)

```
lib/ruby2js/converter.rb (10 pragmas)
lib/ruby2js/node.rb (8 pragmas)
lib/ruby2js/prism_walker.rb (5 pragmas)
lib/ruby2js/serializer.rb (19 pragmas)
lib/ruby2js/converter/block.rb (1 pragma)
lib/ruby2js/converter/class.rb (1 pragma)
lib/ruby2js/converter/class2.rb (3 pragmas)
lib/ruby2js/converter/def.rb (3 pragmas)
lib/ruby2js/converter/for.rb (1 pragma)
lib/ruby2js/converter/hash.rb (2 pragmas)
lib/ruby2js/converter/kwbegin.rb (8 pragmas)
lib/ruby2js/converter/logical_or.rb (2 pragmas)
lib/ruby2js/converter/masgn.rb (8 pragmas)
lib/ruby2js/converter/nullish.rb (2 pragmas)
lib/ruby2js/converter/return.rb (4 pragmas)
lib/ruby2js/converter/send.rb (5 pragmas)
lib/ruby2js/converter/vasgn.rb (4 pragmas)
```

### Selfhost Filter Files (to audit in Phase 3)

```
lib/ruby2js/filter/selfhost/core.rb (33 lines)
lib/ruby2js/filter/selfhost/walker.rb (187 lines)
lib/ruby2js/filter/selfhost/converter.rb (323 lines)
lib/ruby2js/filter/selfhost/spec.rb (74 lines)
```

### Build Pipeline Files (to audit in Phase 4)

```
demo/selfhost/scripts/transpile_walker.rb
demo/selfhost/scripts/transpile_converter.rb
demo/selfhost/scripts/transpile_spec.rb
demo/selfhost/preamble.mjs
demo/selfhost/test_harness.mjs
demo/selfhost/package.json
```

---

## Appendix B: Selfhost Directory Audit

### Current File Inventory

| File | Lines | Size | Purpose |
|------|-------|------|---------|
| **Core Runtime** | | | |
| ruby2js.mjs | 491 | 16KB | CLI debugging tool with AST inspection |
| test_harness.mjs | 355 | 10KB | Test framework, polyfills, Ruby2JS.convert |
| preamble.mjs | 16 | 600B | NotImplementedError class (unused?) |
| prism_browser.mjs | 119 | 4KB | Browser WASI polyfill for @ruby/prism |
| **Test Files** | | | |
| test_walker.mjs | 270 | 7KB | Walker unit tests |
| test_serializer.mjs | 155 | 4KB | Serializer tests |
| debug_whitespace.mjs | 49 | 2KB | Debugging helper |
| **Spec Infrastructure** | | | |
| run_spec.mjs | 14 | 400B | Single spec runner |
| run_all_specs.mjs | 237 | 8KB | Manifest-driven spec runner |
| spec_manifest.json | 39 | 1KB | Spec readiness manifest |
| **Build** | | | |
| Rakefile | 145 | 4KB | Build tasks |
| package.json | 23 | 1KB | npm configuration |
| package-lock.json | 22 | 570B | npm lockfile |
| **Demo** | | | |
| browser_demo.html | 581 | 15KB | Browser demo page |
| README.md | 302 | 10KB | Documentation |
| **Generated (dist/)** | | | |
| converter.mjs | ~11700 | 397KB | Transpiled converter |
| walker.mjs | ~1800 | 64KB | Transpiled walker |
| transliteration_spec.mjs | ~1500 | 52KB | Transpiled spec |
| serializer_spec.mjs | ~300 | 10KB | Transpiled spec |

### Duplication Analysis

**Significant Duplication Found:**

1. **`PrismSourceBuffer` / `PrismSourceRange` classes** - Duplicated in:
   - `ruby2js.mjs` (lines 19-52)
   - `test_harness.mjs` (lines 15-56)
   - `test_walker.mjs` (lines 9-24)

2. **`Namespace` class** - Duplicated in:
   - `ruby2js.mjs` (lines 65-127)
   - `test_harness.mjs` (lines 228-290)

3. **Prism initialization** - Similar patterns in:
   - `ruby2js.mjs`
   - `test_harness.mjs`
   - `test_walker.mjs`

4. **Mock globals** (`Hash`, `RUBY_VERSION`, etc.) - Duplicated in:
   - `ruby2js.mjs` (lines 58-63)
   - `test_harness.mjs` (lines 58-72)

### ruby2js.mjs Analysis (491 lines)

**Current Composition:**
- Lines 1-63: Setup (Prism init, globals, PrismSourceBuffer, PrismSourceRange)
- Lines 65-128: Namespace class (duplicate)
- Lines 130-140: Walker/Converter imports
- Lines 142-313: AST formatting utilities (formatPrismNode, inspectPrismNode, findPrismNodes, formatAst)
- Lines 315-397: Argument parsing
- Lines 399-491: Main execution

**Target Size:** ~150-200 lines

**Reduction Strategy:**
1. Extract shared classes to `shared.mjs` (~100 lines saved)
2. Move AST formatting to `ast_utils.mjs` if needed for debugging (~170 lines)
3. Keep CLI argument parsing and main execution (~120 lines)
4. Alternative: If AST debugging is rare, consider removing it entirely and using separate debug tools

### Files That Could Be Removed

| File | Recommendation | Rationale |
|------|----------------|-----------|
| `.spec_manifest.json.swp` | **Remove** | Editor swap file, should be in .gitignore |
| `preamble.mjs` | **Review** | Appears unused (transpile_converter.rb generates its own preamble) |
| `debug_whitespace.mjs` | **Consider removing** | One-off debugging script, could be recreated when needed |

### Files That Could Be Consolidated

| Current | Proposed | Benefit |
|---------|----------|---------|
| test_harness.mjs + ruby2js.mjs | shared/runtime.mjs + test_harness.mjs + ruby2js.mjs | Single source for PrismSourceBuffer, Namespace, globals |
| test_walker.mjs + test_serializer.mjs | Keep separate but share test utilities | Cleaner test structure |

### Recommendations for Phase 4

1. **Create `shared/` directory** with:
   - `runtime.mjs` - PrismSourceBuffer, PrismSourceRange, Namespace, globals
   - `ast_utils.mjs` - AST formatting (optional, for debugging)

2. **Slim down ruby2js.mjs** to:
   - Import shared runtime
   - CLI argument parsing
   - Minimal execution wrapper
   - Target: <200 lines

3. **Slim down test_harness.mjs** to:
   - Import shared runtime
   - Test framework (describe/it/assertions)
   - Ruby2JS.convert wrapper
   - Target: <200 lines

4. **Evaluate preamble.mjs**:
   - If unused, remove it
   - If needed, consider transpiling NotImplementedError from Ruby

5. **Clean up**:
   - Add `.swp` to .gitignore
   - Consider removing debug_whitespace.mjs or moving to scripts/

### Questions to Answer in Phase 4

1. **Is ruby2js.mjs the right debugging tool?**
   - Who uses it?
   - Are the AST inspection features (`--ast`, `--find`, `--inspect`) valuable?
   - Should this be a separate dev-only tool?

2. **Should Namespace be transpiled from Ruby?**
   - `lib/ruby2js/namespace.rb` exists
   - Would unify Ruby and JS implementations
   - May simplify test_harness.mjs setup

3. **Can test assertions be transpiled?**
   - `must_equal`, `must_include`, `must_match` in test_harness.mjs
   - Could be a transpilable Ruby module
   - Would reduce hand-written JS

4. **Browser demo integration with ruby2js.com** (ANSWERED)
   - `demo/selfhost/browser_demo.html` → copied to `docs/src/demo/selfhost/index.html`
   - The self-hosted demo will become the **primary demo** on ruby2js.com
   - Opal demo (~24MB) will remain for comparison
   - Possibly a WASM Ruby demo added later for comparison
   - This means `browser_demo.html` is **critical infrastructure**, not throwaway

---

## Appendix C: ruby2js.com Demo Architecture

### Current State

The ruby2js.com website (in `docs/`) includes **two live demos**:

| Demo | Technology | Size | Location |
|------|------------|------|----------|
| Opal (main) | Opal-compiled Ruby2JS | ~24MB | `/demo` |
| Self-Hosted | Transpiled Ruby2JS + Prism WASM | ~2.5MB | `/demo/selfhost/` |

### Future Vision

The **self-hosted demo will become primary** because:
- ~10x smaller (~2.5MB vs ~24MB)
- Faster load time
- Demonstrates Ruby2JS's capabilities (dogfooding)
- Multiple demos for comparison (Opal, Self-Hosted, possibly WASM Ruby)

### File Flow

```
demo/selfhost/                      docs/src/demo/selfhost/
├── browser_demo.html          →    ├── index.html
├── prism_browser.mjs          →    ├── prism_browser.mjs
├── dist/                           ├── dist/
│   ├── walker.mjs             →    │   ├── walker.mjs
│   └── converter.mjs          →    │   └── converter.mjs
└── node_modules/@ruby/prism   →    └── node_modules/@ruby/prism/
```

### Code Duplication Problem (More Severe Than Previously Thought)

The same runtime classes are now duplicated in **FOUR** places:

| Class | demo/selfhost/ | docs/src/demo/selfhost/ |
|-------|----------------|-------------------------|
| PrismSourceBuffer | ruby2js.mjs, test_harness.mjs, test_walker.mjs | index.html (inline) |
| PrismSourceRange | ruby2js.mjs, test_harness.mjs, test_walker.mjs | index.html (inline) |
| Namespace | ruby2js.mjs, test_harness.mjs | index.html (inline) |
| Polyfills | test_harness.mjs | index.html (inline) |

### Implications for Phase 4

**Critical insight:** The browser demo (`browser_demo.html` → `index.html`) is the **production deliverable**, not just a development tool.

This changes priorities:
1. **Shared runtime is essential** - Code must be shared between Node.js tools and browser demo
2. **browser_demo.html quality matters** - It's user-facing, not developer-only
3. **Polyfills should be in dist/** - Auto-generated by polyfill filter, not hand-written in HTML
4. **Size matters** - Every line of inline JS in browser_demo.html adds to the 2.5MB

### Recommended Architecture

```
demo/selfhost/
├── shared/
│   ├── runtime.mjs           # PrismSourceBuffer, PrismSourceRange, Namespace
│   └── polyfills.mjs         # (or generated into dist/walker.mjs)
├── dist/
│   ├── walker.mjs            # Transpiled (includes polyfills)
│   └── converter.mjs         # Transpiled
├── ruby2js.mjs               # CLI tool (imports shared/runtime.mjs)
├── test_harness.mjs          # Test framework (imports shared/runtime.mjs)
├── browser_demo.html         # Demo (imports shared/runtime.mjs as module)
└── ...
```

**Benefits:**
- Single source of truth for runtime classes
- browser_demo.html shrinks from 663 lines to ~200 lines (UI only)
- Easier to maintain
- Changes propagate to all consumers

### Questions Resolved

| Question | Answer |
|----------|--------|
| Is browser_demo.html important? | **Yes** - becomes primary demo on ruby2js.com |
| Should code be shared? | **Yes** - critical for maintainability |
| Should polyfills be in HTML? | **No** - should be generated into dist/ files |
| Is ruby2js.mjs needed? | **Yes** - useful debugging tool, but should share runtime |
