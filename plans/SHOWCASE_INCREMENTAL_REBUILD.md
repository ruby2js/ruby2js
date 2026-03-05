# Ballroom Testing & Development Plan

## Context

The ballroom app (`test/ballroom`, pushed to `github.com:rubys/ballroom`) is a dance competition management system rebuilt from the original showcase app using current Rails idioms. The goal is a single Ruby codebase deployable as both a Rails app and a JavaScript app via Juntos.

## Current State (March 2025)

### What exists

- **33 models** — most scaffold-level; Event, Person, Studio, Dance enriched with scopes, validations, associations
- **29 controllers** — 27 standard CRUD scaffolds; EventsController has `root`, StudiosController has `unpair`
- **214 Rails tests passing** (29 controller test suites + 2 system tests + 32 model tests)
- **214/217 Juntos tests passing** — 3 system test failures (events root, studios pair/unpair, studios CRUD)
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

## Two Testing Dimensions

### Behavior (system tests)

System tests exercise user flows end-to-end: visit page, click link, fill form, assert result. They run under both Rails (`bin/rails test test/system`) and Juntos (`npx juntos test`). Differences reveal transpiler/runtime bugs.

**Current:** 2 system test files (studios, events). 3 Juntos failures to fix.

### Presentation (render comparison)

`juntos render` outputs HTML for any route without starting a server. A matching Rails render script can produce the same. Normalizing and diffing the two outputs catches presentation drift: missing CSS classes, wrong links, absent associations, layout differences.

**Current:** `juntos render` works. Rails render script needs to be written.

## Tooling Needed

### 1. Rails render script

A script that renders a Rails page to stdout without starting a server. Must bypass `HostAuthorization` middleware. Something like:

```bash
cd test/ballroom
bin/rails runner scripts/render.rb /studios
```

### 2. Comparison harness

A script or rake task that:
1. Renders a path via Rails → HTML
2. Renders the same path via `juntos render --html` → HTML
3. Normalizes both (strip CSRF tokens, asset fingerprints, whitespace)
4. Reports meaningful differences

Can be run against different databases to test variety:
```bash
cp ~/git/showcase/db/2025-charlotte.sqlite3 storage/development.sqlite3
bin/compare-render /studios /people /heats /dances
```

## Development Sequence

Work is driven by **what the root page links to**, fixing issues as encountered. Each step produces:
- Working Rails implementation
- Passing Rails tests
- Passing Juntos tests
- Clean render comparison (no presentation drift)

### Phase 1: Fix what's broken

1. **Fix 3 Juntos system test failures** — events root, studios pair/unpair, studios CRUD
2. **Write Rails render script** — enables presentation comparison
3. **Run render comparison on all 19 working pages** — establish baseline, fix any drift

### Phase 2: Implement missing collection actions

Each follows the same pattern: implement action + view in Rails, add controller test, add system test, verify Juntos, compare render output.

| Priority | Route | Controller Action | Complexity |
|----------|-------|-------------------|------------|
| 1 | `/events/settings` | Event config form | Medium — form for Event.current |
| 2 | `/people/students` | Filtered people list | Low — index with type filter |
| 3 | `/people/backs` | Back number list | Low — index with number display |
| 4 | `/events/summary` | Competition summary | Medium — aggregation views |
| 5 | `/events/publish` | Publish controls | Medium — status management |

### Phase 3: Enrich beyond scaffolds

The scaffold views work but don't match the showcase's real UI. Enrich views and controllers to match actual competition workflows, testing each change against multiple databases:

| Area | Key changes |
|------|-------------|
| **Studios** | Pair management UI, student counts per studio |
| **People** | Role-based views (student/judge/DJ), display_name formatting |
| **Dances** | Category grouping, drag-drop reorder |
| **Heats** | Entry display, scheduling, multi-dance heats |
| **Categories** | Ordered list, lock toggle, extensions |
| **Entries** | Lead/follow/instructor associations, validation |
| **Scores** | Scoring forms, judge assignment |

### Phase 4: Advanced features

- **Concerns:** HeatScheduler, DanceLimitCalculator, Printable
- **STI models:** Billable subtypes, Package/Option/PackageInclude
- **Active Storage:** Solo recordings, formations
- **Authentication:** User model, session management

## Verification Commands

```bash
# Rails tests
cd test/ballroom
bin/rails test                    # All tests (214 currently)
bin/rails test test/system        # System tests only

# Juntos tests (after tarball rebuild)
cd ~/git/ruby2js
bundle exec rake -f demo/selfhost/Rakefile release
cd test/ballroom
npm install ../../artifacts/tarballs/juntos-dev-beta.tgz
npx juntos test                   # All tests

# Render smoke test
npx juntos render --check / /studios /people /heats /dances /categories

# Render with specific database
cp ~/git/showcase/db/2025-charlotte.sqlite3 storage/development.sqlite3
npx juntos render / /studios /people

# Full HTML for inspection
npx juntos render --html /studios | less

# Search for expected content
npx juntos render --search "Studios" /
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
