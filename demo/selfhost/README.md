# Self-Hosted Ruby2JS

This directory contains Ruby2JS running entirely in JavaScript, using the actual Ruby2JS converter transpiled from Ruby source.

## Status: Transliteration Complete

The full transliteration test suite passes. Two tests are intentionally skipped (Proc source location - a JavaScript limitation).

**Supported:**
- Classes, methods, blocks, string interpolation
- Arrays, hashes, if/else/case, loops, operators
- Comments (preserved in output)
- Full transliteration test suite

**Not yet supported:**
- eslevel options
- Filters
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

# Build transpiled files (using Rakefile - recommended)
rake build

# Or using npm scripts
npm run build

# Run tests
npm test
```

## Key Files

| File | Description |
|------|-------------|
| `dist/runtime.mjs` | Transpiled runtime classes (PrismSourceBuffer, Hash, etc.) |
| `dist/converter.mjs` | Transpiled converter |
| `dist/walker.mjs` | Transpiled PrismWalker |
| `dist/namespace.mjs` | Transpiled Namespace class |
| `dist/bundle.mjs` | Entry point that re-exports all modules |
| `prism_browser.mjs` | Browser WASM loader for Prism |
| `ruby2js.mjs` | CLI tool for JS converter |
| `browser_demo.html` | Browser demo page |
| `run_all_specs.mjs` | Manifest-driven spec runner for CI |

## Source Files

All JavaScript modules are transpiled from Ruby source files:

| Ruby Source | JavaScript Output |
|-------------|-------------------|
| `lib/ruby2js/selfhost/runtime.rb` | `dist/runtime.mjs` |
| `lib/ruby2js/selfhost/prism_browser.rb` | `prism_browser.mjs` |
| `lib/ruby2js/selfhost/bundle.rb` | `dist/bundle.mjs` |
| `lib/ruby2js/namespace.rb` | `dist/namespace.mjs` |
| `lib/ruby2js/prism_walker.rb` | `dist/walker.mjs` |
| `lib/ruby2js/converter.rb` + handlers | `dist/converter.mjs` |

## npm Scripts

| Script | Description |
|--------|-------------|
| `npm test` | Run all tests via manifest |
| `npm run build` | Build all transpiled files |
| `npm run build:runtime` | Regenerate runtime from Ruby source |
| `npm run build:prism-browser` | Regenerate prism_browser from Ruby source |
| `npm run build:namespace` | Regenerate namespace from Ruby source |
| `npm run build:walker` | Regenerate walker from Ruby source |
| `npm run build:converter` | Regenerate converter from Ruby source |
| `npm run build:bundle` | Regenerate bundle from Ruby source |
| `npm run clean` | Remove all transpiled files |

## Rake Tasks

The Rakefile provides dependency-aware builds (only rebuilds when source changes):

| Task | Description |
|------|-------------|
| `rake build` | Build all transpiled files |
| `rake build_ready` | Build core + ready specs |
| `rake test` | Build and run all tests |
| `rake ci` | CI build (ready must pass, partial informational) |
| `rake clean` | Remove dist directory |

## CLI Usage

```bash
# Basic conversion (reads from stdin)
echo 'puts "hello"' | node ruby2js.mjs --stdin

# Show raw Prism AST
echo 'x = 1' | node ruby2js.mjs --stdin --ast

# Show Walker AST (Parser-compatible format)
echo 'x = 1' | node ruby2js.mjs --stdin --walker-ast
```

## Browser Demo

Open `browser_demo.html` directly in a browser, or run via a local server:

```bash
# From demo/selfhost directory
npx serve .
# Open http://localhost:3000/browser_demo.html
```

The browser demo loads Prism WASM and runs the transpiled converter entirely client-side.

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

- **2 tests skipped**: Proc source location (JavaScript limitation - can't get source of a function)
- **No filters**: The `functions`, `camelCase`, `esm`, etc. filters are not yet transpiled
- **No eslevel**: ES level configuration options are not yet supported

## Future Work

1. Transpile filters to JavaScript
2. Add eslevel support
3. Add configuration options

## References

- [plans/SELF_HOSTING.md](../../plans/SELF_HOSTING.md) - Original roadmap
- [plans/PRAGMA_SELFHOST.md](../../plans/PRAGMA_SELFHOST.md) - Implementation details
