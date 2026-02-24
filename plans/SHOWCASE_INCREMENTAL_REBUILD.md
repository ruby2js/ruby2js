# Incremental Showcase Rebuild Plan

## Context

The showcase application (dance competition management) has 33 models, 34 controller test files, and 104 total test files. Porting it wholesale to Juntos was too large a step.

## Goal

The original showcase app is four years old and doesn't always reflect current best practices. This rebuild aims for the same functionality using current Rails idioms — cleaner, more maintainable Ruby that also transpiles cleanly to JavaScript. The result should be a single codebase deployable as both a Rails app and a JavaScript app.

## Current State

The **ballroom** app (`test/ballroom`, pushed to `github.com:rubys/ballroom`) provides a working foundation:

- **33 models** with the same schema as showcase (same migrations, same tables)
- **28 scaffold controllers** with full CRUD
- **196 tests** passing under both Rails (`bin/rails test`) and Juntos (`bin/juntos test`)
- Same database — a ballroom instance and showcase instance can share a SQLite file

What's missing: showcase-specific model logic (methods, validations, scopes, normalizes, callbacks), custom controller actions, custom views, and domain algorithms.

## Approach

- Work directly in `test/ballroom` — no creation scripts needed
- Each phase enriches existing scaffold models/controllers with showcase functionality
- Use current Rails idioms, not necessarily the original's patterns — prefer simpler, cleaner code that serves both Rails and JS deployment
- Test after each change under both Rails and Juntos
- Juntos failures drive transpiler/runtime improvements in ruby2js
- Commit to ballroom repo; update submodule pointer in ruby2js

## Verification

```bash
cd test/ballroom
bin/rails test           # Rails tests
bin/juntos test          # Juntos tests
```

Both must show 0 failures. Any Juntos failures drive improvements to the transpiler/runtime.

## Phase Breakdown

### Phase 1: Level + Age + Studio — Model Logic

Enrich the simplest models with showcase-specific logic.

**Level:**
- Add method: `initials` (first letter of each word)
- Add model tests: presence, `initials` method

**Age:**
- Add model tests: fixture loading, category values

**AgeCost:**
- belongs_to :age already exists
- Add model tests: associations

**Studio:**
- Add `validates :name, presence: true, uniqueness: true`
- Add `normalizes :name, with: -> name { name.strip }`
- Add `scope :by_name, -> { order(:name) }` (simplified from arel_table version)
- Add model tests: name validation, uniqueness, normalization, scope

**StudioPair:**
- Add model tests: associations

**StudiosController:**
- Add `unpair` custom action
- Add `pair` via create/update
- Add controller tests: pair/unpair (4 tests beyond scaffold CRUD)

**Likely Juntos improvements needed:**
- `normalizes` support in model filter
- Scope support verification (basic scopes should work)

---

### Phase 2: Category + CatExtension — Validations & Delegates

**Category:**
- Add validates: name presence/uniqueness (unless spacer), order presence/uniqueness
- Add `normalizes :name`
- Add `before_destroy :delete_owned_dances`
- Add `scope :ordered, -> { order(:order) }`
- Add methods: `heats`, `is_spacer?`, `base_category`, `part`
- Replace scaffold controller with: CRUD + `drop` (drag-drop reorder) + `toggle_lock`
- Add/adapt showcase tests (568 lines model, 652 lines controller)

**CatExtension:**
- Add delegates: `name`, `ballrooms`, `cost_override`, `pro`, `routines`, `locked`, `base_category` (all to :category)

**Likely Juntos improvements needed:**
- `before_destroy` callback with method reference
- Delegation pattern (`delegate :name, to: :category`)
- Turbo Stream responses for `drop` action
- `assert_select` alternatives for DOM assertions

---

### Phase 3: Dance + Multi + MultiLevel — Complex Associations

**Dance:**
- Add 8 belongs_to Category associations (open, closed, solo, multi + pro variants)
- Add has_many: heats, songs, multi_children, multi_dances, multi_levels
- Add `normalizes :name`
- Add custom `name_unique` validation
- Add methods: `effective_limit`, `uses_scrutineering?`, `freestyle_category`
- Replace scaffold controller with: CRUD + `drop` + `trophies` + `heats`
- Add/adapt showcase tests (839 lines model, 135 lines controller)

**Multi:**
- belongs_to :parent (Dance), belongs_to :dance

**MultiLevel:**
- belongs_to :dance
- Add validates: age/level ranges

**Likely Juntos improvements needed:**
- Models with 8+ belongs_to associations
- Complex custom validators

---

### Phase 4: Person + Judge — STI & Conditional Validations

**Person:**
- Add STI-like type column (Student, Professional, Guest, Judge, Placeholder)
- Add conditional validation: level required if type == 'Student'
- Add `normalizes :name` (complex: strip, whitespace, comma handling)
- Add associations: studio, level, age, entries (3 types), formations, options, scores, payments
- Add methods: `active?`, `display_name`, `first_name`, `last_name`, `eligible_heats`, `default_package`
- Add scopes: `by_name`, `with_option`, `with_option_unassigned`
- Replace scaffold controller with showcase-specific actions
- Add/adapt showcase tests

**Judge:**
- `alias_attribute :sort_order, :sort` (already done)
- Add showcase-specific logic as needed

**Likely Juntos improvements needed:**
- STI-like inheritance with type column
- Complex normalizes with multi-step lambda
- Conditional validations with lambdas
- Complex scopes with joins/subqueries

---

### Phase 5: Billable + Package/Option System — True STI

**Billable:**
- Add STI: Package < Billable, Option < Billable

**PackageInclude:**
- Self-referential: belongs_to :package (Billable), belongs_to :option (Billable)

**PersonOption, Table, Question, Answer, Payment:**
- Add showcase-specific associations and validations

**Likely Juntos improvements needed:**
- True STI (Package < Billable, Option < Billable)
- Self-referential associations via PackageInclude
- Nested attributes

---

### Phase 6: Entry — Complex Validations

**Entry:**
- Add belongs_to: lead/follow/instructor (Person), studio, age, level
- Add custom `has_one_instructor` validation
- Add has_many :heats
- Add methods: `subject`, `partner`, `pro`, `level_name`, `age_category`, `invoice_studio`
- Add/adapt showcase tests (719 lines)

**Likely Juntos improvements needed:**
- Custom validator classes
- Association-based validation (checking type of associated records)

---

### Phase 7: Heat + Score + Solo + Formation + Recording — Domain Logic

**Heat:**
- Add complex `rank_placement` and `rank_summaries` methods (scrutineering Rules 5-11)
- Add delegation through Entry to Person

**Score:**
- Add scopes: category_scores, heat_scores

**Solo:**
- Add has_one_attached :song_file
- Add belongs_to: combo_dance, category_override

**Formation, Recording, Song:**
- Add Active Storage attachments where needed

**Tests:**
- Add/adapt showcase tests (841 lines heat, plus score tests)

**Likely Juntos improvements needed:**
- Active Storage (`has_one_attached`)
- Deep delegation chains (Heat -> Entry -> Person)
- Complex algorithmic methods (scrutineering)

---

### Phase 8: Event + User + Location + Showcase — Configuration & Auth

**Event:**
- Singleton pattern (`Event.current`)
- Many configuration fields

**User:**
- Authentication, authorization
- `owned?`, `authorized?`

**Location, Showcase, Region, Feedback:**
- Standard associations

**Likely Juntos improvements needed:**
- Singleton pattern
- Authentication/authorization

---

### Phase 9: Concerns + Advanced Features

**Concerns:**
- Printable (PDF rendering)
- HeatScheduler (heat scheduling algorithm)
- DanceLimitCalculator (per-dance limit enforcement)
- BlobUploadable (S3/Tigris uploads)
- Compmngr (spreadsheet import)

---

### Phase 10: System Tests

Browser-based system tests using Capybara/Selenium. Full stack including JavaScript interactions.

## Already Resolved

Issues discovered and fixed while building the ballroom base:

- **Inflector integration** — Controller and helpers filters now use `Inflector.underscore`, `classify`, `pluralize` instead of naive string operations
- **`classify()` helper** — Added to transform.mjs/vite.mjs, replacing 8 inline split/map/capitalize/join patterns
- **Empty test suites** — cli.mjs skips generating .test.mjs for model tests with no test() calls
- **`alias_attribute`** — Model filter generates getter/setter pairs via `this.attributes[original]`; constructor invokes setters for scalar values
- **Test output noise** — CRUD logging uses `console.info`/`console.debug`, suppressed in test setup
- **Compound controller names** — AgeCosts, CatExtensions, PersonOptions now generate correct view imports
- **Pluralization in helpers** — `form_with(model:)` uses `Inflector.pluralize` for path helpers
