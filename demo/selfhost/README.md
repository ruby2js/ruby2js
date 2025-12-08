# Self-Hosted Ruby2JS

This directory contains a proof-of-concept demonstrating Ruby2JS running entirely in JavaScript, using the actual Ruby2JS converter transpiled from Ruby source.

## Status: Phase 4 In Progress (Spec Integration)

See `plans/PRAGMA_SELFHOST.md` for the full roadmap.

- [x] Phase 1: Filter infrastructure (pragma, combiner, require filters)
- [x] Phase 2: Walker transpilation (prism_walker.rb → JavaScript)
- [x] Phase 3: Converter transpilation (converter.rb + 60 handlers → JavaScript)
- [ ] Phase 4: Spec integration and debugging (73/249 tests passing)
- [ ] Phase 5: Spec transpilation
- [ ] Phase 6: Browser demo integration

## Architecture

```
Ruby Source Code
       ↓
@ruby/prism (WebAssembly, ~2MB)
       ↓
Prism AST (JavaScript objects)
       ↓
PrismWalker (transpiled from lib/ruby2js/prism_walker.rb)
       ↓
Parser-compatible AST (Ruby2JS::Node format)
       ↓
Converter (transpiled from lib/ruby2js/converter.rb + handlers)
       ↓
JavaScript Output
```

## Key Files

| File | Description |
|------|-------------|
| `dist/converter.mjs` | Transpiled converter (~11,700 lines) |
| `dist/walker.mjs` | Transpiled PrismWalker |
| `dist/transliteration_spec.mjs` | Transpiled test suite |
| `ruby2js.mjs` | CLI debugging tool for JS converter |
| `test_harness.mjs` | Minitest-compatible test framework |
| `test_walker.mjs` | Unit tests for PrismWalker (29 tests) |
| `scripts/transpile_converter.rb` | Build script for converter |
| `scripts/transpile_walker.rb` | Build script for walker |
| `scripts/transpile_spec.rb` | Build script for specs |

## Quick Start

```bash
cd demo/selfhost
npm install

# Build transpiled files
npm run build:converter   # Transpile converter
npm run build:walker      # Transpile walker
npm run build:spec        # Transpile test suite

# Run tests
npm test
```

## npm Scripts

| Script | Description |
|--------|-------------|
| `npm test` | Run walker unit tests + spec tests |
| `npm run test:walker` | Run walker unit tests only (29 tests) |
| `npm run test:spec` | Run spec tests only (249 tests) |
| `npm run build` | Build walker and spec |
| `npm run build:converter` | Regenerate converter from Ruby source |
| `npm run build:walker` | Regenerate walker from Ruby source |
| `npm run build:spec` | Regenerate spec from Ruby source |

## Filter Chain

The transpilation uses this filter chain:

```ruby
filters: [
  Ruby2JS::Filter::Pragma,           # Handle # Pragma: skip
  Ruby2JS::Filter::Combiner,         # Merge reopened classes
  Ruby2JS::Filter::Require,          # require_relative → inline
  Ruby2JS::Filter::Selfhost::Core,   # Core transformations
  Ruby2JS::Filter::Selfhost::Walker, # private/protected removal
  Ruby2JS::Filter::Selfhost::Converter, # handle :type patterns
  Ruby2JS::Filter::Functions,        # Ruby methods → JS
  Ruby2JS::Filter::Return,           # Autoreturn for methods
  Ruby2JS::Filter::ESM               # ES module exports
]
```

## Philosophy

### Pragma-Based Approach

The self-hosting uses a **pragma-based approach** where Ruby source files are annotated with special comments that guide transpilation:

```ruby
require 'prism' # Pragma: skip   # Don't transpile this require

def respond_to?(method) # Pragma: skip   # Skip this method entirely
  # ...
end
```

This allows the same Ruby source to:
1. Run normally in Ruby (pragmas are just comments)
2. Transpile correctly to JavaScript (pragmas guide transformations)

### What Belongs Where

| Pattern | Filter | Notes |
|---------|--------|-------|
| `.freeze` removal | functions | No-op in JS |
| `.to_sym` removal | functions | Symbols are strings |
| `arr[-1] = x` | functions | Negative index assignment |
| `(a..b).step(n)` | functions + for.rb | Range with step |
| Autoreturn | return | Method bodies |
| `# Pragma: skip` | pragma | Skip statements |
| `handle :type` | selfhost/converter | Handler pattern |
| `private`/`protected` | selfhost/walker | Visibility modifiers |

## Generated Output

The transpiled converter is ~11,700 lines of JavaScript containing:

- `Token` class - Source token wrapper
- `Line` class - Output line management
- `Serializer` class - Output formatting
- `Converter` class - AST to JavaScript conversion
- 60+ handler methods (`on_send`, `on_def`, `on_class`, etc.)

## Size Comparison

| Approach | Size | Notes |
|----------|------|-------|
| Self-hosted | ~2.5MB | prism.wasm + walker + converter |
| Opal-based | ~24MB | Opal runtime + parser gem + Ruby2JS |

~10x smaller than the Opal-based approach.

## Source File Modifications

The following Ruby source files required modifications for transpilation:

### lib/ruby2js/serializer.rb
- Changed `each_with_index` + `break` to `while` loop (JS `forEach` can't break)
- Added `# Pragma: skip` to `[]`, `[]=`, `<<` methods (not valid JS method names)
- Added alternative methods: `at`, `set`, `append`
- Changed `yield` to explicit `&block` parameter

### lib/ruby2js/converter.rb
- Applied `jsvar()` to pending variable declarations (handles reserved words like `function`)
- Enhanced comment handling for edge cases

### lib/ruby2js/converter/case.rb, regexp.rb
- Refactored rest parameters to be last (JS requirement)

### lib/ruby2js/converter/send.rb
- Wrapped `throw` in IIFE when in expression context (JS limitation)

## Debugging

The `ruby2js.mjs` CLI tool helps debug transpilation issues:

```bash
# Basic conversion (reads from stdin)
echo 'self.foo ||= 1' | node ruby2js.mjs --stdin

# Show raw Prism AST (JS @ruby/prism output)
echo 'self.foo' | node ruby2js.mjs --stdin --ast

# Show Walker AST (after PrismWalker transforms to Parser-compatible format)
echo 'self.foo' | node ruby2js.mjs --stdin --walker-ast

# Find a specific node type in the AST
echo 'self.foo ||= 1' | node ruby2js.mjs --stdin --find OrAssignNode

# Inspect specific property paths
echo 'self.foo ||= 1' | node ruby2js.mjs --stdin --inspect "value.name.receiver"
```

Compare with Ruby-side output using `bin/ruby2js --ast` and `bin/ruby2js --filtered-ast`.

## Next Steps

### Phase 4: Spec Integration (IN PROGRESS)
Current status: 73/249 tests passing (29%)

Remaining issues:
- `_implicitBlockYield is not a function` errors
- Empty interpolation handling
- Mass assignment parsing
- Various converter handler issues

### Phase 5: Spec Transpilation
1. Extend `selfhost/spec.rb` for full Minitest support
2. Transpile complete test suite to JavaScript
3. Run tests in Node.js

### Phase 6: Browser Demo
1. Create unified module exporting `Ruby2JS.convert()`
2. Update `browser_demo.html` to use real converter
3. Document any remaining limitations

## References

- [PRAGMA_SELFHOST.md](../../plans/PRAGMA_SELFHOST.md) - Detailed implementation plan
- [SELF_HOSTING.md](../../plans/SELF_HOSTING.md) - Original roadmap
