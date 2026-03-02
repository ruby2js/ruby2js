# Phlex Demos Plan

Three demos to prove Ruby2JS + Phlex handles real applications, not toys.

> **Status (March 2026):** All three demos and prerequisites are implemented.
> Demos have `dist/` output from previous builds. Whether they currently run
> correctly in-browser has not been verified recently.

## Strategic Goals

| Demo                  | Message                       | Audience                               |
| --------------------- | ----------------------------- | -------------------------------------- |
| **Stimulus Showcase** | Interactive UIs without React | Developers evaluating Hotwire vs React |
| **shadcn Components** | Build design systems          | Teams building component libraries     |
| **rubymonolith Blog** | Complete apps work            | Anyone asking "but does it scale?"     |

Together they cover the spectrum: **widget → design system → application**.

## Sequencing Rationale

The Stimulus Showcase was hardest because it required both Phlex and Stimulus filters to work and self-host. Once that was done, subsequent demos primarily exercised already-working code.

```
Demo 1: Stimulus Showcase     ████████████████████  (investment)
Demo 2: shadcn Components     ██████                (incremental)
Demo 3: rubymonolith Blog     ████████              (validation)
```

---

## Prerequisites — ALL DONE

### P1: Enable Custom Filters in ruby2js.yml — DONE

Filter selection via YAML configuration is working. The phlex demos use per-directory filter configs:

```yaml
# Example: demo/phlex-stimulus/config/ruby2js.yml
components:
  filters:
    - phlex
    - functions
    - esm

stimulus:
  filters:
    - stimulus
    - camelCase
    - functions
    - esm
```

Build scripts resolve filter names to modules dynamically via `resolve_filters()`.

**Note:** `demo/phlex-blog/scripts/build.rb` hardcodes filters in its `OPTIONS` hash rather than reading them from YAML. The YAML config is read for `eslevel`/`comparison` only. This is a minor inconsistency but doesn't block functionality.

### P2: Transpile Phlex and Stimulus Filters for Self-Hosting — DONE

| Component          | Status    | Location                                        |
| ------------------ | --------- | ----------------------------------------------- |
| `phlex` filter     | **Done**  | `demo/selfhost/filters/phlex.js`                |
| `stimulus` filter  | **Done**  | `demo/selfhost/filters/stimulus.js`             |
| `pnode` converter  | **Done**  | Included via `converter/*.rb` glob in Rakefile  |
| `functions`        | Done      | `demo/selfhost/filters/functions.js`            |
| `esm`              | Done      | `demo/selfhost/filters/esm.js`                  |
| ERB pnode xformer  | **Done**  | `demo/selfhost/dist/erb_pnode_transformer.mjs`  |

### P3: ruby2js-rails Package — EXISTS

The `packages/ruby2js-rails/` directory contains:
- `ruby2js.js` (590KB) — transpiled Ruby2JS bundle
- `build.mjs` (127KB) — transpiled build script
- `lib/` — erb_compiler.js, migration_sql.js, seed_sql.js

**Unclear:** Whether this package is up to date with the latest selfhost build, or whether it needs to be rebuilt.

### P4: JavaScript Build Integration — DONE

Build scripts in each demo read config and load filters. The phlex-stimulus and phlex-components demos use dynamic filter loading. The phlex-blog demo hardcodes filters but still works.

---

## Demo 1: Stimulus Showcase — IMPLEMENTED

**Purpose:** Prove Phlex + Stimulus = React alternative

**Filters exercised:** `phlex`, `stimulus`, `esm`, `functions`

**Location:** `demo/phlex-stimulus/`

### Components — All Implemented

| Component | Phlex View                              | Stimulus Controller                  |
| --------- | --------------------------------------- | ------------------------------------ |
| Counter   | `app/components/counter_view.rb`        | `app/controllers/counter_controller.rb`   |
| Toggle    | `app/components/toggle_view.rb`         | `app/controllers/toggle_controller.rb`    |
| Tabs      | `app/components/tabs_view.rb`           | `app/controllers/tabs_controller.rb`      |
| Modal     | `app/components/modal_view.rb`          | `app/controllers/modal_controller.rb`     |
| Dropdown  | `app/components/dropdown_view.rb`       | `app/controllers/dropdown_controller.rb`  |
| Accordion | `app/components/accordion_view.rb`      | `app/controllers/accordion_controller.rb` |
| Showcase  | `app/components/showcase_view.rb`       | —                                    |

### Structure

```
demo/phlex-stimulus/
├── app/
│   ├── components/          # 7 Phlex view files
│   └── controllers/         # 6 Stimulus controller files
├── config/
│   └── ruby2js.yml          # Filter config (phlex, stimulus, functions, esm)
├── dist/                    # Built JS output
│   ├── components/
│   └── javascript/
├── scripts/
│   └── build.rb             # Build script with dynamic filter loading
├── index.html
├── styles.css
└── package.json
```

### Status

- [x] All 6 components + showcase view written
- [x] Build script works (`scripts/build.rb`)
- [x] `dist/` contains built output
- [ ] **Unclear:** Whether demo runs correctly in browser with current builds

---

## Demo 2: shadcn Components — IMPLEMENTED

**Purpose:** Prove component libraries with variants work

**Filters exercised:** `phlex`, `stimulus` (for Dialog/Tabs), `functions`

**Location:** `demo/phlex-components/`

### Components — All Implemented

| Component | File                           | Patterns                                    |
| --------- | ------------------------------ | ------------------------------------------- |
| Button    | `app/components/button.rb`     | Variants (primary, secondary, etc.), sizes  |
| Card      | `app/components/card.rb`       | Compound components (Header, Title, etc.)   |
| Input     | `app/components/input.rb`      | Form integration, disabled state            |
| Badge     | `app/components/badge.rb`      | Simple variants                             |
| Alert     | `app/components/alert.rb`      | Variants, icon slot, dismissible            |
| Dialog    | `app/components/dialog.rb`     | Portal-like behavior, Stimulus integration  |
| Tabs      | `app/components/tabs.rb`       | Compound component, Stimulus integration    |
| Showcase  | `app/components/showcase_view.rb` | Displays all components                  |

### Structure

```
demo/phlex-components/
├── app/
│   └── components/          # 8 component files
├── config/
│   └── ruby2js.yml          # Filter config
├── dist/                    # Built JS output
│   ├── components/
│   └── controllers/
├── scripts/
│   └── build.rb
├── index.html
├── styles.css
└── package.json
```

### Status

- [x] All 7 components + showcase written
- [x] Build script works
- [x] `dist/` contains built output
- [ ] **Unclear:** Whether demo runs correctly in browser with current builds

---

## Demo 3: rubymonolith Blog — IMPLEMENTED

**Purpose:** Prove complete apps work

**Filters exercised:** `phlex`, `stimulus`, `esm`, `functions`, rails filters

**Location:** `demo/phlex-blog/`

### Structure

```
demo/phlex-blog/
├── app/
│   ├── components/          # nav, post_card, post_form, 4 view files
│   ├── controllers/         # application_controller.rb, posts_controller.rb
│   ├── models/              # post.rb
│   └── views/               # application_view.rb, posts.rb
├── config/
│   └── ruby2js.yml
├── db/
├── dist/                    # Built JS output (components, config, controllers, db, lib, models, views)
├── scripts/
│   └── build.rb             # Build script (330 lines, hardcodes filters)
├── index.html
├── styles.css
└── README.md
```

### Components

| File                              | Purpose                          |
| --------------------------------- | -------------------------------- |
| `app/components/nav_component.rb` | Navigation bar                   |
| `app/components/post_card_component.rb` | Post card display          |
| `app/components/post_form_component.rb` | Post create/edit form      |
| `app/components/posts_index_view.rb`    | Post listing page          |
| `app/components/posts_show_view.rb`     | Single post page           |
| `app/components/posts_new_view.rb`      | New post page              |
| `app/components/posts_edit_view.rb`     | Edit post page             |
| `app/controllers/posts_controller.rb`   | CRUD actions               |
| `app/models/post.rb`                    | Post model                 |
| `app/views/application_view.rb`         | Base view with helpers     |

### Status

- [x] Full CRUD app written (controllers, models, views, components)
- [x] Build script works
- [x] `dist/` contains built output (7 directories)
- [ ] **Unclear:** Whether demo runs correctly in browser with current builds
- **Note:** `build.rb` hardcodes filters rather than reading from YAML config

---

## Remaining Work / Unclear Items

### 1. Browser Testing
None of the three demos have been verified to run correctly in-browser recently. The `dist/` directories contain built output, but it's unknown whether:
- The builds are current (they may be stale relative to recent filter/converter changes)
- The runtime dependencies are satisfied (Stimulus, Phlex runtime, etc.)
- The index.html pages correctly load and initialize the built JS

### 2. ruby2js-rails Package Freshness
`packages/ruby2js-rails/` exists but may be out of date. If demos depend on it for runtime, it may need rebuilding after recent selfhost changes.

### 3. phlex-blog Filter Config Inconsistency
`demo/phlex-blog/scripts/build.rb` hardcodes its filter list rather than reading from `ruby2js.yml`. The other two demos use dynamic filter loading. This should be harmonized if the demos are maintained going forward.

### 4. Self-Hosting Validation
The phlex and stimulus selfhost filters exist, but it's unclear whether the demos have been tested end-to-end with the self-hosted transpiler (as opposed to the Ruby transpiler).

---

## Success Criteria

### Demo 1: Stimulus Showcase
- [x] All 6 components written
- [x] All Stimulus controllers written
- [x] Both filters self-host (phlex.js, stimulus.js exist)
- [ ] All components render correctly in browser
- [ ] All interactions work (click, keyboard)
- [ ] Demo runs with self-hosted transpiler

### Demo 2: shadcn Components
- [x] All 7 components written
- [x] Showcase view written
- [ ] Variants work (visual verification)
- [ ] Compound components compose correctly
- [ ] Demo runs in browser

### Demo 3: rubymonolith Blog
- [x] Controllers, models, views, components written
- [ ] Full CRUD works in browser (create, read, update, delete posts)
- [ ] Forms validate and show errors
- [ ] Navigation works
- [ ] Matches functionality of existing rails blog demo
