# NPM Beta Distribution: Two-Package Approach

Distribute Ruby2JS 6.0 beta via URL-based tarballs hosted on ruby2js.com, bypassing npm registry until stable release.

## Overview

Two npm packages distributed as tarballs:

1. **`ruby2js`** - Core converter + filters
2. **`ruby2js-rails`** - Rails runtime (adapters, targets, erb_runtime) - depends on ruby2js

## Distribution Model

### URLs (updated on every deploy)

```
https://www.ruby2js.com/releases/ruby2js-beta.tgz
https://www.ruby2js.com/releases/ruby2js-rails-beta.tgz
https://www.ruby2js.com/demo/ruby2js-on-rails.tar.gz
```

### Version Strategy

Each tarball contains a timestamped version (e.g., `6.0.0-beta.20251222`). The URL stays stable; content updates on each deploy. Users run `npm update` to get latest.

**Tested behavior:**
- `npm install <url>` - Fetches and installs
- `npm install` (with lock file) - Uses cached version
- `npm update` - Re-fetches URL, detects version change, updates

## Package Structure

### Package 1: `ruby2js`

**Source:** `demo/selfhost/`

```
ruby2js-beta.tgz
  package/
    package.json
    ruby2js.js          # Core converter (~525 KB)
    ruby2js-cli.js      # CLI tool
    prism_browser.js    # Browser Prism loader
    filters/
      functions.js
      esm.js
      cjs.js
      return.js
      erb.js
      stimulus.js
      rails/
        model.js
        controller.js
        routes.js
        schema.js
        seeds.js
        logger.js
      ...
    lib/
      erb_compiler.js
```

**package.json:**
```json
{
  "name": "ruby2js",
  "version": "6.0.0-beta.20251222",
  "type": "module",
  "main": "ruby2js.js",
  "bin": {
    "ruby2js": "./ruby2js-cli.js"
  },
  "exports": {
    ".": "./ruby2js.js",
    "./filters/*": "./filters/*",
    "./lib/*": "./lib/*"
  },
  "dependencies": {
    "@ruby/prism": "^1.6.0"
  }
}
```

### Package 2: `ruby2js-rails`

**Source:** `demo/ruby2js-on-rails/vendor/ruby2js/` (minus selfhost)

```
ruby2js-rails-beta.tgz
  package/
    package.json
    erb_runtime.mjs
    adapters/
      active_record_dexie.mjs
      active_record_sqljs.mjs
      active_record_better_sqlite3.mjs
      active_record_pg.mjs
    targets/
      browser/
        rails.js
      node/
        rails.js
      bun/
        rails.js
      deno/
        rails.js
```

**package.json:**
```json
{
  "name": "ruby2js-rails",
  "version": "6.0.0-beta.20251222",
  "type": "module",
  "exports": {
    "./adapters/*": "./adapters/*",
    "./targets/*": "./targets/*",
    "./erb_runtime.mjs": "./erb_runtime.mjs"
  },
  "dependencies": {
    "ruby2js": "https://www.ruby2js.com/releases/ruby2js-beta.tgz"
  }
}
```

### Demo App: `ruby2js-on-rails.tar.gz`

**After migration:** No vendor directory, just app code.

```
ruby2js-on-rails/
  app/
    models/
    controllers/
    views/
  config/
  db/
  scripts/
  package.json          # Depends on ruby2js-rails
  bin/dev
  ...
```

**package.json:**
```json
{
  "name": "ruby2js-on-rails",
  "version": "0.1.0",
  "type": "module",
  "dependencies": {
    "ruby2js-rails": "https://www.ruby2js.com/releases/ruby2js-rails-beta.tgz",
    "dexie": "^4.0.10",
    "sql.js": "^1.11.0"
  },
  "optionalDependencies": {
    "better-sqlite3": "^11.0.0",
    "pg": "^8.13.0"
  },
  "devDependencies": {
    "chokidar": "^3.5.3",
    "js-yaml": "^4.1.0",
    "ws": "^8.14.2"
  }
}
```

## User Experience

### Getting Started (unchanged)

```bash
curl -L https://www.ruby2js.com/demo/ruby2js-on-rails.tar.gz | tar xz
cd ruby2js-on-rails
npm install      # Fetches ruby2js-rails → ruby2js from URLs
bin/dev
```

### Getting Updates

```bash
npm update       # Gets latest ruby2js and ruby2js-rails
```

### Dependency Chain

```
ruby2js-on-rails (demo app)
  └── ruby2js-rails (runtime)
        └── ruby2js (converter)
              └── @ruby/prism (parser)
```

## Build Pipeline

### GitHub Action (on every push to master)

```yaml
- name: Build selfhost
  run: |
    cd demo/selfhost
    npm run build

- name: Package ruby2js
  run: |
    cd demo/selfhost
    VERSION="6.0.0-beta.$(date +%Y%m%d%H%M)"
    npm version $VERSION --no-git-tag-version
    npm pack
    mv ruby2js-*.tgz $DEPLOY_DIR/releases/ruby2js-beta.tgz

- name: Package ruby2js-rails
  run: |
    # Create package from vendor/ruby2js (minus selfhost)
    cd demo/ruby2js-on-rails/vendor/ruby2js
    # ... package adapters, targets, erb_runtime
    npm pack
    mv ruby2js-rails-*.tgz $DEPLOY_DIR/releases/ruby2js-rails-beta.tgz

- name: Package demo
  run: |
    # Create demo tarball (no vendor/ruby2js/selfhost)
    tar czf ruby2js-on-rails.tar.gz ruby2js-on-rails/
    mv ruby2js-on-rails.tar.gz $DEPLOY_DIR/demo/
```

## Migration Tasks

### Phase 1: Create ruby2js package

- [ ] Create `demo/selfhost/package.json` with proper exports
- [ ] Add CLI to package (`ruby2js-cli.js`)
- [ ] Test `npm pack` produces correct tarball
- [ ] Test installation from local tarball
- [ ] Test `npm update` behavior with changing versions

### Phase 2: Create ruby2js-rails package

- [ ] Create package structure for adapters/targets/erb_runtime
- [ ] Create `package.json` with dependency on ruby2js URL
- [ ] Test `npm pack` produces correct tarball
- [ ] Test transitive dependency resolution

### Phase 3: Update demo app

- [ ] Remove `vendor/ruby2js/selfhost/` from demo
- [ ] Update `package.json` to depend on ruby2js-rails URL
- [ ] Update `scripts/build.mjs` imports:
  ```javascript
  // Before
  import * as Ruby2JS from "../vendor/ruby2js/selfhost/ruby2js.js";
  import { Rails_Model } from "../vendor/ruby2js/selfhost/filters/rails/model.js";

  // After
  import * as Ruby2JS from "ruby2js";
  import { Rails_Model } from "ruby2js/filters/rails/model.js";
  ```
- [ ] Update adapter imports in build script
- [ ] Test full build and runtime

### Phase 4: Deploy pipeline

- [ ] Add tarball creation to GitHub Action
- [ ] Deploy tarballs to ruby2js.com/releases/
- [ ] Test end-to-end: curl → npm install → bin/dev
- [ ] Test npm update gets new versions

### Phase 5: Documentation

- [ ] Update blog post with new installation instructions
- [ ] Document npm update workflow
- [ ] Note: "Beta via URL, stable via npm registry"

## Size Comparison

| Artifact | Before | After |
|----------|--------|-------|
| ruby2js-on-rails.tar.gz | ~600 KB | ~50 KB |
| Converter (in demo) | Bundled | Fetched via npm |
| Total download (npm install) | N/A | ~600 KB |

Net transfer is similar, but:
- Demo tarball is much smaller (faster initial download)
- Converter updates don't require re-downloading demo
- Clear separation of concerns

## Transition to Stable

When ready for stable release:

1. Publish `ruby2js` to npm registry
2. Publish `ruby2js-rails` to npm registry
3. Update ruby2js-rails dependency to registry version
4. Users change URL to version: `"ruby2js-rails": "^6.0.0"`

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| URL caching issues | Medium | Tested: `npm update` works correctly |
| Transitive dep resolution | Medium | Test ruby2js-rails → ruby2js chain |
| Build script import changes | Low | Straightforward path updates |
| Demo breaks on deploy | Medium | Test locally before merge |

## Timeline

| Task | Effort |
|------|--------|
| Phase 1: ruby2js package | 1 day |
| Phase 2: ruby2js-rails package | 1 day |
| Phase 3: Update demo app | 1 day |
| Phase 4: Deploy pipeline | 1 day |
| Phase 5: Documentation | 1 day |
| **Total** | **~5 days** |
