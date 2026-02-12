# Fizzy Benchmark: Transpiling a Production Rails Application

Validate that idiomatic Rails applications can be transpiled to JavaScript and run on non-Ruby platforms using Ruby2JS/Juntos.

---

## Goal

Fizzy serves as an ideal benchmark because:

1. **Created by 37signals** - The company that created Rails
2. **Production application** - Real-world complexity, not a toy example
3. **Idiomatic Rails 8** - Uses standard patterns (Hotwire, concerns, RESTful controllers)
4. **No exotic dependencies** - Standard gems, no custom DSLs

## Thesis

> The more idiomatic your Rails application is, the greater likelihood that Juntos will be able to handle it properly.

Fizzy tests this thesis at scale. The [blog demo](https://ruby2js.github.io/ruby2js/blog/) already proves the concept for a simple Rails app (articles + comments with Turbo Streams, running entirely on GitHub Pages). Fizzy validates it for production complexity: 41 models, 65 controllers, 60 Stimulus controllers, 24-module concern composition, polymorphic associations, CurrentAttributes. The ejected test suite has 829 tests across 188 files.

## Application Overview

| Metric | Count |
|--------|-------|
| Models | ~41 |
| Controllers | ~65 (17 top-level + ~50 nested) |
| Stimulus Controllers | ~60 |
| Database | SQLite (UUID primary keys) |
| Frontend | Hotwire (Turbo + Stimulus) |
| Rails Version | 8.2 (main branch) |

### Key Patterns

- **Concern-based composition** - Card model includes 24 modules
- **Polymorphic associations** - eventable, reactable, source
- **Turbo Stream broadcasting** - Real-time updates
- **Nested controllers** - `Cards::CommentsController`, etc.
- **Strong parameters** - `.expect()` syntax (Rails 7.1+)
- **CurrentAttributes** - Request context (`Current.user`, `Current.account`)

---

## Dependency Landscape

Porting a Rails application to JavaScript is more than porting the application itself — every gem dependency needs a JavaScript equivalent. Fizzy's Gemfile has 45 entries (32 production + 13 dev/test). They fall into five categories, each with a different strategy.

### Already JavaScript

These gems wrap JavaScript libraries. The ejected app uses the JS originals directly.

| Gem | JS Original | Notes |
|-----|-------------|-------|
| `stimulus-rails` | `@hotwired/stimulus` | Rails gem wraps the JS package |
| `turbo-rails` | `@hotwired/turbo` | Rails gem wraps the JS package |
| `importmap-rails` | ESM `import` | Native browser/Node module resolution |
| `lexxy` | `lexical` (Meta) | Rich text editor; built on Lexical, [standalone JS package planned](https://github.com/basecamp/lexxy) |

### Direct npm Equivalents

Ruby gems with well-known JavaScript counterparts. Drop-in replacement at the API boundary.

| Gem | npm Equivalent | Fizzy Usage |
|-----|---------------|-------------|
| `bcrypt` | `bcryptjs` | Password hashing (`has_secure_password`) |
| `rqrcode` | `qrcode` | QR code generation for 2FA |
| `redcarpet` | `marked` or `markdown-it` | Markdown → HTML (via ActionText) |
| `rouge` | `highlight.js` or `shiki` | Code syntax highlighting (via ActionText) |
| `web-push` | `web-push` | Browser push notifications (same API name) |
| `image_processing` | `sharp` | Image variants (resize, crop) |
| `aws-sdk-s3` | `@aws-sdk/client-s3` | S3 file storage (AWS publishes both) |
| `zip_kit` | `fflate` or `archiver` | Streaming ZIP exports (3 classes: Writer, Reader, RemoteIO) |
| `platform_agent` / `useragent` | `ua-parser-js` | Browser/device detection (`ApplicationPlatform` model) |
| `mittens` | `stemmer` or `natural` | Word stemming for search index |
| `geared_pagination` | Custom | Keyset pagination (pattern, not library — ~20 lines) |
| `jbuilder` | Native JSON | 28 `.json.jbuilder` templates → plain object serialization |
| `net-http-persistent` | `fetch` / `undici` | HTTP keep-alive for push notification delivery |

### Rails Framework (ruby2js-rails adapters)

Core Rails infrastructure. These need purpose-built adapters in the `ruby2js-rails` package.

| Gem / Component | Adapter Approach | Status |
|----------------|-----------------|--------|
| `sqlite3` | `node:sqlite` / `bun:sqlite` | Done — built-in, no native dependency |
| ActiveRecord | ORM with SQLite adapter | Done — query builder, migrations, associations |
| ActiveSupport::Concern | AST filter | Done — transpile-time transformation |
| ActionController | Express/Hono-style routing | Partial — RESTful CRUD transpiles, needs HTTP adapter |
| CurrentAttributes | `AsyncLocalStorage` | Partial — `$with()` escape done, needs request lifecycle |
| ActionMailer | `nodemailer` | Not started — `deliver_later` → async delivery |
| ActionText | Lexical + storage adapter | Not started — `has_rich_text` stub done, needs rendering |
| ActiveStorage | S3 direct / local filesystem | Not started — file upload, image variant pipeline |
| ActionCable / `solid_cable` | WebSocket server | Not started — Turbo Stream broadcasting |
| `solid_cache` | In-memory `Map` or Redis | Not started — `json.cache!` blocks in jbuilder views |
| `solid_queue` | Event loop / `queueMicrotask` | Not started — Fizzy's jobs are simple method calls |

### Deployment / Operations (not needed in ejected app)

These gems handle Ruby-specific deployment, optimization, or monitoring. The ejected JavaScript app uses its own stack (Node/Bun process, reverse proxy, etc.).

`bootsnap` · `kamal` · `puma` · `thruster` · `propshaft` · `trilogy` · `autotuner` · `mission_control-jobs` · `benchmark`

### Dev / Test (framework equivalents)

| Ruby Gem | JS Equivalent | Notes |
|----------|--------------|-------|
| `minitest` / `mocha` | Lightweight Node runner | vitest-compatible globals, per-file process isolation |
| `capybara` / `selenium-webdriver` | Playwright | Browser integration tests |
| `webmock` / `vcr` | `msw` (Mock Service Worker) | HTTP request mocking/recording |
| `faker` | `@faker-js/faker` | Test data generation |
| `debug` | Node inspector | `--inspect` flag |
| `brakeman` / `bundler-audit` | `npm audit` / ESLint security plugins | Static analysis |

### Key Insight

Of Fizzy's 45 gem dependencies:
- **4** are already JavaScript — the gem just wraps a JS package (Hotwire, Lexical)
- **14** have direct npm equivalents — swap at the API boundary
- **9** are deployment/operations — not needed in the ejected app
- **13** are dev/test tools — vitest + Playwright replaces the Ruby test stack
- **5** are Rails framework gems — these need purpose-built adapters

The `rails` gem alone provides 7 sub-frameworks used by Fizzy (ActiveRecord, ActionController, CurrentAttributes, ActionMailer, ActionText, ActiveStorage, ActionCable). Combined with `sqlite3`, `solid_cable`, `solid_cache`, and `solid_queue`, that's 11 distinct adapter concerns — the core of the remaining work. Several (SQLite, ActiveRecord ORM, Concerns) are already done.

---

## What's Been Accomplished

**Transpilation is complete with zero syntax errors.** All file categories transform successfully:

- **995 JavaScript files pass syntax check** (models, controllers, views, routes, migrations, seeds, tests, Stimulus controllers, concerns)
- **1 file skipped** - `magic_link/code.rb` (`class << self` in non-class context)
- **188 test files** in the ejected output (511 individual test cases discovered by runner)

### Concern-Aware Filter (New)

ActiveSupport::Concern modules are now handled at the AST level by a dedicated Rails filter (`lib/ruby2js/filter/rails/concern.rb`), replacing the previous runtime stub approach. The filter:

- **Strips** DSL calls: `extend ActiveSupport::Concern`, `included do...end`, `class_methods do...end`, `delegate`, `include`
- **Transforms** `attr_accessor`/`reader`/`writer` into def pairs that the module converter's existing getter/setter detection produces correct `get`/`set` accessors from
- **Transforms** `alias_method` into delegating defs (strips when names differ only by `?`/`!`)
- **Forces the IIFE path** to ensure underscore-prefix ivars (`this._x`) instead of ES2022 private fields (`this.#x`) which are invalid in object literal context

This fixed several ejected output bugs: `prototype is not defined` in concern modules, `#field` syntax errors in object literals, and circular reference errors from namespace assignments.

### Enum Transpilation (New)

Rails `enum` declarations are now fully transpiled by the model filter:

- **Frozen values constant** — `Export.statuses = Object.freeze({drafted: "drafted", ...})`
- **Instance predicate methods** — `get drafted() { return this.status === "drafted" }`
- **Static scope methods** — `static drafted() { return this.where({status: "drafted"}) }`
- **Inline transforms** — `record.drafted?` → `record.drafted`, `record.published!` → `record.update({status: "published"})`
- **Options** — `prefix:`, `scopes: false`, explicit hash overrides

### URL Helpers (New)

`include Rails.application.routes.url_helpers` is now recognized in both model and non-model classes:

- **Strips the include** — Prevents the crashing `Object.defineProperties(... url_helpers)` pattern
- **Generates import** — `import { polymorphic_url, polymorphic_path } from "ruby2js-rails/url_helpers.mjs"`
- **Runtime module** — `polymorphic_url(record)` resolves model instances to URL paths via `constructor.tableName` + `id`

### Other Fixes This Round

- **Module converter IIFE getter return** — Getter bodies in the IIFE path were missing `return` statements; fixed by adding `autoreturn` wrapping
- **ESM autoexport for namespaced classes** — `Account::Export < Export` now unnests correctly with TDZ avoidance (`_Export` internal name + `export { _Export as Export }`)
- **Classify inflector** — New `classify` method for proper PascalCase (`access_tokens` → `AccessToken` not `Access_token`)
- **Polymorphic/through association imports** — Skip import generation for polymorphic and `:through` associations that don't map to single model classes
- **Nested model import resolution** — Flat imports in model files resolve to nested paths using the actual models list
- **Vitest config isolation** — Absolute paths prevent parent project vitest config from leaking into ejected test runner

Dozens of earlier transpilation bugs were also fixed (ERB comments, nested params, hash shorthand, async render, duplicate imports, private field handling, nested class imports, reserved word escaping, bare case/raise, etc.). These fixes benefit all Ruby2JS users, not just Fizzy.

---

## Strategy: Full Application, Prioritized by Impact

The initial approach scoped Fizzy to a cards-in-columns core (~34 tests). That core is now substantially working (50 tests passing including non-core tests). The strategy has shifted to **full application testing** — all 829 tests run, prioritized by root cause impact.

The three highest-impact root causes account for the majority of failures:
1. Missing route path exports in `config/paths.js` — 70+ controller test files can't even load (96 errored files total)
2. Missing adapter methods — `update_column`, `valid?`, `delete_all`, `find_or_create_by`, etc. (~54 tests)
3. Test helper functions — `sign_in_as`, `untenanted`, fixture shorthands (~43 tests)

Fixing route path exports alone would unblock ~70 controller test files and expose the actual test-level failures in those files.

---

## Current Status (Updated 2026-02-11)

### Overall: 47/511 tests passing, 5/188 test files fully passing

| Category | Files | Tests | Notes |
|----------|-------|-------|-------|
| **Fully passing** | 5 | 47 | All tests in file pass |
| **Partially failing** | 87 | 464 fail | At least one test registered; some fail |
| **Errored** | 96 | — | File can't load (describe body throws, missing exports) |

### Passing Files

| Test File | Tests |
|-----------|-------|
| **card/pinnable** | 4/4 |
| **column** | 2/2 |
| **board/cards** | 1/1 |
| **card/messages** | 1/1 |
| **user/configurable** | 1/1 |

Plus 38 additional passing tests spread across 87 partially-failing files.

### Root Causes by Impact

| # | Root Cause | Failures | % | Fix Complexity |
|---|-----------|----------|---|----------------|
| 1 | **Missing route path exports** | ~70 files errored | 37% of files | Medium — `config/paths.js` needs route helper generation |
| 2 | **`sign_in_as` not defined** | ~22 tests (in files that load) | ~5% | Medium — test helper + HTTP dispatch layer |
| 3 | **Missing adapter methods** | ~54 | 11% | Medium — `update_column`, `valid?`, `delete_all`, `destroy_all`, `find_or_create_by`, `with_lock`, `maximum`, `left_outer_joins`, `exists?` |
| 4 | **Test helper variables/functions** | ~43 | 8% | Low-Medium — `untenanted`, fixture table shorthands, `assert_emails`, `SecureRandom` |
| 5 | **Schema/migration gaps** | ~34 | 7% | Low — missing columns (`body`, `signing_secret`, `description`, `blob_id`), NOT NULL constraints |
| 6 | **Undefined property access** | ~30 | 6% | Varies — null associations, async/await gaps |
| 7 | **ActiveStorage not implemented** | 24 | 5% | High — `has_one_attached`/`has_many_attached` + `.attach` |
| 8 | **Getter-vs-method gap** | ~29 | 6% | Medium — Ruby `obj.method` → JS `obj.method` (property) instead of `obj.method()` |
| 9 | **Null query results** | ~13 | 3% | Varies — queries returning null unexpectedly |
| 10 | **Settings accessors** | 12 | 2% | Low — `store_accessor`/`settings` concern methods |
| 11 | **`validates_uniqueness_of`** | 9 | 2% | Medium — needs DB-backed uniqueness check |
| 12 | **`attribute_present?`** | 9 | 2% | Low — simple method on ActiveRecord |
| 13 | **Expected errors not thrown** | 8 | 2% | Medium — validation implementations |
| 14 | **Other** (assertion mismatches, transpilation bugs) | ~40 | 8% | Varies |

### What's Been Done (completed priorities from previous plan)

- [x] **Time helpers** — `freeze_time`, `travel_to`, Duration, `.ago`, `.from_now`, `Time.current` all implemented
- [x] **Test parse errors** — setter `await`, `::` namespace in `assert_difference` fixed
- [x] **Concern method inheritance** — `track_event`, enum bang inlining, `Object.defineProperty` mixing
- [x] **belongs_to `default:`** — `_resolveDefaults()` generation + adapter call
- [x] **Scope-to-scope chaining** — zero-arg getter scopes rewritten as property access
- [x] **Dirty tracking** — `_changes` dict, `<attr>_changed` methods
- [x] **Enum defaults** — `_enumDefaults` static property, applied in constructor
- [x] **Enum predicate getters** — `defget` for `drafted?`/`published?` etc.
- [x] **Imports/fixtures/ivar-hoisting** — all moved from text post-processing to AST-level
- [x] **Lightweight test runner** — Node-native vitest-compatible runner (bypasses Vite OOM)
- [x] **Deferred concern mixing** — `_mixConcerns()` pattern avoids circular dependency TDZ errors
- [x] **Accurate test counting** — errored files no longer inflate pass count

---

## What's Been Accomplished

**Transpilation is complete with zero syntax errors.** All file categories transform successfully:

- **995 JavaScript files pass syntax check** (models, controllers, views, routes, migrations, seeds, tests, Stimulus controllers, concerns)
- **1 file skipped** - `magic_link/code.rb` (`class << self` in non-class context)
- **188 test files** in the ejected output, runnable via lightweight Node-native test runner

### Recent Fixes

| Fix | Layer | Details |
|-----|-------|---------|
| belongs_to `default:` | Transpiler + Adapter | `_resolveDefaults()` method evaluates lambda defaults before callbacks |
| Dirty tracking | Adapter | `_changes` dict, `<attr>_changed` methods via `attr_accessor` |
| Enum predicate getters | Transpiler | `defget` forces getter output for `drafted?`/`published?` |
| Enum defaults | Transpiler + Adapter | `_enumDefaults` static property, applied in constructor for new records |
| Concern method inheritance | Eject tooling | `Object.defineProperty` mixing, callback merging from parent concerns |
| Enum bang inlining in concerns | Transpiler | `published!` → `this.update({status: "published"})` in concern IIFE |
| Scope-to-scope chaining | Transpiler | Zero-arg getter scopes rewritten as property access in scope bodies |
| Test parse error: setter await | Transpiler | Skip `await` on setter sends (`user.name = "foo"`) |
| Test parse error: `::` namespace | Transpiler | `Account::JoinCode` → `Account.JoinCode` in assert_difference |
| AST-level imports/fixtures | Transpiler | Moved from text post-processing to AST-level test filter |
| AST-level ivar hoisting | Transpiler | `@x` declarations hoisted to describe scope at AST level |
| AST-level Current attributes | Transpiler | `Current.account = ...` injected at AST level in beforeEach |
| AST-level redirect assertions | Transpiler | `assert_redirected_to` transformed at AST level |
| Lightweight test runner | Eject tooling | Node-native vitest-compatible runner, bypasses Vite OOM |
| Deferred concern mixing | Eject tooling | `_mixConcerns()` pattern avoids circular dependency TDZ errors |
| Transactional tests | Transpiler | `loop do ... break value` support for transaction blocks |
| SQLite db.close() | Adapter | Prevents native memory accumulation across test files |

### Earlier Fixes (Closeable Sprint)

| Fix | Layer | Details |
|-----|-------|---------|
| Transaction async/await | Transpiler | `transaction do...end` blocks transpile with async callback + awaited statements |
| UUID primary keys | Adapter | `createTable` records UUID tables; `_insert` auto-generates UUIDs only for those tables |
| `reload()` association caches | Adapter | Clears has_one caches and eagerly reloads; preserves has_many (in-memory records) |
| `HasOneReference.destroy()` | Adapter | Safe navigation `not_now&.destroy` delegates through the thenable proxy |
| `CollectionProxy.at()` | Adapter | Negative index support via `Array.prototype.at()` |
| `track_event` + StringInquirer | Adapter | Event action wrapped as StringInquirer; pushed into card's events proxy |
| `relation.where()` no-arg | Adapter | Returns clone without adding condition |
| CurrentAttributes settle() | Adapter | `_pending` array for async setter chains, `settle()` resolves them |
| Fixture polymorphic refs | Eject tooling | `parsePolymorphicRef` resolves `eventable_type`/`eventable_id` pairs |
| Fixture reload chains | Eject tooling | `.reload.property` → `(await .reload()).property` |
| `present?`/`blank?` on associations | Transpiler | `closure.present?` → `this.closure !== null` (not `.length > 0`) |
| `create_X` for has_one | Transpiler | Auto-generated `create_closure(attrs)` methods |
| Concern `self.` prefix | Transpiler | Bare method calls rewritten to `self.method` in concern bodies |
| Predicate getters in concerns | Transpiler | `closed?` → `get closed()` for `?`-suffix concern methods |
| Scope static getters | Transpiler | `scope :closed, -> {}` → `static get closed()` |
| `super` in concerns | Transpiler | `super` → `this.attributes["column"]` for raw DB value |
| Namespaced table names | Transpiler | `Card::NotNow` → `card_not_nows` (Rails convention) |
| Include chain following | Eject tooling | `include ::Eventable` follows to `app/models/concerns/` for association merging |
| Reverse has_one fixtures | Eject tooling | Closure/NotNow fixtures resolved from card dependency |

### Fixture Resolution

Rails fixture loading auto-resolves association references. Implemented matching behavior:

| Feature | Details |
|---------|---------|
| UUID v5 generation | `fixtureIdentifyUUID(label)` matches Rails' `FixtureSet.identify(label, :uuid)` using OID namespace |
| `_uuid` suffix stripping | `board: writebook_uuid` → strips `_uuid`, looks up `writebook` in `boards` fixtures |
| Association `_id` suffixing | `board: writebook_uuid` → `board_id: <resolved_uuid>` (appends `_id` for FK columns) |
| Convention-based FK inference | If `pluralize(col)` matches a fixture table, treat as FK even without explicit `belongs_to` |
| Association map via `new Function()` | Parses `static associations = {...}` from JS model files using brace-balanced extraction + evaluation |
| Transitive dependency resolution | Fixture references are followed transitively to ensure all dependent fixtures are created |
| Topological sorting | Fixtures are created in dependency order (accounts before users, users before cards) |
| Reverse has_one resolution | For has_one associations, scan fixture tables for records pointing back |
| Polymorphic resolution | `eventable_type`/`eventable_id` pairs resolved from fixture references |

### Test Runner

Vitest/Vite causes OOM at ~4GB regardless of configuration (forks, threads, vmThreads, isolation settings, 8GB heap limit). The test suite uses a **lightweight Node-native runner** that provides vitest-compatible globals (`describe`, `test`, `expect`, `beforeAll`, `beforeEach`, `afterEach`, `afterAll`) with a custom ESM loader to intercept `import from 'vitest'`. Each test file runs in its own Node process (~0.175s including DB setup + 33 migrations). Full 188-file suite completes in ~35 seconds.

Generated files in `ejected/test/`:
- `runner.mjs` — Test framework with describe/test/expect/hooks/CLI
- `register-loader.mjs` — ESM loader registration
- `vitest-loader.mjs` — Resolves 'vitest' imports to shim
- `vitest-shim.mjs` — Re-exports globals as vitest module

Key design decisions:
- **Per-file process isolation** — avoids ESM module cache accumulation (188 files × module instances = OOM in single process)
- **Deferred concern mixing** — `_mixConcerns()` static methods called after all models load, avoiding circular dependency TDZ errors
- **describe try/finally** — if describe callback throws, `_currentSuite` is properly restored (prevents silent test nesting)

### Test Infrastructure

| Feature | Details |
|---------|---------|
| Global model exposure | All exported models available as globals (Rails autoloading behavior) |
| Model namespace nesting | `Search.Highlighter`, `ZipFile.Writer`, `Storage.Entry` — nested classes attached to parent |
| `CurrentAttributes` functional | `attribute()` creates static getter/setters, `settle()` for async chains, instance methods promoted to static |
| `beforeEach` variable hoisting | `let x = ...` inside `beforeEach` → hoisted to describe scope (Rails `setup` → JS scoping fix) |
| `assert_difference` / `assert_changes` | Functional stubs with `::` → `.` conversion for Ruby namespace syntax |
| Mock/stub framework | `mock()`, `stub()`, `.stubs()`, `.expects()`, `.returns()`, `.yields()` — Mocha-compatible |
| `Object.prototype.stubs/expects` | All objects support Mocha-style mocking via prototype extension |
| Time helpers | `freeze_time`, `travel_to`, `travel_back`, Duration (`.ago`, `.from_now`), `Time.current` — fully implemented |
| Job helpers | `perform_enqueued_jobs`, `assert_enqueued_with` — pass-through stubs |
| IO/Net stubs | `StringIO`, `Tempfile`, `Net.HTTP`, `Resolv.DNS` — minimal stubs |
| Turbo helpers | `assert_turbo_stream_broadcasts` — no-op stub |

### Migration Filter Improvements

The migration filter (`lib/ruby2js/filter/rails/migration.rb`) now handles several patterns that Fizzy's migrations require:

| Pattern | Example | Status |
|---------|---------|--------|
| `CONST.each { \|var\| add_column ... }` | `MISSING_TABLES.each { \|t\| add_column t, "account_id", :uuid }` | Done |
| `add_reference` | `add_reference :users, :identity, type: :uuid` | Done |
| `polymorphic: true` | `t.references :owner, polymorphic: true` | Done |
| `rename_table` | `rename_table :account_exports, :exports` | Done |
| `t.index` inside `create_table` | `t.index [:col1, :col2], unique: true` | Done |
| `id: :uuid` on `create_table` | `create_table :entries, id: :uuid` | Done |
| `change_column` | `change_column :table, :col, :type` | Silently skipped (SQLite limitation) |
| `type:` on `t.references` | `t.references :account, type: :uuid` | Done |

### SQLite Adapter

| Fix | Details |
|-----|---------|
| `node:sqlite` in Vitest | `createRequire` from `node:module` bypasses Vite's module interception |
| `removeColumn` index cleanup | Auto-drops indexes referencing the column before `DROP COLUMN` |
| `renameTable` | `ALTER TABLE ... RENAME TO` support |
| UUID PK auto-generation | `createTable` records UUID tables; `_insert` generates `crypto.randomUUID()` only for those |
| `_update` fallback to INSERT | Handles fixtures with pre-set UUIDs that set `_persisted=true` |
| `reload()` | Clears has_one caches, preserves has_many, eagerly resolves has_one |

### Functional Validation

- [x] All 33 migrations run successfully
- [x] Fixture creation with UUID resolution
- [x] Basic CRUD operations (create, update, destroy)
- [x] belongs_to / has_one / has_many associations
- [x] Polymorphic associations (eventable)
- [x] Concern composition (6 Card concerns mixed in)
- [x] Callbacks fire (before_save, after_create)
- [x] Enum predicates and scopes
- [x] Transaction blocks with async/await
- [x] CurrentAttributes (Current.user, Current.account)
- [x] Time duration helpers (`.week.ago`, `freeze_time`, `travel_to`, `Time.current`)
- [ ] Controller tests (need `sign_in_as` helper)
- [ ] Turbo Stream responses
- [ ] Real-time updates via Action Cable

---

## Development Workflow

### One Command (Recommended)

```bash
# Full pipeline: build selfhost → eject → install deps → symlink packages → run tests
bundle exec rake -f test/Rakefile fizzy

# With custom timeout (default 300s)
bundle exec rake -f test/Rakefile fizzy[600]

# Re-run tests only (skip build/eject, reuse existing ejected/)
bundle exec rake -f test/Rakefile fizzy_test
```

The `fizzy` task handles the entire pipeline reliably:

1. **Builds selfhost** — transpiles ruby2js to JS, copies `ruby2js.js` to both packages
2. **Ejects Fizzy** — runs `cli.mjs eject -d sqlite` in the Fizzy directory
3. **Installs npm deps** — `npm install` in ejected/
4. **Symlinks dev packages** — replaces installed `ruby2js` and `ruby2js-rails` in `node_modules/` with symlinks to the local package directories
5. **Runs tests** — lightweight Node-native runner, each file in its own process (per-file timeout)

The symlink step is critical: it ensures the ejected app always uses the current dev source for adapters, runtime, and the transpiler bundle. Without it, `npm install` fetches published (stale) versions from tarballs.

Set `FIZZY_DIR` if Fizzy is not at `~/git/fizzy`:
```bash
FIZZY_DIR=/path/to/fizzy bundle exec rake -f test/Rakefile fizzy
```

### Manual Steps (for debugging)

If you need to run individual steps:

```bash
# 1. Build selfhost (after changing filters/converters/model.rb)
bundle exec rake -f demo/selfhost/Rakefile local

# 2. Eject
cd /path/to/fizzy
node /path/to/ruby2js/packages/ruby2js-rails/cli.mjs eject -d sqlite

# 3. Install deps + symlink (in ejected/)
cd ejected
npm install
rm -rf node_modules/ruby2js node_modules/ruby2js-rails
ln -s /path/to/ruby2js/packages/ruby2js node_modules/ruby2js
ln -s /path/to/ruby2js/packages/ruby2js-rails node_modules/ruby2js-rails

# 4. Run a single test file
node --import ./test/register-loader.mjs test/runner.mjs test/models/card/pinnable.test.mjs

# 4b. Run all tests via Rakefile (from ruby2js root)
bundle exec rake -f test/Rakefile fizzy_test
```

### What Triggers a Rebuild

| Change | Required Steps |
|--------|----------------|
| `lib/ruby2js/filter/**/*.rb` | Full pipeline (selfhost build → eject → test) |
| `lib/ruby2js/converter/**/*.rb` | Full pipeline |
| `packages/ruby2js-rails/adapters/*.mjs` | Just re-run tests (symlinks make changes immediate) |
| `packages/ruby2js-rails/transform.mjs` | Re-eject + test (transform.mjs generates setup/config) |
| `packages/ruby2js-rails/cli.mjs` | Re-eject + test |
| Test globals/assertions only | Just re-run tests (if globals.mjs is in transform.mjs, re-eject) |

### Database Options

Use `-d sqlite` for built-in `node:sqlite` (Node 25+) or `bun:sqlite`. Use `-d better_sqlite3` if you need the native addon. The eject command transforms all Ruby source files, writes JavaScript to `ejected/`, and reports failures.

---

## Known Considerations

### Supported (Works Today)

| Category | Patterns |
|----------|----------|
| Models | belongs_to, has_many, has_one, validations, scopes, callbacks, enums (predicates + scopes + inline transforms), normalizes, url_helpers (polymorphic_url/path), has_rich_text, store, after_touch |
| Controllers | RESTful CRUD, before_action, respond_to, strong params (.expect syntax) |
| Views | ERB, partials, form helpers, Turbo Streams |
| JavaScript | Stimulus controllers, Turbo, @rails/request.js |
| Concerns | extend ActiveSupport::Concern, included, class_methods, attr_accessor, alias_method, delegate — all handled at AST level |
| Structure | Nested controllers, namespaced models, Struct.new + class reopening |

### Needs Runtime Implementation

| Item | Notes |
|------|-------|
| CurrentAttributes | AsyncLocalStorage adapter exists conceptually; needs request lifecycle integration |
| ActionMailer | nodemailer adapter |
| Polymorphic associations | ORM query enhancement |
| ActionText | Rich text storage and rendering |

### Infrastructure (Outside App Scope)

| Item | Notes |
|------|-------|
| Rate limiting | Cloudflare, nginx |
| File uploads | ActiveStorage adapter or direct S3 |
| Search | SQLite FTS or external service |

### Explicitly Not Supported

| Item | Reason |
|------|--------|
| C extension gems | Requires Ruby runtime |
| Runtime metaprogramming | Must be resolvable at build time |
| `eval` / `instance_eval` with dynamic strings | Security and transpilation limits |

---

## What We Learned

Key insights from the transpilation effort:

1. **Idiomatic Rails transpiles well.** Standard MVC patterns, RESTful controllers, Active Record associations, ERB views — all transform mechanically. The thesis holds.

2. **The hard part is runtime, not syntax.** Getting 572 files to produce valid JavaScript was the easy half. Making them *run* requires adapters for Rails infrastructure (CurrentAttributes, ActionMailer, ActionText) that have no direct JavaScript equivalent.

3. **Concern composition works via AST transformation, not runtime emulation.** Rather than stubbing concern DSL methods (`attr_accessor`, `included`, `class_methods`) at runtime, a dedicated filter transforms them at transpile time. `attr_accessor :x` becomes getter/setter def pairs that the existing module converter handles naturally. This produces clean JavaScript (proper `get`/`set` accessors in IIFE return objects) with zero converter changes needed.

4. **Private fields don't compose.** JavaScript's `#field` syntax requires declaration in the enclosing class, but concern methods reference fields from the *including* class. The workaround (underscored private: `_field`) trades encapsulation for composability. The concern filter forces the IIFE path (which uses `_` prefix) by injecting a `public` marker that the module converter processes and omits.

5. **Import path resolution for nested classes is tricky.** Ruby's `Identity::AccessToken` is a namespace convention; JavaScript needs explicit file paths. The transpiler needs recursive model discovery, collision-aware class naming, and wider regex patterns for nested paths. Fixed: `findModels` is now recursive, controller filter resolves namespaced constants, and import regexes match `/` in paths.

6. **Nine categories of syntax errors can hide in plain sight.** Fizzy exposed issues across 9 converters/filters (module private fields, `for` as reserved word, super in module context, bare case/raise, duplicate field+getter, setter names, masgn in if, receiverless merge). All 50 errors were eliminated with targeted fixes.

7. **Every fix benefits all users.** Bugs found via Fizzy were fixed in core Ruby2JS, improving transpilation for all applications.

8. **Cascading failures mask progress.** All 188 test files initially failed from ~16 distinct root causes. The models index eagerly imports every model; one failure cascades to everything. Breaking the cascade required framework stubs, import resolution fixes, and name collision guards — each fix unblocking dozens of tests. Now all models load and all 33 migrations run; failures are at the test assertion level.

9. **Rails DSL transpilation is tractable.** `enum`, `scope`, `has_secure_token`, `normalizes`, `serialize`, `include url_helpers` — each is a distinct DSL pattern, but they all follow the same approach: detect in metadata collection, skip in body transform, generate equivalent JS. The pattern is repeatable.

10. **Ruby→JS filter code requires careful idiom choices.** Filter code (Ruby) must also work when transpiled to JS for selfhost. Key traps: `hash.each { |k,v| }` fails on plain JS objects (use `hash.keys.each`), `concat` returns a new array in JS (use `push` in a loop), and `each_with_index.map.to_h` chains don't transpile (use explicit loops).

11. **Circular imports require lazy resolution, not eager imports.** Rails uses autoloading (lazy name resolution); the transpiler was converting to eager ESM imports, creating cycles. The fix: `modelRegistry["ClassName"]` for association lookups — the registry is populated by `models/index.js` after all imports complete.

12. **Ruby `::` is a namespace, not a property chain.** `Account::DataTransfer::RecordSet` transpiled to `Account.DataTransfer.RecordSet` (a property chain requiring `Account` to exist), but JS classes don't have nested namespace properties. The fix: resolve the full `::` path to a direct import of the leaf class with a computed relative file path.

13. **Built-in SQLite eliminates dependency friction.** `node:sqlite` (Node 25+) and `bun:sqlite` provide the same synchronous SQLite API as `better-sqlite3` without native compilation. This removes npm link resolution issues, cross-platform build failures, and binary compatibility problems. The adapter API surface is only 6 methods (`exec`, `prepare`, `all`, `run`, `close`, constructor), making the switch trivial.

14. **Migration transpilation requires pattern expansion, not just direct translation.** Rails migrations use Ruby patterns like constant array iteration (`TABLES.each { |t| add_column t, ... }`) and polymorphic references (`t.references :owner, polymorphic: true`). These can't be translated line-by-line; the migration filter must expand loops by substituting variables with each constant value, and expand `polymorphic: true` into two column definitions (`_id` + `_type`). The selfhost build then transpiles this filter to JS, so Ruby code that manipulates AST nodes must itself be transpilable.

15. **Vite intercepts `node:` built-in imports.** Dynamic `import('node:sqlite')` in Vitest gets resolved as bare `'sqlite'` by Vite's module system. Neither `server.deps.external` nor `ssr.external` configuration prevents this. The workaround: `createRequire` from `node:module` bypasses Vite's module interception entirely. This is a known footgun when using Node built-ins in Vite-based test runners.

16. **SQLite DROP COLUMN requires index cleanup.** Unlike PostgreSQL/MySQL, SQLite fails on `ALTER TABLE ... DROP COLUMN` if any index references the column. Rails handles this automatically; the built-in SQLite adapter must query `sqlite_master` for referencing indexes and drop them before the column removal.

17. **Rails fixtures use convention over configuration for FK resolution.** A fixture column `board: writebook_uuid` auto-resolves to `board_id: <uuid>` even without an explicit `belongs_to :board` declaration. Rails checks if `board_id` exists in the schema and pluralizes the column name to find the fixture table. The eject tool replicates this with `inferTargetTable()` — check the association map first, then fall back to `pluralize(col)` matching fixture tables.

18. **UUID v5 generation must match Rails exactly.** Rails' `FixtureSet.identify(label, :uuid)` uses the OID namespace (`6ba7b812-9dad-11d1-80b4-00c04fd430c8`) with SHA-1 hashing. The JS implementation must set version 5 bits (`hash[6] = (hash[6] & 0x0f) | 0x50`) and variant bits (`hash[8] = (hash[8] & 0x3f) | 0x80`) identically, or fixture cross-references break.

19. **`new Function()` beats regex for parsing JS object literals.** The `static associations = {...}` blocks in ejected model files are valid JS object literals we just generated. Extracting with brace-balanced substring + `new Function('return ' + literal)()` is more robust than nested regex matching and handles any valid JS syntax.

20. **Rails autoloading makes every model globally available.** Tests reference `Current`, `Search`, `ZipFile` without imports because Rails autoloads them. The eject test setup must expose all models as globals after import. Similarly, `ZipFile::Writer` (nested class) needs `ZipFile.Writer = Writer` — generated from the directory structure (`zip_file/writer.js`).

21. **`let` inside `beforeEach` is invisible to tests.** Ruby's `setup do @x = ... end` creates instance variables accessible everywhere. After transpilation, `let x = ...` inside `beforeEach(() => {...})` is block-scoped. The hoisting transform must extract `let` declarations to the enclosing `describe` scope using brace-balanced parsing, not simple regex.

22. **Vitest/Vite OOM is inherent, not configurable.** Every vitest configuration (forks with 8GB heap, threads, vmThreads, fileParallelism:false + isolate:false, NODE_OPTIONS=8GB) results in ~4GB worker OOM. Vite's SSR module transformation system accumulates memory that isn't released. The solution is to bypass Vite entirely with a lightweight Node-native test runner providing vitest-compatible globals.

23. **Circular ESM imports need deferred initialization.** When model A's concern imports model B and model B's concern imports model A, Node ESM fails with TDZ errors (unlike Vite's SSR which handles this). The fix: defer concern method mixing to a `_mixConcerns()` static method called after all models are loaded, rather than doing it at module evaluation time.

24. **describe try/finally prevents cascading failures.** If a `describe` callback throws (e.g., undefined `sign_in_as`), the `_currentSuite` pointer must be restored via try/finally. Otherwise all subsequent `describe` calls in the same process silently nest under the dead suite, registering 0 top-level tests.

25. **Accurate test counting requires checking errored files first.** When a test file errors (describe body throws), the runner still reports "Tests 0 passed | 0 failed" — which matches a "passed" pattern. The Rakefile must check for errored test files (from the "Test Files" line) before checking the "Tests" line, and must also treat "0 passed | 0 failed" (with no errored files) as "no tests registered" rather than "passed".

---

## Next Steps: Prioritized by Impact

### Priority 1: Route Path Exports (~70 errored controller test files)

The single highest-impact fix. Nearly all controller tests error at import time because `config/paths.js` doesn't export the needed route helper functions (e.g., `board_column_path`, `card_comments_path`).

**Approach:**
- Generate route path functions from `config/routes.rb` during eject
- Each function takes an object/ID and returns a URL path string
- Populate `config/paths.js` with all named route helpers

**Complexity:** Medium — route DSL parsing exists in the routes filter; need to generate JS path helper functions from it.

### Priority 2: `sign_in_as` + Controller Test Infrastructure

Once controller tests can load (Priority 1), most will fail because `sign_in_as` is not defined. This function authenticates a user for controller action testing.

**Approach:**
- Implement `sign_in_as(user)` in test globals — sets `Current.user` and `Current.session`
- May also need basic HTTP request dispatch (`get`, `post`, `patch`, `delete`) if controller tests call actions directly
- Controller tests also need `assert_response`, `assert_redirected_to`, response body assertions

**Complexity:** Medium-High — `sign_in_as` itself is simple, but making controller tests actually *run* requires an HTTP dispatch layer.

### Priority 3: Missing Adapter Methods (~54 tests)

Add commonly-needed ActiveRecord methods to `active_record_base.mjs` / `active_record_sql.mjs`:

| Method | Failures | Implementation |
|--------|----------|----------------|
| `update_column(col, val)` | 4 | Direct SQL UPDATE, skip callbacks |
| `valid?` / `validate` | 7 | Run validation callbacks, return boolean |
| `delete_all` | 2 | SQL DELETE without callbacks |
| `destroy_all` | 3 | Iterate and call `destroy()` on each |
| `find_or_create_by(attrs)` | 4 | `find_by(attrs) \|\| create(attrs)` |
| `with_lock` | 5 | SQLite single-writer — just execute the block |
| `maximum(col)` | 3 | `SELECT MAX(col)` query |
| `left_outer_joins` | 2 | LEFT JOIN SQL clause |
| `exists?` | varies | `SELECT 1 ... LIMIT 1` |

### Priority 4: Schema/Migration Gaps (~34 tests)

Missing columns in ejected SQLite schema:
- `comments.body` — likely ActionText (`has_rich_text :body`), needs column or stub
- `webhooks.signing_secret` — `has_secure_token :signing_secret` not creating column
- `exports.account` — migration column missing
- `storage_entries.blob_id` — ActiveStorage schema not complete
- Various NOT NULL constraints failing

### Priority 5: Getter-vs-Method Gap (~29 tests)

Ruby `obj.method_name` (method call) → JS `obj.method_name` (property access). Two sub-issues:
- **In test code**: `_fixtures.cards_logo.tagged_with` should be `_fixtures.cards_logo.tagged_with()`
- **In model code**: `this.assigned_to` returns the function object instead of calling it

### Priority 6: Test Helper Functions (~43 tests)

Multiple smaller issues:
- `untenanted` — multi-tenant test helper (15 tests)
- Fixture table shorthands (`account_join_codes`, `webhook_deliveries`, `cards`) — direct table accessors (22 tests)
- `assert_emails`, `assert_kind_of`, `assert_nothing_raised` — test assertion stubs
- `SecureRandom` — Ruby stdlib, needs `crypto.randomUUID()` equivalent

### Priority 7: Settings / Store Accessors (12 tests)

`user.settings.bundle_email_every_few_hours` — Settings model uses `store_accessor` or custom concern.

### Priority 8: ActiveStorage (24 tests)

`has_one_attached` / `has_many_attached` with `.attach` method. High complexity — needs file storage adapter.

### Priority 9: Validation Implementation (~17 tests)

- `validates_uniqueness_of` — needs DB-backed uniqueness check (9 tests)
- Expected errors not thrown — missing validation logic (8 tests)

---

## Milestones

### Milestone 1: 100 tests (~53 more)
Focus on Priorities 3-5 (adapter methods, schema gaps, getter-vs-method). These are model-test focused and don't require controller infrastructure.

### Milestone 2: Controller tests load (~70 errored files unblocked)
Requires Priority 1 (route path exports). Currently 96 files error at import time; fixing route paths unblocks ~70 of them and reveals the real test-level failures.

### Milestone 3: 200+ tests
Requires Priority 2 (`sign_in_as` + controller test dispatch). Once controller tests can load, `sign_in_as` and HTTP dispatch are needed to actually run them.

### Milestone 4: Infrastructure Adapters
ActionText, ActiveStorage, ActionMailer — feature-specific, not blocking core tests.

### Milestone 5: External Annotations
When runtime adapters are substantially complete and type disambiguation becomes the bottleneck, see [EXTERNAL_ANNOTATIONS.md](./EXTERNAL_ANNOTATIONS.md) for the plan to support **RBS files** (type information) and **ruby2js.yml directives** (method-level skip/semantic overrides) as external overlays — enabling transpilation of unmodified Rails applications.
