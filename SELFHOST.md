# Selfhost Development Guide

The selfhost project (`demo/selfhost/`) transpiles Ruby2JS itself to JavaScript, enabling the converter to run in browsers. Ruby specs are also transpiled and run against the JS converter.

## Spec Manifest Categories

The `demo/selfhost/spec_manifest.json` tracks which specs work with the selfhost converter:

- **ready**: Specs that must pass (CI fails if they don't)
- **partial**: Specs being worked on (failures are informational)
- **blocked**: Specs waiting on dependencies (e.g., filters not yet transpiled)

## Building Selfhost

Run from the repository root:

```bash
# Build everything for local development
bundle exec rake -f demo/selfhost/Rakefile local

# Build everything for npm release (tarballs in artifacts/tarballs/)
bundle exec rake -f demo/selfhost/Rakefile release

# Clean all generated files
bundle exec rake -f demo/selfhost/Rakefile clean
```

The `local` build uses relative paths for development. The `release` build converts to npm package imports and creates tarballs.

## Running Selfhost Tests

```bash
cd demo/selfhost

# Run all specs
node run_all_specs.mjs

# Run with failure details for partial specs
node run_all_specs.mjs --verbose

# Run only ready specs (for CI)
node run_all_specs.mjs --ready-only

# Run only partial specs (for development)
node run_all_specs.mjs --partial-only

# Skip transpilation (use pre-built files)
node run_all_specs.mjs --skip-transpile
```

## Debugging a Specific Spec

To debug a failing spec with full details:

```bash
# Rebuild everything (from repository root)
bundle exec rake -f demo/selfhost/Rakefile local

cd demo/selfhost

# Transpile just one spec
bundle exec ruby scripts/transpile_spec.rb ../../spec/serializer_spec.rb > dist/serializer_spec.mjs

# Run it directly to see all failures
node -e "
import('./test_harness.mjs').then(async h => {
  await h.initPrism();
  await import('./dist/serializer_spec.mjs');
  h.runTests();
});
"
```

## Common Failure Patterns

1. **Transpilation bug**: The Ruby-to-JS conversion produces incorrect code
   - Check `lib/ruby2js/filter/` for filter issues
   - Check `lib/ruby2js/converter/` for conversion issues
   - Use `bin/ruby2js --ast` vs `--filtered-ast` to see where transformation happens

2. **Missing polyfill**: A Ruby method has no JS equivalent in the test harness
   - Add to `demo/selfhost/test_harness.mjs`

3. **Runtime incompatibility**: Code works in Ruby but not in JS
   - Fix in source Ruby file (`lib/ruby2js/*.rb`) with dual-compatible code
   - Example: `arg.is_a?(Range)` won't work in JS; use `arg.respond_to?(:begin)` instead

## Promoting Specs

When a partial spec passes all tests:
1. Move it from `partial` to `ready` in `spec_manifest.json`
2. Commit and push - CI will now enforce it passes

## Debugging Selfhost Transpilation Failures

**Never edit generated files.** Files ending in `.js` in the selfhost directory are generated outputs. Fix issues in the original source:
- Ruby source in `lib/ruby2js/` (for dual-compatible code)
- Converter handlers in `lib/ruby2js/converter/`
- Filters in `lib/ruby2js/filter/`

**Approach selection:**
- Few occurrences → change Ruby source (e.g., add explicit `self.`)
- Pervasive pattern → change selfhost filter
- Affects all users → change core Ruby2JS filter

**Workflow:**
1. Rebuild and run tests: `bundle exec rake -f demo/selfhost/Rakefile local && cd demo/selfhost && node run_all_specs.mjs --verbose`
2. Create minimal reproduction: `bin/ruby2js --filter selfhost -e 'your_code'`
3. Examine AST: `bin/ruby2js --filter selfhost --filtered-ast -e 'your_code'`
4. Assess how widespread the issue is with grep
5. Fix and verify
