# Publish Ruby2JS-on-Rails Demo

This plan covers renaming, restructuring, and publishing the demo as a downloadable tarball that runs with just `npm install && npm run dev`.

## Overview

The demo currently lives in `demo/ruby2js-on-rails/`. It needs to be:
1. Renamed to `ruby2js-on-rails`
2. Restructured so framework code is in `/vendor/ruby2js/`
3. Packaged as a self-contained tarball requiring only Node.js

## Phase 1: Rename ruby2js-on-rails → ruby2js-on-rails

### 1.1 Directory rename
- [ ] Rename `demo/ruby2js-on-rails/` to `demo/ruby2js-on-rails/`

### 1.2 Update references in code
- [ ] `demo/selfhost/Rakefile` - paths to ruby2js-on-rails
- [ ] `demo/ruby2js-on-rails/package.json` - package name
- [ ] `demo/ruby2js-on-rails/README.md` - all references
- [ ] Any import paths or comments referencing the old name

### 1.3 Update references in plans/docs
- [ ] `plans/RUBY2JS_ON_RAILS.md` - rename file and update content
- [ ] `plans/RUNTIME_TARGETS_AND_CONFIG.md` - update references
- [ ] Any other plans referencing ruby2js-on-rails

### 1.4 Update blog post
- [ ] `~/git/intertwingly/src/3393.md` - update all references

## Phase 2: Restructure for /vendor/ruby2js/

### 2.1 Current structure (in demo/ruby2js-on-rails/)
```
├── app/                    # User code
├── config/
├── db/
├── lib/
│   ├── adapters/           # → vendor/ruby2js/adapters/
│   └── targets/            # → vendor/ruby2js/targets/
├── scripts/
│   ├── build.rb            # Source for transpiled build.mjs
│   └── build.mjs           # → vendor/ruby2js/build.mjs
├── dev-server.mjs
├── server.mjs
├── index.html
└── package.json
```

### 2.2 Target structure (for published tarball)
```
ruby2js-on-rails/
├── app/                      # User's Ruby source
│   ├── controllers/
│   ├── helpers/
│   ├── models/
│   └── views/
├── bin/
│   ├── dev                   # Runs npm run dev
│   └── rails                 # Supports 'rails server' with options
├── config/
│   ├── database.yml
│   ├── routes.rb
│   ├── ruby2js.yml
│   └── schema.rb
├── db/
│   └── seeds.rb
├── dist/                     # Created at runtime
├── vendor/ruby2js/
│   ├── adapters/
│   │   ├── active_record_dexie.mjs
│   │   ├── active_record_sqljs.mjs
│   │   ├── active_record_better_sqlite3.mjs
│   │   └── active_record_pg.mjs
│   ├── targets/
│   │   ├── browser/rails.js
│   │   ├── node/rails.js
│   │   ├── bun/rails.js
│   │   └── deno/rails.js
│   ├── selfhost/
│   │   ├── ruby2js.js        # Pre-transpiled converter
│   │   ├── filters/          # Pre-transpiled filters
│   │   └── lib/              # Supporting modules
│   ├── erb_runtime.mjs
│   └── build.mjs             # Pre-transpiled build script
├── dev-server.mjs
├── server.mjs
├── index.html
├── package.json
└── README.md
```

### 2.3 Restructure demo directory to match
- [ ] Create `vendor/ruby2js/` directory structure
- [ ] Move `lib/adapters/` → `vendor/ruby2js/adapters/`
- [ ] Move `lib/targets/` → `vendor/ruby2js/targets/`
- [ ] Move `lib/erb_runtime.mjs` → `vendor/ruby2js/erb_runtime.mjs`
- [ ] Update `scripts/build.rb` paths to reference vendor/
- [ ] Update `dev-server.mjs` paths
- [ ] Update `server.mjs` paths
- [ ] Remove empty `lib/` directory
- [ ] Keep `scripts/` for development (build.rb source)

### 2.4 Create bin/ directory for Rails familiarity

**bin/dev** (shell script)
```bash
#!/usr/bin/env bash
npm run dev "$@"
```

**bin/rails** (shell script)
Supports the following subcommands:

`bin/rails server` with options:
- `-p, --port PORT` - Use specified port (default: 3000)
- `-b, --binding HOST` - Bind to HOST (default: localhost)
- `-e, --environment ENV` - Use ENV (development/production)
- `--runtime RUNTIME` - Use node/bun/deno runtime (default: browser)

`bin/rails build` - One-shot build for static deployment (browser target)

Other `bin/rails` subcommands should print a helpful message explaining this is Ruby2JS-on-Rails, not full Rails.

### 2.5 Update build script paths
The build script needs to know where to find:
- Adapters: `vendor/ruby2js/adapters/`
- Targets: `vendor/ruby2js/targets/`
- Selfhost transpiler: `vendor/ruby2js/selfhost/`
- ERB runtime: `vendor/ruby2js/erb_runtime.mjs`

## Phase 3: Create publish script

### 3.1 Script location
Create `demo/selfhost/scripts/publish_demo.rb`

The script is Ruby since there's only one implementation (no selfhosting needed) and it can leverage existing Ruby tooling.

### 3.2 Script responsibilities

1. **Create output directory**
   ```
   dist/ruby2js-on-rails/
   ```

2. **Copy user app (Ruby source)**
   - `app/` - controllers, helpers, models, views
   - `config/` - database.yml, routes.rb, ruby2js.yml, schema.rb
   - `db/` - seeds.rb

3. **Assemble vendor/ruby2js/ (pre-transpiled)**
   - Copy adapters from demo
   - Copy targets from demo
   - Copy erb_runtime.mjs from demo
   - Copy selfhost transpiler from `demo/selfhost/`:
     - `ruby2js.js`
     - `filters/*.js`
     - `lib/*.js`
   - Transpile and copy `build.mjs` from `scripts/build.rb`

4. **Copy runtime files**
   - `dev-server.mjs`
   - `server.mjs`
   - `index.html`
   - `README.md`

5. **Create bin/ directory**
   - `bin/dev` - shell script wrapping npm run dev
   - `bin/rails` - shell script supporting `rails server` options
   - Make both executable (chmod +x)

6. **Generate package.json**
   - Name: `ruby2js-on-rails`
   - Scripts (runtime only):
     - `dev` - start dev server with HMR
     - `build` - one-shot build
     - `start` - serve built output
     - `dev:node`, `dev:bun`, `dev:deno` - server targets
   - Dependencies:
     - `@aspect-build/prism-wasm` - parser
     - `dexie` - IndexedDB adapter
     - `sql.js` - SQLite WASM (optional)
     - `js-yaml` - YAML config parsing
     - `chokidar` - file watching
     - `ws` - WebSocket for HMR
   - Optional dependencies:
     - `better-sqlite3` - Node SQLite
     - `pg` - PostgreSQL
   - Remove:
     - Any `build:ruby` or Ruby-dependent scripts
     - Dev dependencies not needed for runtime

7. **Create tarball**
   - Output: `dist/ruby2js-on-rails.tar.gz`
   - Contents rooted at `ruby2js-on-rails/`

### 3.3 Add to selfhost Rakefile
- [ ] Add `publish_demo` task that runs the script
- [ ] Ensure selfhost is built first (dependency)

## Phase 4: Update dev-server.mjs and server.mjs

### 4.1 Path updates
Both files need to reference vendor paths:
- [ ] Selfhost transpiler: `./vendor/ruby2js/selfhost/ruby2js.js`
- [ ] Build script: `./vendor/ruby2js/build.mjs`

### 4.2 Ensure prism.wasm is found
The selfhost transpiler loads prism.wasm at runtime. It must:
- Reference `node_modules/@aspect-build/prism-wasm/prism.wasm`
- NOT be bundled in the tarball (comes via npm install)
- Be listed as a dependency in package.json

## Phase 5: Testing

### 5.1 Automated smoke test
Create a smoke test script that verifies the published tarball works:

```bash
# Run as part of CI or manually before deploy
bundle exec rake publish_demo:smoke
```

The smoke test must:
- [ ] Extract tarball to temp directory
- [ ] Run `npm install`
- [ ] Run `npm run build`
- [ ] Verify dist/ contains expected output files
- [ ] Clean up temp directory

### 5.2 Manual testing (before first deploy)
- [ ] Run `npm run dev` - verify browser demo works
- [ ] Edit a Ruby file - verify HMR works
- [ ] Run `npm run dev:node` - verify server demo works

### 5.3 Verify no Ruby required
- [ ] Ensure package.json has no Ruby-dependent scripts
- [ ] Ensure README doesn't reference Ruby commands

## Phase 6: Deploy

### 6.1 Upload tarball
- [ ] Deploy to https://www.ruby2js.com/demo/ruby2js-on-rails.tar.gz

### 6.2 Update blog post Quick Start
- [ ] Update URL in `~/git/intertwingly/src/3393.md`

## Constraints

### Development workflow must be preserved
After this plan is executed, developers must still be able to:
```bash
git clone https://github.com/ruby2js/ruby2js.git
cd ruby2js/demo/ruby2js-on-rails
npm install
npm run dev
```

This means:
- The demo directory structure must work both in-repo and as a standalone tarball
- In-repo: references `../selfhost/` for the transpiler
- Tarball: includes `vendor/ruby2js/` with pre-transpiled framework
- The publish script creates the vendor structure; the repo uses symlinks or path resolution that works in both contexts

## Dependencies

- Selfhost build must be complete and working
- All filters used by the demo must be transpiled
- Smoke tests should pass before publishing
