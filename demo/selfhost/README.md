# Self-Hosted Ruby2JS

This directory contains Ruby2JS running entirely in JavaScript, using the actual Ruby2JS converter transpiled from Ruby source.

## Goals

The goal is **not** to create a separate JavaScript implementation of Ruby2JS. That approach—while it could pass the same test suite—would require maintaining two different codebases in perpetuity.

Instead, the goal is to:

1. **Identify gaps** in Ruby2JS's ability to transpile Ruby to JavaScript
2. **Fix those gaps** in the Ruby implementation so it can transpile itself
3. **Produce two compatible implementations from one source**: the original Ruby and the transpiled JavaScript

This "dogfooding" approach ensures that improvements benefit all Ruby2JS users, not just the selfhost. When a Ruby pattern doesn't transpile correctly, we fix the converter or filters—making Ruby2JS better for everyone.

## Status: Filters In Progress

A single `ruby2js.mjs` bundle provides the full converter for both CLI and browser use. The same code is tested in CI, runs in Node.js CLI, and works in browsers.

**Supported:**
- Classes, methods, blocks, string interpolation
- Arrays, hashes, if/else/case, loops, operators
- Comments (preserved in output)
- Full transliteration, serializer, and namespace test suites passing
- **Functions filter**: 123/191 tests passing (64%)

**In Progress:**
- Functions filter (partial support, transpiled from Ruby source)
- Filter infrastructure (SEXP helpers, FilterProcessor base class)

**Not yet supported:**
- Other filters (camelCase, esm, react, stimulus, etc.)
- Full configuration options

## Architecture

```
Ruby Source Code
       ↓
@ruby/prism (WebAssembly)
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

## Quick Start

```bash
cd demo/selfhost
npm install
npm run build
npm test
```

## Key Files

| File | LOC | Description |
|------|-----|-------------|
| `ruby2js.mjs` | 15,218 | Unified bundle - CLI and importable module |
| `prism_browser.mjs` | 231 | Browser WASM loader for Prism |
| `browser_demo.html` | 388 | Browser demo page |
| `test_harness.mjs` | 435 | Test framework for specs |
| `run_all_specs.mjs` | 309 | Manifest-driven spec runner for CI |
| `spec_manifest.json` | 36 | Spec status tracking (ready/partial/blocked) |
| `dist/` | — | Transpiled specs and filters |

### Scripts

| File | LOC | Description |
|------|-----|-------------|
| `scripts/transpile_bundle.rb` | 87 | Transpiles Ruby2JS bundle to JS |
| `scripts/transpile_filter.rb` | 207 | Transpiles filters (e.g., functions) to JS |
| `scripts/transpile_spec.rb` | 39 | Transpiles RSpec files to JS |
| `scripts/transpile_prism_browser.rb` | 28 | Transpiles browser Prism loader |
| `scripts/test_handlers.rb` | 94 | Test helper for converter handlers |

### Transpiled Output (dist/)

| File | LOC | Description |
|------|-----|-------------|
| `dist/functions_filter.mjs` | 2,040 | Transpiled Functions filter |
| `dist/functions_spec.mjs` | 1,077 | Transpiled Functions filter tests |
| `dist/transliteration_spec.mjs` | 1,391 | Transpiled transliteration tests |
| `dist/serializer_spec.mjs` | 333 | Transpiled serializer tests |
| `dist/namespace_spec.mjs` | 62 | Transpiled namespace tests |

## Source Files

The unified bundle is transpiled from Ruby source files:

| Ruby Source | LOC | JavaScript Output |
|-------------|-----|-------------------|
| `lib/ruby2js/selfhost/bundle.rb` | 94 | `ruby2js.mjs` |
| `lib/ruby2js/selfhost/runtime.rb` | 176 | (inlined in bundle) |
| `lib/ruby2js/selfhost/cli.rb` | 424 | (inlined in bundle) |
| `lib/ruby2js/selfhost/prism_browser.rb` | 117 | `prism_browser.mjs` |
| `lib/ruby2js/namespace.rb` | 86 | (inlined in bundle) |
| `lib/ruby2js/prism_walker.rb` | 261 | (inlined in bundle) |
| `lib/ruby2js/converter.rb` + handlers | 548+ | (inlined in bundle) |
| `lib/ruby2js/filter/processor.rb` | 333 | (in bundle, for filter base class) |
| `lib/ruby2js/filter/functions.rb` | 1,455 | `dist/functions_filter.mjs` |

## npm Scripts

| Script | Description |
|--------|-------------|
| `npm test` | Run all tests (CLI, walker, specs) |
| `npm run build` | Build bundle, prism_browser, and specs |
| `npm run build:bundle` | Regenerate ruby2js.mjs from Ruby source |
| `npm run build:prism-browser` | Regenerate prism_browser.mjs |
| `npm run build:spec` | Transpile test specs |
| `npm run clean` | Remove generated files |

## Spec Runner Options

The spec runner (`run_all_specs.mjs`) supports several options:

```bash
# Run all specs (ready specs must pass, partial are informational)
node run_all_specs.mjs

# Show failure details for partial specs
node run_all_specs.mjs --verbose

# Only run ready specs (CI mode)
node run_all_specs.mjs --ready-only

# Only run partial specs (development mode)
node run_all_specs.mjs --partial-only

# Skip transpilation (use pre-built dist/*.mjs files)
node run_all_specs.mjs --skip-transpile
```

Spec status is tracked in `spec_manifest.json`:
- **ready**: Must pass (CI fails if they don't)
- **partial**: Run but don't fail CI (in development)
- **blocked**: Skipped with explanation (waiting on dependencies)

## CLI Usage

```bash
# Basic conversion (reads from stdin or file)
echo 'puts "hello"' | node ruby2js.mjs
node ruby2js.mjs myfile.rb

# Show raw Prism AST
echo 'x = 1' | node ruby2js.mjs --ast

# Show Walker AST (Parser-compatible format)
echo 'x = 1' | node ruby2js.mjs --walker-ast

# Find nodes in AST
echo 'x ||= 1' | node ruby2js.mjs --find=OrAssign

# Full help
node ruby2js.mjs --help
```

## Browser Usage

Import directly from the bundle:

```html
<script type="module">
  import { convert } from './ruby2js.mjs';

  const js = convert('puts "hello"');
  console.log(js); // console.log("hello")
</script>
```

Or open `browser_demo.html` via a local server:

```bash
npx serve .
# Open http://localhost:3000/browser_demo.html
```

## Exported API

The bundle exports:

```javascript
import {
  convert,           // Main conversion function
  Ruby2JS,           // Module with internal classes
  initPrism,         // Initialize Prism parser
  getPrismParse,     // Get the Prism parse function
  // Plus runtime classes for advanced usage
} from './ruby2js.mjs';

// Simple usage
const js = convert(rubySource, { eslevel: 2022 });

// Access internal classes
const { PrismWalker, Converter, Serializer, Node, Namespace } = Ruby2JS;
```

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
  Ruby2JS::Filter::Polyfill,         # Ruby method polyfills
  Ruby2JS::Filter::Functions,        # Ruby methods → JS
  Ruby2JS::Filter::Return,           # Autoreturn for methods
  Ruby2JS::Filter::ESM               # ES module exports
]
```

## Known Limitations

- **Some tests skipped**: Proc source location and similar JavaScript limitations
- **Partial filter support**: Functions filter is 64% passing (123/191 tests)
- **Blocked specs**: Most filter specs still blocked - see `spec_manifest.json` for details
- **Super handling**: Ruby's `super` in filter methods needs manual fixup in transpiled output

## Future Work

1. Complete Functions filter (remaining 68 failing tests)
2. Transpile additional filters (camelCase, esm, react, etc.)
3. Add configuration options
4. Reduce manual fixups needed in `transpile_filter.rb`

## References

- [plans/SELF_HOSTING.md](../../plans/SELF_HOSTING.md) - Original roadmap
- [plans/PRAGMA_SELFHOST.md](../../plans/PRAGMA_SELFHOST.md) - Implementation details
