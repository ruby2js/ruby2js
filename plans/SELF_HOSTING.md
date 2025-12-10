# Self-Hosting Plan: Ruby2JS in JavaScript

## Status: Transliteration Complete ✅

Ruby2JS runs entirely in the browser using the actual Ruby2JS converter transpiled to JavaScript.

**Live demo:** https://ruby2js.com/demo/selfhost/

**Supported:**
- Full transliteration test suite (2 tests intentionally skipped - Proc source location)
- Classes, methods, blocks, string interpolation
- Arrays, hashes, if/else/case, loops, operators
- Comments preserved in output

**Not yet supported:**
- eslevel options
- Filters (functions, esm, camelCase, etc.)
- Other configuration options

## Architecture

```
Ruby Source (user input)
    ↓
@ruby/prism (WebAssembly)
    ↓
Prism AST (JavaScript objects)
    ↓
PrismWalker (transpiled from lib/ruby2js/prism_walker.rb)
    ↓
Parser-compatible AST
    ↓
Converter (transpiled from lib/ruby2js/converter.rb + handlers)
    ↓
JavaScript Output
```

## Key Components

| Component | Ruby Source | Transpiled Output |
|-----------|-------------|-------------------|
| Walker | `lib/ruby2js/prism_walker.rb` + submodules | `dist/walker.mjs` |
| Converter | `lib/ruby2js/converter.rb` + handlers | `dist/converter.mjs` |
| Namespace | `lib/ruby2js/namespace.rb` | `dist/namespace.mjs` |
| Runtime | `lib/ruby2js.rb` (associate_comments) | `shared/runtime.mjs` |

## Shared Code

Comment handling is shared between Ruby and JavaScript:

- **Ruby**: `lib/ruby2js.rb` has `Ruby2JS.associate_comments` and `CommentsMap < Hash`
- **JavaScript**: `shared/runtime.mjs` has `associateComments` and uses `Map`

Both the CLI (`ruby2js.mjs`) and browser demo import from `shared/runtime.mjs`.

## Implementation History

### Phase 1-5: Core Infrastructure ✅
- Prism Walker transpilation
- Converter transpilation (60+ handlers)
- Serializer rewrite (removed inheritance from String/Array)
- Browser demo with WASI polyfill
- CI integration with spec manifest

### Phase 6: Test-Driven Completion ✅
- Transliteration spec passes (2 skipped)
- Comment handling implemented
- Shared runtime between CLI and browser

## Filter Chain

The transpilation uses this filter chain:

```ruby
filters: [
  Ruby2JS::Filter::Pragma,              # Handle # Pragma: skip
  Ruby2JS::Filter::Combiner,            # Merge reopened classes
  Ruby2JS::Filter::Require,             # require_relative → inline
  Ruby2JS::Filter::Selfhost::Core,      # Core transformations
  Ruby2JS::Filter::Selfhost::Walker,    # private/protected removal
  Ruby2JS::Filter::Selfhost::Converter, # handle :type patterns
  Ruby2JS::Filter::Polyfill,            # Ruby method polyfills
  Ruby2JS::Filter::Functions,           # Ruby methods → JS
  Ruby2JS::Filter::Return,              # Autoreturn for methods
  Ruby2JS::Filter::ESM                  # ES module exports
]
```

## Building

```bash
cd demo/selfhost
npm install
npm run build    # Build all transpiled files
npm test         # Run tests
```

## Future Work

1. **Transpile filters** - functions, esm, camelCase, etc.
2. **Add eslevel support** - ES version targeting
3. **Add configuration options** - width, indent, etc.

## References

- [demo/selfhost/README.md](../demo/selfhost/README.md) - Development guide
- [@ruby/prism npm package](https://www.npmjs.com/package/@ruby/prism)
- [Live demo](https://ruby2js.com/demo/selfhost/)
