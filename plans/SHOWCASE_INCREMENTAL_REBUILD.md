# Ballroom Testing & Development Plan

## Context

The ballroom app (`test/ballroom`, pushed to `github.com:rubys/ballroom`) is a dance competition management system rebuilt from the original showcase app (`~/git/showcase`) using current Rails idioms. The goal is a single Ruby codebase deployable as both a Rails app and a JavaScript app via Juntos.

## Current State (March 2025)

### What exists

- **33 models** — most scaffold-level; Event, Person, Studio, Dance enriched with scopes, validations, associations
- **29 controllers** — 27 standard CRUD scaffolds; EventsController has `root`, StudiosController has `unpair`
- **217 Juntos tests passing** (29 controller test suites + 2 system tests + 32 model tests)
- **5 collection routes defined but not implemented:** `students`, `backs`, `summary`, `publish`, `settings`

### What renders via `juntos render`

19 pages confirmed working:
```
200 OK  /            (2.7KB)    200 OK  /studios       (4.3KB)
200 OK  /studios/1   (2.1KB)   200 OK  /studios/1/edit (3.9KB)
200 OK  /studios/new (2.7KB)   200 OK  /people        (489.0KB)
200 OK  /people/1    (2.8KB)   200 OK  /people/new    (4.6KB)
200 OK  /heats       (8362.5KB) 200 OK  /dances       (127.2KB)
200 OK  /dances/1    (3.1KB)   200 OK  /dances/new    (5.6KB)
200 OK  /categories  (31.8KB)  200 OK  /categories/1  (2.9KB)
200 OK  /events/1    (6.6KB)   200 OK  /events/1/edit (16.3KB)
200 OK  /levels      (8.5KB)   200 OK  /ages         (10.1KB)
200 OK  /judges      (7.0KB)
```

5 collection action pages fail (controller actions not implemented):
`/events/summary`, `/events/publish`, `/events/settings`, `/people/students`, `/people/backs`

### Test data

544 real competition SQLite databases in `~/git/showcase/db/` (318 MB total). Any can be copied to `storage/development.sqlite3` for testing with diverse data.

## Three Testing Dimensions

### 1. Behavior (system tests)

System tests exercise user flows end-to-end: visit page, click link, fill form, assert result. They run under both Rails (`bin/rails test test/system`) and Juntos (`npx juntos test`). Differences reveal transpiler/runtime bugs.

**Current:** 217/217 Juntos tests passing (2 system test files + 29 controller + 32 model).

### 2. Transpiler fidelity (ballroom Rails vs ballroom Juntos)

Both render the same ballroom app from the same database. Normalizing and diffing the HTML catches transpiler bugs: missing CSS classes, wrong links, absent associations, layout differences.

**Tools:**
- `scripts/render.rb --html /path` — Rails render (done)
- `npx juntos render --html /path` — Juntos render (done)

### 3. Showcase parity (showcase Rails vs ballroom Rails)

Ballroom was rebuilt from showcase. Comparing their HTML output for the same routes and database verifies that the ballroom rebuild actually matches the original UI. This drives Phase 3 (enriching beyond scaffolds).

**Tools:**
- Showcase: `~/git/showcase/.claude/skills/render-page/scripts/render.rb DB --html /path`
- Ballroom: `test/ballroom/scripts/render.rb --html /path`

**Route differences to account for:**
| Showcase route | Ballroom route | Notes |
|---------------|---------------|-------|
| `/event/settings` | `/events/settings` | Singular vs plural controller |
| `/event/summary` | `/events/summary` | |
| `/event/publish` | `/events/publish` | |
| `/people/students` | `/people/students` | Same |
| `/people/backs` | `/people/backs` | Same |
| `/studios` | `/studios` | Same |
| `/people` | `/people` | Same |
| `/heats` | `/heats` | Same |
| `/dances` | `/dances` | Same |
| `/categories` | `/categories` | Same |

## Tooling

### 1. Rails render script — DONE

`test/ballroom/scripts/render.rb` renders Rails pages without starting a server, bypassing HostAuthorization middleware.

```bash
cd test/ballroom
ruby scripts/render.rb / /studios /people
ruby scripts/render.rb --html /studios
ruby scripts/render.rb --test /studios           # uses test fixtures
ruby scripts/render.rb --search "Studios" /
ruby scripts/render.rb --check / /studios /people
```

### 2. Transpiler comparison harness — TODO

A script that:
1. Renders a path via `scripts/render.rb --html` → Rails HTML
2. Renders the same path via `npx juntos render --html` → Juntos HTML
3. Normalizes both (strip CSRF tokens, asset fingerprints, whitespace)
4. Reports meaningful differences

```bash
cd test/ballroom
scripts/compare.rb /studios /people /heats /dances
```

### 3. Showcase comparison harness — TODO

A script that:
1. Copies a database to both showcase and ballroom `storage/development.sqlite3`
2. Renders shared routes via both render scripts
3. Normalizes both (strip layout chrome, asset paths, CSRF tokens)
4. Reports content-level differences (the actual view body, ignoring layout/head)

```bash
scripts/compare-showcase.rb ~/git/showcase/db/2025-charlotte.sqlite3 / /studios /people /heats /dances
```

**Normalization challenges:**
- Different layouts (showcase may have different nav, head tags)
- Different asset fingerprints
- Different Turbo/Stimulus attributes
- Showcase views are mature; ballroom views are scaffolds → expect large diffs initially
- Focus on **body content** within `<main>` or similar container, not full page

## Development Sequence

Work is driven by **what the root page links to**, fixing issues as encountered. Each step produces:
- Working Rails implementation
- Passing Juntos tests
- Clean transpiler comparison (no ballroom Rails vs Juntos drift)
- Reduced showcase comparison diff (ballroom converging on showcase output)

### Phase 1: Establish baselines — IN PROGRESS

1. ~~Fix Juntos test failures~~ — **DONE** (vitest.config.js fix, 217/217 passing)
2. ~~Write Rails render script~~ — **DONE** (`scripts/render.rb`)
3. **Build transpiler comparison harness** — compare ballroom Rails vs Juntos HTML
4. **Run transpiler comparison on all 19 working pages** — fix any drift
5. **Build showcase comparison harness** — compare showcase vs ballroom HTML
6. **Run showcase comparison on root page** — understand the gap

### Phase 2: Implement missing collection actions

Each follows the same pattern: study the showcase implementation, implement action + view in ballroom, verify Juntos, compare both ways.

| Priority | Route | Showcase controller | Notes |
|----------|-------|-------------------|-------|
| 1 | `/events/settings` | `event#settings` | Event config form |
| 2 | `/people/students` | `people#students` | Filtered people list |
| 3 | `/people/backs` | `people#backs` | Back number assignment |
| 4 | `/events/summary` | `event#summary` | Competition summary |
| 5 | `/events/publish` | `event#publish` | Publish controls |

### Phase 3: Enrich beyond scaffolds

Replace scaffold views with showcase-matching views, driven by showcase comparison diffs. Test each change against multiple databases. Work page by page, starting from the root:

| Area | Key changes | Showcase reference |
|------|-------------|-------------------|
| **Root (/)** | Event info, judge list, navigation grid | `event#root` |
| **Studios** | Pair management UI, student counts | `studios_controller.rb` |
| **People** | Role-based views, display_name formatting | `people_controller.rb` |
| **Dances** | Category grouping, drag-drop reorder | `dances_controller.rb` |
| **Heats** | Entry display, scheduling, multi-dance | `heats_controller.rb` |
| **Categories** | Ordered list, lock toggle, extensions | `categories_controller.rb` |
| **Entries** | Lead/follow/instructor associations | `entries_controller.rb` |
| **Scores** | Scoring forms, judge assignment | `scores_controller.rb` |

### Phase 4: Advanced features

- **Concerns:** HeatScheduler, DanceLimitCalculator, Printable
- **STI models:** Billable subtypes, Package/Option/PackageInclude
- **Active Storage:** Solo recordings, formations
- **Authentication:** User model, session management

## Verification Commands

```bash
# Juntos tests (after tarball rebuild)
cd ~/git/ruby2js
bundle exec rake -f demo/selfhost/Rakefile release
cd test/ballroom
npm install ../../artifacts/tarballs/juntos-dev-beta.tgz
npx juntos test                   # All tests (217 currently)

# Rails render
cd test/ballroom
ruby scripts/render.rb / /studios /people /heats /dances /categories

# Juntos render
npx juntos render / /studios /people /heats /dances /categories

# Render with specific database
cp ~/git/showcase/db/2025-charlotte.sqlite3 storage/development.sqlite3
ruby scripts/render.rb / /studios /people
npx juntos render / /studios /people

# Showcase render (same database)
cd ~/git/showcase
RAILS_APP_DB=2025-charlotte .claude/skills/render-page/scripts/render.rb --html /studios
```

## Already Resolved

Issues discovered and fixed while building the ballroom base:

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
