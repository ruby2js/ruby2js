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

# Build transpiled files
npm run build

# Run tests
npm test
```

## Key Files

| File | Description |
|------|-------------|
| `dist/converter.mjs` | Transpiled converter |
| `dist/walker.mjs` | Transpiled PrismWalker |
| `dist/namespace.mjs` | Transpiled Namespace class |
| `shared/runtime.mjs` | Shared runtime (comment handling, etc.) |
| `ruby2js.mjs` | CLI tool for JS converter |
| `run_all_specs.mjs` | Manifest-driven spec runner for CI |

## npm Scripts

| Script | Description |
|--------|-------------|
| `npm test` | Run all tests via manifest |
| `npm run build` | Build walker, converter, namespace, and spec |
| `npm run build:converter` | Regenerate converter from Ruby source |
| `npm run build:walker` | Regenerate walker from Ruby source |
| `npm run build:namespace` | Regenerate namespace from Ruby source |

## CLI Usage

```bash
# Basic conversion (reads from stdin)
echo 'puts "hello"' | node ruby2js.mjs

# Show raw Prism AST
echo 'x = 1' | node ruby2js.mjs --ast

# Show Walker AST (Parser-compatible format)
echo 'x = 1' | node ruby2js.mjs --walker-ast
```

## Browser Demo

The browser demo is at `docs/src/demo/selfhost/index.html`. To run locally:

```bash
# From repo root
cd docs
bundle exec rake selfhost
bin/bridgetown start
# Open http://localhost:4000/demo/selfhost/
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

## Shared Code

Comment handling is shared between Ruby and JavaScript:

- **Ruby**: `lib/ruby2js.rb` has `Ruby2JS.associate_comments` and `CommentsMap`
- **JavaScript**: `shared/runtime.mjs` has equivalent `associateComments` and uses `Map`

The CLI (`ruby2js.mjs`) and browser demo both import from `shared/runtime.mjs`.

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
