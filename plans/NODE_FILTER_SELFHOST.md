# Node Filter Selfhost: Enabling Ruby Build Script Transpilation

## Status: Stage 1 Complete

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

The Node filter now covers all file operations used in `build.rb` and no longer uses `extend SEXP`.

## Remaining Work

### Stage 2: Transpile Node Filter to Selfhost

**Goal:** Get `node_spec.rb` passing in selfhost.

```bash
# Transpile the filter
bundle exec ruby demo/selfhost/scripts/transpile_filter.rb \
  lib/ruby2js/filter/node.rb > demo/selfhost/filters/node.js

# Run tests
cd demo/selfhost
node run_all_specs.mjs --partial-only
```

**Potential issues:**
- Prism AST differences
- Missing method mappings
- Import/export handling

**Update spec_manifest.json:**
```json
{
  "partial": [
    "node_spec.rb",  // Move from blocked
    ...
  ]
}
```

### Stage 3: Handle YAML Dependency

`build.rb` uses `YAML.load_file` for `config/database.yml`. Options:

| Approach | Pros | Cons |
|----------|------|------|
| Add YAML filter | Clean Ruby code | New filter to maintain |
| Use js-yaml directly | Already a devDependency | Ruby code becomes JS-aware |
| Inline config | No YAML needed | Less flexible |

**Recommended:** Create minimal YAML filter that maps:
- `YAML.load_file(path)` → `jsyaml.load(fs.readFileSync(path, 'utf8'))`
- `YAML.dump(obj)` → `jsyaml.dump(obj)`

### Stage 4: Structure build.rb for Import

The dev server needs to import `SelfhostBuilder` class:

```javascript
import { SelfhostBuilder } from './scripts/build.mjs';
```

Ensure `build.rb` exports a class that can be imported:

```ruby
class SelfhostBuilder
  def initialize
    # ...
  end

  def build_all
    # ...
  end

  def build_file(path)
    # Hot reload support
  end
end
```

### Stage 5: Transpile and Verify

```bash
# Transpile build.rb
bin/ruby2js --filter node --filter functions --filter esm \
  demo/rails-in-js/scripts/build.rb > demo/rails-in-js/scripts/build.mjs

# Run smoke test
cd demo/rails-in-js
npm run test:smoke
```

The smoke test already compares Ruby vs selfhost output - it should pass with no diff.

### Stage 6: Delete Hand-Maintained Script

Once `build.mjs` is generated from `build.rb`:

1. Update `package.json` to use transpiled script
2. Delete hand-maintained `build-selfhost.mjs`
3. Update dev-server to import from `build.mjs`

## Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| Node filter without extend SEXP | ✅ Complete | Commit `82f4986` |
| Node filter in selfhost | ⏳ Pending | Stage 2 |
| YAML filter or workaround | ⏳ Pending | Stage 3 |
| js-yaml package | ✅ Available | Already devDependency |
| fs.glob (Node 22+) | ✅ Available | Node 23.11.0 installed |

## Success Criteria

1. `node_spec.rb` passes in selfhost (partial → ready)
2. `build.rb` transpiles to working `build.mjs`
3. `npm run dev` works with transpiled build script
4. `npm run test:smoke` shows no diff
5. Hand-maintained `build-selfhost.mjs` deleted

## Open Questions

1. **Should build.mjs be checked in or generated?**
   - Generated: Always in sync, but requires transpile step
   - Checked in: Works without Ruby, but can drift

2. **Hot reload architecture**
   - Does transpiled `build.rb` need to match `SelfhostBuilder` interface exactly?
   - Or should dev-server be updated to work with simpler interface?

3. **YAML config vs environment variables**
   - Could eliminate YAML dependency by using `DATABASE=sqljs` env var
   - Already supported, just needs to be the default path
