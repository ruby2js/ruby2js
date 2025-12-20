# Node Filter Selfhost: Enabling Ruby Build Script Transpilation

## Status: Stage 5 In Progress

Enable the Node filter to run in selfhost, allowing `build.rb` to be transpiled to JavaScript. This eliminates the need for a hand-maintained `build-selfhost.mjs` and enables the Rails-in-JS demo to run with zero Ruby dependency.

## Goal

**Transpile `build.rb` to `build.mjs`** so the Rails-in-JS demo can build and run entirely in JavaScript, with hot reload, without Ruby installed.

## Why This Matters

The Rails-in-JS demo currently requires two build scripts:
- `build.rb` - Ruby version (authoritative)
- `build-selfhost.mjs` - Hand-maintained JavaScript version

This duplication is:
1. Error-prone (scripts can drift)
2. Extra maintenance burden
3. Doesn't fully prove selfhost works

With Node filter in selfhost, we can transpile `build.rb` → `build.mjs`, proving Ruby2JS can transpile its own build tooling.

## Completed Work

### Stage 1: Node Filter Enhancements ✅

| Feature | Commit | Description |
|---------|--------|-------------|
| Async option | `df53ebe` | `async: true` for `fs/promises` with `await` |
| FileUtils.mkdir_p | `df53ebe` | `fs.mkdirSync(path, {recursive: true})` |
| FileUtils.rm_rf | `df53ebe` | `fs.rmSync(path, {recursive: true, force: true})` |
| File.expand_path | `df53ebe` | `path.resolve()` |
| Dir.exist? | `cc879bd` | `fs.existsSync()` |
| Dir.glob | `cc879bd` | `fs.globSync()` (Node 22+) |
| Remove extend SEXP | `82f4986` | Lazy initialization unblocks selfhost |

### Stage 2: Transpile Node Filter to Selfhost ⏭️ SKIPPED

Not needed. The Node filter is only required at transpilation time (Ruby), not runtime (JS).

### Stage 3: SelfhostBuild Filter ✅

Created `lib/ruby2js/filter/selfhost_build.rb` to handle build-script-specific transformations:

| Transformation | Ruby | JavaScript |
|----------------|------|------------|
| YAML.load_file | `YAML.load_file(path)` | `yaml.load(fs.readFileSync(path, 'utf8'))` |
| YAML.dump | `YAML.dump(obj)` | `yaml.dump(obj)` |
| $LOAD_PATH | `$LOAD_PATH.unshift(...)` | Removed |
| require ruby2js | `require 'ruby2js'` | `import Ruby2JS from '../../selfhost/ruby2js.js'` |
| require filters | `require 'ruby2js/filter/rails/model'` | `import Rails_Model from '../../selfhost/filters/rails/model.js'` |
| require_relative | `require_relative '../lib/foo'` | `import '../lib/foo.js'` |
| erb_compiler | `require_relative '../lib/erb_compiler'` | `import { ErbCompiler } from '../../selfhost/lib/erb_compiler.js'` |
| Filter constants | `Ruby2JS::Filter::Rails::Model` | `Rails_Model` |

### Stage 4: Restructure build.rb ✅

Refactored `build.rb` to export a `SelfhostBuilder` class with:
- Constructor taking `dist_dir`
- `build()` method for full builds
- Explicit `()` on all method calls for JS compatibility
- Explicit Rails sub-filter requires for correct imports

## Remaining Work

### Stage 5: Fix Selfhost Export Issues 🔄 IN PROGRESS

The transpiled `build.mjs` has import issues because selfhost modules use named exports, not default exports:

| Module | Current Import | Needed Import |
|--------|----------------|---------------|
| ruby2js.js | `import Ruby2JS from ...` | Named or init pattern |
| filters/*.js | `import X from ...` | `import { X } from ...` |

**Options:**
1. Update selfhost_build filter to detect named vs default exports
2. Add default exports to selfhost modules
3. Use the hand-written build-selfhost.mjs pattern (dynamic imports with destructuring)

**Additional runtime issues found:**
- `process.env.fetch()` doesn't exist in JS (need `process.env.X || default`)
- `hash.keys` needs Functions filter to convert to `Object.keys(hash)`
- CLI check `$0` doesn't exist in JS

### Stage 6: Wire Up and Verify ⏳ PENDING

Once Stage 5 is complete:
1. Test `node scripts/build.mjs` produces same output as `ruby scripts/build.rb`
2. Update dev-server to import from `build.mjs`
3. Run smoke tests
4. Delete `build-selfhost.mjs`

## Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| Node filter without extend SEXP | ✅ Complete | Commit `82f4986` |
| selfhost_build filter | ✅ Complete | Handles YAML, requires, constants |
| ESM/CJS __dir__ support | ✅ Complete | `import.meta.dirname` / `__dirname` |
| Selfhost named exports | ⏳ Blocking | Need to handle non-default exports |

## Files Modified

| File | Change |
|------|--------|
| `lib/ruby2js/filter/selfhost_build.rb` | New filter for build script transpilation |
| `spec/selfhost_build_spec.rb` | Tests for selfhost_build filter |
| `lib/ruby2js/filter/esm.rb` | Added `__dir__` → `import.meta.dirname` |
| `lib/ruby2js/filter/cjs.rb` | Added `__dir__` → `__dirname` |
| `demo/rails-in-js/scripts/build.rb` | Restructured as SelfhostBuilder class |
| `demo/rails-in-js/scripts/build.mjs` | Generated (not yet working) |

## Success Criteria

1. ~~`node_spec.rb` passes in selfhost~~ (not needed)
2. `build.rb` transpiles to working `build.mjs`
3. `npm run dev` works with transpiled build script
4. `npm run test:smoke` shows no diff
5. Hand-maintained `build-selfhost.mjs` deleted

## Key Insight

The transpiled `build.mjs` cannot be a drop-in replacement for the hand-written `build-selfhost.mjs` because:

1. **Ruby2JS.convert** - The Ruby version calls Ruby's Ruby2JS, but the JS version needs the selfhost converter with async initialization
2. **Export patterns** - Selfhost uses named exports and requires initialization (`initPrism()`)
3. **Filter loading** - Selfhost filters need `.prototype` passed to the pipeline

The hand-written version exists because it uses a fundamentally different architecture suited to JS:
- `async init()` method to load Prism WASM and filters
- Dynamic imports with destructuring for named exports
- `SelfhostBuilder.converter.convert()` instead of `Ruby2JS.convert()`

## Recommendation

**Keep build-selfhost.mjs hand-maintained** but use the transpiled version as a reference to keep them in sync. The architectural differences between Ruby and JS execution models make full automation impractical without significant selfhost changes.

Alternatively, modify selfhost to:
1. Add default exports alongside named exports
2. Create a `Ruby2JS.convert()` facade that handles initialization
3. This would enable the transpiled version to work
