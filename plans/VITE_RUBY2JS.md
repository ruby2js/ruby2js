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

### Phase 2: Juntos Vite Preset ✅ Complete

**Delivered:** `packages/ruby2js-rails/vite.mjs`

| Component | Status |
|-----------|--------|
| `juntos()` preset function | ✅ Done |
| Structural transforms via SelfhostBuilder | ✅ Done |
| Platform-specific Rollup config | ✅ Done |
| `.rbx` support (React filter) | ✅ Done |
| Stimulus HMR | ✅ Done |
| Documentation | ✅ Done |

```javascript
// Works today
import { juntos } from 'ruby2js-rails/vite';

export default juntos({
  database: 'dexie',
  target: 'browser'
});
```

**Proving ground:** The workflow demo (`test/workflow/`) exercises:
- Models, controllers, views, routes
- RBX files (Ruby + JSX) with React/ReactFlow
- Database integration

### Phase 2b: CLI Integration ✅ Complete

Make the Juntos CLI a thin wrapper around Vite. Vite is now the default—no flags needed.

| Task | Status |
|------|--------|
| Update `juntos dev` | ✅ Auto-detects vite.config.js |
| Update `juntos build` | ✅ Auto-detects vite.config.js |
| Generate vite.config.js | ✅ Created by `juntos install` |
| Vite middleware mode | ✅ SSR dev server for Node targets |

**Design:** Presence of `dist/vite.config.js` determines Vite vs legacy mode. Delete the file to opt out.

**Note:** Database commands (`juntos db:migrate`, `juntos db:seed`) remain unchanged.

**Vite Middleware Mode (Node Server Targets):**

For `--target node` (and similar server targets), use Vite's middleware mode instead of standalone dev server. This enables instant server-side updates without rebuilding:

```javascript
// juntos dev --target node
import express from 'express';
import { createServer as createViteServer } from 'vite';

const app = express();

const vite = await createViteServer({
  server: { middlewareMode: true },
  appType: 'custom'
});

app.use(vite.middlewares);  // HMR client, asset transforms

app.get('*', async (req, res) => {
  // ssrLoadModule: transforms Ruby → JS on-demand, caches until file changes
  const { Application } = await vite.ssrLoadModule('/dist/application.js');
  const html = await Application.render(req);
  res.send(html);
});
```

| Component | Purpose |
|-----------|---------|
| `middlewareMode` | Vite runs inside the app server |
| `ssrLoadModule` | Loads server modules on-demand, invalidates on file change |
| `transformIndexHtml` | Injects HMR client into HTML responses |

This follows the same pattern used by Remix, SvelteKit, and other SSR frameworks.

### Phase 2c: HMR for Structural Changes (Partial ✅)

Extend HMR beyond Stimulus controllers. Easy wins implemented; full dependency tracking deferred.

| File Type | HMR Behavior | Status |
|-----------|--------------|--------|
| Stimulus (`.rb`) | Hot swap via custom event | ✅ Done |
| View (`.rbx`) | React HMR | ✅ Done (Vite default) |
| View (`.html.erb`) | Vite module invalidation | ✅ Done (Vite default) |
| Plain Ruby (`.rb`) | Vite module invalidation | ✅ Done (Vite default) |
| Model (`.rb`) | Full reload | ✅ Done (safe fallback) |
| Rails Controller (`.rb`) | Full reload | ✅ Done (safe fallback) |
| Routes (`routes.rb`) | Full reload | ✅ Done (safe fallback) |

**What's implemented:** Models, Rails controllers, and routes trigger full page reload. Everything else uses Vite's default HMR (module invalidation).

**Deferred:** Full incremental HMR for models/controllers/routes would require dependency tracking to know what else to invalidate. Current approach is safe and fast enough for most workflows.

### Phase 3: Publish Tarballs ✅ Complete

| Tarball | URL |
|---------|-----|
| `ruby2js-beta.tgz` | `https://www.ruby2js.com/releases/ruby2js-beta.tgz` |
| `vite-plugin-ruby2js-beta.tgz` | `https://www.ruby2js.com/releases/vite-plugin-ruby2js-beta.tgz` |
| `ruby2js-rails-beta.tgz` | `https://www.ruby2js.com/releases/ruby2js-rails-beta.tgz` |

Added `:vite_plugin_tarball` task to `docs/Rakefile`. All three tarballs are built during `rake npm_packages` and deployed to ruby2js.com.

### Phase 3b: Docker/Node Target Verification ✅ Complete

**Verified:** Full Docker build with `--target node --database sqlite` works end-to-end.

| Component | Status |
|-----------|--------|
| Vite respects `JUNTOS_TARGET` env var | ✅ Fixed (env vars override vite.config.js) |
| Server-side build target (`node18`) | ✅ Added (enables top-level await) |
| Rollup input path for server.mjs | ✅ Fixed (points to node_modules) |
| `emptyOutDir: false` preserves node_modules | ✅ Added |
| Hotwire packages externalized | ✅ Added (@hotwired/stimulus, turbo) |
| Docker build + db prepare + server start | ✅ Verified |

**Test workflow:**
```bash
cd test/blog
docker build -t ruby2js-blog .
docker run -p 3000:3000 ruby2js-blog
# Server runs at http://localhost:3000 with seeded data
```

**Key fixes applied:**
- `loadConfig()` now checks `process.env.JUNTOS_TARGET` before `overrides.target`
- Spread order fixed so calculated values aren't overwritten
- `getBuildTarget()` returns `node18` for server targets (supports top-level await)
- Server entry point: `node_modules/ruby2js-rails/server.mjs`

### Phase 4: Production Asset Pipeline (Planned)

Rails-equivalent of `assets:precompile` — client-side bundling, tree shaking, and fingerprinting for production deployments.

**Current state (import maps):**
```html
<script type="importmap">
  { "imports": { "@hotwired/turbo": "/node_modules/..." } }
</script>
<script type="module">
  import * as Turbo from '@hotwired/turbo';
</script>
```

**Target state (bundled):**
```html
<script type="module" src="/assets/app-Bx7K3j2F.js"></script>
```

| Task | Description | Status |
|------|-------------|--------|
| Conditional index.html | Import maps for dev, bundled script for prod | Planned |
| Client-side Vite build | Bundle JS for browser targets in production | Planned |
| Tree shaking | Remove unused code from Turbo/Stimulus | Planned |
| Asset fingerprinting | Content-hash filenames (like Sprockets/Propshaft) | Planned (Vite built-in) |
| CSS bundling | Include Tailwind in Vite pipeline | Planned |
| Manifest generation | Map logical names to fingerprinted paths | Planned (Vite built-in) |

**Implementation approach:**

1. **Environment detection** — Check `NODE_ENV=production` or `--mode production`

2. **Template index.html differently:**
   ```javascript
   // vite.mjs - transformIndexHtml hook
   transformIndexHtml(html, { mode }) {
     if (mode === 'production') {
       // Remove importmap, Vite injects bundled scripts
       return html.replace(/<script type="importmap">.*?<\/script>/s, '');
     }
     return html;
   }
   ```

3. **Enable Vite bundling for browser production:**
   ```javascript
   // getRollupOptions for browser + production
   case 'browser':
     return {
       input: 'index.html',
       // Vite automatically bundles, tree-shakes, fingerprints
     };
   ```

4. **CLI integration:**
   ```bash
   juntos build                    # Development (import maps)
   juntos build --mode production  # Production (bundled)
   juntos assets:precompile        # Alias for production build
   ```

**Benefits over import maps:**
- Smaller payloads (tree shaking removes unused code)
- Fewer HTTP requests (bundled chunks)
- Aggressive caching (fingerprinted filenames)
- Minification

**Trade-offs:**
- Build step required
- Slower builds
- More complex debugging (source maps help)

### Phase 4b: Source File Watching (Bridge)

As an interim step toward the ultimate architecture, add source file watching to enable HMR when editing original source files.

**Current limitation:** Vite runs from `dist/`, so editing original source doesn't trigger HMR.

**Bridge solution:**
1. Vite plugin watches original source directory (via `appRoot`)
2. On file change, re-transpile just that file to dist/
3. Vite picks up the dist/ change and does HMR

```javascript
// In configureServer hook
server.watcher.add(path.join(appRoot, 'app'));
server.watcher.on('change', async (file) => {
  if (file.startsWith(appRoot) && file.endsWith('.rb')) {
    await transpileFile(file, distDir);
    // Vite automatically picks up dist/ change
  }
});
```

This maintains the current architecture while providing good DX.

---

## Ultimate Architecture: TypeScript Model

The long-term vision is to make Ruby2JS work like TypeScript + Vite:

| TypeScript | Ruby2JS |
|------------|---------|
| Source is `.ts` | Source is `.rb`, `.rbx`, `.erb` |
| Vite transforms via esbuild (fast JS compiler) | Vite transforms via selfhost transpiler |
| `tsc` exists but not required for dev | Ruby transpiler exists but not required for dev |
| `dist/` is production output only | `dist/` is production output only |

### Current vs Ultimate Directory Structure

**Current (dist/ as working directory):**
```
my-app/
├── app/                    # Original source
│   ├── models/
│   ├── controllers/
│   └── views/
├── config/
│   ├── database.yml
│   └── routes.rb
├── dist/                   # Working directory (problematic)
│   ├── vite.config.js      # ❌ Should be in project root
│   ├── package.json        # ❌ Should be in project root
│   ├── node_modules/       # ❌ Should be in project root
│   ├── app/                # Transpiled copies
│   └── lib/                # Runtime (copied)
```

**Ultimate (source-first, like TypeScript):**
```
my-app/
├── app/                    # Source (Vite serves directly)
│   ├── models/*.rb
│   ├── controllers/*.rb
│   └── views/*.erb, *.rbx
├── config/
│   ├── database.yml
│   └── routes.rb
├── vite.config.js          # ✅ Project root
├── package.json            # ✅ Project root
├── node_modules/           # ✅ Project root
└── dist/                   # Output only (gitignored)
    └── assets/             # Bundled production assets
```

### Files That Should Move to Project Root

| File | Current Location | Ultimate Location | Reason |
|------|------------------|-------------------|--------|
| `vite.config.js` | `dist/` | Project root | Standard Vite convention |
| `package.json` | `dist/` | Project root | Standard npm convention |
| `node_modules/` | `dist/` | Project root | Standard npm convention |
| `index.html` | `dist/` | Project root or `public/` | Vite convention |
| `tailwind.config.js` | `dist/` | Project root | Standard Tailwind convention |

### Files That Stay in dist/ (Output Only)

| File | Purpose |
|------|---------|
| `assets/*.js` | Bundled, fingerprinted JavaScript |
| `assets/*.css` | Bundled, fingerprinted CSS |
| `index.html` | Production HTML with asset references |

### Runtime Files Strategy

**Current:** Runtime (`lib/active_record.mjs`, adapters, etc.) copied to `dist/lib/`.

**Ultimate:** Runtime installed as npm package, imported directly:
```javascript
// In transpiled output
import { ActiveRecord } from 'ruby2js-rails/runtime';
```

No copying needed—Vite resolves from `node_modules/`.

### Migration Path to Ultimate Architecture

1. **Phase 4b (now):** Source watching as bridge—current architecture, good DX
2. **Selfhost parity:** Complete JavaScript transpiler to match Ruby transpiler
3. **Vite plugin transformation:** Plugin uses selfhost for on-the-fly `.rb` → `.js`
4. **Move config files:** `vite.config.js`, `package.json` to project root
5. **Remove dist/ copying:** Vite serves source directly, dist/ is output only

### Build Output Philosophy: No Intermediate Directory

**Current problem:** `juntos build -f astro` generates an intermediate Astro project into `dist/`, which then builds into `dist/dist/`. This nested structure is confusing.

**Target philosophy:** `juntos build` produces only deployable output. The intermediate project structure (Astro's `src/`, `astro.config.mjs`, etc.) should be hidden by default.

```bash
# Current (confusing)
juntos build -f astro
# Result: dist/ contains full Astro project, dist/dist/client/ is deployable

# Ultimate (clean)
juntos build -f astro
# Result: dist/ contains only deployable files (index.html, browser-worker.mjs, etc.)
```

**Implementation approach:** Run the entire pipeline (generate Astro project → npm install → astro build → esbuild bundle) in a temp directory, then copy only the final output to `dist/`.

### The `juntos eject` Command

For users who want to customize the intermediate project (modify Astro config, add plugins, etc.), provide an eject command:

```bash
juntos eject -f astro
# Result: astro/ directory with full Astro project source
```

After ejecting:
- User owns the intermediate project
- Can modify `astro.config.mjs`, add Astro plugins, customize layouts
- Runs `npm run build` directly instead of `juntos build`

**Eject is one-way:** Once ejected, the user maintains the project. Similar to Create React App's eject model, but less destructive since the original Rails source remains untouched.

### Framework Conversion vs Build Targets

Two orthogonal dimensions:

| Dimension | Flag | Examples |
|-----------|------|----------|
| **Framework** | `-f` | `astro`, `vue`, `svelte` (output project structure) |
| **Target** | `-t` | `browser`, `node`, `cloudflare` (runtime environment) |

```bash
# Same Rails app, different output frameworks
juntos build -f astro -t browser     # Astro with IndexedDB
juntos build -f astro -t cloudflare  # Astro with D1
juntos build -f vue -t browser       # Vue SPA with IndexedDB
juntos build -f svelte -t node       # SvelteKit with SQLite

# Default: Rails-native output
juntos build -t browser              # Juntos runtime, no framework conversion
```

When `-f` is specified, the intermediate project uses that framework's conventions (Astro's file-based routing, Vue's SFCs, etc.). When omitted, uses Juntos-native patterns.

### Selfhost Transpiler Requirements

For the ultimate architecture, the selfhost transpiler must handle:

| Category | Status |
|----------|--------|
| Core Ruby syntax | ✅ Complete |
| Functions filter | ✅ Complete |
| ESM filter | ✅ Complete |
| React filter | ✅ Complete |
| ERB compilation | ✅ Complete (`ErbCompiler.js` + `erb.js` filter) |
| Rails helpers filter | ✅ Complete (`rails/helpers.js`) |
| Stimulus filter | 🔄 In progress |
| Rails model filter | 🔄 In progress |
| Rails controller filter | 🔄 In progress |

Once these filters work in JavaScript, the Vite plugin can transform on-the-fly without pre-building.

---

### Phase 5: Framework SFC Presets

Once the Rails/Juntos pattern is solid, add presets for Single File Components:

| Preset | Description | Priority |
|--------|-------------|----------|
| Vue | `<script lang="ruby">` in `.vue` files | Medium |
| Svelte | `<script lang="ruby">` in `.svelte` files | Medium |
| Astro | Ruby frontmatter (`#!ruby`) in `.astro` files | Medium |

These are thin (~40 lines each) — detect `lang="ruby"`, transform, pass to framework plugin.

**Note:** Basic `.rbx` support (Ruby + JSX) is in Phase 2. Phase 5 is about parsing framework-specific SFC formats and extracting Ruby script blocks.

---

## Future: Extensibility

### Phase 6: Extract Shared Infrastructure

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

### Phase 7: Prove with Second Framework

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

### Phase 2 (Juntos Preset) ✅
1. `juntos()` preset returns working Vite plugin array
2. Structural transforms (models, controllers, views, routes) run in buildStart
3. `.rbx` files (Ruby + JSX) work with React filter
4. Platform-specific Rollup config generated for each target
5. Stimulus HMR works for controller changes
6. Documentation covers preset usage

### Phase 2b (CLI Integration)
7. `juntos dev` starts Vite with full Rails app transformation
8. `juntos build` produces deployable output via Vite
9. `juntos dev --target electron` runs Vite + Electron together
10. `juntos build --target capacitor` produces assets for `cap sync`
11. `juntos test` runs Vitest with Ruby specs

### Phase 2c (Full HMR)
12. Model changes trigger HMR without page reload
13. Controller changes update route handlers via HMR
14. ERB view changes trigger HMR
15. RBX component changes trigger React HMR
16. Route file changes regenerate routes.js via HMR

### Phase 4 (Production Asset Pipeline)
17. `juntos build --mode production` bundles client JS
18. Tree shaking removes unused Turbo/Stimulus code
19. Asset fingerprinting produces content-hashed filenames
20. `juntos assets:precompile` works as alias

### Phase 5 (Framework SFC Presets)
21. Vue SFCs accept `<script lang="ruby">`
22. Astro frontmatter accepts `#!ruby`

### Phase 7 (Extensibility)
23. Hanami app works with extracted shared infrastructure
24. Framework-specific code is <1000 lines

---

## Migration Path

### Use Vite Directly (Available Now)

Create a `vite.config.js` and use Vite commands:

```javascript
// vite.config.js
import { juntos } from 'ruby2js-rails/vite';

export default juntos({
  database: 'dexie',
  target: 'browser'
});
```

```bash
npx vite          # Development
npx vite build    # Production
```

The Juntos CLI continues to work unchanged for database commands:
```bash
bin/juntos db:migrate
bin/juntos db:seed
```

### After Phase 2b (CLI Integration)

Once Phase 2b is complete, the CLI becomes a thin wrapper:

```bash
# These will run Vite internally
juntos dev    # → npx vite
juntos build  # → npx vite build
```

No breaking changes — same commands, Vite foundation underneath.

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
