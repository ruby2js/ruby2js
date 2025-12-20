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

### Stage 5: Fix Selfhost Export Issues ✅ COMPLETE

Updated `selfhost_build.rb` filter to handle all export and initialization differences:

| Transformation | Before | After |
|----------------|--------|-------|
| `require 'ruby2js'` | `import Ruby2JS from ...` | `import * as Ruby2JS from ...; await Ruby2JS.initPrism()` |
| `require 'ruby2js/filter/X'` | `import X from ...` | `import { X } from ...` |
| `Ruby2JS::Filter::X` | `X` | `X.prototype` |
| `$0` | `$0` (invalid JS) | `` `file://${process.argv[1]}` `` |
| `require 'fileutils'` | `require("fileutils")` | (removed) |

**Key changes to `lib/ruby2js/filter/selfhost_build.rb`:**
- Namespace import with async init for `require 'ruby2js'`
- Named imports `{ X }` for filter requires
- `.prototype` suffix on filter constants for pipeline compatibility
- `$0` → template literal for ESM main script check
- Remove `fileutils` require (handled by Node filter)

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

~~The transpiled `build.mjs` cannot be a drop-in replacement~~ **UPDATE: The `selfhost_build` filter now handles all the architectural differences:**

1. **Ruby2JS.convert** - ✅ Filter generates `import * as Ruby2JS` with `await Ruby2JS.initPrism()`
2. **Export patterns** - ✅ Filter generates named imports `{ X }` for selfhost modules
3. **Filter loading** - ✅ Filter adds `.prototype` to filter constants

The transpiled version should now be functionally equivalent to the hand-written version, with the filter handling:
- Top-level await for async initialization
- Named imports for selfhost's export pattern
- Prototype references for pipeline compatibility
- ESM main script check via `$0` → template literal

## Next Steps

Test the transpiled `build.mjs` end-to-end:
1. Transpile `build.rb` with the updated filter
2. Run `node scripts/build.mjs` and compare output with `ruby scripts/build.rb`
3. If successful, the hand-written `build-selfhost.mjs` can be deleted
