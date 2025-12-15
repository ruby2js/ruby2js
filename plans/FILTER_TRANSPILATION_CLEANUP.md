# Filter Transpilation Cleanup Plan

## Goal

Make filter transpilation a clean, declarative process: just specify which filters to apply in what order, with no manual gsubs or preambles. The transpile script should become:

```ruby
js = Ruby2JS.convert(source,
  eslevel: 2022,
  filters: [...],
  # options
).to_s
puts js
```

## Current State

`demo/selfhost/scripts/transpile_filter.rb` has:
- **~90 lines of preamble** (imports, helper functions, infrastructure)
- **12 gsub operations** (post-processing fixes)
- **~20 lines of postamble** (registration, exports)

## Analysis

### Gsubs to Eliminate

| # | Pattern | Purpose | Classification |
|---|---------|---------|----------------|
| 1 | Remove `const Ruby2JS = {Filter: (() => {` | Fix module wrapper | Selfhost-specific |
| 2 | Remove `return {Functions}` IIFE tail | Fix module wrapper | Selfhost-specific |
| 3-6 | Fix empty ternary/assignment/return from `super` | Handle Ruby filter super calls | **General-use** (affects all filters) |
| 7 | `this._options` → `_options` | Module-level options | Selfhost-specific |
| 8 | `x === s(...)` → `nodesEqual(x, s(...))` | AST structural comparison | Selfhost-specific |
| 9 | Fix mutating `compact` polyfill | Non-mutating compact for frozen arrays | **General-use** (polyfill filter) |
| 10 | `Regexp.` → `RegExp.` | Ruby constant to JS | **General-use** (converter) |
| 11 | `s("const", null, Object)` → `s("const", null, "Object")` | Quote Object constant | Selfhost-specific |
| 12 | Spread regopt node fix | Children spread issue | Selfhost-specific |

### Preamble Items

| Item | Purpose | Classification |
|------|---------|----------------|
| Import statement | Load ruby2js.js | Selfhost-specific (ESM output) |
| Parser.AST.Node alias | Bridge Ruby Parser gem API | Selfhost-specific |
| SEXP helpers (s, S) | AST construction | Selfhost-specific |
| `ast_node` function | Check if value is AST node | Selfhost-specific |
| `include = () => {}` | No-op for Ruby's include | Selfhost-specific |
| Filter.exclude/include | No-op stubs | Selfhost-specific |
| DEFAULTS array | Filter registration | Selfhost-specific |
| Filter infrastructure | excluded, included, process, etc. | Selfhost-specific |
| ES level getters | es2015-es2025 property checks | Selfhost-specific |
| `nodesEqual` function | AST structural comparison | Selfhost-specific |

### Postamble Items

| Item | Purpose | Classification |
|------|---------|----------------|
| DEFAULTS.push | Register filter | Selfhost-specific |
| Ruby2JS.Filter.X assignment | Namespace registration | Selfhost-specific |
| `_setup` function | Bind infrastructure at runtime | Selfhost-specific |
| ES module export | ESM compatibility | Selfhost-specific |

## Proposed Changes

### Phase 1: General-Use Improvements

These changes benefit all Ruby2JS users, not just selfhost.

#### 1.1 Fix `Regexp` → `RegExp` in Converter

**Location**: `lib/ruby2js/converter/const.rb` (or new converter)

**Current**: Only converts at ES2025+ level.

**Change**: Always convert `Regexp` → `RegExp` (it's the same thing in JS).

```ruby
# In converter, when encountering Regexp constant
handle :const do |*args|
  # ...existing code...
  if name == :Regexp
    put 'RegExp'
    return
  end
  # ...
end
```

**Rationale**: There's no reason to emit `Regexp` in JavaScript output; it doesn't exist.

#### 1.2 Fix Polyfill `compact` to be Non-Mutating

**Location**: `lib/ruby2js/filter/polyfill.rb`

**Current**: The polyfill modifies the array in place (like `compact!`).

**Change**: Use `filter()` for non-mutating behavior:

```ruby
# Change from:
Object.defineProperty(Array.prototype, "compact", {
  get() {
    let i = this.length - 1;
    while (i >= 0) {
      if (this[i] === null || this[i] === undefined) this.splice(i, 1);
      i--
    };
    return this
  },
  configurable: true
});

# To:
Object.defineProperty(Array.prototype, "compact", {
  get() { return this.filter(x => x !== null && x !== undefined); },
  configurable: true
});
```

**Rationale**: Ruby's `compact` returns a new array; `compact!` mutates. The polyfill should match Ruby semantics.

**Additional fix (2024-12-14)**: Added `compact!` handling to Functions filter. When Ruby code uses `compact!`, it now transpiles to:
```javascript
array.splice(0, array.length, ...array.filter(x => x != null))
```
This mutates the array in place, matching Ruby's `compact!` semantics.

#### 1.3 Handle `super` in Filter Methods

**Location**: `lib/ruby2js/filter/selfhost/converter.rb` or new filter

**Problem**: Ruby filters use `super` to delegate to the next filter in the chain. When transpiled, `super` becomes empty because JS classes don't have the same filter chain mechanism.

**Current gsubs**:
```ruby
js = js.gsub(/: (\s*}\s*(?:else|$))/, ': process_children(node)\1')
js = js.gsub(/: (\s*;)/, ': process_children(node)\1')
js = js.gsub(/= ;/, '= process_children(node);')
js = js.gsub(/return (\s*}\s*(?:else|$))/, 'return process_children(node)\1')
js = js.gsub(/return (\s*;)/, 'return process_children(node)\1')
```

**Solution**: Add AST-level handling in selfhost filter to detect `super` calls in filter `on_*` methods and replace with `process_children(node)`.

This is tricky because:
- `super` with no args should become `process_children(node)`
- `super(x)` should become `process(x)`

**Classification**: While this affects "all filters", it's only relevant when transpiling filters to JS, which is a selfhost-specific use case.

### Phase 2: Selfhost Filter Module Infrastructure

Create a new filter: `lib/ruby2js/filter/selfhost/filter.rb`

This filter would be applied when transpiling a Ruby2JS filter to JavaScript. It handles:

#### 2.1 Module Structure Detection

Detect the Ruby filter module pattern:
```ruby
module Ruby2JS
  module Filter
    module Functions
      # ...
    end
    DEFAULTS << Functions
  end
end
```

Transform to JS class/object with proper exports.

#### 2.2 Generate Preamble

When the filter detects it's processing a Ruby2JS filter, prepend:

```javascript
import { Ruby2JS } from '../ruby2js.js';

const Parser = { AST: { Node: Ruby2JS.Node } };
const SEXP = Ruby2JS.Filter.SEXP;
const s = SEXP.s.bind(SEXP);
const S = s;

const ast_node = (node) => {
  if (!node || typeof node !== 'object') return false;
  return 'type' in node && 'children' in node;
};

// ... rest of infrastructure
```

#### 2.3 Handle `this._options` → `_options`

Transform instance variable access to module-level variable.

#### 2.4 Handle AST Comparisons

Transform `node === s(:type, ...)` to `nodesEqual(node, s(:type, ...))`.

This requires pattern detection:
- LHS is a variable or property access
- RHS is an `s(...)` call
- Operator is `===` or `==`

#### 2.5 Handle `super` Calls

As described in 1.3, but implemented in the AST.

#### 2.6 Generate Postamble

Append filter registration and ES module export:

```javascript
DEFAULTS.push(FilterName);
Ruby2JS.Filter.FilterName = FilterName;

FilterName._setup = function(opts) {
  // ... bind infrastructure
};

export { FilterName as default, FilterName };
```

### Phase 3: Handle Edge Cases

#### 3.1 Object Constant Quoting

Pattern: `s("const", null, Object)` where `Object` is the JS global.

**Solution**: In the selfhost filter, when creating `s()` calls with constant references to JS globals (`Object`, `Array`, `String`, etc.), quote them as strings.

#### 3.2 Regopt Node Spread

Pattern: `...arg.children.last` where `last` is a regopt node.

**Problem**: Regopt nodes need `.children` to be spread, not the node itself.

**Solution**: Detect spread of `.last` or similar on children arrays and wrap appropriately:
```javascript
...(arg.children.last.children || [])
```

### Phase 4: Remove gsubs from transpile_filter.rb

After implementing Phases 1-3, update `transpile_filter.rb` to:

```ruby
#!/usr/bin/env ruby
require 'ruby2js'
require 'ruby2js/filter/selfhost'
require 'ruby2js/filter/selfhost/filter'  # NEW
# ... other requires

filter_file = ARGV[0] || raise("Usage: transpile_filter.rb <filter_file>")
source = File.read(filter_file)

js = Ruby2JS.convert(source,
  eslevel: 2022,
  comparison: :identity,
  underscored_private: true,
  selfhost_filter: true,  # NEW: enables filter-specific handling
  filters: [
    Ruby2JS::Filter::Pragma,
    Ruby2JS::Filter::Selfhost::Filter,  # NEW
    Ruby2JS::Filter::Selfhost::Core,
    Ruby2JS::Filter::Selfhost::Converter,
    Ruby2JS::Filter::Polyfill,
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM
  ]
).to_s

puts js
```

No gsubs. No preamble. No postamble.

## Implementation Order

### Immediate (Low Risk, High Value) ✅ COMPLETE

1. ✅ **Fix polyfill `compact`** - Changed to non-mutating `filter()` approach
2. ✅ **Fix `Regexp` → `RegExp`** - Now always converts in const.rb

### Short Term (Selfhost Infrastructure)

3. **Create `selfhost/filter.rb`** - New filter for filter transpilation
4. **Move preamble generation** - Into the new filter
5. **Move postamble generation** - Into the new filter
6. **Handle `this._options`** - In new filter

### Medium Term (Complex AST Handling)

7. **Handle `super` calls** - Requires AST pattern matching
8. **Handle AST comparisons** - Requires pattern detection
9. **Handle Object constant quoting** - Edge case
10. **Handle regopt spread** - Edge case

### Validation

After each phase, run:
```bash
cd demo/selfhost
npm run build:filters
npm test
```

Verify 183+ functions filter tests still pass.

## Success Criteria

### Phase 1: Syntactically Valid JavaScript ✅ COMPLETE

All 27 filters transpile to syntactically valid JavaScript (verified 2024-12-14):

```
✓ action_cable    ✓ active_functions  ✓ active_support
✓ alpine          ✓ camelCase         ✓ cjs
✓ combiner        ✓ erb               ✓ esm
✓ functions       ✓ haml              ✓ jest
✓ jsx             ✓ lit-element       ✓ lit
✓ node            ✓ nokogiri          ✓ phlex
✓ polyfill        ✓ pragma            ⊘ processor (base class, skipped)
✓ react           ✓ require           ✓ return
✓ securerandom    ⊘ selfhost (loader, skipped)
✓ stimulus        ✓ tagged_templates  ✓ turbo
```

**Specs status** (48/51 transpile to valid JS):
- 48 specs transpile successfully
- 3 expected failures: execjs_spec (skip statement issue), selfhost_spec_spec, selfhost_walker_spec (meta specs)

**Note on ExecJS**: The ExecJS module will need a completely different implementation in JavaScript—it will likely reduce to `eval`. This allows writing code that works in both Ruby (using ExecJS to run JS) and JavaScript (using eval directly) environments.

**Validation**: For each transpiled file, run:
```bash
node --check filters/<name>.js
```

### Phase 2: Clean Transpilation Process

1. `transpile_filter.rb` has no gsubs
2. `transpile_filter.rb` has no heredoc preamble/postamble
3. Filter transpilation is purely declarative (specify filters, get output)

### Phase 3: Functional Tests

**Current test results** (2024-12-14, latest):

| Category | Status | Tests |
|----------|--------|-------|
| Ready specs | ✅ 3/3 passing | 290 tests (transliteration, serializer, namespace) |
| Partial specs | 8 filters tested | See matrix below |

#### Filter Test Matrix

| Filter | Syntax Valid | Tests Passing | Pass Rate | Notes |
|--------|--------------|---------------|-----------|-------|
| functions | ✓ | 189/203 | 93% | High coverage |
| camelCase | ✓ | 17/19 | 89% | Near ready |
| tagged_templates | ✓ | 6/7 | 86% | Near ready |
| return | ✓ | 8/25 | 32% | Needs work |
| esm | ✓ | 4/40 | 10% | Needs work |
| cjs | ✓ | 1/19 | 5% | Needs work |
| polyfill | ✓ | 0/0 | N/A | No spec tests |
| pragma | ✓ | 0/71 | 0% | Needs work |

#### Blocked Filters

These filters have transpilation issues that need selfhost improvements:

| Filter | Issue |
|--------|-------|
| securerandom | `extend SEXP` Ruby DSL not supported |
| node | `extend SEXP` Ruby DSL not supported |
| combiner | Ruby2JS constant redeclaration |
| react | Empty `let ;` statement from super |

#### Recent Progress (2024-12-14)

**AST-level transformations added to `selfhost/filter.rb`:**
- ✅ `nodesEqual` - AST structural comparison (`x == s(...)` → `nodesEqual(x, s(...))`)
- ✅ Instance variable to module-level (`@options` → `_options`)
- ✅ Writer method renaming (`def options=` → `def set_options`)
- ✅ Singleton methods (`def self.X` → `function X`) - fixes IIFE context issue

**Converter improvements:**
- ✅ Fixed assignment in logical expressions (parentheses for `a && (b = c)`)
- ✅ Fixed `respond_to?` with implicit self target
- ✅ Dynamic filter name extraction from transpiled output

**Test harness improvements:**
- ✅ Auto-load filters based on spec name
- ✅ Filter-to-file mapping for non-standard names (e.g., `camelcase_spec.rb` → `camelCase.js`)

#### Functions Filter Failure Analysis (14 remaining)

| Category | Count | Description |
|----------|-------|-------------|
| **Block-pass (`&:method`)** | 3 | Symbol-to-proc not expanded |
| **Metaprogramming** | 5 | Missing class context |
| **Class.new object literal** | 4 | Anonymous class → object literal |
| **Runtime errors** | 2 | matchAll undefined, body.length() |

## Completion Criteria

The plan is complete when:

1. **All 29 filters** transpile to syntactically valid JavaScript
2. **All filter specs** transpile to syntactically valid JavaScript
3. **Pass/fail matrix** is generated for all filter test suites
4. **No manual post-processing** required in transpile scripts

At that point, we can assess which filters are ready for production use and prioritize fixing the remaining failures based on user demand.

## Next Steps After Completion

Based on the pass/fail matrix:

1. Identify filters with high pass rates (>90%) - candidates for immediate release
2. Identify filters with common failure patterns - may indicate missing selfhost handling
3. Prioritize fixes based on filter popularity/demand
4. Consider which filters are essential for the npm package vs. optional
