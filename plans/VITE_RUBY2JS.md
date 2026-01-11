# Ruby in the Modern Frontend Ecosystem

A Vite-native approach that makes Ruby a first-class language in the standard frontend toolchain.

## Strategic Context

**Vite is not just a build tool—it's the infrastructure standard for modern frontend development.**

| Framework | Vite Status |
|-----------|-------------|
| Vue 3 / Nuxt 3 | Default (same creator) |
| Svelte / SvelteKit | Default |
| Astro | Built on Vite |
| Solid / SolidStart | Default |
| Qwik | Default |
| Remix | Migrated to Vite |
| Preact | Official preset |
| Lit | Recommended |

The notable exception is Next.js (uses Turbopack). But for the broader ecosystem, **Vite is the common denominator**.

**This plan is about committing to Vite as the foundation**, not adding it as a feature.

---

## The New Vision

### Juntos = ruby2js-rails + Vite Preset

Juntos is not a separate build system. It's a configuration pattern for Vite.

```javascript
// vite.config.js
import { juntos } from 'ruby2js-rails/vite';

export default juntos({
  database: 'dexie',
  target: 'browser'
});
```

The `juntos()` preset provides:
- Ruby file transformation (via `vite-plugin-ruby2js`)
- Rails structural transforms (models, controllers, views, routes)
- Platform-specific output (browser, Node, Electron, Capacitor, edge)
- HMR for Stimulus controllers

### CLI Becomes Thin

| Command | What it does |
|---------|--------------|
| `juntos dev` | `npx vite` |
| `juntos build` | `npx vite build` |
| `juntos db:migrate` | Runs migrations via `ruby2js-rails` |
| `juntos deploy` | `vite build` + platform CLI |

Users who want to eject just copy `vite.config.js` and use Vite directly.

### Build Targets

The `--target` flag configures output for different platforms:

```bash
juntos dev --target electron     # Vite + Electron
juntos build --target capacitor  # Web assets for mobile
juntos deploy --target vercel    # Edge deployment
```

**Target categories:**

| Category | Targets | CLI Flow |
|----------|---------|----------|
| **Browser** | `browser` (default) | `juntos dev` → `juntos build` → static hosting |
| **PWA** | `pwa` | `juntos build -t pwa` → installable, offline-first |
| **Server** | `node`, `bun`, `deno` | `juntos dev` → `juntos build` → `juntos up` |
| **Desktop** | `electron`, `tauri` | `juntos dev -t electron` → `juntos build -t electron` → packaging |
| **Mobile** | `capacitor` | `juntos dev` → `juntos build -t capacitor` → `cap sync` → Xcode/Android Studio |
| **Edge** | `vercel`, `cloudflare`, `deno-deploy`, `fly` | `juntos build` → `juntos deploy -t <target>` |

**Desktop (Electron):**

```bash
# Development: Vite dev server + Electron
juntos dev --target electron -d sqlite

# Production: Build + package
juntos build --target electron -d sqlite
npx electron-builder  # User runs packaging
```

Vite handles both renderer (web) and main (Node) processes. Database options: `sqlite` (better-sqlite3), `dexie`, or remote (Neon, Turso).

**Mobile (Capacitor):**

```bash
# Development: Browser-based, then test on device
juntos dev -d dexie
npx cap run ios  # When ready to test native

# Production: Build + sync + app store
juntos build --target capacitor -d dexie
npx cap sync
# Open Xcode/Android Studio for final build
```

Capacitor wraps the web build in a native container. Database options: `dexie` (IndexedDB), SQLite plugin, or remote.

**Desktop (Tauri):**

```bash
# Development: Vite + Tauri
juntos dev --target tauri -d sqlite

# Production: Build + package
juntos build --target tauri -d sqlite
npx tauri build  # Produces .dmg, .msi, .AppImage
```

Tauri is a Rust-based alternative to Electron with smaller binaries (~10MB vs ~150MB) and better security. Uses the OS webview instead of bundling Chromium.

**PWA (Progressive Web App):**

```bash
# Build with PWA support
juntos build --target pwa -d dexie

# Result: installable, works offline
```

Uses `vite-plugin-pwa` to generate service workers, manifest, and offline support. Ideal for the offline-first use case from the original vision:

> "When hotel wifi inevitably fails mid-event, scoring continues."

Database options: `dexie` (IndexedDB) or `sqljs` (SQLite in WASM) for full offline support.

**Edge (Serverless):**

```bash
# Cloudflare Workers
juntos deploy --target cloudflare -d d1

# Vercel Edge
juntos deploy --target vercel -d neon
```

See `lib/ruby2js/cli/deploy.rb` for full deploy implementation.

### Testing with Vitest

Vitest is Vite-native testing. Ruby tests use the same transform pipeline as app code.

```ruby
# spec/models/article_spec.rb
describe Article do
  it "validates presence of title" do
    article = Article.new(title: "")
    expect(article).not_to be_valid
  end
end
```

```bash
juntos test                    # Runs Vitest
juntos test --coverage         # With coverage (maps to Ruby source)
```

**Filter rename:** The existing `jest` filter becomes `vitest` (Jest noted as compatible in docs).

**Mock support to add:**

```ruby
# Ruby (RSpec-style)
callback = double("callback")
allow(callback).to receive(:call).and_return(42)

# Vitest output
const callback = vi.fn().mockReturnValue(42);
```

**Vite config integration:**

```javascript
// The juntos preset includes Vitest defaults
export function juntos(options) {
  return {
    // ... app config
    test: {
      include: ['**/*.{test,spec}.rb'],
      // Ruby files use same transform pipeline
    }
  };
}
```

### Why This Works Now

The JavaScript builder (`packages/ruby2js-rails/build.mjs`) is:
- **Complete** — handles models, controllers, views, routes, migrations
- **Verified** — CI smoke tests confirm identical output to Ruby version
- **Tested** — runs against real Rails apps (blog, chat) with multiple databases

Layer 2 (structural transforms) isn't "needs porting" — it's done.

---

## Package Structure

Three npm packages (published as tarballs, later to npm):

| Package | Contents | Status |
|---------|----------|--------|
| `ruby2js` | Core transpiler, Prism WASM, filters | Exists |
| `ruby2js-rails` | Runtime + build.mjs + Vite preset | Exists (needs preset) |
| `vite-plugin-ruby2js` | Thin plugin: .rb → .js | Built (Phase 1 complete) |

### Dependency Graph

```
juntos app (user's project)
  └── ruby2js-rails
        ├── ruby2js-rails/vite (juntos preset)
        │     └── vite-plugin-ruby2js
        │           └── ruby2js
        └── ruby2js-rails/runtime (ActiveRecord, adapters, etc.)
```

---

## Implementation Phases

### Phase 1: Core Vite Plugin ✅ Complete

**Delivered:** `packages/vite-plugin-ruby2js/`

| Component | Status |
|-----------|--------|
| Core plugin (`.rb` → `.js` transformation) | ✅ Done |
| Rails preset (stimulus, erb filters) | ✅ Done |
| Source maps | ✅ Done |
| HMR for Stimulus controllers | ✅ Done |
| Tests (12 passing) | ✅ Done |
| Example project | ✅ Done |

```javascript
// Works today
import ruby2js from 'vite-plugin-ruby2js';
import { rails } from 'vite-plugin-ruby2js/presets/rails';

export default defineConfig({
  plugins: [ruby2js()]  // or rails()
});
```

### Phase 2: Juntos Vite Preset

**Goal:** Add `juntos()` preset to `ruby2js-rails` that wraps `build.mjs`.

| Task | Description |
|------|-------------|
| Create `ruby2js-rails/vite.mjs` | Export `juntos()` preset function |
| Wire structural transforms | Call `build.mjs` functions from Vite hooks |
| Generate platform config | Output correct entry points for target |
| Update CLI | Make `juntos dev` → `vite`, `juntos build` → `vite build` |
| Add .rbx support | Recognize `.rbx` extension, apply React filter |

**Proving ground:** The workflow demo (`demo/workflow-builder/`) exercises:
- Models, controllers, views, routes
- RBX files (Ruby + JSX) with React/ReactFlow
- Database integration

This provides a real React app to validate against.

**The preset does what `juntos build` does today, but as Vite plugins:**

```javascript
// ruby2js-rails/vite.mjs
import ruby2js from 'vite-plugin-ruby2js';
import { SelfhostBuilder } from './build.mjs';

export function juntos(options = {}) {
  const builder = new SelfhostBuilder(null, options);

  return [
    ruby2js({ filters: ['Stimulus', 'Functions', 'ESM', 'Return'] }),

    {
      name: 'juntos-structure',
      buildStart() {
        // Transform models, controllers, views, routes
        builder.transformStructure();
      }
    },

    {
      name: 'juntos-config',
      config() {
        return {
          build: {
            rollupOptions: builder.getRollupOptions()
          }
        };
      }
    }
  ];
}
```

### Phase 3: Publish Tarballs

| Tarball | Contents |
|---------|----------|
| `vite-plugin-ruby2js-beta.tgz` | Core Vite plugin |
| `ruby2js-rails-beta.tgz` | Updated with Vite preset |

Update documentation to show Vite-first approach.

### Phase 4: Framework SFC Presets

Once the Rails/Juntos pattern is solid, add presets for Single File Components:

| Preset | Description | Priority |
|--------|-------------|----------|
| Vue | `<script lang="ruby">` in `.vue` files | Medium |
| Svelte | `<script lang="ruby">` in `.svelte` files | Medium |
| Astro | Ruby frontmatter (`#!ruby`) in `.astro` files | Medium |

These are thin (~40 lines each) — detect `lang="ruby"`, transform, pass to framework plugin.

**Note:** Basic `.rbx` support (Ruby + JSX) is in Phase 2. Phase 4 is about parsing framework-specific SFC formats and extracting Ruby script blocks.

---

## Future: Extensibility

### Phase 5: Extract Shared Infrastructure

After Rails is solid, refactor for other Ruby frameworks:

```
ruby2js-runtime (new shared package)
├── adapters/          # Dexie, SQLite, Neon, D1, etc.
├── query-builder/     # SQL generation, chainable API
├── templates/         # ERB, Haml compilation
└── vite/              # Base plugin, common hooks

ruby2js-rails (becomes thin)
├── active-record.js   # AR wrapper using runtime/adapters
├── conventions.js     # Rails file locations, naming
├── routes-parser.js   # routes.rb DSL
└── vite-preset.js     # Rails-specific Vite config
```

### Phase 6: Prove with Second Framework

Validate the extraction by supporting Hanami:

```
ruby2js-hanami
├── repository.js      # Repository pattern using runtime/adapters
├── conventions.js     # Hanami file locations
├── routes-parser.js   # Hanami routing DSL
└── vite-preset.js     # Hanami-specific Vite config
```

If the shared infrastructure is well-designed, Hanami support should be ~500-1000 lines of framework-specific code.

---

## Ruby Detection Strategy

A Juntos application can mix JavaScript, TypeScript, and Ruby components.

| Context | Ruby Signal | Example |
|---------|-------------|---------|
| Standalone file | File extension | `.rb`, `.rbx` |
| Vue `<script>` | `lang` attribute | `<script lang="ruby">` |
| Svelte `<script>` | `lang` attribute | `<script lang="ruby">` |
| Astro frontmatter | Shebang | `#!ruby` |

See [Ruby Detection Strategy](#appendix-ruby-detection-examples) appendix for examples.

---

## Success Criteria

### Phase 2 (Juntos Preset)
1. `juntos dev` starts Vite with full Rails app transformation
2. `juntos build` produces deployable output via Vite
3. Existing blog/chat demos work unchanged
4. CI smoke tests pass with Vite-based build
5. `juntos dev --target electron` runs Vite + Electron together
6. `juntos build --target capacitor` produces assets for `cap sync`
7. `juntos test` runs Vitest with Ruby specs

### Phase 4 (Framework Presets)
8. React components can be authored in Ruby
9. Vue SFCs accept `<script lang="ruby">`
10. Astro frontmatter accepts `#!ruby`

### Phase 6 (Extensibility)
11. Hanami app works with extracted shared infrastructure
12. Framework-specific code is <1000 lines

---

## Migration Path

### For Existing Juntos Apps

No breaking changes. The CLI commands work the same:

```bash
# Before (custom build system)
juntos dev    # → ruby2js-rails-dev
juntos build  # → SelfhostBuilder

# After (Vite foundation)
juntos dev    # → vite
juntos build  # → vite build
```

The difference is internal — Vite runs the show, Juntos is the configuration.

### For Users Who Want Control

```bash
# Eject to pure Vite
cp node_modules/ruby2js-rails/vite-template.config.js vite.config.js
# Now it's just a Vite project
npx vite
```

---

## Open Questions

1. **Caching**: Disk cache for faster cold starts? Vite has built-in caching; may be sufficient.

2. **IDE support**: Syntax highlighting for Ruby in Vue/Svelte SFCs? Possible via VS Code language injection.

3. **Structural transform timing**: Should models/controllers/views transform on each file change, or batch? Need to test performance.

---

## Appendix: Ruby Detection Examples

### Vue with Ruby

```vue
<script setup lang="ruby">
count = ref(0)

def increment
  count.value += 1
end
</script>

<template>
  <button @click="increment">{{ count }}</button>
</template>
```

### Svelte with Ruby

```svelte
<script lang="ruby">
count = 0

def increment
  count += 1
end
</script>

<button on:click={increment}>{count}</button>
```

### Astro with Ruby Frontmatter

```astro
---
#!ruby
posts = await fetch_posts()
featured = posts.select { |p| p.featured? }.first(3)
---

<Layout>
  {featured.map { |post| <Card post={post} /> }}
</Layout>
```

---

## References

### Packages
- `packages/vite-plugin-ruby2js/` — Core Vite plugin (Phase 1 complete)
- `packages/ruby2js-rails/` — Rails runtime + build.mjs
- `demo/selfhost/` — Selfhost transpiler source

### CI Verification
- `.github/workflows/ci.yml` — `demo-test` job runs smoke tests
- `test/smoke-test.mjs` — Compares Ruby vs JS builder output

### Related Plans
- [UNIFIED_VIEWS.md](./UNIFIED_VIEWS.md) — Multi-framework view targeting
- [HOTWIRE_TURBO.md](./HOTWIRE_TURBO.md) — Stimulus/Turbo integration
