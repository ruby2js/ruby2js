# Self-Hosted Ruby2JS Demo

This directory contains a proof-of-concept demonstrating Ruby2JS running entirely in the browser, without Opal.

## Architecture

```
Ruby Source Code
       ↓
@ruby/prism (WebAssembly, ~2.7MB)
       ↓
Prism AST (JavaScript objects)
       ↓
PrismWalker (transpiled from Ruby)
       ↓
Parser-compatible AST
       ↓
Converter (minimal, hand-written JS)
       ↓
JavaScript Output
```

## Files

| File | Description |
|------|-------------|
| `browser_demo.html` | Interactive browser demo (open via HTTP server) |
| `transpile_walker.rb` | Ruby script that generates `transpiled_walker.mjs` |
| `transpiled_walker.mjs` | Generated JS: PrismWalker + Converter |
| `test_harness.mjs` | Minitest-compatible test framework for JS |
| `test_transpiled_walker.mjs` | Tests for the walker (14 tests) |
| `test_full_pipeline.mjs` | End-to-end pipeline tests (13 tests) |
| `walker.mjs` | Earlier hand-written PoC walker |
| `run_tests.mjs` | Earlier test runner |

## Running the Browser Demo

The demo requires HTTP (not `file://`) due to ES module and WASM restrictions:

```bash
cd demo/selfhost
python3 -m http.server 8080
# Open http://localhost:8080/browser_demo.html
```

## Running the Tests

```bash
cd demo/selfhost
node test_transpiled_walker.mjs  # 14 tests
node test_full_pipeline.mjs      # 13 tests
```

## Regenerating the Transpiled Walker

```bash
cd demo/selfhost
ruby transpile_walker.rb > transpiled_walker.mjs
```

This uses the `selfhost` filter to transpile Ruby code to JavaScript.

## What the Minimal Converter Supports

**Supported:**
- Literals: integers, floats, strings, symbols, nil, true, false
- Variables: local (`x`), instance (`@x`), assignments
- Collections: arrays, hashes
- Method calls: `foo.bar(args)`, `puts` → `console.log`
- Definitions: `def foo(a, b=1, *rest)` → `function foo(a, b=1, ...rest)`
- Control flow: `if/else`

**Not supported:**
- Classes, modules
- Loops (while, until, for)
- Case/when statements
- Exception handling (begin/rescue)
- Blocks, lambdas, procs
- Operators (+, -, &&, ||, etc.)
- Ranges, regex
- Most method mappings (only `puts` is mapped)

The full Ruby2JS converter has 60+ handlers and 23 filters. This is a minimal proof-of-concept.

## Size Comparison

| Approach | Size | Notes |
|----------|------|-------|
| Self-hosted | ~2.8MB | prism.wasm + WASI shim + walker/converter |
| Opal-based | ~24MB | Opal runtime + parser gem + Ruby2JS |

## Key Differences: JS Prism vs Ruby Prism

When writing walker code for JavaScript:

1. **String content**: `node.unescaped` returns `{encoding, validEncoding, value}`, use `.value`
2. **Arguments**: Use `node.arguments_` (underscore) not `node.arguments`
3. **Nested arguments**: `node.arguments_.arguments_` for the actual array
4. **Constructor names**: `IntegerNode`, `StringNode`, etc. (used for visitor dispatch)

## The Selfhost Filter

The `lib/ruby2js/filter/selfhost.rb` filter enables transpiling Ruby2JS internals:

- `s(:type, ...)` → `s('type', ...)` (symbols to strings)
- `node.type == :sym` → `node.type === 'string'`
- `class Foo < Prism::Visitor` → class with self-dispatch `visit()` method
- `visit_integer_node` → `visitIntegerNode` (camelCase for JS Prism)
- `.compact` → `.filter(x => x != null)`

## Next Steps

See `plans/SELF_HOSTING.md` for the full roadmap, including:

- Phase 2.5: Move general-purpose transforms (like `.compact`) to `functions` filter
- Phase 3: Transpile more filters (functions, esm, camelCase, return)
- Phase 4: Replace the ruby2js.com demo with the self-hosted version
