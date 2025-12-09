# Self-Hosted Ruby2JS

This directory contains a proof-of-concept demonstrating Ruby2JS running entirely in JavaScript, using the actual Ruby2JS converter transpiled from Ruby source.

## Status: Phase 6 Complete (CI Integration)

See `plans/PRAGMA_SELFHOST.md` for the full roadmap.

- [x] Phase 1: Filter infrastructure (pragma, combiner, require filters)
- [x] Phase 2: Walker transpilation (prism_walker.rb → JavaScript)
- [x] Phase 3: Converter transpilation (converter.rb + 60 handlers → JavaScript)
- [x] Phase 4: Spec integration and debugging (225/249 passing, 12 skipped)
- [x] Phase 5: Browser demo (browser_demo.html with WASI polyfill)
- [x] Phase 6: CI integration (spec manifest system)

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
| `run_all_specs.mjs` | Manifest-driven spec runner for CI |
| `run_spec.mjs` | Run a single spec file |
| `spec_manifest.json` | Spec readiness manifest (ready/partial/blocked) |
| `browser_demo.html` | Browser demo with WASI polyfill |
| `prism_browser.mjs` | Browser-compatible @ruby/prism loader |
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
| `npm test` | Run walker unit tests + all specs via manifest |
| `npm run test:walker` | Run walker unit tests only (31 tests) |
| `npm run test:spec` | Run a single spec file |
| `npm run test:all-specs` | Run all specs via manifest |
| `npm run build` | Build walker, converter, and spec |
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

## Spec Manifest System

The `spec_manifest.json` file tracks which specs are ready to run in the selfhost environment:

```json
{
  "ready": ["transliteration_spec.rb"],
  "partial": [{"spec": "serializer_spec.rb", "reason": "...", "expected_pass": 6}],
  "blocked": {"comments_spec.rb": "needs filters", ...}
}
```

### Categories

| Category | CI Behavior | When to Use |
|----------|-------------|-------------|
| `ready` | Must pass (CI fails if they don't) | Fully working specs |
| `partial` | Run but don't fail CI | Specs that partially work |
| `blocked` | Skipped with explanation | Specs waiting on dependencies |

### Current Status

- **Ready**: `transliteration_spec.rb` (225 passed, 12 skipped)
- **Partial**: `serializer_spec.rb` (6 passed, 20 failed - needs polyfills)
- **Blocked**: 24 specs (waiting on filters to be transpiled)

### Adding New Specs

1. Add to `blocked` with reason explaining what's needed
2. When partially working, move to `partial` with `expected_pass` count
3. When fully working, move to `ready`

## Browser Demo

The `browser_demo.html` file demonstrates Ruby2JS running entirely in the browser:

- Uses `prism_browser.mjs` - WASI polyfill for @ruby/prism WebAssembly
- Loads transpiled walker and converter
- Provides interactive Ruby → JavaScript conversion

To run locally:
```bash
# Start a local server
python3 -m http.server 8080
# Open http://localhost:8080/browser_demo.html
```

## Known Limitations

- **Comments not preserved**: Ruby comments are not yet included in JavaScript output. Requires implementing `associate_comments` logic in JavaScript to map Prism comments to AST nodes.

## Future Work

1. **Transpile filters to JavaScript** (biggest blocker for most specs)
2. Implement `associate_comments` in JavaScript for comment preservation
3. Fix remaining serializer spec failures
4. Move specs from blocked → partial → ready as dependencies are met
5. Eventually: scan spec directory like Ruby tests do

## Known Skipped Tests

12 tests are currently skipped in the selfhost environment. These use `skip() if defined? Function`
which activates in JavaScript but not Ruby. See PRAGMA_SELFHOST.md for detailed root causes.

| Issue | Fix Approach | Files to Debug |
|-------|--------------|----------------|
| Empty heredocs | Adjust trailing newline handling | converter/xstr.rb, heredoc handling |
| Redo within loop | Fix `@state[:loop]` tracking | converter/next.rb, while.rb |
| Singleton method | Debug `on_defs` handler | converter/defs.rb |
| Class extensions | Convert Hash iteration to `Object.entries` | converter/class.rb |
| Hash pattern destructuring | Add `visit_hash_pattern_node` | prism_walker.rb |
| Switch/case whitespace | Fix `respace` blank line logic | serializer.rb |

### Debugging Skipped Tests

1. **Identify the test**: Find the test in `spec/transliteration_spec.rb` with `skip() if defined? Function`

2. **Compare Ruby vs JS output**:
   ```bash
   # Ruby output
   bin/ruby2js -e 'YOUR_RUBY_CODE_HERE'

   # JS output
   echo 'YOUR_RUBY_CODE_HERE' | node demo/selfhost/ruby2js.mjs --stdin
   ```

3. **Inspect AST differences**:
   ```bash
   # Ruby AST
   bin/ruby2js --ast -e 'YOUR_CODE'

   # JS Walker AST
   echo 'YOUR_CODE' | node demo/selfhost/ruby2js.mjs --stdin --walker-ast
   ```

4. **For serializer issues**, use `test_serializer.mjs`:
   ```bash
   cd demo/selfhost
   node test_serializer.mjs
   ```

5. **For converter issues**, add console.log in the transpiled `dist/converter.mjs` to trace handler execution.

## References

- [PRAGMA_SELFHOST.md](../../plans/PRAGMA_SELFHOST.md) - Detailed implementation plan with skipped test details
- [SELF_HOSTING.md](../../plans/SELF_HOSTING.md) - Original roadmap
