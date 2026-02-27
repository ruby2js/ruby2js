# Incremental Showcase Rebuild Plan

## Context

The showcase application (dance competition management) has 33 models, 34 controller test files, and 104 total test files. Porting it wholesale to Juntos was too large a step.

## Goal

The original showcase app is four years old and doesn't always reflect current best practices. This rebuild aims for the same functionality using current Rails idioms — cleaner, more maintainable Ruby that also transpiles cleanly to JavaScript. The result should be a single codebase deployable as both a Rails app and a JavaScript app.

## Current State

The **ballroom** app (`test/ballroom`, pushed to `github.com:rubys/ballroom`) provides a working foundation:

- **33 models** with schema matching showcase (same migrations, same tables)
- **28 scaffold controllers** with full CRUD
- **196 tests** passing under both Rails (`bin/rails test`) and Juntos (`bin/juntos test`)
- **Root dashboard** (`events/root.html.erb`) with navigation links to all major sections
- Same database — a ballroom instance and showcase instance can share a SQLite file

Models already enriched beyond scaffolds: Event (`current`, `assign_judges?`), Person (`display_name`, `present?`, `by_name` scope, associations), Studio (`normalizes`, `validates`, `by_name` scope, `pairs`, studio pair associations), Judge (`alias_attribute`), Level, Age.

## Approach

Work is driven by **user scenarios reachable from the root page**, not model-by-model enrichment. Each step:

1. Pick a scenario (e.g., "create, modify, and delete studios")
2. Implement in modern Rails idioms — update models, views, controllers
3. Add tests: controller tests for CRUD/custom actions, system test for the user flow
4. Get it working under `bin/rails test` first
5. Verify under `npx juntos test`, fixing transpiler/runtime issues as needed
6. Commit to ballroom repo; update submodule pointer in ruby2js

System tests use Capybara-style helpers (`visit`, `fill_in`, `click_button`, `assert_text`) and run in jsdom under `juntos test` — no browser required. Each scenario gets at least one system test to exercise the transpiled views end-to-end.

## Verification

```bash
cd test/ballroom
bin/rails test           # Rails tests
npx juntos test          # Juntos tests (jsdom, no browser)
```

Both must show 0 failures. Any Juntos failures drive improvements to the transpiler/runtime.

## Root Page Navigation

The root page (`events#root`) links to these sections, which define the scenario order:

| Link | Route | Controller | Priority |
|------|-------|------------|----------|
| Studios | `studios_path` | StudiosController | Step 1 |
| Students | `students_people_path` | PeopleController | Step 3 |
| Heats | `heats_path` | HeatsController | Step 7 |
| Dances | `dances_path` | DancesController | Step 4 |
| Agenda | `categories_path` | CategoriesController | Step 5 |
| Backs | `backs_people_path` | PeopleController | Step 3 |
| Summary | `summary_events_path` | EventsController | Step 8 |
| Publish | `publish_events_path` | EventsController | Step 8 |
| Settings | `settings_events_path` | EventsController | Step 2 |
| Judge/DJ links | `person_path(person)` | PeopleController | Step 3 |

## Step Breakdown

### Step 1: Studios — CRUD + Pair/Unpair

**Scenario:** Navigate from root to studios list, create a studio, edit it, pair two studios, unpair them, delete a studio.

**Already done (model):** `validates :name`, `normalizes :name`, `scope :by_name`, `pairs` method, studio pair associations.

**Remaining work:**
- Rework studios views beyond scaffold (index with pair status, form with pair controls)
- Enrich StudiosController: `pair` action, `unpair` action, index ordering by name
- Controller tests: CRUD + pair/unpair
- System test: create → edit → delete flow; pair/unpair flow
- Verify under `juntos test`

**Likely Juntos issues:** Custom controller actions, Turbo responses for pair/unpair.

---

### Step 2: Settings — Event Configuration

**Scenario:** Navigate from root to settings, update event configuration fields, return to root and see changes reflected.

**Remaining work:**
- Implement `settings` collection action on EventsController (form for Event.current)
- Settings view with grouped fields (general, scoring, display, costs)
- Controller tests: get settings, update event
- System test: visit settings → change event name → verify root reflects change

**Likely Juntos issues:** Collection routes, `Event.sole` / `Event.current` singleton pattern.

---

### Step 3: People — Students, Judges, DJs

**Scenario:** Navigate from root to students list, create a student with studio/level/age associations. View a judge's detail page from root. Browse the backs list.

**Remaining work:**
- Implement `students` and `backs` collection actions on PeopleController
- Rework people views: students list (filtered by type), person show with role-specific display
- Enrich Person model as needed for views (conditional validations for students, name normalization)
- Controller tests: students list, backs list, CRUD for students
- System test: create student → assign to studio → verify on students list

**Likely Juntos issues:** Collection routes with type filtering, conditional validations, complex `normalizes`.

---

### Step 4: Dances — CRUD + Category Associations

**Scenario:** Navigate from root to dances list, create a dance, assign it to categories, reorder dances.

**Remaining work:**
- Enrich Dance model: category belongs_to associations, `normalizes :name`, custom validations
- Rework dances views: index with category grouping, form with category selects
- Enrich DancesController: `drop` (reorder) action
- Multi/MultiLevel model logic as needed
- Controller tests: CRUD + reorder
- System test: create dance → assign category → verify on list

**Likely Juntos issues:** Models with many belongs_to associations, drag-drop reorder via Turbo.

---

### Step 5: Agenda — Categories + CatExtensions

**Scenario:** Navigate from root to agenda (categories list), reorder categories, toggle lock, manage category extensions.

**Remaining work:**
- Enrich Category model: validations, `before_destroy`, `is_spacer?`, `heats` method
- CatExtension: delegation to category
- Rework categories views: ordered list with lock toggle, drag-drop reorder
- CategoriesController: `drop`, `toggle_lock`, `delete_owned_dances`
- Controller tests: CRUD + custom actions
- System test: reorder categories → toggle lock → verify

**Likely Juntos issues:** `before_destroy` callbacks, `delegate`, Turbo Stream for reorder/toggle.

---

### Step 6: Entries — Complex Associations + Validations

**Scenario:** Create entries linking students to dances (via lead/follow/instructor associations).

**Remaining work:**
- Enrich Entry model: belongs_to associations (lead, follow, instructor as Person), custom `has_one_instructor` validation, helper methods
- Rework entries views: form with person/dance selects
- Controller tests: CRUD with validation edge cases
- System test: create entry → verify associations

**Likely Juntos issues:** Custom validator classes, association-based validations.

---

### Step 7: Heats — Scheduling + Scoring

**Scenario:** Navigate from root to heats list, view heat details, enter scores.

**Remaining work:**
- Enrich Heat model: delegation through Entry to Person, scheduling logic
- Score model: scopes, scoring methods
- Rework heats views: heat list with entries, scoring form
- Controller tests: CRUD + scoring
- System test: view heat → enter score → verify

**Likely Juntos issues:** Deep delegation chains, complex algorithmic methods (scrutineering).

---

### Step 8: Summary + Publish + Remaining Event Actions

**Scenario:** Navigate from root to summary view, publish results.

**Remaining work:**
- Implement `summary` and `publish` collection actions on EventsController
- Summary/publish views
- User/auth as needed
- Controller tests
- System test: view summary → publish

**Likely Juntos issues:** Authentication, authorization, report generation.

---

### Step 9: Supporting Models + Advanced Features

Implement as needed when reached through scenarios above:

- **Billable/Package/Option:** STI, self-referential PackageInclude
- **Solo/Formation/Recording/Song:** Active Storage, specialized views
- **Location/Showcase/Region/Feedback:** Standard CRUD
- **Concerns:** Printable, HeatScheduler, DanceLimitCalculator, BlobUploadable, Compmngr

---

## Already Resolved

Issues discovered and fixed while building the ballroom base:

- **Inflector integration** — Controller and helpers filters now use `Inflector.underscore`, `classify`, `pluralize` instead of naive string operations
- **`classify()` helper** — Added to transform.mjs/vite.mjs, replacing 8 inline split/map/capitalize/join patterns
- **Empty test suites** — cli.mjs skips generating .test.mjs for model tests with no test() calls
- **`alias_attribute`** — Model filter generates getter/setter pairs via `this.attributes[original]`; constructor invokes setters for scalar values
- **Test output noise** — CRUD logging uses `console.info`/`console.debug`, suppressed in test setup
- **Compound controller names** — AgeCosts, CatExtensions, PersonOptions now generate correct view imports
- **Pluralization in helpers** — `form_with(model:)` uses `Inflector.pluralize` for path helpers
- **`polymorphic_path` for local variables** — `link_to text, lvar` now uses `polymorphic_path()` instead of inferring path helper from variable name (fixes `dj`/`emcee` routing)
