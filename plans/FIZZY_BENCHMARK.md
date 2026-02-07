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

### Runtime Issues

All 188 test files still fail, but the cascade is now much shallower. The models index eagerly imports every model — each remaining load-time error blocks all tests. Current distinct root errors:

| Root Error | Count | Category |
|-----------|-------|----------|
| `ERB.Util` not defined | 1 | Framework namespace stub needed |
| `ActiveStorage.Blob` / `ActionText.RichText` | 6 | Framework namespace references in model code |
| `ActiveRecord.Type` / `ActiveModel` | 2 | Framework namespace references |
| `ZipKit.RemoteIO` / `ZipKit.Streamer` | 3 | Gem class (zip_kit) not available |
| `SearchTestHelper` not defined | 5 | Test helper not imported |
| `CardActivityTestHelper` not defined | 2 | Test helper not imported |
| Broken view import paths | 5 | `_partials.js`, nested partial resolution |
| Mangled constant name | 1 | `m_a_x__u_n_r_e_a_d__n_o_t_i_f_i_c_a_t_i_o_n_s` |

**Key insight:** These are all runtime/adapter gaps, not transpilation issues. The generated JavaScript is syntactically correct. Adding framework namespace stubs (`ERB`, `ActiveStorage`, `ActionText`, `ActiveRecord`, `ZipKit`) to the test globals would unblock the cascade and reveal which tests can actually pass.

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

8. **Cascading failures mask progress.** All 188 test files fail, but from only ~16 distinct root causes. The models index eagerly imports every model; one failure cascades to everything. The cascade is now much shallower — most remaining errors are framework namespace stubs (`ActiveStorage`, `ActionText`, `ERB`, `ZipKit`).

9. **Rails DSL transpilation is tractable.** `enum`, `scope`, `has_secure_token`, `normalizes`, `serialize`, `include url_helpers` — each is a distinct DSL pattern, but they all follow the same approach: detect in metadata collection, skip in body transform, generate equivalent JS. The pattern is repeatable.

10. **Ruby→JS filter code requires careful idiom choices.** Filter code (Ruby) must also work when transpiled to JS for selfhost. Key traps: `hash.each { |k,v| }` fails on plain JS objects (use `hash.keys.each`), `concat` returns a new array in JS (use `push` in a loop), and `each_with_index.map.to_h` chains don't transpile (use explicit loops).

11. **Circular imports require lazy resolution, not eager imports.** Rails uses autoloading (lazy name resolution); the transpiler was converting to eager ESM imports, creating cycles. The fix: `modelRegistry["ClassName"]` for association lookups — the registry is populated by `models/index.js` after all imports complete.

12. **Ruby `::` is a namespace, not a property chain.** `Account::DataTransfer::RecordSet` transpiled to `Account.DataTransfer.RecordSet` (a property chain requiring `Account` to exist), but JS classes don't have nested namespace properties. The fix: resolve the full `::` path to a direct import of the leaf class with a computed relative file path.

13. **Built-in SQLite eliminates dependency friction.** `node:sqlite` (Node 25+) and `bun:sqlite` provide the same synchronous SQLite API as `better-sqlite3` without native compilation. This removes npm link resolution issues, cross-platform build failures, and binary compatibility problems. The adapter API surface is only 6 methods (`exec`, `prepare`, `all`, `run`, `close`, constructor), making the switch trivial.

---

## Next Phase: External Annotations

When runtime adapters are substantially complete and type disambiguation becomes the bottleneck, see [EXTERNAL_ANNOTATIONS.md](./EXTERNAL_ANNOTATIONS.md) for the plan to support **RBS files** (type information) and **ruby2js.yml directives** (method-level skip/semantic overrides) as external overlays — enabling transpilation of unmodified Rails applications.
