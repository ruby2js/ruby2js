# Self-Hosted Ruby2JS

This directory contains Ruby2JS running entirely in JavaScript, using the actual Ruby2JS converter transpiled from Ruby source.

## Goals

The goal is **not** to create a separate JavaScript implementation of Ruby2JS. That approach—while it could pass the same test suite—would require maintaining two different codebases in perpetuity.

Instead, the goal is to:

1. **Identify gaps** in Ruby2JS's ability to transpile Ruby to JavaScript
2. **Fix those gaps** in the Ruby implementation so it can transpile itself
3. **Produce two compatible implementations from one source**: the original Ruby and the transpiled JavaScript

This "dogfooding" approach ensures that improvements benefit all Ruby2JS users, not just the selfhost. When a Ruby pattern doesn't transpile correctly, we fix the converter or filters—making Ruby2JS better for everyone.

## Status: Filters Working

A single `ruby2js.js` bundle provides the full converter for both CLI and browser use. The same code is tested in CI, runs in Node.js CLI, and works in browsers.

**Supported:**
- Classes, methods, blocks, string interpolation
- Arrays, hashes, if/else/case, loops, operators
- Comments (preserved in output)
- Full transliteration, serializer, and namespace test suites passing (291 tests)
- **Functions filter**: 190/203 tests passing (94%)

**Filter Infrastructure:**
- Filter runtime bundled into `ruby2js.js` (no separate imports needed)
- `Selfhost::Filter` generates imports, registration, and exports automatically
- Transpile script is pure declarative (45 lines, no gsubs or manual wrappers)

**Not yet fully tested:**
- Other filters (camelCase at 89%, tagged_templates at 86%, others need work)
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
Pipeline (transpiled from lib/ruby2js/pipeline.rb)
  ├─ Filter chain (optional)
  └─ Converter setup
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

| File                 | Description                                                              |
| -------------------- | ------------------------------------------------------------------------ |
| `ruby2js.js`         | Generated bundle - converter + filter runtime                            |
| `ruby2js.mjs`        | CLI entry point (use with `node ruby2js.mjs`)                            |
| `filter_runtime.js`  | Filter runtime source (appended to ruby2js.js during build)             |
| `prism_browser.js`   | Generated browser WASM loader                                            |
| `browser_demo.html`  | Browser demo page                                                        |
| `test_harness.mjs`   | Test framework for specs                                                 |
| `run_all_specs.mjs`  | Manifest-driven spec runner for CI                                       |
| `spec_manifest.json` | Spec status tracking (ready/partial/blocked)                             |
| `filters/`           | Generated transpiled filters                                             |
| `lib/`               | Generated transpiled libraries (erb_compiler.js)                         |
| `dist/`              | Generated transpiled specs                                               |

### Scripts

| File                                 | Description                                               |
| ------------------------------------ | --------------------------------------------------------- |
| `scripts/transpile_bundle.rb`        | Transpiles Ruby2JS bundle to JS (includes filter runtime) |
| `scripts/transpile_filter.rb`        | Transpiles filters - pure declarative                     |
| `scripts/transpile_spec.rb`          | Transpiles RSpec files to JS                              |
| `scripts/transpile_prism_browser.rb` | Transpiles browser Prism loader                           |
| `scripts/transpile_erb_compiler.rb`  | Transpiles ERB compiler for browser use                   |
| `scripts/build_all.rb`               | Batch build for filters and specs                         |
| `scripts/publish_demo.rb`            | Creates ruby2js-on-rails distribution tarball             |
| `scripts/test_handlers.rb`           | Test helper for converter handlers                        |

### Transpiled Output

**Filters (`filters/`)** - Transpiled from `lib/ruby2js/filter/*.rb`:

| File                      | Description                    |
| ------------------------- | ------------------------------ |
| `filters/functions.js`    | Ruby method → JS equivalents   |
| `filters/esm.js`          | ES module imports/exports      |
| `filters/camelCase.js`    | snake_case → camelCase         |
| `filters/stimulus.js`     | Stimulus controller patterns   |
| `filters/rails/*.js`      | Rails-specific filters         |

**Specs (`dist/`)** - Transpiled from `spec/*.rb`:

| File                            | Description                       |
| ------------------------------- | --------------------------------- |
| `dist/transliteration_spec.mjs` | Transpiled transliteration tests  |
| `dist/serializer_spec.mjs`      | Transpiled serializer tests       |
| `dist/functions_spec.mjs`       | Transpiled Functions filter tests |

## Source Files

The unified bundle is transpiled from Ruby source files:

| Ruby Source                             | LOC   | JavaScript Output                  |
| --------------------------------------- | ----- | ---------------------------------- |
| `lib/ruby2js/selfhost/bundle.rb`        | 94    | `ruby2js.mjs`                      |
| `lib/ruby2js/selfhost/runtime.rb`       | 176   | (inlined in bundle)                |
| `lib/ruby2js/selfhost/cli.rb`           | 424   | (inlined in bundle)                |
| `lib/ruby2js/selfhost/prism_browser.rb` | 117   | `prism_browser.mjs`                |
| `lib/ruby2js/namespace.rb`              | 86    | (inlined in bundle)                |
| `lib/ruby2js/prism_walker.rb`           | 261   | (inlined in bundle)                |
| `lib/ruby2js/converter.rb` + handlers   | 548+  | (inlined in bundle)                |
| `lib/ruby2js/pipeline.rb`               | 160   | (inlined in bundle)                |
| `lib/ruby2js/filter/processor.rb`       | 333   | (in bundle, for filter base class) |
| `lib/ruby2js/filter/functions.rb`       | 1,455 | `filters/functions.js`             |

## npm Scripts

| Script                        | Description                                        |
| ----------------------------- | -------------------------------------------------- |
| `npm test`                    | Run all tests (CLI, walker, specs)                 |
| `npm run build`               | Build everything (bundle, filters, specs, lib)     |
| `npm run build:bundle`        | Regenerate ruby2js.js from Ruby source             |
| `npm run build:prism-browser` | Regenerate prism_browser.js                        |
| `npm run build:filters`       | Transpile all filters to filters/                  |
| `npm run build:erb-compiler`  | Transpile ERB compiler to lib/                     |
| `npm run build:spec`          | Transpile test specs to dist/                      |
| `npm run clean`               | Remove generated files                             |

## Rake Tasks

Run from the repository root:

```bash
bundle exec rake -f demo/selfhost/Rakefile <task>
```

### Main Tasks

| Task      | Description                                            |
| --------- | ------------------------------------------------------ |
| `local`   | Build everything for local development                 |
| `release` | Build everything for npm release (creates tarballs)    |
| `clean`   | Remove all generated files                             |
| `test`    | Build and run all tests                                |

### Additional Tasks

| Task            | Description                                        |
| --------------- | -------------------------------------------------- |
| `build`         | Build bundle, prism_browser, filters, specs        |
| `build_ready`   | Build only ready specs                             |
| `build_partial` | Build only partial specs                           |
| `build_lib`     | Build lib files (erb_compiler, migration_sql, etc) |
| `build_mjs`     | Build build.mjs with local paths                   |
| `build_mjs:npm` | Build build.mjs with npm package imports           |
| `build_filters` | Build all manifest filters                         |
| `ci`            | CI mode (ready must pass, partial informational)   |

### Examples

```bash
# Build for local development
bundle exec rake -f demo/selfhost/Rakefile local

# Build release tarballs (outputs to artifacts/tarballs/)
bundle exec rake -f demo/selfhost/Rakefile release

# Clean all generated files
bundle exec rake -f demo/selfhost/Rakefile clean

# Run tests
bundle exec rake -f demo/selfhost/Rakefile test
```

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
  import { convert } from './ruby2js.js';

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
  // Core conversion
  convert,           // Main conversion function
  Ruby2JS,           // Module with internal classes
  initPrism,         // Initialize Prism parser
  getPrismParse,     // Get the Prism parse function

  // Filter runtime (for transpiled filters)
  Parser,            // Parser.AST.Node alias
  SEXP, s, S,        // AST construction helpers
  ast_node,          // Check if value is AST node
  Filter, DEFAULTS,  // Filter registration
  processNode,       // Process AST node through filter chain
  process_children,  // Process children of a node
  nodesEqual,        // Structural AST comparison
  registerFilter,    // Register a filter
  // ... and more
} from './ruby2js.js';

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
- **Functions filter**: 13 remaining failures (block-pass, metaprogramming, Class.new patterns)
- **Other filters**: camelCase (89%), tagged_templates (86%) near ready; others need work

## Future Work

1. Complete Functions filter (13 remaining failures)
2. Promote high-passing filters (camelCase, tagged_templates) to ready status
3. Fix common patterns in lower-passing filters (esm, cjs, pragma)
4. Add configuration options for browser/Node.js environments

## References

- [plans/SELF_HOSTING.md](../../plans/SELF_HOSTING.md) - Original roadmap
- [plans/PRAGMA_SELFHOST.md](../../plans/PRAGMA_SELFHOST.md) - Implementation details
