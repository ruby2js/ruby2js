# Self-Hosting Plan: Ruby2JS in JavaScript

## Status: Full Converter Transpiled

Ruby2JS can now run entirely in the browser using the actual Ruby2JS converter transpiled to JavaScript.

**Working demo:** `demo/selfhost/browser_demo.html`

**Related:**
- [PRISM_WALKER.md](./PRISM_WALKER.md) - Direct AST translation from Prism to Parser-compatible format
- [demo/selfhost/](../demo/selfhost/) - Browser demo with transpiled converter

## Current Architecture

```
Ruby Source (user input)
    ↓
@ruby/prism (WASM, ~2.7MB)
    ↓
Prism AST (JavaScript objects)
    ↓
PrismWalker (transpiled from Ruby)
    ↓
Parser-compatible AST
    ↓
Converter (transpiled from Ruby2JS source, ~7000 lines)
    ↓
JavaScript Output
```

## What Works

The self-hosted converter supports:

- **Literals**: integers, floats, strings, symbols, nil, true, false
- **Variables**: local (`x`), instance (`@x`), assignments
- **Collections**: arrays, hashes (with symbol keys)
- **Control flow**: `if/else/elsif`, `case/when`
- **Definitions**: `def foo(args)` → `function foo(args)`
- **Operators**: arithmetic, comparison, logical
- **Begin blocks**: multiple statements with proper separators

## Current Limitations

- No implicit `return` for method bodies (use explicit `return`)
- Comments are not preserved in output
- No indentation in output (newlines work)
- Classes and modules not yet tested
- Some complex patterns may not work

## Implementation Progress

### Phase 1: Prism Walker ✅ COMPLETE

Direct AST translation from Prism to Parser-compatible format.

### Phase 2: Proof of Concept ✅ COMPLETE

End-to-end pipeline working in browser with minimal hand-written converter.

### Phase 3: Full Converter Transpilation ✅ COMPLETE

The actual Ruby2JS converter (~60 handlers) has been transpiled to JavaScript using the `selfhost` filter.

**Key accomplishments:**
- Transpiled all converter handlers to JavaScript
- Handler discovery via prototype scanning
- Proper separator/newline handling via Serializer base class
- Ruby idiom translations (Hash operations, method renaming, etc.)

**Selfhost filter transformations:**
- `s(:type, ...)` → `s('type', ...)` - symbols to strings for AST types
- `node.type == :sym` → `node.type === 'string'` - type comparisons
- `handle :type do ... end` → `on_type(...)` method definitions
- `class Foo < Prism::Visitor` → class with self-dispatch `visit()` method
- `visit_integer_node` → `visitIntegerNode` - camelCase for JS Prism API
- `@sep`, `@nl`, `@ws` → `this._sep`, etc. - Serializer base class properties
- `Hash === obj` → type check for options hash vs AST node
- `hash[:key].to_s` → nil-safe `(hash.key || '').toString()`
- `hash.include?(key)` → `key in hash` for known hash variables
- `hash.select {...}` → `Object.fromEntries(Object.entries(...).filter(...))`
- `respond_to?(:prop)` → `typeof obj === 'object' && 'prop' in obj`

### Phase 4: Serializer and Walker Refactoring ✅ COMPLETE

**Serializer rewrite:**
- Removed inheritance from standard library classes (`Token < String`, `Line < Array`)
- Removed operator overloading (`def +`, `def ==`)
- Uses composition instead (Token wraps `@string`, Line wraps `@tokens`)
- Now fully transpilable without hand-written JavaScript stubs

**Class reopening support:**
- Added support for Ruby's class reopening pattern in selfhost filter
- `module Ruby2JS; class PrismWalker; def foo; end; end; end` → `PrismWalker.prototype.foo = function() {}`
- All 12 prism_walker sub-modules now transpile successfully
- Main prism_walker.rb transpiles to ~139 lines, sub-modules to ~1,560 lines combined

**Additional selfhost filter improvements:**
- `node.call` (property access) no longer incorrectly becomes `node.call(this)`
- `visit` and `visit_parameters` added to SELF_METHODS for proper `this.` prefix
- `module Ruby2JS` wrapper stripped when containing only class reopenings

### Phase 5: Demo Integration ✅ COMPLETE

- Browser demo loads Prism WASM
- Walker translates Prism AST
- Converter produces JavaScript output
- Vertical whitespace enabled (newlines, separators)

### Phase 6: Test-Driven Completion (In Progress)

Now that proof-of-concept is complete, we're taking a systematic spec-by-spec approach:

**Strategy:**
1. Self-host each test spec (starting with `transliteration_spec`)
2. Run it, accept initial failures
3. Iterate: fix issues, reduce failure count
4. Once spec passes, move to next spec
5. Replace scaffolding with self-hosted code as we go

**Spec Order (tentative, by dependency):**
1. `transliteration_spec` - Core conversion without filters
2. `es20xx_spec` files - ES version targeting
3. Filter specs (functions, esm, camelCase, etc.)
4. Integration specs

**Current Status:**
- [ ] `transliteration_spec` - Not started
- [ ] Other specs - Not started

## Regenerating the Self-Hosted Converter

```bash
# From the ruby2js root directory
bundle exec ruby lib/ruby2js/selfhost.rb --esm > demo/selfhost/selfhost_converter.mjs
```

## Running the Browser Demo

```bash
cd demo/selfhost
python3 -m http.server 8080
# Open http://localhost:8080/browser_demo.html
```

## Size Comparison

| Approach | Size | Notes |
|----------|------|-------|
| Self-hosted | ~2.9MB | prism.wasm + WASI shim + walker + converter |
| Opal-based | ~24MB | Opal runtime + parser gem + Ruby2JS |

**~8x smaller** than the current Opal-based demo.

## Next Steps

### Immediate: Test-Driven Iteration

1. **Self-host `transliteration_spec`** - Create JS test runner for this spec
2. **Run and capture failures** - Establish baseline failure count
3. **Fix one issue at a time** - Each fix should reduce failures
4. **Track progress** - Document which tests pass/fail

### After transliteration_spec passes

1. **ES level specs** - `es2015_spec`, `es2020_spec`, etc.
2. **Filter specs** - One filter at a time

### Long-term

1. **Replace ruby2js.com demo** - Use self-hosted version instead of Opal
2. **npm package** - Publish as `@ruby2js/browser` or similar
3. **Source maps** - Map generated JS back to Ruby source

## Technical Notes

### Handler Discovery

The Ruby converter uses `handle :type do ... end` which calls `define_method`. In JavaScript, we discover handlers by scanning the prototype for `on_*` methods:

```javascript
for (const key of Object.getOwnPropertyNames(proto)) {
  if (key.startsWith('on_') && typeof proto[key] === 'function') {
    types.push(key.slice(3));
  }
}
```

### Serializer Base Class

The JavaScript preamble provides a `Serializer` class that the `Converter` extends:

```javascript
class Serializer {
  constructor() {
    this._sep = '; ';   // Statement separator
    this._nl = '';      // Newline (empty = compact)
    this._ws = ' ';     // Whitespace
    this._indent = 0;   // Indentation level
  }

  enable_vertical_whitespace() {
    this._sep = ';\n';
    this._nl = '\n';
    this._ws = this._nl;
    this._indent = 2;
  }
}
```

### Ruby-to-JavaScript Idiom Mapping

| Ruby | JavaScript | Notes |
|------|------------|-------|
| `Hash === obj` | `typeof obj === 'object' && !obj.type` | Detect options hash vs AST node |
| `hash[:key].to_s` | `(hash.key \|\| '').toString()` | Nil-safe stringification |
| `@vars.include?(key)` | `key in this._vars` | Hash key existence |
| `array.compact!` | `array.splice(0, array.length, ...array.filter(x => x != null))` | In-place compact |
| `hash.merge!(other)` | `Object.assign(hash, other)` | In-place merge |
| `hash.select {...}` | `Object.fromEntries(Object.entries(hash).filter(...))` | Hash filtering |

## Maintenance Overview (Final State)

Once self-hosting is complete, here's what needs to be maintained:

### Hand-Written Files (~1,150 lines total)

| File | Lines | Purpose |
|------|-------|---------|
| `lib/ruby2js/filter/selfhost.rb` | ~950 | AST transformations for Ruby→JS patterns |
| `preamble.mjs` | ~60 | JS stubs (Node, s(), Hash, NotImplementedError) |
| Build script (Rakefile task) | ~50 | Lists files, calls Ruby2JS.convert, concatenates |
| `browser_demo.html` | ~100 | Demo UI |

### Generated Files (regenerated on build)

| File | Lines | Source |
|------|-------|--------|
| `transpiled_walker.mjs` | ~1,700 | From `lib/ruby2js/prism_walker.rb` + submodules |
| `transpiled_converter.mjs` | ~6,500 | From `lib/ruby2js/converter.rb` + handlers + serializer |

The `selfhost.rb` filter encodes "how to transpile Ruby2JS's Ruby idioms to JavaScript."
Once it handles all the patterns, changes to the converter/walker Ruby code automatically
flow through to the browser version on rebuild.

## Success Criteria

- [x] Bundle size < 3MB (achieved ~2.9MB vs 24MB)
- [x] Basic Ruby converts to JavaScript in browser
- [ ] Parse + convert "Hello World" in < 100ms
- [ ] Pass `transliteration_spec` (__ / __ tests)
- [ ] Pass `es20xx_spec` files
- [ ] Support `functions`, `esm`, `camelCase` filters
- [ ] Works in Chrome, Firefox, Safari (latest)

## References

- [@ruby/prism npm package](https://www.npmjs.com/package/@ruby/prism)
- [Prism JavaScript documentation](https://github.com/ruby/prism/blob/main/docs/javascript.md)
- [Current Opal-based demo](https://www.ruby2js.com/)
