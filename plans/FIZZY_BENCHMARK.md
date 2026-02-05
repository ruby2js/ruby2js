# Fizzy Benchmark: Transpiling a Production Rails Application

This plan documents the approach for transpiling Basecamp's Fizzy application to run on Node.js with SQLite3 using Ruby2JS/Juntos.

---

## Current Status (February 2025)

### Testing Methodology

Progress is measured by running `npx juntos eject` in the Fizzy directory with local npm-linked Ruby2JS packages.

#### Setting Up npm link (one-time)

```bash
# Link the packages globally (from ruby2js root)
cd packages/ruby2js && npm link
cd ../ruby2js-rails && npm link

# Link into Fizzy
cd /path/to/fizzy
npm link ruby2js ruby2js-rails

# Verify symlinks
ls -la node_modules/ruby2js  # Should show -> ../../ruby2js/packages/ruby2js
```

#### Rebuilding After Changes

After modifying filters or converters, rebuild with:

```bash
bundle exec rake -f demo/selfhost/Rakefile local
```

The `build.mjs` in ruby2js-rails uses relative imports to `demo/selfhost/`, so the npm-linked packages pick up changes automatically.

#### Running the Eject Test

```bash
cd /path/to/fizzy
DEBUG=1 npx juntos eject 2>&1 | grep -iE "(error|syntax|skipped|failed|transforming)"
```

The eject command:
1. Transforms all Ruby source files (models, controllers, views, routes, migrations, seeds)
2. Writes individual JavaScript files to `ejected/`
3. Runs Node.js syntax checking on all output files
4. Reports transformation failures and syntax errors

**Note:** Fizzy's default `package.json` points to beta tarballs on ruby2js.github.io. The npm link overrides these with local packages for testing.

### Transpilation Phases: All Complete

| Phase | Status |
|-------|--------|
| Transforming models | ✓ Complete |
| Transforming migrations | ✓ Complete |
| Transforming seeds | ✓ Complete |
| Transforming routes | ✓ Complete |
| Transforming views | ✓ Complete |
| Transforming Stimulus controllers | ✓ Complete |
| Transforming Rails controllers | ✓ Complete |

### Remaining Issues

**0 syntax errors** - All 861 JavaScript files pass syntax check.

**0 files skipped (transpilation)** - All views now transpile successfully.

**0 test files skipped** - All 188 test files transpile successfully.

**Runtime issues** - Tests load (90 tests discovered) but fail due to:
- Missing nested model files (`account/export.js`, `boardscoped.js`, `access_token.js`)
- Test helpers not yet transpiled (`SearchTestHelper`, `CardActivityTestHelper`)
- Parent vitest config interferes when running from fizzy/ejected (workaround: test in isolated directory)

### Recent Fixes

| Commit | Fix |
|--------|-----|
| `0b41fc3` | Add global stubs for `$private()`, `include()`, `ActiveSupport`, `ActionMailer` |
| `5310712` | Fix relative import paths for nested test files during eject |
| `a6a56b8` | Fix stack overflow in `transform_http_to_action` for literal URL paths |
| `a6a56b8` | Fix AR association methods matching too broadly (`reader.find {}` vs `article.comments.find`) |
| `f8721df` | Create parent directories for nested test files during eject |
| (pending) | Handle ERB comments `<%# ... %>` - skip entirely instead of Ruby `#` comment |
| (pending) | Fix nested param parsing: `article[title]` → `params.article.title` (all targets) |
| (pending) | Fix nested resource collection path: `form_with model: [@article, Comment.new]` |
| (pending) | Fix `broadcast_remove_to` default target (empty `${}` → `notification_${this.id}`) |
| (pending) | Fix async render functions for views with `await` partial calls |
| (pending) | Fix hash shorthand `{name:}` → `{name}` (not `{name()}`) |
| (pending) | Fix assignment in conditionals `unless x = expr` → `if (!(x = expr))` |
| (pending) | Fix duplicate path helpers for singular resources (`resource :foo` → prefixed names) |
| (pending) | Fix duplicate controller imports in routes.js |
| (pending) | Fix duplicate _implicitBlockYield parameter in view render functions |
| (pending) | Convert test file ivars to local vars for all test classes (not just IntegrationTest) |
| (pending) | Force underscored_private in class_extend (private fields don't work with function-style) |
| (pending) | Fix `body.flatten!` → `body = body.flatten` for selfhost JS compatibility |
| `93101af` | Auto-detect Struct.new/Class.new + class reopening in pragma filter |
| `e01761a` | Add `class << self` support to class.rb for selfhost |
| `1b854a1` | Fix duplicate parameter (`**kwargs` only) and hash shorthand inside classes |
| `9dc20d5` | Escape reserved words in method calls (`with()` → `$with()`) |
| `83418cc` | Fix array comparison for JS selfhost, document npm link setup |
| `201c669` | Fix empty module const, Struct.new, nested class imports |
| `5a6ad24` | Handle Ruby 3.4 `it` parameter in `tap` and single-symbol `params.expect` |
| `3e435af` | Support `break value` in loops, implicit block parameter, kwarg handlers |
| `ce2fbc8` | Handle `class << self` blocks and bare `new()` in class context |

### Next Steps

1. **Transpile nested model files** - Files like `account/export.rb`, `identity/access_token.rb` need to be generated as separate JS files
2. **Transpile test helpers** - `SearchTestHelper`, `CardActivityTestHelper`, etc. need to be transpiled and exported
3. **Functional testing** - Test CRUD operations, associations, etc.

---

## Goal

Validate that idiomatic Rails applications can be transpiled to JavaScript and run on non-Ruby platforms. Fizzy serves as an ideal benchmark because:

1. **Created by 37signals** - The company that created Rails
2. **Production application** - Real-world complexity, not a toy example
3. **Idiomatic Rails 8** - Uses standard patterns (Hotwire, concerns, RESTful controllers)
4. **No exotic dependencies** - Standard gems, no custom DSLs

## Thesis

> The more idiomatic your Rails application is, the greater likelihood that Juntos will be able to handle it properly.

Fizzy tests this thesis. Success would demonstrate that Ruby2JS can handle real-world Rails applications. Failures will document specific limitations.

## Application Overview

| Metric | Count |
|--------|-------|
| Models | ~41 |
| Controllers | ~65 (17 top-level + ~50 nested) |
| Stimulus Controllers | ~60 |
| Database | SQLite (UUID primary keys) |
| Frontend | Hotwire (Turbo + Stimulus) |
| Rails Version | 8.2 (main branch) |

### Key Patterns Used

- **Concern-based composition** - Card model includes 24 modules
- **Polymorphic associations** - eventable, reactable, source
- **Turbo Stream broadcasting** - Real-time updates
- **Nested controllers** - `Cards::CommentsController`, etc.
- **Strong parameters** - `.expect()` syntax (Rails 7.1+)
- **CurrentAttributes** - Request context (`Current.user`, `Current.account`)

---

## Phase 1: Foundation (Simple Models & Controllers)

**Goal:** Validate basic transpilation works with Fizzy's simplest components.

### Models to Transpile

| Model | Complexity | Key Patterns |
|-------|------------|--------------|
| Tag | Low | `belongs_to`, `has_many`, `normalizes`, simple validations |
| Column | Low | `belongs_to`, `has_many`, positioned concern |
| Step | Low | `belongs_to`, validated content |
| Pin | Low | `belongs_to` (user, card) |
| Closure | Low | Tracks card closure state |
| Tagging | Low | Join table |

### Controllers to Transpile

| Controller | Actions | Patterns |
|------------|---------|----------|
| TagsController | index | Simple resource |
| ColumnsController | CRUD | Standard RESTful |

### Expected Challenges

- `normalizes` directive - may need transpiler support
- Concern inclusion - verify module composition works
- UUID primary keys - verify ORM handles non-integer IDs

### Success Criteria

- [x] Models transpile without errors (transformation phase completes)
- [ ] Basic CRUD operations work
- [ ] Associations load correctly
- [ ] Validations prevent invalid data

**Status:** Transformation completes. Some models have syntax errors in output (see Current Status).

---

## Phase 2: Intermediate Complexity

**Goal:** Handle models with callbacks, multiple associations, and richer behavior.

### Models to Transpile

| Model | Complexity | Key Patterns |
|-------|------------|--------------|
| Comment | Medium | `belongs_to`, `has_many`, `has_rich_text`, callbacks, delegate |
| Reaction | Medium | Polymorphic (`reactable`), `after_create` callback |
| Assignment | Medium | Multiple `belongs_to`, custom validation (LIMIT constant) |
| Watch | Medium | Polymorphic (`watchable`) |
| Notification | Medium | Polymorphic (`source`), broadcasting |

### Controllers to Transpile

| Controller | Patterns |
|------------|----------|
| Cards::CommentsController | Nested resource, turbo_stream responses |
| Cards::ReactionsController | Polymorphic creation |
| NotificationsController | Bulk operations, respond_to blocks |

### Expected Challenges

- **Polymorphic associations** - `belongs_to :reactable, polymorphic: true`
- **`has_rich_text`** - ActionText integration
- **`delegate`** - Method delegation to associations
- **Turbo Stream templates** - `.turbo_stream.erb` rendering
- **`after_create_commit`** - Post-transaction callbacks

### Discovered Issues

- **Empty interpolation** - `dom_id` calls producing `${}` in turbo stream templates
- **Private fields** - Instance variables converted to `#field` appearing outside class context

### Success Criteria

- [x] Transformation phase completes for all views
- [ ] Polymorphic associations resolve correctly
- [ ] Rich text content saves and loads
- [ ] Turbo Stream responses render
- [ ] Callbacks fire in correct order

---

## Phase 3: Complex Models

**Goal:** Handle Fizzy's most sophisticated models with extensive concern composition.

### Models to Transpile

| Model | Complexity | Key Patterns |
|-------|------------|--------------|
| Card | High | 24 included concerns, transactions, complex scopes |
| User | High | 8 concerns, role enum, settings association |
| Board | Medium-High | Filterable, publishable, touch callbacks |
| Filter | High | Complex query builder (20+ conditions) |
| Event | Medium-High | Polymorphic, webhook dispatch |

### Card Concerns to Handle

```
Accessible, Assignable, Attachments, Broadcastable, Closeable, Colored,
Commentable, Entropic, Eventable, Exportable, Golden, Mentions, Multistep,
Pinnable, Postponable, Promptable, Readable, Searchable, Stallable, Statuses,
Storage::Tracked, Taggable, Triageable, Watchable
```

### Controllers to Transpile

| Controller | Patterns |
|------------|----------|
| CardsController | FilterScoped, respond_to (html/json), etag caching |
| BoardsController | Conditional rendering, fresh_when |
| FiltersController | Complex domain model |
| UsersController | Role management, admin protection |

### Expected Challenges

- **24-module composition** - Method resolution, callback ordering
- **Transaction blocks** - Multi-model atomic updates
- **Complex scopes** - Filter builds 20+ query conditions
- **Default associations** - `belongs_to :creator, default: -> { Current.user }`
- **Batch operations** - `update_all`, `in_batches`

### Success Criteria

- [ ] Card model with all concerns loads
- [ ] Transactions maintain atomicity
- [ ] Filter queries execute correctly
- [ ] Default associations resolve Current context

---

## Phase 4: Infrastructure Adapters

**Goal:** Implement adapters for Rails infrastructure that doesn't have direct JavaScript equivalents.

### CurrentAttributes (Transpilation Bug Found)

**Ruby Pattern:**
```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :account

  def with_account(value)
    with(account: value) { yield }
  end
end
```

**Current Bug:** The `with` method from ActiveSupport::CurrentAttributes is being transpiled to JavaScript's `with` statement (deprecated/forbidden in strict mode):

```javascript
// WRONG - current output:
with_account(value, ) {
  return with({account: value}, )  // JS 'with' is forbidden in strict mode
}
```

**Correct JavaScript Approach:**
```javascript
import { AsyncLocalStorage } from 'async_hooks';

const currentStorage = new AsyncLocalStorage();

export const Current = {
  get user() { return currentStorage.getStore()?.user },
  get account() { return currentStorage.getStore()?.account },

  with(attrs, callback) {
    const prev = currentStorage.getStore() || {};
    return currentStorage.run({...prev, ...attrs}, callback);
  },

  withAccount(value, callback) {
    return this.with({account: value}, callback);
  }
};
```

**Tasks:**
- [x] Investigate AsyncLocalStorage behavior in Node.js
- [ ] Fix transpilation of `with()` method calls (not JS `with` statement)
- [ ] Handle trailing comma in method parameters `(value, )`
- [ ] Determine how to integrate with request lifecycle

### ActionMailer (Implementation Required)

**Ruby Pattern:**
```ruby
UserMailer.welcome_email(@user).deliver_later
```

**Proposed JavaScript Approach:**
```javascript
import nodemailer from 'nodemailer';

// Transpile to:
await UserMailer.welcome_email(user).deliver();
```

**Tasks:**
- [ ] Create ActionMailer adapter using nodemailer
- [ ] Handle `deliver_later` → async delivery
- [ ] Map mailer view rendering

### Background Jobs (Pattern Mapping)

**Ruby Pattern:**
```ruby
NotifyRecipientsJob.perform_later(notifiable)
```

**JavaScript Equivalent:**
```javascript
// Simple async execution (no persistence):
setTimeout(() => notifiable.notify_recipients(), 0);

// Or with queueMicrotask:
queueMicrotask(() => notifiable.notify_recipients());
```

**Note:** Fizzy's jobs are simple method calls. JavaScript's event loop handles "fire and forget" natively. No job queue infrastructure needed for basic functionality.

---

## Phase 5: Full Application

**Goal:** Run the complete Fizzy application on Node.js with SQLite3.

### Integration Tasks

- [ ] Route generation from `config/routes.rb`
- [ ] View transpilation (all ERB templates)
- [ ] Stimulus controller copying/adaptation
- [ ] Asset pipeline integration
- [ ] Database migrations

### Testing Strategy

1. **Unit tests** - Transpile and run model specs
2. **Controller tests** - Transpile and run with test harness
3. **Integration tests** - End-to-end flows
4. **Manual testing** - Browser-based verification

### Success Criteria

- [ ] Application starts without errors
- [ ] User can create account and log in
- [ ] CRUD operations work for boards/cards/comments
- [ ] Real-time updates via Turbo Streams
- [ ] Search functionality works

---

## Known Considerations

### Supported (Works Today or Minor Fixes)

| Category | Patterns |
|----------|----------|
| Models | belongs_to, has_many, has_one, validations, scopes, callbacks, enums |
| Controllers | RESTful CRUD, before_action, respond_to, strong params |
| Views | ERB, partials, form helpers, Turbo Streams |
| JavaScript | Stimulus controllers, Turbo, @rails/request.js |

### Needs Implementation

| Item | Approach | Status |
|------|----------|--------|
| CurrentAttributes | AsyncLocalStorage adapter | Bug found: `with()` → `$with()` (escaped as reserved word) |
| ActionMailer | nodemailer adapter | Not started |
| Polymorphic associations | ORM enhancement | Not started |
| `normalizes` directive | Transpiler addition | Not started |
| Complex concern composition | Verify/fix module resolution | Not started |
| Nested class syntax (`::`) | Convert `Account::Export` to valid import | Bug found |
| Module-as-hash export | `export X = {}` → `export const X = {}` | Bug found |
| Struct + class reopening | Pragma filter auto-detects and uses class_extend | ✓ Fixed |
| `class << self` in class_extend | Add sclass support to class.rb handler | Bug found |

### Infrastructure (Outside App Scope)

| Item | Notes |
|------|-------|
| Rate limiting | Handle at infrastructure level (Cloudflare, nginx) |
| File uploads | ActiveStorage adapter or direct S3 |
| Search | SQLite FTS or external service |

### Explicitly Not Supported

| Item | Reason |
|------|--------|
| C extension gems | Requires Ruby runtime |
| Runtime metaprogramming | Must be resolvable at build time |
| `eval` / `instance_eval` with dynamic strings | Security and transpilation limits |

---

## Timeline Estimate

| Phase | Scope | Estimate |
|-------|-------|----------|
| Phase 1 | Simple models | 1-2 days |
| Phase 2 | Intermediate models | 3-5 days |
| Phase 3 | Complex models | 1-2 weeks |
| Phase 4 | Infrastructure adapters | 1 week |
| Phase 5 | Full integration | 1-2 weeks |

**Total:** 4-6 weeks of focused effort

**Note:** Estimates assume surprises will be discovered and fixed along the way. The value is in documenting what works and what doesn't, not in achieving 100% compatibility.

---

## Appendix: Fizzy File Inventory

### Models (~41)
```
account.rb, assignment.rb, board.rb, card.rb, closure.rb, column.rb,
comment.rb, event.rb, export.rb, filter.rb, identity.rb, magic_link.rb,
notification.rb, pin.rb, reaction.rb, session.rb, step.rb, tag.rb,
tagging.rb, user.rb, watch.rb, webhook.rb, ...
```

### Top-Level Controllers (~17)
```
application_controller.rb, boards_controller.rb, cards_controller.rb,
events_controller.rb, filters_controller.rb, join_codes_controller.rb,
landings_controller.rb, notifications_controller.rb, pwa_controller.rb,
qr_codes_controller.rb, searches_controller.rb, sessions_controller.rb,
signups_controller.rb, tags_controller.rb, users_controller.rb,
webhooks_controller.rb
```

### Nested Controllers (~50)
```
cards/assignments_controller.rb, cards/boards_controller.rb,
cards/closures_controller.rb, cards/columns_controller.rb,
cards/comments_controller.rb, cards/drafts_controller.rb,
cards/goldnesses_controller.rb, cards/images_controller.rb,
cards/not_nows_controller.rb, cards/pins_controller.rb,
cards/previews_controller.rb, cards/publishes_controller.rb,
cards/reactions_controller.rb, cards/readings_controller.rb,
cards/steps_controller.rb, cards/taggings_controller.rb,
cards/triages_controller.rb, cards/watches_controller.rb,
...
```

### Stimulus Controllers (~60)
```
auto_save_controller.js, auto_submit_controller.js, badge_controller.js,
card_hotkeys_controller.js, collapsible_columns_controller.js,
combobox_controller.js, details_controller.js, dialog_controller.js,
drag_and_drop_controller.js, fetch_on_visible_controller.js,
navigable_list_controller.js, ...
```
