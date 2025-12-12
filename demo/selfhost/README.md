# Self-Hosted Ruby2JS

This directory contains Ruby2JS running entirely in JavaScript, using the actual Ruby2JS converter transpiled from Ruby source.

## Status: Unified Bundle Complete

A single `ruby2js.mjs` bundle provides the full converter for both CLI and browser use. The same code is tested in CI, runs in Node.js CLI, and works in browsers.

**Supported:**
- Classes, methods, blocks, string interpolation
- Arrays, hashes, if/else/case, loops, operators
- Comments (preserved in output)
- Full transliteration and serializer test suites passing

**Not yet supported:**
- Filters (functions, camelCase, esm, etc.)
- Other configuration options

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

| File | Description |
|------|-------------|
| `ruby2js.mjs` | Unified bundle - CLI and importable module |
| `prism_browser.mjs` | Browser WASM loader for Prism |
| `browser_demo.html` | Browser demo page |
| `test_harness.mjs` | Test framework for specs |
| `run_all_specs.mjs` | Manifest-driven spec runner for CI |
| `dist/` | Transpiled test specs only |

## Source Files

The unified bundle is transpiled from Ruby source files:

| Ruby Source | JavaScript Output |
|-------------|-------------------|
| `lib/ruby2js/selfhost/bundle.rb` | `ruby2js.mjs` |
| `lib/ruby2js/selfhost/runtime.rb` | (inlined in bundle) |
| `lib/ruby2js/selfhost/cli.rb` | (inlined in bundle) |
| `lib/ruby2js/selfhost/prism_browser.rb` | `prism_browser.mjs` |
| `lib/ruby2js/namespace.rb` | (inlined in bundle) |
| `lib/ruby2js/prism_walker.rb` | (inlined in bundle) |
| `lib/ruby2js/converter.rb` + handlers | (inlined in bundle) |

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
- **No filters**: The `functions`, `camelCase`, `esm`, etc. filters are not yet transpiled
- **Blocked specs**: Some specs require filters - see `spec_manifest.json` for details

## Future Work

1. Transpile filters to JavaScript
2. Add configuration options

## References

- [plans/SELF_HOSTING.md](../../plans/SELF_HOSTING.md) - Original roadmap
- [plans/PRAGMA_SELFHOST.md](../../plans/PRAGMA_SELFHOST.md) - Implementation details
