# Ballroom Testing & Development Plan

## Context

The ballroom app (`test/ballroom`, pushed to `github.com:rubys/ballroom`) is a dance competition management system rebuilt from the original showcase app (`~/git/showcase`) using current Rails idioms. The goal is a single Ruby codebase deployable as both a Rails app and a JavaScript app via Juntos.

## Current State (March 2026)

### What exists

- **35 models** — Event, Person, Studio, Dance enriched with scopes, validations, associations; Locale (non-AR service class with Intl.DateTimeFormat dual-runtime support)
- **29 controllers** — 27 standard CRUD scaffolds; EventsController has enriched `root` action, StudiosController has `unpair`
- **217 Juntos tests passing** (28 controller test suites + 2 system tests + 3 model tests)
- **Ejected directory** — 348 JS files covering all models, controllers, views, tests, config
- **Application helpers** — `localized_date` in `ApplicationHelper`, imported automatically by ERB filter via `@helpers/` virtual prefix
- **Showcase route aliases** — `/event/summary`, `/event/publish`, `/event/settings` mapped to plural controller actions

### What renders via `juntos render`

All standard pages render successfully:
```
/            /studios      /studios/1    /studios/1/edit  /studios/new
/people      /people/1     /people/new   /heats           /dances
/dances/1    /dances/new   /categories   /categories/1    /events/1
/events/1/edit  /levels    /ages         /judges
```

5 collection action pages not yet implemented:
`/events/summary`, `/events/publish`, `/events/settings`, `/people/students`, `/people/backs`

### Test data

544 real competition SQLite databases in `~/git/showcase/db/` (318 MB total). Any can be copied to `storage/development.sqlite3` for testing with diverse data.

## Juntos CLI Reference

All commands run from `test/ballroom/`.

### Core Commands

| Command | Description |
|---------|-------------|
| `npx juntos dev` | Start development server with hot reload |
| `npx juntos build` | Build for deployment |
| `npx juntos test` | Run tests with Vitest |
| `npx juntos e2e` | Run end-to-end tests with Playwright (`--headed`, `--ui`) |
| `npx juntos server` | Start production server (requires prior build) |
| `npx juntos up` | Build and run locally (node, bun, browser) |
| `npx juntos deploy` | Build and deploy to serverless platform |

### Debugging & Inspection Commands

#### `juntos render` — Render pages without a server

Renders pages via Vite SSR, producing the same HTML the browser would see.

```bash
npx juntos render --html /                    # Output full HTML for root page
npx juntos render --html /studios /people     # Render multiple pages
npx juntos render --check / /studios /people  # Exit 0 if all succeed, 1 if any fail
npx juntos render --search "Galaxy" /studios  # Grep rendered output
npx juntos render -v /studios                 # Verbose (show timing, errors)
```

Global options work here too: `-d sqlite`, `-t node`, `-e development`.

#### `juntos transform` — Show transpiled JavaScript

Shows the JavaScript output for any Ruby source file. Essential for debugging transpilation.

```bash
npx juntos transform app/models/studio.rb              # Model → JS class
npx juntos transform app/views/studios/_form.html.erb   # ERB → JS render function
npx juntos transform app/controllers/studios_controller.rb  # Controller → JS
npx juntos transform app/helpers/application_helper.rb  # Helper → JS module

# Show intermediate Ruby (ERB → Ruby before JS transpilation)
npx juntos transform --intermediate app/views/studios/edit.html.erb

# Use Playwright filter for test files
npx juntos transform --e2e test/system/studios_test.rb
```

#### `juntos eject` — Write all transpiled JS to disk

Writes the complete JS application to `ejected/` (or custom dir). Useful for inspecting the full output, running without Vite, or debugging import resolution.

```bash
npx juntos eject                                # Full eject to ejected/
npx juntos eject --out /tmp/ballroom-js         # Custom output dir
npx juntos eject --include "app/models/*"       # Only models
npx juntos eject --exclude "test/*"             # Skip tests
DEBUG=1 npx juntos eject                        # Stack traces + JS syntax checking
```

The ejected directory is a standalone JS app with its own `package.json`, `vite.config.js`, and `vitest.config.js`.

#### `juntos info` — Show current configuration

```bash
npx juntos info                    # Environment, database, project info
npx juntos info --metadata         # Full pre-analyzed metadata as JSON
npx juntos info --metadata | jq .helpers    # Inspect helper metadata
npx juntos info --metadata | jq .models     # Inspect model metadata
npx juntos info --metadata | jq .routes     # Inspect route metadata
```

#### `juntos lint` — Static analysis for transpilation issues

```bash
npx juntos lint                    # Scan all Ruby files
npx juntos lint --strict           # Stricter rules
npx juntos lint --summary          # Untyped variable summary
npx juntos lint --suggest          # Auto-generate type hints
npx juntos lint app/models/        # Scan specific directory
```

Checks for: `ambiguous_method`, `method_missing`, `eval_call`, `retry_statement`, and 7 other rule types.

#### `juntos doctor` — Check environment and prerequisites

```bash
npx juntos doctor                  # Verify Ruby, Node, gems, npm packages
```

#### `juntos db` — Database management

```bash
npx juntos db create     # Create database
npx juntos db migrate    # Run migrations
npx juntos db seed       # Seed data
npx juntos db prepare    # Create + migrate + seed
npx juntos db drop       # Drop database
npx juntos db reset      # Drop + prepare
```

## Ruby-Side Debugging Tools

These are in the main `ruby2js` repo (run from repo root):

```bash
# Basic transpilation
bin/ruby2js -e 'self.foo ||= 1'

# Show AST before/after filters
bin/ruby2js --ast -e 'self.foo ||= 1'
bin/ruby2js --filtered-ast -e 'self.foo ||= 1'

# Apply specific filters
bin/ruby2js --filter functions --filter esm -e 'puts "hello"'
bin/ruby2js --filter rails -e 'Location.pick(:locale)'

# Compare Ruby vs JS transpiler output side-by-side
bin/compare -e 'foo rescue nil'
bin/compare --filter rails --es2022 demo/blog/app/models/comment.rb
bin/compare --diff -e 'x ||= 1'
```

## Comparison & Testing Harnesses

All scripts run from `test/ballroom/`.

### 1. Rails render script

Renders ballroom pages via Rails without starting a server.

```bash
ruby scripts/render.rb / /studios /people       # Status + size for each path
ruby scripts/render.rb --html /studios          # Output full HTML
ruby scripts/render.rb --test /studios          # Use test fixtures instead of dev DB
ruby scripts/render.rb --search "Studios" /     # Grep rendered output
ruby scripts/render.rb --check / /studios       # Exit 0/1 for CI
ruby scripts/render.rb --verbose /studios       # Timing and debug info
```

### 2. Transpiler comparison harness — DONE

`scripts/compare.rb` renders each path via both Rails and Juntos, normalizes HTML (strips CSRF tokens, asset fingerprints, importmaps, whitespace), and reports MATCH/DIFFER.

```bash
ruby scripts/compare.rb / /studios /people /heats /dances
ruby scripts/compare.rb --diff /studios         # Show unified diff
ruby scripts/compare.rb --test /studios         # Use test fixtures
ruby scripts/compare.rb --verbose /studios      # Extra detail
```

**What it normalizes:**
- CSRF meta tags and tokens
- Asset fingerprint hashes in URLs
- Importmap script blocks
- Self-closing slash differences (`<br>` vs `<br/>`)
- Trailing whitespace and blank lines

### 3. Showcase comparison harness — DONE

`scripts/compare-showcase.rb` compares the original showcase Rails app against ballroom's Juntos output, using the same database.

```bash
# Use a showcase database (name, relative, or absolute path)
ruby scripts/compare-showcase.rb 2025-charlotte /
ruby scripts/compare-showcase.rb 2025-charlotte / /studios /people /dances

# Show unified diff instead of summary
ruby scripts/compare-showcase.rb 2025-charlotte --diff /

# Verbose output
ruby scripts/compare-showcase.rb 2025-charlotte --verbose / /studios
```

**How it works:**
1. Resolves the database path (checks `~/git/showcase/db/`, relative, absolute)
2. Copies to ballroom's `storage/development.sqlite3`
3. Renders via showcase's render script and ballroom's Juntos render
4. Extracts `<main>` content for comparison (ignores layout/head)
5. Handles route mapping (`/event/*` ↔ `/events/*`)
6. Reports diffs or MATCH/DIFFER per page

### Typical verification workflow

```bash
cd ~/git/ruby2js

# 1. Run Ruby tests
bundle exec rake test

# 2. Rebuild and install tarballs
bundle exec rake -f demo/selfhost/Rakefile release
cd test/ballroom
rm -rf node_modules/juntos node_modules/juntos-dev
npm install ../../artifacts/tarballs/juntos-beta.tgz ../../artifacts/tarballs/juntos-dev-beta.tgz

# 3. Run Juntos tests
npx juntos test

# 4. Re-eject and inspect
npx juntos eject
cat ejected/app/helpers/application_helper.js

# 5. Render and compare
npx juntos render --html /
ruby scripts/compare.rb / /studios /people /dances
ruby scripts/compare-showcase.rb 2025-charlotte --diff /
```

## Three Testing Dimensions

### 1. Behavior (system tests)

System tests exercise user flows end-to-end: visit page, click link, fill form, assert result. They run under both Rails (`bin/rails test test/system`) and Juntos (`npx juntos test`). Differences reveal transpiler/runtime bugs.

**Current:** 217/217 Juntos tests passing (28 controller + 3 model + 2 system test suites).

### 2. Transpiler fidelity (ballroom Rails vs ballroom Juntos)

Both render the same ballroom app from the same database. The `scripts/compare.rb` harness normalizes and diffs the HTML, catching transpiler bugs: missing CSS classes, wrong links, absent associations, layout differences.

### 3. Showcase parity (showcase Rails vs ballroom Juntos)

Comparing showcase's Rails output against ballroom's Juntos output for the same routes and database. The `scripts/compare-showcase.rb` harness drives Phase 3 work (enriching beyond scaffolds).

**Route differences handled automatically:**
| Showcase route | Ballroom route | Notes |
|---------------|---------------|-------|
| `/event/settings` | `/events/settings` | Singular vs plural; alias routes defined |
| `/event/summary` | `/events/summary` | |
| `/event/publish` | `/events/publish` | |

## Development Sequence

Work is driven by **what the root page links to**, fixing issues as encountered. Each step produces:
- Working Rails implementation
- Passing Juntos tests
- Clean transpiler comparison (no ballroom Rails vs Juntos drift)
- Reduced showcase comparison diff (ballroom converging on showcase output)

### Phase 1: Establish baselines — DONE

1. ~~Fix Juntos test failures~~ — **DONE** (vitest.config.js fix, 217/217 passing)
2. ~~Write Rails render script~~ — **DONE** (`scripts/render.rb`)
3. ~~Build transpiler comparison harness~~ — **DONE** (`scripts/compare.rb`)
4. ~~Run transpiler comparison on all working pages~~ — **DONE** (iteratively refined)
5. ~~Build showcase comparison harness~~ — **DONE** (`scripts/compare-showcase.rb`)
6. ~~Run showcase comparison on root page~~ — **DONE** (root page rebuilt to match)

### Phase 2: Implement missing collection actions

Each follows the same pattern: study the showcase implementation, implement action + view in ballroom, verify Juntos, compare both ways.

| Priority | Route | Showcase controller | Notes |
|----------|-------|-------------------|-------|
| 1 | `/events/settings` | `event#settings` | Event config form |
| 2 | `/people/students` | `people#students` | Filtered people list |
| 3 | `/people/backs` | `people#backs` | Back number assignment |
| 4 | `/events/summary` | `event#summary` | Competition summary |
| 5 | `/events/publish` | `event#publish` | Publish controls |

### Phase 3: Enrich beyond scaffolds — IN PROGRESS

Replace scaffold views with showcase-matching views, driven by showcase comparison diffs. Test each change against multiple databases. Work page by page, starting from the root.

| Area | Status | Key changes |
|------|--------|-------------|
| **Root (/)** | **DONE** | Dashboard with event info, localized date, judge/DJ/emcee lists, 3x3 nav grid, info box, conditional backs link |
| **Studios index** | **DONE** | Table with location/count columns, totals row, info box, back-to-event link |
| **Studios show/edit** | Partial | Pair management UI exists (`unpair` action) |
| **People** | Not started | Role-based views, display_name formatting |
| **Dances** | Not started | Category grouping, drag-drop reorder |
| **Heats** | Not started | Entry display, scheduling, multi-dance |
| **Categories** | Not started | Ordered list, lock toggle, extensions |
| **Entries** | Not started | Lead/follow/instructor associations |
| **Scores** | Not started | Scoring forms, judge assignment |

### Phase 4: Advanced features

- **Concerns:** HeatScheduler, DanceLimitCalculator, Printable
- **STI models:** Billable subtypes, Package/Option/PackageInclude
- **Active Storage:** Solo recordings, formations
- **Authentication:** User model, session management

## Key Infrastructure Built

### Application helper pipeline

The ERB filter detects calls to app helper methods (e.g., `localized_date`) via metadata and generates `@helpers/` virtual imports. The Vite plugin resolves these to `app/helpers/*.rb`, transpiles, and adds cross-model imports. The eject pipeline writes helpers to `ejected/app/helpers/` with `postProcessTestHelper()` converting module objects to named exports.

Key files:
- `lib/ruby2js/filter/rails/helpers.rb` — ERB detection + import generation
- `packages/juntos-dev/transform.mjs` — `extractHelperMethods()`, `buildAppManifest()` helper scanning
- `packages/juntos-dev/vite.mjs` — `@helpers/` resolution, `addCrossModelImports()` for helpers
- `packages/juntos-dev/cli.mjs` — eject helper file writing with cross-model imports

### Locale model with dual-runtime date formatting

`app/models/locale.rb` — 445-line non-AR service class supporting 13 locales. Uses `defined?(Intl)` guards:
- **JS runtime:** Native `Intl.DateTimeFormat` for date/range formatting
- **Ruby runtime:** Manual locale-specific formatting (month names, ordinals, separators)

The `defined?(Intl)` pattern transpiles to `typeof Intl !== 'undefined'`, enabling clean runtime detection without changing callers.

### Adapter `pick()` method

`Model.pick(:column)` returns a single value (like `pluck` limited to 1 result). Static wrappers added to SQL, Dexie, and Supabase adapters. Instance method on `Relation`.

## Already Resolved

Issues discovered and fixed while building ballroom:

- **Inflector integration** — filters use `Inflector.underscore`, `classify`, `pluralize`
- **`classify()` helper** — added to transform.mjs/vite.mjs
- **Empty test suites** — cli.mjs skips generating .test.mjs for model tests with no test() calls
- **`alias_attribute`** — model filter generates getter/setter pairs
- **Test output noise** — CRUD logging uses `console.info`/`console.debug`, suppressed in test
- **Compound controller names** — AgeCosts, CatExtensions, PersonOptions generate correct view imports
- **Pluralization in helpers** — `form_with(model:)` uses `Inflector.pluralize` for path helpers
- **`polymorphic_path` for local variables** — `link_to text, lvar` uses `polymorphic_path()`
- **`juntos render` command** — renders pages via Vite SSR without starting a server
- **Vite plugin log suppression** — `[juntos]` messages silenced when `logLevel: 'silent'`
- **Vitest config** — ballroom needs `environment: 'jsdom'`, `pool: 'forks'`, `singleFork: true`
- **STI disabled** — `self.inheritance_column = nil` for models with `type` column
- **`pick` not awaited** — added to `AR_CLASS_METHODS` in `active_record.rb`
- **`pick()` static wrapper missing** — added to SQL, Dexie, Supabase adapters
- **`ArgumentError` mapping** — mapped to `TypeError` in functions filter
- **Implicit returns in begin/rescue/end** — autoreturn handler in `return.rb` now handles `:rescue` and `:ensure` wrapping `:rescue`
- **Helper cross-model imports** — `addCrossModelImports()` extended for `app/helpers/` files
- **Helper method extraction ordering** — `extractHelperMethods()` must run before `addCrossModelImports()` (prepended imports break `^` anchored regex)
- **Form cosmetic diffs** — newlines, value attributes, HTML escaping, select options
- **belongs_to await** — async association getters, `action_name`, query params
- **Falsy id=0** — `extract_id` path helper fix for falsy-but-valid IDs
- **Heat number getter** — strips `.0` from whole-number floats
