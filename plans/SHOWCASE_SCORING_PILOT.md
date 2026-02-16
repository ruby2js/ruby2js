# Showcase Scoring Pilot: SQLite WASM + Juntos Browser SPA

Validate that a production Rails application's read-heavy, offline-critical subsystem can be extracted as a Juntos browser SPA backed by SQLite WASM, interoperating with the existing Rails server.

---

## Context

The [showcase](https://github.com/rubys/showcase) application manages dance competition events (~350 events across 87 cities in 8 countries). Each event is a separate SQLite3 database. The scoring/judging subsystem is the highest-value target for offline support: judges need to record scores during events despite unreliable Wi-Fi, and the read path (heats, entries, dances, scores) is naturally self-contained.

The existing Rails app already has:
- `GET /event.sqlite3` endpoint (`event#database`) that serves a raw SQL dump via `sqlite3 #{database} .dump`
- A partially-built offline scoring SPA (~60-70% complete, documented in `showcase/plans/OFFLINE_SCORING_COMPLETION.md`)
- Turbo Stream broadcasting for real-time score updates

## Goal

Replace the existing scoring SPA with a Juntos browser SPA that:

1. Fetches the full SQLite dump from the Rails server
2. Imports it into SQLite WASM with OPFS in the browser
3. Runs transpiled ActiveRecord models querying the local database
4. Renders transpiled ERB scoring views identically to Rails
5. Writes scores to local SQLite + POSTs back to Rails when online

## Why This Pilot

| Criterion | Fit |
|-----------|-----|
| **Offline need** | Judges must score during Wi-Fi dropouts — the strongest offline use case |
| **Natural CQRS** | Reads dominate (heat lists, entries, scores). Writes are append-only scores with no conflicts (each judge scores independently) |
| **Small data** | Event databases are 150-450KB compressed — easily fits in browser |
| **Self-contained** | Scoring reads don't need admin tables (users, invoices, payments) |
| **Testable** | Output can be diffed against Rails HTML for real event data |
| **Stepping stone** | Validates the architecture for the eventual CloudFlare Durable Objects migration |

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Browser                                         │
│                                                  │
│  ┌──────────────┐    ┌────────────────────────┐ │
│  │ Juntos SPA   │    │ SQLite WASM + OPFS     │ │
│  │              │    │                        │ │
│  │ Transpiled   │───▶│ Full event database    │ │
│  │ models/views │    │ (imported from dump)   │ │
│  │              │    │                        │ │
│  └──────┬───────┘    └────────────────────────┘ │
│         │                                        │
└─────────┼────────────────────────────────────────┘
          │ POST /scores (when online)
          ▼
┌─────────────────────┐
│  Rails Server       │
│                     │
│  GET /event.sqlite3 │
│  POST /scores       │
│  GET /version_check │
└─────────────────────┘
```

### Data Flow

1. **Bootstrap**: SPA fetches `/event.sqlite3`, feeds the SQL dump to `sqlite-wasm`, stores in OPFS
2. **Reads**: Transpiled models (`Heat.where(...)`, `Score.find_by(...)`) query local WASM SQLite directly
3. **Writes**: Score saves write to local SQLite immediately. A write queue POSTs to Rails when connectivity is available. `GET /version_check` detects staleness.
4. **Incremental updates** (future): `after_save`/`after_destroy` callbacks capture changes server-side; client fetches only deltas since last sync.

## Scope

### Models to Transpile

The scoring read path requires these models (and their associations):

| Model | Role | Key associations |
|-------|------|------------------|
| `Heat` | Central — a scored dance slot | `belongs_to :dance, :entry`, `has_many :scores`, `has_one :solo` |
| `Score` | A judge's score for a heat | `belongs_to :judge` (Person), `belongs_to :heat` |
| `Entry` | Lead/follow pair or solo entry | `belongs_to :lead, :follow, :instructor` (Person) |
| `Person` | Dancer, judge, or professional | STI types, `has_one :judge` |
| `Dance` | Waltz, Foxtrot, etc. | Category associations, `scrutineering` method |
| `Category` | Grouping of dances | `has_many :cat_extensions` |
| `Judge` | Judge metadata | `belongs_to :person`, ballroom/sort prefs |
| `Solo` | Solo performance details | `belongs_to :heat` |
| `Event` | Event configuration | `Event.current` singleton |
| `Age` | Age division | Used by Entry |
| `Level` | Skill level | Used by Entry |
| `Studio` | Dance studio | Used by Entry/Person |

Models explicitly **excluded** from the pilot: User, Invoice, Payment, Billable, PackageInclude, Location, Showcase, Region, Song, Recording, Feedback, Question, Answer, PersonOption, StudioPair, Table, Formation, Multi, MultiLevel.

### Views to Transpile

The scoring interface renders heats for a specific judge. Key views:

- Heat list (judge's agenda)
- Heat detail (entries in a heat, score input)
- Scrutineering results (skating system calculations)
- Category scoring

### What Stays in Rails

- Authentication (judges access via a link with their judge ID)
- Admin interface (all CRUD operations)
- Event setup, scheduling, invoicing
- The `GET /event.sqlite3` endpoint itself

## Implementation Plan

### Phase 1: Infrastructure (ruby2js)

#### 1a. Include/exclude filtering for Vite plugin ✅

Done in `ffa843f1`. The Vite plugin now supports `include`/`exclude` glob filtering via `config/ruby2js.yml`, matching the existing eject CLI. The `globToRegex`, `matchesAny`, and `shouldIncludeFile` functions are shared from `transform.mjs`.

Configuration in `config/ruby2js.yml`:
```yaml
include:
  - app/models/heat.rb
  - app/models/score.rb
  - app/models/entry.rb
  - app/models/person.rb
  - app/models/dance.rb
  - app/models/category.rb
  - app/models/judge.rb
  - app/models/solo.rb
  - app/models/event.rb
  - app/models/age.rb
  - app/models/level.rb
  - app/models/studio.rb
  - app/views/scores/**
```

#### 1b. SQLite WASM adapters ✅

Done in `f8f7e034` and `1b5ddbcd`. Three new files:

- `adapters/dialects/sqlite_browser.mjs` — shared base extracting DDL helpers, query/execute, and `importDump(sqlText)` from the common sql.js pattern
- `adapters/active_record_sqlite_wasm.mjs` — `@sqlite.org/sqlite-wasm` with OPFS persistence (falls back to in-memory)
- `adapters/active_record_wa_sqlite.mjs` — `wa-sqlite` with OPFS VFS via `OPFSCoopSyncVFS`

Registered as `sqlite-wasm`/`sqlite_wasm` and `wa-sqlite`/`wa_sqlite` in `transform.mjs`, `vite.mjs`, and `builder.rb`. Both default to `target: 'browser'`.

#### 1c. Pragma support for conditional code ✅

Verified — no code changes needed. The pragma filter already supports 11 targets including `browser`, plus a `server` meta-target. The Vite plugin passes `config.target` to every `convert()` call. For `sqlite-wasm`, `DEFAULT_TARGETS` maps to `'browser'` automatically, so pragmas work without explicit target configuration. Usage:

```ruby
import ServerOnly from "server-only" # Pragma: server
import BrowserLib from "browser-lib" # Pragma: browser
```

### Phase 2: Pilot Application (showcase)

#### 2a. Juntos project setup

Create a Juntos project within showcase (or as a sibling) with:
- `vite.config.js` using `juntos({ database: 'sqlite-wasm', target: 'browser' })`
- `config/ruby2js.yml` with include patterns for scoring models/views
- `config/database.yml` with `adapter: sqlite-wasm`

**Validation — Models transpile without errors:**

1. All 12 models transpile — no parse errors, no unsupported syntax. Showcase models likely use patterns the demos don't (STI, complex scopes, `Event.current` singleton, custom methods with SQL-heavy logic like `Heat#rank_placement`).
2. Generated `app/models/index.js` lists all 12 models with correct imports — the include filter didn't accidentally exclude dependencies.
3. Association graph is complete — no dangling `belongs_to` pointing to excluded models. Every referenced model class is in the bundle.
4. Syntax check the output — `node -c` on each generated `.js` file catches transpilation bugs before anything runs.

*Likely issues*: Unsupported Ruby patterns (STI `type` column handling, class methods with complex default arguments, `scope` lambdas with SQL fragments).

#### 2b. Database bootstrap

A Stimulus controller or standalone module that:
1. Fetches `/event.sqlite3` on first load
2. Feeds the SQL dump to the WASM SQLite instance
3. Stores in OPFS (keyed by event)
4. Signals "ready" so views can render
5. Checks `/version_check` periodically to detect staleness

This is browser-only code — it doesn't exist in Rails, so no conditional branching needed.

**Validation — Models can query imported data:**

1. Import succeeds — `importDump()` handles the full dump without errors. Real dumps may have SQLite-specific syntax (`INSERT OR REPLACE`, `PRAGMA` statements, triggers) that the statement splitter doesn't handle.
2. Table verification — `SELECT name FROM sqlite_master WHERE type='table'` returns the expected tables (heats, scores, entries, people, dances, categories, judges, solos, events, ages, levels, studios).
3. Basic queries work — `Heat.all()`, `Score.where({heat_id: 1})`, `Entry.find(1)` return rows with correct types (integers are integers, not strings).
4. Associations resolve — `heat.scores`, `heat.dance`, `entry.lead` return the right related records. This tests that foreign keys in the imported data match what the transpiled models expect.
5. Row counts match — Compare `Heat.count()` in the browser against `Heat.count` from Rails console for the same event database.

*Likely issues*: Column type mismatches (SQLite's loose typing vs what the adapter expects), association naming mismatches between the dump schema and transpiled model declarations, `importDump()` choking on triggers or views in the dump.

#### 2c. Score write-back

When a judge submits a score:
1. Write to local SQLite immediately (judge sees instant feedback)
2. Queue an HTTP POST to `/scores` (or `/batch_scores`)
3. Process queue when online, retry on failure
4. The existing `batch_scores` endpoint accepts bulk uploads — reuse it

**Validation — Round-trip data integrity:**

1. Local write persists — Create a score via `Score.create(...)`, verify `Score.find(id)` returns it, close and reopen the OPFS database, verify it's still there.
2. POST payload matches Rails format — Capture the HTTP POST body and verify it matches what the existing `/batch_scores` endpoint expects. Compare against a real request from the current Rails scoring UI.
3. Rails accepts the POST — Actually POST to a test instance and verify the score appears in the Rails database.
4. Conflict-free — Two scores from different judges for the same heat don't collide (each judge has an independent score row).

*Likely issues*: CSRF token handling, authentication (judges access via link with judge ID — how does the SPA authenticate POSTs?), field naming mismatches between transpiled model attributes and Rails strong params.

#### 2d. Mount point

Either:
- A new route in Rails that serves the Juntos SPA's `index.html` (simplest)
- Modify the existing `/scores/:judge/heats` route to serve the SPA when a query param or cookie is set (allows A/B testing)

**Validation — End-to-end rendering parity:**

1. SPA loads and renders — Navigate to the mount point, see the heat list for a specific judge.
2. Visual diff against Rails — For 3-5 heats, screenshot the Rails-rendered page and the SPA-rendered page side by side. This is manual initially but feeds into Phase 3's automated HTML diff.
3. Navigation works — Click through heat list → heat detail → back, verify no broken routes or missing views.
4. Data matches — Spot-check that names, scores, and dance labels shown in the SPA match exactly what Rails shows.

*Likely issues*: Missing view helpers (the scoring views likely use helpers not yet transpiled), ERB partials that reference excluded models or controller methods, route generation differences.

### Phase 3: Validation

#### 3a. Automated HTML diff testing

The primary exit criterion: for a set of real event database dumps, the Juntos SPA's rendered HTML for each heat view must match the Rails-rendered HTML (modulo whitespace and asset URLs).

```
For each test event:
  1. Load event.sqlite3 into WASM
  2. For each judge, for each heat:
     a. Render via Juntos (headless browser)
     b. Render via Rails
     c. Diff the HTML
  3. Report mismatches
```

This provides confidence without writing bespoke tests — the real event data IS the test suite.

#### 3b. Offline smoke test

1. Load the SPA online (database fetched)
2. Disconnect network
3. Navigate heats, enter scores
4. Reconnect
5. Verify scores sync to Rails

## Key Unknowns

| Unknown | Risk | Mitigation |
|---------|------|------------|
| SQLite WASM + OPFS browser support | Medium — Safari added OPFS in 16.4, but some older devices at events | Fall back to in-memory with localStorage backup |
| Scrutineering logic complexity | Low — `Heat#rank_placement` is ~150 lines of pure computation, should transpile cleanly | Test against known event results |
| SQL dump import performance | Low — dumps are 150-450KB, import should be < 1 second | Profile on low-end tablets |
| ERB view parity | Medium — scoring views may use helpers not yet transpiled | Identify gaps early with the HTML diff tool |
| OPFS storage quota | Low — event databases are small | Check quota API, warn if low |

## Success Criteria

1. **Functional parity**: HTML diff shows zero meaningful differences for scoring views across 5+ real event dumps
2. **Offline capability**: Scores entered offline sync correctly when connectivity resumes
3. **Performance**: Initial load (fetch + import) under 3 seconds on a mid-range tablet
4. **No Rails changes required**: The existing `/event.sqlite3`, `/scores`, and `/version_check` endpoints work as-is

## What This Proves

If the pilot succeeds, it validates:

1. **SQLite dump → WASM import** as a data transport mechanism (replacing JSON serialization + hydration)
2. **Transpiled models querying real SQLite** (not just IndexedDB)
3. **Transpiled ERB views producing identical output** against production data
4. **The adapter abstraction** — same models, different database backend, no code changes
5. **Include/exclude filtering** — Juntos can target a subset of a large Rails app
6. **The path to Durable Objects** — if models work against WASM SQLite in the browser, they'll work against D1 on CloudFlare with minimal adapter changes

## Future Extensions

- **Incremental sync**: Application-level change capture via `after_save`/`after_destroy`, client fetches deltas
- **Emcee SPA**: Same architecture, different view subset (heat announcements, music cues)
- **CloudFlare deployment**: Move from browser-only to Durable Object with D1, using the same transpiled models
- **Full CQRS**: Extend beyond scoring to all read-heavy event operations (schedules, results display)
