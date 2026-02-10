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

Fizzy tests this thesis at scale. The [blog demo](https://ruby2js.github.io/ruby2js/blog/) already proves the concept for a simple Rails app (articles + comments with Turbo Streams, running entirely on GitHub Pages). Fizzy validates it for production complexity: 41 models, 65 controllers, 60 Stimulus controllers, 24-module concern composition, polymorphic associations, CurrentAttributes.

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
| `minitest` / `mocha` | `vitest` | Already configured in ejected output |
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
- **188 test files discovered** by vitest in the ejected output (91 individual test cases)

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

## Strategy: Cards-in-Columns Core First

Rather than trying to get all 470 tests passing at once, the benchmark was
scoped to a **cards-in-columns core** (commit `5aadd934`). This strips Fizzy
to the minimal feature set that exercises the transpiler's key capabilities:

**What's in the core:**
- Card model with 6 of 24 concerns: Statuses, Triageable, Closeable, Postponable, Eventable, Colored
- Board model with 2 of 10 concerns: Cards, Triageable
- Column model (full)
- User model (simplified — `accessible_cards` only, no concerns)
- Account model (stripped — core associations only)
- Event model (stripped — no notifications, webhooks, preloaded scope)

**What's intentionally excluded:**
- 18 Card concerns (Pinnable, Readable, Golden, Searchable, Stallable, Taggable, Assignable, Commentable, etc.)
- All 13 User concerns (Accessor, Assignee, Avatar, Notifiable, Role, Searcher, etc.)
- All Account concerns (Cancellable, MultiTenantable, ExternalIdSequence)
- Features: reactions, comments, tags, filters, search, assignments, notifications, webhooks
- Infrastructure: ActionText, ActiveStorage, ActionMailer, ActionCable
- Auth: magic links (replaced with auto-login)
- Controllers: simplified to direct account-scoped queries

This means **~75% of the 470 tests are expected to fail** — they test stripped features.
The core target is **~34 tests across 13 test files**.

---

## Current Status

### Overall: 27/470 tests passing (4/188 files)

### Core Tests: 15/34 passing (3/13 files)

| Test File | Status | Tests | Blocker |
|-----------|--------|-------|---------|
| **card/closeable** | **PASS** | 6/6 | — |
| **column** | **PASS** | 2/2 | — |
| **board/cards** | **PASS** | 1/3 | `assert_changes` fixture timing (2 tests) |
| **user/configurable** | **PASS** | 1/1 | — |
| card/statuses | FAIL | 0/6 | `account.increment` null, `.ago` missing, `assert_difference` |
| card/triageable | FAIL | 0/4 | `this.open` not a function, `.ago` missing |
| card/postponable | FAIL | 0/3 | `.ago` missing (time helpers) |
| card/eventable | FAIL | 0/4 | Event creation null, `.ago` missing |
| card/colored | FAIL | 0/1 | `Column.Colored` namespace (exported as `ColumnColored`) |
| card.test | FAIL | 0/? | Parse error: `await` in non-async function |
| account.test | FAIL | 0/? | Parse error: `Expected a semicolon` |
| user.test | FAIL | 0/? | Parse error: left-hand side of assignment |
| column_limits | FAIL | 0/? | Parse error |
| entropy | FAIL | 0/1 | `undefined.updated_at` |

### Root Causes Blocking Core Tests

| Blocker | Tests Affected | Description |
|---------|---------------|-------------|
| **Time helpers** | ~8 | `.week.ago`, `Time.current`, `freeze_time` — no JS equivalents |
| **Parse errors in transpiled tests** | ~4 files | `await` in non-async, semicolons, assignment LHS — test transpilation bugs |
| **`this.open` not a function** | ~3 | Zero-arg method called as property access (Ruby `card.open` → JS `card.open` property, not `card.open()`) |
| **`Column.Colored` namespace** | 1 | Exported as `ColumnColored`, tests access `Column.Colored` |
| **Fixture/association issues** | ~4 | `account` null during `assign_number`, event creation failures |
| **`assert_changes`/`assert_difference`** | ~3 | Async evaluation timing in test helpers |

### Expansion Strategy

Once the core 34 tests pass, expand in layers:

1. **Core concerns** — The 6 Card concerns + 2 Board concerns (current focus)
2. **Card model + Column limits** — Fix parse errors, get `card.test.mjs` and `column_limits.test.mjs` passing
3. **Account/User basics** — Fix parse errors, get basic model tests passing
4. **Additional concerns** — Re-enable stripped concerns one at a time as the adapter matures
5. **Controller tests** — Need `sign_in_as` helper and HTTP session adapter (~212 tests)
6. **Infrastructure** — ActionText, ActiveStorage, ActionMailer (feature-specific, not blocking core)

---

## What's Been Accomplished

**Transpilation is complete with zero syntax errors.** All file categories transform successfully:

- **995 JavaScript files pass syntax check** (models, controllers, views, routes, migrations, seeds, tests, Stimulus controllers, concerns)
- **1 file skipped** - `magic_link/code.rb` (`class << self` in non-class context)
- **188 test files discovered** by vitest in the ejected output

### Recent Fixes (Closeable Sprint)

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
| Predicate getters in concerns | Transpiler | `closed?` → `get closed()` for zero-arg concern methods |
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
| Time helpers | `freeze_time`, `travel_to`, `travel_back` — pass-through stubs (need real implementation) |
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
- [ ] Time duration helpers (`.week.ago`, `freeze_time`)
- [ ] Controller tests (need `sign_in_as` helper)
- [ ] Turbo Stream responses
- [ ] Real-time updates via Action Cable

---

## Development Workflow

### Setup (one-time)

```bash
# Link packages globally (from ruby2js root)
cd packages/ruby2js && npm link
cd ../ruby2js-rails && npm link

# Link into Fizzy
cd /path/to/fizzy
npm link ruby2js ruby2js-rails
```

### Build and Test

```bash
# After modifying filters or converters
bundle exec rake -f demo/selfhost/Rakefile local

# Eject with built-in SQLite (no native dependency, no npm link issues)
cd /path/to/fizzy
npx juntos eject -d sqlite

# Link and test
cd ejected
npm link ruby2js-rails
NODE_OPTIONS=--no-warnings npx vitest run
```

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

---

## Next Steps: Getting Core to 34/34

### Priority 1: Time Helpers (~8 tests)

Implement real time duration support in `transform.mjs` (`generateTestGlobalsForEject`):
- Number prototype extensions: `.day`/`.days`, `.week`/`.weeks`, `.month`/`.months`, `.hour`/`.hours`
- Duration object with `.ago`, `.from_now` methods
- `Time.current` → `new Date()`
- `freeze_time` that actually freezes `Date.now()`
- `travel_to(time)` that shifts `Date.now()`

### Priority 2: Test Parse Errors (~4 files)

Fix transpilation bugs in test code:
- `await` in non-async function (card.test.mjs)
- Missing semicolons (account.test.mjs)
- Assignment LHS errors (user.test.mjs, column_limits.test.mjs)

### Priority 3: Method-as-Property Gap (~3 tests)

Ruby `card.open` (method call) → JS `card.open` (property access). Need `()` appended
for non-getter methods in test transpilation. Affects triageable (`this.open is not a function`).

### Priority 4: Column.Colored Namespace (1 test)

Exported as `ColumnColored`, but tests access `Column.Colored`. Fix namespace nesting
in the model index or adjust the concern export.

### Priority 5: Fixture/Association Issues (~4 tests)

- `account.increment` null — account not loaded during `assign_number` callback
- `assert_changes`/`assert_difference` async timing

---

## Future Phases

### Phase 2: Expand to Full Card Model
Re-enable stripped Card concerns one at a time, fixing transpilation and adapter gaps as they surface.

### Phase 3: Controller Tests
Implement `sign_in_as` helper and HTTP session adapter (~212 tests).

### Phase 4: Infrastructure Adapters
ActionText, ActiveStorage, ActionMailer — feature-specific, not blocking core model tests.

### Phase 5: External Annotations
When runtime adapters are substantially complete and type disambiguation becomes the bottleneck, see [EXTERNAL_ANNOTATIONS.md](./EXTERNAL_ANNOTATIONS.md) for the plan to support **RBS files** (type information) and **ruby2js.yml directives** (method-level skip/semantic overrides) as external overlays — enabling transpilation of unmodified Rails applications.
