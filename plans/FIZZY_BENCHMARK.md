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

## What's Been Accomplished

**Transpilation is complete with zero syntax errors.** All file categories transform successfully:

- **995 JavaScript files pass syntax check** (models, controllers, views, routes, migrations, seeds, tests, Stimulus controllers, concerns)
- **2 files skipped** - `magic_link/code.rb` (`class << self` in non-class context), `user/day_timeline/serializable.rb` (`alias`)
- **90 tests discovered** by vitest in the ejected output

Dozens of transpilation bugs were found and fixed along the way (ERB comments, nested params, hash shorthand, async render, duplicate imports, private field handling, nested class imports, namespaced exports, concern private fields, reserved word escaping, bare case/raise, etc.). These fixes benefit all Ruby2JS users, not just Fizzy.

---

## Remaining Work

The frontier has shifted from **"does it transpile?"** to **"does it run?"**

### Runtime Issues

These prevent the 90 discovered tests from passing:

| Issue | Description |
|-------|-------------|
| Test helpers | `SearchTestHelper`, `CardActivityTestHelper` need transpilation and export |
| Vitest config isolation | Parent vitest config interferes when running from fizzy/ejected |

### Infrastructure Adapters

Rails infrastructure that needs JavaScript equivalents:

| Adapter | Approach | Status |
|---------|----------|--------|
| CurrentAttributes | AsyncLocalStorage | `with()` now escapes to `$with()` (reserved word fix). Need adapter integration with request lifecycle. |
| ActionMailer | nodemailer | Not started. `deliver_later` → async delivery, mailer view rendering. |
| Background Jobs | Event loop | Fizzy's jobs are simple method calls. `perform_later` → `queueMicrotask`. No queue infrastructure needed. |
| ActionText | TBD | `has_rich_text` needs a storage/rendering adapter |
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

# Run the eject test
cd /path/to/fizzy
DEBUG=1 npx juntos eject 2>&1 | grep -iE "(error|syntax|skipped|failed|transforming)"
```

The eject command transforms all Ruby source files, writes JavaScript to `ejected/`, runs syntax checking, and reports failures.

---

## Known Considerations

### Supported (Works Today)

| Category | Patterns |
|----------|----------|
| Models | belongs_to, has_many, has_one, validations, scopes, callbacks, enums, normalizes |
| Controllers | RESTful CRUD, before_action, respond_to, strong params (.expect syntax) |
| Views | ERB, partials, form helpers, Turbo Streams |
| JavaScript | Stimulus controllers, Turbo, @rails/request.js |
| Structure | Nested controllers, concerns, Struct.new + class reopening |

### Needs Runtime Implementation

| Item | Notes |
|------|-------|
| CurrentAttributes | AsyncLocalStorage adapter exists conceptually; needs request lifecycle integration |
| ActionMailer | nodemailer adapter |
| Polymorphic associations | ORM query enhancement |
| Complex concern composition | Method resolution across 24 modules |
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

3. **Concern composition is the biggest architectural challenge.** Ruby's `include` mixin semantics (method resolution order, `super` chains, callback ordering across 24 modules) need careful runtime support.

4. **Private fields don't compose.** JavaScript's `#field` syntax requires declaration in the enclosing class, but concern methods reference fields from the *including* class. The workaround (underscored private: `_field`) trades encapsulation for composability.

5. **Import path resolution for nested classes is tricky.** Ruby's `Identity::AccessToken` is a namespace convention; JavaScript needs explicit file paths. The transpiler needs recursive model discovery, collision-aware class naming, and wider regex patterns for nested paths. Fixed: `findModels` is now recursive, controller filter resolves namespaced constants, and import regexes match `/` in paths.

6. **Nine categories of syntax errors can hide in plain sight.** Fizzy exposed issues across 9 converters/filters (module private fields, `for` as reserved word, super in module context, bare case/raise, duplicate field+getter, setter names, masgn in if, receiverless merge). All 50 errors were eliminated with targeted fixes.

7. **Every fix benefits all users.** Bugs found via Fizzy were fixed in core Ruby2JS, improving transpilation for all applications.
