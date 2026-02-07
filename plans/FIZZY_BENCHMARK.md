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

## Remaining Work

The frontier has shifted from **"does it transpile?"** to **"does it run?"**

### Current Status: 38/747 Tests Passing

All 33 migrations run successfully. Test infrastructure (fixtures, stubs, globals) is now functional. The frontier is model/controller business logic.

**Breakdown:** 188 test files, 747 individual tests. 38 passing (34 model + 4 controller). The remaining 709 failures are ORM features (association proxies, collection queries), transpilation gaps (missing `self.` receivers, `$with` escaping), and mock framework behavior.

### Fixture Resolution (New)

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

### Test Infrastructure (New)

| Feature | Details |
|---------|---------|
| Global model exposure | All exported models available as globals (Rails autoloading behavior) |
| Model namespace nesting | `Search.Highlighter`, `ZipFile.Writer`, `Storage.Entry` — nested classes attached to parent |
| `CurrentAttributes` functional | `attribute()` creates static getter/setters, `$with()` saves/restores, instance methods promoted to static |
| `beforeEach` variable hoisting | `let x = ...` inside `beforeEach` → hoisted to describe scope (Rails `setup` → JS scoping fix) |
| `assert_difference` / `assert_changes` | Functional stubs with `::` → `.` conversion for Ruby namespace syntax |
| Mock/stub framework | `mock()`, `stub()`, `.stubs()`, `.expects()`, `.returns()`, `.yields()` — Mocha-compatible |
| `Object.prototype.stubs/expects` | All objects support Mocha-style mocking via prototype extension |
| Time helpers | `freeze_time`, `travel_to`, `travel_back` — pass-through stubs |
| Job helpers | `perform_enqueued_jobs`, `assert_enqueued_with` — pass-through stubs |
| IO/Net stubs | `StringIO`, `Tempfile`, `Net.HTTP`, `Resolv.DNS` — minimal stubs |
| Turbo helpers | `assert_turbo_stream_broadcasts` — no-op stub |

### Migration Filter Improvements

The migration filter (`lib/ruby2js/filter/rails/migration.rb`) now handles several patterns that Fizzy's migrations require:

| Pattern | Example | Status |
|---------|---------|--------|
| `CONST.each { \|var\| add_column ... }` | `MISSING_TABLES.each { \|t\| add_column t, "account_id", :uuid }` | Done — constant array expansion with AST variable substitution |
| `add_reference` | `add_reference :users, :identity, type: :uuid` | Done — generates `addColumn(table, name_id, type)` |
| `polymorphic: true` | `t.references :owner, polymorphic: true` | Done — generates both `_id` and `_type` columns |
| `rename_table` | `rename_table :account_exports, :exports` | Done — `ALTER TABLE ... RENAME TO` |
| `t.index` inside `create_table` | `t.index [:col1, :col2], unique: true` | Done — emitted as `addIndex` after `createTable` |
| `id: :uuid` on `create_table` | `create_table :entries, id: :uuid` | Done — UUID primary key without autoincrement |
| `change_column` | `change_column :table, :col, :type` | Silently skipped (SQLite limitation) |
| `type:` on `t.references` | `t.references :account, type: :uuid` | Done — overrides default integer type |

### SQLite Adapter Improvements

| Fix | Details |
|-----|---------|
| `node:sqlite` in Vitest | Vite strips `node:` prefix from dynamic imports; fixed via `createRequire` from `node:module` |
| `removeColumn` index cleanup | Auto-drops indexes referencing the column before `DROP COLUMN` (SQLite requirement) |
| `renameTable` | `ALTER TABLE ... RENAME TO` support |

### Runtime Issues (Next Phase)

The remaining 709 test failures cluster into distinct categories:

| Category | Count | Description |
|----------|-------|-------------|
| Association proxy `.create()` | 35 | `board.cards.create(...)` — CollectionProxy needs `.create()` method |
| Bare `create` in models | 21 | Model methods call `create(...)` without `self.` prefix |
| Hook timeouts | 27 | Mock framework `yields()` doesn't invoke callbacks |
| Missing model methods | ~35 | `.access_for`, `.cancel`, `.filters`, `.ago`, `.attach` — business logic |
| `expected undefined` | ~35 | ORM returns undefined instead of null/value (getter/query gaps) |
| `#private` setter errors | 11 | ZipFile uses `#streamer` private field in module context |
| `no such column: description` | 8 | ActionText `has_rich_text` creates virtual column |
| `$with` not defined | 6 | Ruby `with()` → `$with()` escaping needs global availability |
| Controller tests (`sign_in_as`) | 212 | Full HTTP session flow — needs controller test adapter |
| Remaining misc | ~30 | Various transpilation and runtime gaps |

### Infrastructure Adapters

Rails infrastructure that needs JavaScript equivalents:

| Adapter | Approach | Status |
|---------|----------|--------|
| `has_secure_token` | Static no-op on ActiveRecord base | Done — stub in adapter |
| `normalizes` | Static class method | Done — stub in adapter |
| `serialize` | Static class method | Done — stub in adapter |
| `has_rich_text` | Static class method | Done — stub in adapter |
| `store` | Static class method | Done — stub in adapter |
| `after_touch` | Callback registration | Done — added to CALLBACKS list |
| `index_by` | ActiveSupport filter transpilation | Done — transpiles to JS equivalent |
| `enum` | Rails model filter | Done — predicates, scopes, frozen values |
| `url_helpers` | Model filter + runtime module | Done — strips include, imports polymorphic_url/path |
| `StandardError` / `RuntimeError` | Functions filter → `Error` | Done — mapped in `on_const` |
| Circular imports | modelRegistry for associations | Done — lazy resolution via `modelRegistry["ClassName"]` |
| `::` namespace in extends | Eject tool import resolution | Done — `Account::DataTransfer::RecordSet` → `import { RecordSet }` |
| SQLite adapter | Built-in `node:sqlite` / `bun:sqlite` | Done — no native dependency, cross-runtime |
| Migration constant loops | AST expansion of `CONST.each` | Done — variable substitution in migration bodies |
| `add_reference` / polymorphic | Migration filter | Done — generates `_id` + `_type` columns |
| `rename_table` | Migration filter + adapter | Done — `ALTER TABLE ... RENAME TO` |
| `id: :uuid` primary keys | Migration filter | Done — UUID PKs without autoincrement |
| `t.index` inside `create_table` | Migration filter | Done — inline indexes emitted after table creation |
| Eject cascade breakers | Framework stubs + import fixes | Done — `ActionView`, `extend`, `IPAddr`, `Mittens`, `validates` stubs |
| `alias_method` prototype | Prototype chain walking | Done — `Object.getOwnPropertyDescriptor` with chain traversal |
| Model name collisions | Export name reading | Done — reads actual export names from transpiled files |
| CurrentAttributes | AsyncLocalStorage | `with()` now escapes to `$with()` (reserved word fix). Need adapter integration with request lifecycle. |
| ActionMailer | nodemailer | Not started. `deliver_later` → async delivery, mailer view rendering. |
| Background Jobs | Event loop | Fizzy's jobs are simple method calls. `perform_later` → `queueMicrotask`. No queue infrastructure needed. |
| ActionText | TBD | `has_rich_text` needs a storage/rendering adapter — 2 models use it |
| ActiveStorage | Direct S3 or local | File uploads, image variants |

### Functional Validation

Once runtime issues are resolved:

- [ ] Application starts without errors
- [ ] Basic CRUD operations work (create/read/update/delete cards)
- [ ] Associations load correctly (polymorphic, has_many through)
- [ ] Validations prevent invalid data
- [ ] Concern composition works (Card with 24 modules)
- [ ] Turbo Stream responses render
- [ ] Callbacks fire in correct order
- [ ] CurrentAttributes resolve in request context
- [ ] Real-time updates via Turbo Streams/Action Cable

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

## Next Phase: External Annotations

When runtime adapters are substantially complete and type disambiguation becomes the bottleneck, see [EXTERNAL_ANNOTATIONS.md](./EXTERNAL_ANNOTATIONS.md) for the plan to support **RBS files** (type information) and **ruby2js.yml directives** (method-level skip/semantic overrides) as external overlays — enabling transpilation of unmodified Rails applications.
