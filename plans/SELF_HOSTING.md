# Self-Hosting Plan: Ruby2JS in JavaScript

## Status: Proof of Concept Complete

This plan explores transpiling Ruby2JS itself to JavaScript, enabling it to run entirely in the browser with the `@ruby/prism` npm package for parsing.

**Related:**
- [PRISM_WALKER.md](./PRISM_WALKER.md) - The prism walker is now complete and provides direct AST translation.
- [demo/selfhost/](../demo/selfhost/) - Working proof-of-concept with browser demo.

## Proof of Concept Results

A working end-to-end demo is available at `demo/selfhost/browser_demo.html`:

```
Ruby Source → @ruby/prism (WASM) → PrismWalker (transpiled) → Converter → JavaScript
```

**What works:**
- Browser demo converting Ruby to JavaScript (~2.8MB total vs 24MB with Opal)
- PrismWalker successfully transpiled from Ruby using the `selfhost` filter
- 27 JavaScript tests passing (14 walker + 13 pipeline)
- 18 Ruby tests for the selfhost filter

**What the minimal converter supports:**
- Literals: integers, floats, strings, symbols, nil, booleans
- Variables: local and instance, read and write
- Collections: arrays, hashes
- Method calls with `puts` → `console.log` mapping
- Method definitions with optional/rest parameters
- Basic if/else control flow

**What it doesn't support (requires full implementation):**
- Classes, modules
- Loops, case/when, exception handling
- Blocks, lambdas, procs
- Operators (+, -, &&, ||, etc.)
- Most method mappings (60+ handlers, 23 filters in full Ruby2JS)

**Key learnings:**
1. The `selfhost` filter handles most Ruby2JS patterns well
2. `method(:name)` references and no-arg methods (→ getters) need manual handling
3. JS Prism has API differences: `arguments_`, `unescaped.value`
4. Browser requires WASI shim for WebAssembly

## Current Architecture

The online demo at ruby2js.com currently uses:

1. **Opal** - Ruby compiled to JavaScript (~24MB `ruby2js.js` file)
2. **whitequark parser gem** - Compiled via Opal for AST generation
3. **Ruby2JS core** - Compiled via Opal

This works but has significant drawbacks:
- 24MB JavaScript bundle (132K lines)
- Opal runtime overhead
- Cannot use Prism (Opal doesn't support it)
- Slow initial load time

## Proposed Architecture

```
Ruby Source (user input)
    ↓
@ruby/prism (WASM, ~2MB)
    ↓
Prism AST (JavaScript objects)
    ↓
Ruby2JS.js (self-hosted, transpiled from Ruby)
    ↓
JavaScript Output
```

## Key Components

### 1. `@ruby/prism` npm Package

The official Prism parser compiled to WebAssembly with JavaScript bindings.

**Installation:**
```bash
npm install @ruby/prism
```

**Usage (Node.js):**
```javascript
import { loadPrism } from "@ruby/prism";
const parse = await loadPrism();
const result = parse("puts 'hello'");
// result.value is the AST
// result.comments, result.errors, result.warnings available
```

**Usage (Browser):**
Requires WASI shim and manual WebAssembly instantiation. See [Prism JavaScript docs](https://github.com/ruby/prism/blob/main/docs/javascript.md).

**AST Format:**
Prism's JavaScript bindings produce native JavaScript objects, NOT the same format as `Prism::Translation::Parser`. This is a **critical difference** from the current Ruby implementation.

### 2. Ruby2JS Core (~12,000 lines)

| Component | Lines | Complexity |
|-----------|-------|------------|
| `lib/ruby2js.rb` | ~450 | High - orchestration, options |
| `lib/ruby2js/converter.rb` | ~350 | High - base converter |
| `lib/ruby2js/converter/*.rb` | ~3,500 | Medium - 60 handlers |
| `lib/ruby2js/filter.rb` | ~200 | Medium - filter base |
| `lib/ruby2js/filter/*.rb` | ~6,500 | Medium-High - 23 filters |
| `lib/ruby2js/serializer.rb` | ~300 | Low - output formatting |
| Other | ~1,000 | Various |

### 3. AST Translation Layer

**The Problem:**

Prism's JavaScript AST is different from both:
- Prism's Ruby AST (`Prism::Node` subclasses)
- whitequark parser AST (`Parser::AST::Node`)

Ruby2JS currently depends on `Parser::AST::Node` format via `Prism::Translation::Parser`.

**Options Considered:**

**Option A: Fork Translation Layer (Ruby first, then transpile)**

1. Vendor `Prism::Translation::Parser` into Ruby2JS
2. Simplify for our needs, remove unused features
3. Create minimal stubs for `Parser::AST::Node`, `Parser::Source::*`
4. Fix bugs we've encountered (comment association, synthetic nodes)
5. Test thoroughly in Ruby
6. Transpile the working Ruby code to JavaScript

**Option B: Adapt Ruby2JS to Prism's Native AST**

Rewrite all handlers and filters to work directly with Prism's AST format.

**Option C: Create Minimal AST Adapter from Scratch**

Build a thin JavaScript adapter without reference to existing translation logic.

**Analysis:**

Option C sounds appealing ("minimal adapter") but is actually Option A done poorly - we'd rediscover all the edge cases that `Prism::Translation::Parser` already handles. The translation layer exists because the mapping is non-trivial:
- Different node type names
- Different child ordering
- Different handling of optional elements
- Location/source range differences
- ~100 node types to map correctly

Option B requires rewriting 60+ handlers and 23 filters - massive effort with high regression risk.

**Recommendation: Option A** - Fork the translation layer in Ruby first.

This approach:
- Starts with working, battle-tested code
- Allows incremental simplification with test coverage
- Fixes can be made in Ruby (easier to debug)
- Only transpile to JavaScript after Ruby version is stable
- Single source of truth during development

## Implementation Phases

### Phase 1: Prism Walker ✅ COMPLETE

**Goal:** Remove `parser` gem dependency while maintaining compatibility.

The `PrismWalker` class (`lib/ruby2js/prism_walker.rb`) now provides direct AST translation:
- ~100 visitor methods translating Prism nodes to Parser-compatible format
- `Ruby2JS::Node` class with Parser::AST::Node compatibility
- Comment extraction and association
- Sourcemap support via shared source buffer
- All 1345 tests pass on Ruby 3.4+

**See:** [PRISM_WALKER.md](./PRISM_WALKER.md) for full details.

### Phase 2: Proof of Concept ✅ COMPLETE

**Goal:** Demonstrate end-to-end pipeline working in browser.

**Completed:**
1. ✅ Created `selfhost` filter (`lib/ruby2js/filter/selfhost.rb`):
   - `s(:type, ...)` → `s('type', ...)` (symbols to strings)
   - `node.type == :sym` → `node.type === 'string'`
   - `handle :type do ... end` → handler registration
   - `case node.type; when :sym` → switch with string cases
   - `class Foo < Prism::Visitor` → self-dispatch visitor pattern
   - `visit_*_node` → `visitCamelCaseNode` method names
   - `.compact` → `.filter(x => x != null)`

2. ✅ Transpiled PrismWalker to JavaScript using selfhost filter

3. ✅ Created minimal converter (hand-written JS due to `method(:name)` pattern issues)

4. ✅ Integrated @ruby/prism with WASI shim for browser

5. ✅ Browser demo working at `demo/selfhost/browser_demo.html`

6. ✅ Test suite: 27 JS tests passing, 18 Ruby filter tests passing

**Success criteria met:** `puts "Hello"` → `console.log("Hello")` works in browser.

**Learnings for full implementation:**
- The selfhost filter works well for most patterns
- Some Ruby patterns need manual JS: `method(:name)`, no-arg methods becoming getters
- Filter order matters: `[:return, :selfhost, :functions]`
- JS Prism API differences must be handled in walker code, not transpilation

### Phase 2.5: Evaluate Selfhost Filter for Reuse

**Goal:** Move general-purpose transformations from `selfhost` to `functions`.

During self-hosting development, some transformations were added to `selfhost` that are actually general-purpose:
- `.compact` → `.filter(x => x != null)` - useful for any Ruby→JS conversion

**Action items:**
- Review selfhost filter for other general-purpose transformations
- Move reusable transformations to appropriate filters (functions, etc.)
- Keep selfhost focused on Ruby2JS-specific patterns only

### Phase 3: Full Converter Implementation

**Goal:** Feature parity with Ruby2JS core converter.

The proof-of-concept handles ~5% of Ruby2JS functionality. Full implementation requires:

| Component | Lines | Effort | Notes |
|-----------|-------|--------|-------|
| Core converter | ~3,500 | 2-3 weeks | 60+ handlers, state management |
| Serializer | ~300 | 3-5 days | Indentation, line wrapping |
| Essential filters | ~1,500 | 1-2 weeks | functions, esm, return, camelCase |
| Additional filters | ~5,000 | 2-4 weeks | As needed (react, stimulus, etc.) |
| Testing & debugging | - | 2-3 weeks | Adapt 1,345 specs to JS |
| **Total** | ~10,000 | **6-9 weeks** | For ~80% feature parity |

**Specific challenges:**

1. **State management** - The converter tracks scope, variables, class context, etc.
   ```ruby
   @vars, @ivars, @scope, @namespace, @block_depth, @class_name, ...
   ```

2. **Handler registration** - Uses `handle :type do ... end` pattern (selfhost handles this)

3. **Method references** - `method(:foo)` doesn't transpile cleanly; may need refactoring

4. **Operator precedence** - Complex logic for parenthesization

5. **ES level switching** - Different output for ES5 vs ES2015+ (classes, arrow functions, etc.)

**Incremental approach:**

Rather than full parity, consider shipping incrementally:

| Milestone | Coverage | Effort |
|-----------|----------|--------|
| Literals + variables | ~20% | Done (PoC) |
| + operators, control flow | ~40% | 1-2 weeks |
| + classes, modules | ~60% | 2-3 weeks |
| + functions filter | ~75% | 1-2 weeks |
| + remaining filters | ~90% | 2-4 weeks |

### Phase 4: Demo Integration

**Goal:** Replace Opal-based demo with self-hosted version.

1. Bundle Ruby2JS.js with @ruby/prism
2. Update demo HTML/JS to use new bundle
3. Performance optimization
4. Error handling and user-friendly diagnostics
5. Source map support (if feasible)

**Estimated effort:** 2-3 weeks

### Total Estimated Effort

| Phase | Status | Effort |
|-------|--------|--------|
| Phase 1: Prism Walker | ✅ Complete | - |
| Phase 2: Proof of Concept | ✅ Complete | - |
| Phase 2.5: Filter cleanup | Pending | 1-2 days |
| Phase 3: Full converter | Pending | 6-9 weeks |
| Phase 4: Demo integration | Pending | 2-3 weeks |
| **Total remaining** | | **8-12 weeks** |

For a "lite" version (~75% coverage), estimate **4-6 weeks**.

## Technical Challenges

### 1. Ruby Idioms in JavaScript

Ruby2JS code uses Ruby idioms that need careful translation:

```ruby
# Ruby - blocks with implicit returns
handlers.each do |type, handler|
  handler.call(node)
end

# JavaScript equivalent
for (const [type, handler] of handlers) {
  handler(node);
}
```

```ruby
# Ruby - symbol keys, method chaining
node.children.map(&:to_s).join(', ')

# JavaScript equivalent
node.children.map(c => c.toString()).join(', ')
```

**Approach:** Create a `selfhost` filter specifically for transpiling Ruby2JS itself.

This filter would understand:
- S-expression construction: `s(:send, target, :method)` → `s('send', target, 'method')`
- AST node patterns: `node.type == :str` → `node.type === 'str'`
- Symbol comparisons in case statements
- Parser-specific method calls

**Opt-in conversions:** Following the pattern from [ECMASCRIPT_UPDATES.md](./ECMASCRIPT_UPDATES.md), specific transformations can be enabled via explicit type wrappers:

```ruby
# Explicit AST node - filter knows to handle specially
Parser::AST::Node.new(:send, [target, :method])

# Explicit S-expression helper
s(:send, target, :method)
```

This keeps the filter focused and avoids false positives on generic Ruby code.

### 2. Dynamic Method Definition

Ruby2JS uses `handle :node_type do ... end` for handler registration:

```ruby
handle :str do |value|
  put value.inspect
end
```

**JavaScript equivalent:**
```javascript
handle('str', (value) => {
  this.put(JSON.stringify(value));
});
```

### 3. S-expression Construction

Ruby2JS creates AST nodes with `s(:type, *children)`:

```ruby
s(:send, target, :method, *args)
```

**JavaScript equivalent:**
```javascript
s('send', target, 'method', ...args)
// or
new ASTNode('send', [target, 'method', ...args])
```

### 4. Regular Expressions

Ruby regexes need translation to JavaScript:
- Named captures
- Unicode properties
- Lookbehind (now supported in modern JS)

### 5. Source Maps

Current Ruby2JS generates source maps. This would need reimplementation for the JS version.

### 6. Test Strategy

Ruby2JS specs use Minitest with `describe`/`it` blocks and `must_equal` assertions. These can be transpiled to JavaScript.

**Options considered:**

| Approach | Pros | Cons |
|----------|------|------|
| Minitest shim | Tests transpile directly; zero dependencies; ~40 lines | Missing features (skip, async, better diffs) |
| Mocha/Jest/Vitest | Battle-tested; watch mode; IDE integration | Need assertion transform; another dependency |

**Recommendation:** Use a minimal Minitest-compatible shim (`describe`, `it`, `must_equal`) for now. The test structure is already compatible with standard JS frameworks—only assertions differ. If better debugging or async support is needed later, add a filter to convert `must_equal` → `expect().toBe()` and switch to Vitest.

**Current implementation:** `demo/selfhost/test_harness.mjs` provides the shim. Transpiled specs run with Node.js and produce familiar Minitest-style output.

## Size Comparison

**Measured from proof-of-concept:**

| Component | Size |
|-----------|------|
| @ruby/prism WASM | ~2.7MB |
| WASI shim | ~50KB |
| Walker + Converter JS | ~15KB |
| **Total (PoC)** | **~2.8MB** |

**Projected for full implementation:**

| Component | Estimated Size |
|-----------|----------------|
| @ruby/prism WASM | ~2.7MB |
| WASI shim | ~50KB |
| Full converter (minified) | ~150KB |
| Core filters (minified) | ~100KB |
| **Total (full)** | **~3MB** |

**Compare to current Opal-based:** **~24MB** (~8x larger)

## Alternative: ruby.wasm

Instead of self-hosting, use [ruby.wasm](https://github.com/aspect-js/aspect) which runs full CRuby in WebAssembly.

**Pros:**
- Full Ruby compatibility
- Uses real Prism
- No code porting needed

**Cons:**
- Large WASM binary (~20MB+)
- Slower startup
- More complex integration

**Recommendation:** Self-hosting is preferred for size and performance.

## Decision Points

Before proceeding, clarify:

1. **Is browser demo a priority?** If not heavily used, may not justify effort.

2. **Target browsers?** Modern only (ES2020+) simplifies implementation.

3. **Filter coverage?** Which filters are essential for the demo?

4. **Maintenance burden?** Two codebases (Ruby + JS) vs. one.

5. **Performance requirements?** Acceptable latency for conversion?

## Success Criteria

- [ ] Bundle size < 2MB (vs current 24MB)
- [ ] Parse + convert "Hello World" in < 100ms
- [ ] Pass 80%+ of existing test cases
- [ ] Support `functions`, `esm`, `camelCase` filters
- [ ] Works in Chrome, Firefox, Safari (latest)

## References

- [@ruby/prism npm package](https://www.npmjs.com/package/@ruby/prism)
- [Prism JavaScript documentation](https://github.com/ruby/prism/blob/main/docs/javascript.md)
- [Prism AST documentation](https://ruby.github.io/prism/)
- [ruby.wasm](https://github.com/aspect-js/aspect)
- [Current Opal-based demo](https://www.ruby2js.com/)

## Appendix: Prism Node Type Mapping

A partial mapping from Prism JavaScript node types to Parser gem types:

| Prism JS | Parser gem | Notes |
|----------|------------|-------|
| `CallNode` | `:send` | Method calls |
| `LocalVariableReadNode` | `:lvar` | |
| `LocalVariableWriteNode` | `:lvasgn` | |
| `InstanceVariableReadNode` | `:ivar` | |
| `InstanceVariableWriteNode` | `:ivasgn` | |
| `StringNode` | `:str` | |
| `IntegerNode` | `:int` | |
| `FloatNode` | `:float` | |
| `SymbolNode` | `:sym` | |
| `ArrayNode` | `:array` | |
| `HashNode` | `:hash` | |
| `DefNode` | `:def` | |
| `ClassNode` | `:class` | |
| `ModuleNode` | `:module` | |
| `IfNode` | `:if` | |
| `CaseNode` | `:case` | |
| `WhileNode` | `:while` | |
| ... | ... | ~100 more |

Full mapping would be developed during Phase 1.
