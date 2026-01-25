# Plan: Vite-Native Cleanup Assessment

## Summary

This plan assesses the current state of the Vite-native restructuring and identifies remaining cleanup opportunities.

## Background

The project originally had a custom build system. Vite was added later. The goal was to explore using Vite "as intended" - with config at project root and on-the-fly transformation rather than pre-compilation.

## What Was Accomplished

### Build Infrastructure
1. **Vite config at project root** ✅
   - `vite.config.js` with minimal config: `juntos()` plugin call
   - Standard npm scripts: `dev`, `build`, `preview`

2. **Standard Vite entry points** ✅
   - `index.html` at root (browser target)
   - `main.js` as entry point
   - Platform-specific entry points generated as needed (Vercel's `api/[[...path]].js`, Deno's `main.ts`)

3. **Multi-target builds working** ✅
   - Browser (dexie) - fully working
   - Node (better-sqlite3) - fully working
   - Cloudflare Workers (D1) - fully working
   - Vercel Edge (Neon) - builds successfully
   - Deno Deploy (Neon) - builds successfully

4. **Web Crypto migration** ✅
   - Replaced `node:crypto` with Web Crypto API
   - CSRF token generation/validation now async
   - Works across all platforms (Node, Cloudflare, Deno, Bun, browsers)

## Current Architecture (Vite-Native)

```
blog/
├── vite.config.js          # Minimal config, just juntos() call
├── package.json            # Standard npm scripts
├── index.html              # Browser entry point
├── main.js                 # App initialization (imports config/routes.rb directly)
├── app/                    # Source Ruby files (Rails structure)
│   ├── controllers/*.rb    # Transformed on-the-fly
│   ├── models/*.rb         # Transformed on-the-fly
│   └── views/**/*.erb      # Transformed on-the-fly
├── config/
│   └── routes.rb           # Transformed on-the-fly
├── db/
│   ├── migrate/*.rb        # Transformed on-the-fly
│   └── seeds.rb            # Transformed on-the-fly
└── dist/                   # Final build output (only directory created by build)

# NO .juntos/ directory - everything is virtual or on-the-fly
```

### Virtual Modules

- `juntos:rails` - Re-exports from target-specific runtime (browser, node, cloudflare, etc.)
- `juntos:active-record` - Injects DB_CONFIG and re-exports from database adapter
- `juntos:application-record` - ApplicationRecord base class
- `juntos:models` - Registry of all models
- `juntos:migrations` - Registry of all migrations
- `juntos:views/*` - Unified view modules (e.g., `juntos:views/articles` → ArticleViews)

## Previous Architecture (Pre-Vite-Native)

```
blog/
├── vite.config.js          # Minimal config, just juntos() call
├── package.json            # Standard npm scripts
├── index.html              # Browser entry point
├── main.js                 # App initialization
├── .juntos/                # Pre-transpiled output (staging) - NOW ELIMINATED
│   ├── app/
│   │   ├── controllers/    # Pre-compiled from app/controllers/*.rb
│   │   ├── models/         # Pre-compiled from app/models/*.rb
│   │   └── views/          # Pre-compiled from app/views/**/*.erb
│   ├── config/
│   │   └── routes.js       # Compiled from config/routes.rb
│   ├── db/
│   │   ├── migrate/        # Compiled migrations
│   │   └── seeds.js        # Compiled seeds
│   └── lib/                # Runtime helpers (rails.js, active_record, adapters)
├── app/                    # Source Ruby files (Rails structure)
├── config/                 # Rails config (routes.rb, database.yml)
└── dist/                   # Final build output
```

## What's In .juntos/ Today

**Nothing! The `.juntos/` directory has been eliminated.**

All content that was previously in `.juntos/` is now handled by:

| Previous Location | Now Handled By |
|-------------------|----------------|
| `.juntos/app/controllers/` | On-the-fly transformation in `juntos-ruby` plugin |
| `.juntos/app/models/` | On-the-fly transformation in `juntos-ruby` plugin |
| `.juntos/app/views/` | On-the-fly transformation in `juntos-erb` plugin |
| `.juntos/config/routes.js` | On-the-fly transformation in `juntos-ruby` plugin |
| `.juntos/config/paths.js` | Paths exported inline from routes.rb |
| `.juntos/db/migrate/` | On-the-fly transformation + `juntos:migrations` virtual module |
| `.juntos/db/seeds.js` | On-the-fly transformation in `juntos-ruby` plugin |
| `.juntos/lib/rails.js` | `juntos:rails` virtual module |
| `.juntos/lib/active_record.mjs` | `juntos:active-record` virtual module |
| `.juntos/lib/*` | Virtual modules or direct imports from `ruby2js-rails` package |

## Analysis: What Can Be Eliminated?

### 1. lib/ files → Virtual Modules + node_modules

**Current:** Files are copied from `ruby2js-rails/` to `.juntos/lib/`, with `active_record.mjs` having `DB_CONFIG` injected.

**The DB_CONFIG injection (build.mjs:1144-1147):**
```javascript
adapter_code = adapter_code.replace(
  "const DB_CONFIG = {};",
  `const DB_CONFIG = ${JSON.stringify(db_config)};`
);
```

**But:** For remote databases (Neon, Turso, etc.), `initDatabase()` prefers `process.env.DATABASE_URL` at runtime - the injected config is rarely used.

**Where DB_CONFIG actually matters:**
- SQLite: database file path
- Dexie: IndexedDB database name

**Solution: Virtual modules**
```javascript
function createVirtualModulesPlugin(config) {
  return {
    name: 'juntos-virtual',
    resolveId(id) {
      if (id === 'juntos:rails') return '\0juntos:rails';
      if (id === 'juntos:active-record') return '\0juntos:active-record';
    },
    load(id) {
      if (id === '\0juntos:rails') {
        // Re-export from the right target runtime
        return `export * from 'ruby2js-rails/lib/rails_${config.target}.js';`;
      }
      if (id === '\0juntos:active-record') {
        // Inject minimal config and re-export from adapter
        return `
          export const DB_CONFIG = ${JSON.stringify({ database: config.dbName })};
          export * from 'ruby2js-rails/adapters/${config.database}.mjs';
        `;
      }
    }
  };
}
```

**Result:** `.juntos/lib/` eliminated entirely. Imports change from:
```javascript
import { ActiveRecord } from '../lib/active_record.mjs';
```
to:
```javascript
import { ActiveRecord } from 'juntos:active-record';
```

**Important caveat (discovered January 2026):** When code imports from the virtual module, Vite bundles the adapter into the output. But tools that run *outside* Vite (like `migrate.mjs`) that import the adapter directly get a **different module instance** with a separate `db` variable. This caused migrations to fail because `initDatabase()` was called on the wrong instance.

**Solution (January 2026):** Rather than having migration code import adapter functions, migrations now receive the adapter as a parameter: `up: async (adapter) => { await adapter.createTable(...); }`. The migration runner (migrate.mjs or Application.runMigrations) passes its initialized adapter instance directly. This decouples migration code from how the adapter is obtained. Note: routes.js still re-exports `initDatabase`, `query`, etc. for use by migrate.mjs and server.mjs (the runners), but migration code itself no longer imports these functions.

### 2. app/models/, app/controllers/ → On-the-fly transformation

**Current:** Pre-transpiled during `buildStart()` to `.juntos/app/`.

**Solution:** Add `load()` hooks like the ERB plugin already does:
```javascript
async load(id) {
  if (id.match(/app\/models\/.*\.rb$/)) {
    const code = await fs.promises.readFile(id, 'utf-8');
    return transformModel(code, id);
  }
  if (id.match(/app\/controllers\/.*\.rb$/)) {
    const code = await fs.promises.readFile(id, 'utf-8');
    return transformController(code, id);
  }
}
```

**Result:** `.juntos/app/models/` and `.juntos/app/controllers/` eliminated.

### 3. app/views/ → Already on-the-fly (ERB plugin)

The `juntos-erb` plugin already transforms `.erb` files on-the-fly. Only need to update imports to reference source files instead of `.juntos/` copies.

### 4. config/routes.js + paths.js → Must be generated (one-to-many)

**Challenge:** `routes.rb` generates multiple files:
- `routes.js` - Route definitions and handlers
- `paths.js` - Path helper functions

This is a one-to-many transformation that can't be handled by a simple `load()` hook.

**Options:**
A. Keep generating to `.juntos/config/` (minimal)
B. Generate to a temp directory (`node_modules/.juntos/`)
C. Virtual module with all routes embedded

**Recommendation:** Option A or B - routes are small, generated once at startup.

### 5. db/migrate/, db/seeds.js → Must be generated (app-specific)

**Challenge:** Migrations are transpiled from Ruby and need to be importable.

**Options:**
A. Keep generating to `.juntos/db/`
B. Virtual module that imports and transforms on-the-fly
C. Generate to `node_modules/.juntos/db/`

**Recommendation:** Option A or C - migrations need to be stable for database versioning.

## Achieved Architecture (Zero .juntos/)

```
# NO .juntos/ directory at all!

# Everything is virtual or on-the-fly:
# - juntos:rails → virtual module re-exporting from ruby2js-rails/targets/*/rails.js
# - juntos:active-record → virtual module re-exporting from adapter
# - juntos:application-record → virtual module with ApplicationRecord class
# - juntos:models → virtual module importing all models
# - juntos:migrations → virtual module importing all migrations
# - juntos:views/* → virtual modules with unified view exports
# - app/models/*.rb → on-the-fly transformation
# - app/controllers/*.rb → on-the-fly transformation
# - config/routes.rb → on-the-fly transformation
# - db/migrate/*.rb → on-the-fly transformation
# - db/seeds.rb → on-the-fly transformation
# - app/views/**/*.erb → on-the-fly transformation via juntos-erb
```

**Benefits:**
- `.juntos/` completely eliminated (was ~20+ files)
- Zero duplication of source files
- True Vite-native development experience
- Source maps point directly to Ruby/ERB files
- Simpler mental model: source → build output, nothing in between

## Open Questions

### 1. Turbo 8 HMR for ERB Templates

**Concept:** Turbo 8 introduced "morphing" which can intelligently update DOM without full page reload. Could this enable HMR for ERB changes?

**Current state:**
- ERB files are transformed on-the-fly by `juntos-erb` plugin
- When ERB changes, Vite triggers a full page reload
- No integration with Turbo's morphing yet

**How it could work:**
1. Detect ERB file change via Vite watcher
2. Re-transpile the changed template
3. Send the new rendered output to browser via WebSocket
4. Use `Turbo.renderStreamMessage()` with `<turbo-stream action="morph">` to update DOM

**Implementation sketch:**
```javascript
// In configureServer hook
server.watcher.on('change', async (file) => {
  if (file.endsWith('.erb')) {
    // Re-render the template
    const html = await renderTemplate(file, currentContext);
    // Send Turbo Stream morph to browser
    server.ws.send({
      type: 'custom',
      event: 'turbo-morph',
      data: { target: getTemplateId(file), html }
    });
  }
});
```

**Challenges:**
- Need to know the current rendering context (instance variables)
- Partials vs full templates have different update strategies
- May need to track which route rendered which template

**Recommendation:** Worth exploring as a follow-up. Start with full-template morphs for layouts/index views.

### 3. Documentation Updates Needed

After cleanup, update:
- `docs/src/_docs/juntos/demos/blog.md` - Reflect new Vite-native structure
- `docs/src/_docs/juntos/cli.md` - Update any CLI references

## The Eject Command

The "everything virtual" approach works because of one key feature: `juntos eject`.

**Purpose:** Generate all transpiled files to a standalone directory that can be taken elsewhere and run without ruby2js or the original Ruby source.

```bash
bin/juntos eject [options]
```

**What it produces:**

```
ejected/
├── app/
│   ├── controllers/     # Transpiled JS controllers
│   ├── models/          # Transpiled JS models
│   └── views/           # Transpiled JS views
├── config/
│   ├── routes.js        # Generated routes
│   └── paths.js         # Path helpers
├── db/
│   ├── migrate/         # Transpiled migrations
│   └── seeds.js         # Transpiled seeds
├── lib/
│   └── ...              # Runtime files (copied from node_modules)
├── package.json         # Dependencies for the target
├── vite.config.js       # Standard Vite config (no ruby2js plugin)
└── index.html           # Entry point
```

**Use cases:**
1. **Deployment** - Deploy transpiled JS without Ruby dependencies
2. **Handoff** - Give the project to someone without ruby2js installed
3. **Debugging** - Inspect generated code when virtual modules are opaque
4. **Migration** - Transition away from Ruby source to pure JS

**Options:**
- `-t, --target TARGET` - Target runtime (browser, node, cloudflare, etc.)
- `-d, --database ADAPTER` - Database adapter
- `-o, --output DIR` - Output directory (default: `ejected/`)
- `--no-node-modules` - Skip copying runtime files (assume npm install)

**Multiple targets:** Run the command multiple times with different options:
```bash
bin/juntos eject -t cloudflare -d d1 -o deploy/cloudflare/
bin/juntos eject -t vercel -d neon -o deploy/vercel/
bin/juntos eject -t browser -d dexie -o deploy/static/
```

Each output is a complete standalone project for that specific target.

**Key insight:** During normal development, everything is virtual/on-the-fly. When you need concrete files, `eject` produces them. Best of both worlds.

## Proposed Next Steps

### Phase 1: Virtual Modules for lib/ (High Impact) ✅ COMPLETE
1. [x] Add `juntos-virtual` plugin with `resolveId`/`load` hooks
2. [x] Create virtual `juntos:rails` that re-exports from target-specific runtime
3. [x] Create virtual `juntos:active-record` that injects minimal config
4. [x] Update route generation to use virtual imports
5. [x] Delete `.juntos/lib/` - everything comes from node_modules

### Phase 2: On-the-Fly Transformation (Medium Risk) ✅ COMPLETE
1. [x] Add `load()` hook for `app/models/*.rb` files
2. [x] Add `load()` hook for `app/controllers/*.rb` files
3. [x] Add `load()` hook for `config/routes.rb` - routes transformed on-the-fly
4. [x] Add `load()` hook for `db/migrate/*.rb` - migrations transformed on-the-fly
5. [x] Add `load()` hook for `db/seeds.rb` - seeds transformed on-the-fly
6. [x] Views already work on-the-fly via `juntos-erb` plugin
7. [x] Virtual modules: `juntos:models`, `juntos:migrations`, `juntos:views/*`, `juntos:application-record`
8. [x] No `.juntos/` directory generated - everything is virtual/on-the-fly

### Phase 3: Migrate Project Structure (Required for CI) ✅ COMPLETE

The old structure had `dist/` containing package.json and vite.config.js, with the Ruby generator creating this structure. The new Vite-native structure has these at project root.

**Old structure (generator-based):**
```
app/
├── app/models/*.rb
├── config/routes.rb
├── dist/                    # Created by Ruby generator
│   ├── package.json         # npm dependencies
│   ├── vite.config.js       # Vite config
│   ├── node_modules/
│   └── .juntos/             # Pre-compiled output (NOW ELIMINATED)
└── bin/juntos               # Ruby binstub
```

**New structure (Vite-native):**
```
app/
├── app/models/*.rb
├── config/routes.rb
├── package.json             # At root (standard Vite)
├── vite.config.js           # At root (standard Vite)
├── node_modules/            # At root
├── dist/                    # Build output only
└── bin/juntos               # Ruby binstub (delegates to gem CLI)
```

**Note:** `index.html` and `main.js` are NOT installed by the generator - they are only needed for browser SPA deployments and should be added separately when needed.

**Completed Tasks:**
1. [x] Updated Ruby generator to install at project root:
   - `lib/ruby2js/installer.rb` - Updated path calculations for root install
   - `lib/generators/ruby2js/install_generator.rb` - Creates files at root, not dist/
   - `lib/ruby2js/rails/builder.rb` - Added `root_install` option for path calculation

2. [x] Updated `vite.config.js` generation:
   - No longer needs `appRoot: '..'` since it's at root
   - Just `juntos()` plugin call with no options needed

3. [x] Updated Ruby CLI commands to run from project root:
   - `lib/ruby2js/cli/dev.rb` - No longer chdir to dist/
   - `lib/ruby2js/cli/build.rb` - No longer chdir to dist/
   - `lib/ruby2js/cli/build_helper.rb` - No longer chdir to dist/
   - `lib/ruby2js/cli/server.rb` - No longer chdir to dist/
   - `lib/ruby2js/cli/up.rb` - No longer chdir to dist/
   - `lib/ruby2js/cli/doctor.rb` - Checks package.json and node_modules at root
   - `lib/ruby2js/cli/db.rb` - Node.js operations run from root (D1 operations still run from dist/)

4. [x] Test scripts continue to work:
   - `test/blog/create-blog` ends with `bin/rails generate ruby2js:install`
   - Generator now creates root-level structure automatically

5. [x] Update CI workflow:
   - `bin/juntos build` works (just calls `vite build`)
   - Smoke tests pass with new structure
   - Integration tests pass (blog, astro_blog, ssg_blog)
   - Removed Ruby from build-site CI step (pure JavaScript now)
   - Removed Ruby from integration-test CI step (pure JavaScript now)
   - Temporarily removed chat, notes, photo_gallery, workflow integration tests (need updates)

### Phase 4: JavaScript CLI (Feature Complete)

Make the JavaScript CLI (`demo/blog/bin/juntos`) feature-complete and move it to the `ruby2js-rails` npm package. This allows Juntos to appeal to both audiences:

- **JavaScript developers**: Use familiar `npm run dev`, `npx vite build`, `npx juntos db:migrate`
- **Rails developers**: Use `bin/juntos dev`, `bin/juntos build` - feels like Rails, but just sets env vars and calls npm/npx

**Current JavaScript CLI status:**
- ✅ `dev` - Start development server
- ✅ `build` - Build for deployment
- ✅ `up` - Build and run locally
- ✅ `deploy` - Build and deploy (Cloudflare, Vercel)
- ✅ `db` - Database commands (D1, SQLite basic support)
- ✅ `info` - Show configuration
- ✅ `doctor` - Check environment
- ❌ `server` - Missing (start production server)

**Out of scope for JavaScript CLI:**
- `--framework` option (Astro/Vue/Svelte conversion) - This is part of the SFC triple-target transpiler project (see `plans/sfc-triple-target.md`), which is incomplete and requires Ruby2JS transpilation. It will remain a separate Ruby-based tool.

**Tasks:**
1. [x] Add missing `server` command to JavaScript CLI
2. [x] Database adapters already supported via generic `migrate.mjs` runner:
   - D1: Cloudflare-specific wrangler commands
   - SQLite/better-sqlite3: Node.js migrate.mjs
   - All others (pg, neon, turso, planetscale, supabase): Node.js migrate.mjs
   - Create/drop for cloud databases done via provider tools (as expected)
3. [x] Update deploy entry points to use virtual modules:
   - Change `../.juntos/lib/rails.js` → `juntos:rails`
   - Change `../.juntos/config/routes.js` → `config/routes.rb`
   - Change `../.juntos/db/migrate/index.js` → `juntos:migrations`
4. [x] Fix migration paths: `node_modules/ruby2js-rails/migrate.mjs` (not `dist/node_modules/`)
5. [x] Move CLI from `demo/blog/bin/juntos` to `packages/ruby2js-rails/cli.mjs`
6. [x] Add `bin` entry to `packages/ruby2js-rails/package.json`:
   ```json
   {
     "bin": {
       "juntos": "./cli.mjs"
     }
   }
   ```
7. [x] Update generator to create shell binstub:
   ```bash
   #!/bin/sh
   exec npx juntos "$@"
   ```

**Result:** After `npm install`, users can run:
- `npx juntos dev` or `bin/juntos dev`
- `npx juntos build` or `bin/juntos build`
- `npx juntos db:migrate` or `bin/juntos db:migrate`

### Phase 5: Remove Ruby CLI ✅ COMPLETE

Ruby CLI infrastructure has been replaced by JavaScript CLI.

**Files removed:**
1. [x] `lib/ruby2js/cli/juntos.rb` - Main CLI dispatcher
2. [x] `lib/ruby2js/cli/dev.rb` - Dev command
3. [x] `lib/ruby2js/cli/build.rb` - Build command
4. [x] `lib/ruby2js/cli/build_helper.rb` - Build helper
5. [x] `lib/ruby2js/cli/server.rb` - Server command
6. [x] `lib/ruby2js/cli/up.rb` - Up command
7. [x] `lib/ruby2js/cli/deploy.rb` - Deploy command
8. [x] `lib/ruby2js/cli/db.rb` - Database commands
9. [x] `lib/ruby2js/cli/info.rb` - Info command
10. [x] `lib/ruby2js/cli/doctor.rb` - Doctor command
11. [x] `lib/ruby2js/cli/` - Directory removed

**Files updated:**
1. [x] `bin/juntos` - Now a shell script that delegates to `npx juntos`
2. [x] `demo/ruby2js.rb` - Subcommand support removed, points to npx
3. [x] `lib/generators/ruby2js/install_generator.rb` - Now self-contained (no installer.rb dependency)
4. [x] `packages/ruby2js-rails/vite.mjs` - Now self-contained (no build.mjs dependency)
5. [x] `test/integration/setup.mjs` - Uses `vite build` instead of SelfhostBuilder

**Files removed:**
1. [x] `lib/ruby2js/installer.rb` - No longer needed, logic moved to install_generator.rb

**Files deprecated (pending removal):**
1. `lib/ruby2js/rails/builder.rb` - DEPRECATED. Eject command will use Vite instead.
2. `packages/ruby2js-rails/build.mjs` - DEPRECATED. Transpiled from builder.rb.

See "Phase 9: Remove builder.rb" for removal plan.

**Verify nothing breaks:**
1. [x] `bundle exec rake test` - Ruby gem tests pass
2. [x] `node run_all_specs.mjs` - Selfhost tests pass
3. [x] CI workflow passes (build-site and integration-test are now Ruby-free)
4. [x] Manual test: `npx juntos dev`, `npx juntos build`, `npx juntos db:migrate`

### Phase 6: Turbo 8 HMR (Experimental)
1. [ ] Research Turbo 8 morphing API
2. [ ] Prototype ERB HMR with morphing
3. [ ] Handle partial vs template updates
4. [ ] Add to documentation if successful

### Phase 7: Eject Command (Vite-based)

The eject command uses `vite build` as its foundation, NOT builder.rb.

1. [ ] Add `juntos eject` subcommand to JavaScript CLI
2. [ ] Run `vite build` to generate transpiled output
3. [ ] Post-process: generate standalone vite.config.js (no ruby2js plugin needed)
4. [ ] Post-process: generate package.json with only runtime dependencies
5. [ ] Copy dist/ to ejected/ directory
6. [ ] Document: ejected app runs with standard `vite dev` / `vite build`

**Key insight:** Eject is just `vite build` + cleanup. No need for separate build system.

### Phase 8: Documentation
1. [ ] Update docs/src/_docs/juntos/demos/blog.md
2. [ ] Update docs/src/_docs/juntos/cli.md
3. [ ] Document new project structure
4. [ ] Document `juntos eject` command
5. [ ] Retest all targets

### Phase 9: Remove builder.rb (Discussion Needed)

**Question:** Should builder.rb be completely removed?

**Current uses of builder.rb:**
1. Selfhost demo (`demo/selfhost/`) - bundles Ruby2JS transpiler for browser
2. Smoke tests (`test/smoke-test.mjs`) - compares Ruby vs JS builder output
3. Release Rakefile (`demo/selfhost/Rakefile`) - creates npm tarballs

**Arguments for removal:**
- 3000+ lines of code that duplicates what Vite does
- Maintenance burden: two build systems that can diverge
- Vite-native philosophy: use Vite for everything
- Confusing: which build system should developers use?

**Arguments for keeping:**
- Selfhost demo needs to bundle the transpiler itself (special case)
- Gradual migration is safer than big-bang removal

**Possible approaches:**
1. **Full removal:** Replace all uses with Vite/Rollup configs
2. **Minimal extraction:** Keep only what selfhost demo needs, delete the rest
3. **Separate project:** Move selfhost bundling to its own focused tool

**Decision needed:** [TODO - discuss and decide]

**If removing, steps would be:**
1. [ ] Update selfhost demo to use Rollup/Vite for bundling
2. [ ] Update smoke tests to test `vite build` output (or remove them)
3. [ ] Update Rakefile to use `vite build` + `npm pack`
4. [ ] Delete `lib/ruby2js/rails/builder.rb`
5. [ ] Delete `packages/ruby2js-rails/build.mjs`
6. [ ] Update any remaining references

## Files to Review

**Vite plugin (already updated):**
- `packages/ruby2js-rails/vite.mjs` - Main Vite plugin (Vite-native complete)

**Need updates for Phase 3:**
- `test/blog/create-blog` - Update to root-level structure
- `test/chat/create-chat` - Same
- `test/photo_gallery/create-photo-gallery` - Same
- `test/workflow/create-workflow` - Same
- `test/notes/create-notes` - Same
- `demo/blog/bin/juntos` - Update deploy commands

**Already removed/simplified:**
- `lib/ruby2js/installer.rb` - Removed (January 2026)
- `lib/generators/ruby2js/install_generator.rb` - Simplified, now self-contained
- `packages/ruby2js-rails/vite.mjs` - No longer depends on build.mjs

## Success Criteria

1. ✅ Blog demo works with NO `.juntos/` footprint - everything is virtual/on-the-fly
2. ✅ CI passes with Vite-native project structure (build-site and integration-test are Ruby-free)
3. [x] Ruby generator creates standard Vite structure (package.json and vite.config.js at root)
4. [ ] Documentation accurately reflects current architecture
5. ✅ Developer experience is improved (no staging directories, cleaner project structure)
6. ⚠️ Most tests pass (chat, notes, photo_gallery, workflow integration tests temporarily removed)

## Current Status (January 2026)

**Phase 1-2 Complete:** The core Vite-native implementation is done:

- **No staging directory**: `.juntos/` is never created
- **All Ruby transformed on-the-fly**: models, controllers, routes, migrations, seeds
- **Virtual modules** for generated code: `juntos:rails`, `juntos:active-record`, `juntos:models`, `juntos:migrations`, `juntos:views/*`, `juntos:application-record`
- **ERB views** transformed on-the-fly by `juntos-erb` plugin
- **Browser build** works: `npm run build` produces `dist/` directly
- **Dev server** works: `npm run dev` with HMR

**Phase 3 Complete:** CI workflow updated:

- **build-site is Ruby-free**: Only Node.js needed for browser builds
- **integration-test is Ruby-free**: Only Node.js needed for vitest
- Smoke tests pass (blog, chat with dexie/sqlite)
- Integration tests pass (blog, astro_blog, ssg_blog)
- Temporarily removed: chat, notes, photo_gallery, workflow integration tests (need Vite-native updates)

**Phase 5 Complete:** Ruby CLI removed, JavaScript CLI is primary:

- Ruby CLI files removed
- `bin/juntos` binstub delegates to `npx juntos`
- Generator simplified to be self-contained (no installer.rb dependency)
- vite.mjs is self-contained (no build.mjs dependency for configuration)
- Integration tests use `vite build` instead of SelfhostBuilder
- **installer.rb removed** - all install logic is now in install_generator.rb
- **builder.rb/build.mjs deprecated** - no longer used by vite.mjs or integration tests

**Issues Discovered During System Testing (January 2026):**

While building system test infrastructure (`rake system[blog,sqlite,node]`), several issues were discovered in the Node.js target build:

1. **External modules incomplete** - Rollup was trying to bundle Node.js built-ins that use the `node:` prefix (e.g., `node:url`, `node:fs/promises`). Also `react-dom/server` wasn't externalized (needed by `rails_server.js` even for non-React apps).
   - **Fixed:** Added both prefixed and unprefixed Node.js builtins to external list, plus React modules for SSR support.

2. **Database configuration not flowing through** - The `juntos:active-record` virtual module exports `DB_CONFIG` at build time, but the adapter's internal `const DB_CONFIG = {}` was a separate variable. Database path from `database.yml` wasn't being used.
   - **Fixed:** `migrate.mjs` and `server.mjs` now load `config/database.yml` directly and pass options to `initDatabase()`.

3. **migrate.mjs using wrong adapter instance** - Migrations import `createTable`, `addIndex`, etc. from `juntos:active-record` which gets bundled into `routes.js`. But `migrate.mjs` was importing a separate adapter module, so calling `initDatabase()` on that adapter didn't initialize the `db` variable used by migrations.
   - **Initial workaround:** `routes.js` re-exported `initDatabase`, `query`, etc. from the bundled adapter.
   - **Proper fix (January 2026):** Refactored migration architecture. Migrations now receive the adapter as a parameter:
     ```javascript
     export const migration = {
       up: async (adapter) => {
         await adapter.createTable('articles', [...]);
       },
       tableSchemas: { articles: '++id, title, body, created_at, updated_at' }
     };
     ```
     This eliminates the module instance coupling. The runner passes the adapter:
     ```javascript
     await migration.up(adapter);  // migrate.mjs, Application.runMigrations
     ```
     Changes made:
     - `lib/ruby2js/filter/rails/migration.rb` - Generates `up: async (adapter) => {...}` with `adapter.createTable()` calls
     - `packages/ruby2js-rails/migrate.mjs` - Already passed adapter (line 178)
     - `packages/ruby2js-rails/targets/node/rails.js` - Passes adapter to `migration.up(adapter)`
     - `packages/ruby2js-rails/targets/browser/rails.js` - Passes adapter to `migration.up(adapter)`
     - `packages/ruby2js-rails/rails_base.js` - Passes adapter to `migration.up(adapter)`
     - `packages/ruby2js-rails/vite.mjs` - Re-exports still needed for `initDatabase`, `query`, `execute`, `insert`, `closeDatabase` (used by migrate.mjs/server.mjs to manage database connection, not by migration code)

4. **Server initialization** - `Application.start()` called `this.initDatabase()` with no config. Added `Application.startServer()` that skips initDatabase (for when database is pre-initialized with config).
   - **Fixed:** `server.mjs` now loads database.yml, calls `initDatabase(dbConfig)`, then calls `Application.startServer()`.

5. **Layout files with yield** - ERB layouts use Ruby's `yield` which can't be transpiled directly.
   - **Fixed (January 2026):** Updated `juntos-erb` plugin to handle layouts:
     - Replaces `<%= yield %>` → `<%= content %>`
     - Replaces `<%= yield :section %>` → `<%= context.contentFor.section || '' %>`
     - Passes `layout: true` option to ERB filter (changes function signature to `layout(context, content)`)
     - Exports as `function layout` instead of `function render`

**System Test Infrastructure (January 2026):**

Added `test/Rakefile` with unified test commands:
- `rake integration[blog]` - Automated vitest tests
- `rake system[blog,sqlite,node]` - Manual browser testing with Docker

The system test builds and runs correctly:
- Database persists to `storage/development.sqlite3`
- Migrations and seeds run successfully
- All pages render correctly (index, show, new, edit)
- Server runs on Node.js with better-sqlite3 adapter

6. **View module reserved word handling** - The view module was exporting `new_` but controllers expected `$new`.
   - **Fixed:** Changed vite.mjs to use `$` prefix (Ruby2JS convention) instead of `_` suffix for reserved words like `new`, `delete`, etc.

**Pending work:**

- Restore chat, notes, photo_gallery, workflow integration tests with Vite-native updates
- Phase 6: Turbo 8 HMR (experimental)
- Phase 7: Eject command (Vite-based, not builder.rb)
- Phase 8: Documentation updates
- Phase 9: Decision on builder.rb removal (see discussion section)
