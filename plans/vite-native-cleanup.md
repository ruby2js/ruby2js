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

### Phase 3: Turbo 8 HMR (Experimental)
1. [ ] Research Turbo 8 morphing API
2. [ ] Prototype ERB HMR with morphing
3. [ ] Handle partial vs template updates
4. [ ] Add to documentation if successful

### Phase 4: Eject Command
1. [ ] Add `juntos eject` subcommand
2. [ ] Generate all transpiled files to output directory
3. [ ] Include standalone vite.config.js (no ruby2js plugin)
4. [ ] Copy runtime files from node_modules
5. [ ] Generate package.json with only runtime dependencies

### Phase 5: Documentation
1. [ ] Update docs/src/_docs/juntos/demos/blog.md
2. [ ] Update docs/src/_docs/juntos/cli.md
3. [ ] Document `juntos eject` command
4. [ ] Retest all targets

## Files to Review

- `packages/ruby2js-rails/vite.mjs` - Main Vite plugin
- `packages/ruby2js-rails/build.mjs` - SelfhostBuilder (pre-compilation)
- `demo/blog/bin/juntos` - CLI (not tracked in git)
- `demo/blog/main.js` - Current entry point imports

## Success Criteria

1. ✅ Blog demo works with NO `.juntos/` footprint - everything is virtual/on-the-fly
2. [ ] Documentation accurately reflects current architecture
3. ✅ Developer experience is improved (no staging directories, cleaner project structure)
4. [ ] All existing tests still pass

## Current Status (January 2025)

The Vite-native implementation is complete. Key achievements:

- **No staging directory**: `.juntos/` is never created
- **All Ruby transformed on-the-fly**: models, controllers, routes, migrations, seeds
- **Virtual modules** for generated code: `juntos:rails`, `juntos:active-record`, `juntos:models`, `juntos:migrations`, `juntos:views/*`, `juntos:application-record`
- **ERB views** transformed on-the-fly by `juntos-erb` plugin
- **Browser build** works: `npm run build` produces `dist/` directly
- **Dev server** works: `npm run dev` with HMR
