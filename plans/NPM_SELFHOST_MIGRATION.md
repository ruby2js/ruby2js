# NPM Package: Opal to Self-Hosted Migration

Replace the Opal-based npm package with the self-hosted version for Ruby2JS 6.0 beta.

## Current State

| Aspect | Opal (current) | Self-hosted |
|--------|----------------|-------------|
| Location | `packages/ruby2js/` | `demo/selfhost/` |
| Bundle size | 4.8 MB | ~525 KB |
| Package name | `@ruby2js/ruby2js` | `ruby2js` |
| Dependencies | None | `@ruby/prism` |
| Module type | CommonJS + ESM wrapper | Native ESM |
| Filters | All bundled | Individually loadable |
| CLI | None | Included |
| Tests | 8 mocha tests | 691 transpiled specs |
| Config loading | `rb2js.config.rb` support | Not implemented |

## Benefits of Migration

1. **10x smaller bundle** - 525 KB vs 4.8 MB
2. **Native ES modules** - No wrapper needed
3. **Individual filter imports** - Tree-shakeable
4. **Built-in CLI** - `npx ruby2js -e 'code'`
5. **Self-proving** - Ruby2JS transpiles itself
6. **Better testing** - 691 specs vs 8 tests

## Migration Phases

### Phase 1: Core Bundle (MVP for Beta)

**Goal:** Get the core converter working in the npm package.

**Tasks:**
- [ ] Copy `demo/selfhost/ruby2js.js` to `packages/ruby2js/`
- [ ] Update `packages/ruby2js/package.json`:
  - Add `"type": "module"`
  - Add `"dependencies": { "@ruby/prism": "^1.6.0" }`
  - Update `"main"` and `"module"` fields
  - Add `"exports"` field for ESM
- [ ] Update or replace `packages/ruby2js/ruby2js.mjs` wrapper
- [ ] Verify existing 8 mocha tests pass
- [ ] Test basic conversion in Node.js

**Estimated effort:** 1-2 days

### Phase 2: Filters

**Goal:** Enable individual filter imports.

**Tasks:**
- [ ] Copy `demo/selfhost/filters/` to `packages/ruby2js/filters/`
- [ ] Update `package.json` exports:
  ```json
  "exports": {
    ".": "./ruby2js.js",
    "./filters/*": "./filters/*"
  }
  ```
- [ ] Test filter imports: `import './filters/functions.js'`
- [ ] Document filter loading pattern

**Estimated effort:** 2-3 days

### Phase 3: CLI

**Goal:** Provide command-line interface.

**Tasks:**
- [ ] Copy `demo/selfhost/ruby2js-cli.js` to `packages/ruby2js/`
- [ ] Add to `package.json`:
  ```json
  "bin": {
    "ruby2js": "./ruby2js-cli.js"
  }
  ```
- [ ] Test `npx ruby2js -e 'puts "hello"'`
- [ ] Test filter flags: `npx ruby2js --filter functions`

**Estimated effort:** 1 day

### Phase 4: Feature Parity (Post-Beta)

**Goal:** Match current npm package capabilities.

**Tasks:**
- [ ] Implement `load_options()` method
- [ ] Add `rb2js.config.rb` file loading support
- [ ] Add `RUBY2JS_OPTIONS` environment variable support
- [ ] Port configuration-related tests

**Estimated effort:** 3-4 days

### Phase 5: Testing & Documentation

**Goal:** Comprehensive validation and docs.

**Tasks:**
- [ ] Run all 8 existing mocha tests
- [ ] Add selfhost spec suite to npm package tests
- [ ] Browser compatibility testing
- [ ] Update `packages/ruby2js/README.md`
- [ ] Document migration from 5.x to 6.x
- [ ] Update website documentation

**Estimated effort:** 3-5 days

## Decisions Required

### 1. Package Name

**Options:**
- **A) Keep `@ruby2js/ruby2js`** - No breaking change for existing users
- **B) Switch to `ruby2js`** - Simpler, matches selfhost package.json

**Recommendation:** Keep `@ruby2js/ruby2js` for continuity. The selfhost `package.json` is for local development only.

### 2. Config Loading for Beta

**Options:**
- **A) Include in beta** - Full feature parity, more work
- **B) Defer to final release** - Ship faster, document limitation

**Recommendation:** Defer to final release. Users can pass options explicitly.

### 3. Which Filters to Include

**Options:**
- **A) All transpiled filters** - Maximum functionality
- **B) Only "ready" filters** - Only those with passing specs
- **C) Core only (no filters)** - Minimal bundle, users import separately

**Recommendation:** Include all transpiled filters. Mark experimental ones in docs.

## Build Process Changes

### Current (Opal)

```bash
# In packages/ruby2js/
npm run build
# Calls: bundle exec rake -f ../../docs/Rakefile ruby2js.js
# Uses Opal compiler, outputs 4.8 MB bundle
```

### Proposed (Self-hosted)

```bash
# Option A: Copy from selfhost build
cd demo/selfhost && npm run build
cp ruby2js.js ../../packages/ruby2js/
cp -r filters ../../packages/ruby2js/

# Option B: Direct build in packages/ruby2js
# Update package.json build script to call selfhost transpiler
```

**Recommendation:** Option A for simplicity. The selfhost build is already working.

## Release Checklist

### Pre-Release
- [ ] All Phase 1 tasks complete
- [ ] Existing npm tests pass
- [ ] Manual testing in Node.js
- [ ] Manual testing in browser
- [ ] Version bumped to `6.0.0-beta.1` in both:
  - `lib/ruby2js/version.rb`
  - `packages/ruby2js/package.json`

### Release
- [ ] `bundle exec rake test_all` passes
- [ ] `bundle exec rake release` (gem)
- [ ] `cd packages/ruby2js && npm publish --tag beta`
- [ ] Publish blog post (`published: true`)
- [ ] Deploy docs site

### Post-Release
- [ ] Verify `npm install ruby2js@beta` works
- [ ] Verify `gem install ruby2js --pre` works
- [ ] Monitor for issues

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| API incompatibility | High | Run existing tests first |
| Missing features | Medium | Document limitations in beta |
| Browser issues | Medium | Test with prism_browser.js |
| Performance regression | Low | Smaller bundle should be faster |

## Timeline

| Phase | Days | Cumulative |
|-------|------|------------|
| Phase 1 (Core) | 1-2 | 1-2 |
| Phase 2 (Filters) | 2-3 | 3-5 |
| Phase 3 (CLI) | 1 | 4-6 |
| Testing & Release | 1-2 | 5-8 |
| **Beta Release** | | **~1 week** |
| Phase 4 (Features) | 3-4 | 8-12 |
| Phase 5 (Docs) | 3-5 | 11-17 |
| **Final Release** | | **~2-3 weeks** |

## Minimum Viable Beta

For the fastest path to beta:

1. Complete Phase 1 only (core bundle)
2. Skip config file support
3. Skip CLI (users can use the gem CLI)
4. Document: "Beta - some features coming in final release"

This gets a working beta out in **1-2 days**.
