# Plan: SFC Triple-Target Demo

## Goal

Transpile the Rails blog demo to three SFC frameworks (Astro, Vue, Svelte), proving the mechanical transformation principle from VISION.md.

---

## Prerequisites: Vite-Native Architecture (Jan 2026)

**This plan was paused** while the Juntos build system was refactored to be "Vite-native." That work is now complete. See `plans/vite-native-cleanup.md` for details.

### What Changed

The old architecture used a `.juntos/` staging directory with pre-compiled files. The new architecture uses Vite's plugin system for on-the-fly transformation:

| Before (Pre-compiled) | After (Vite-native) |
|-----------------------|---------------------|
| `.juntos/app/models/*.js` | Virtual module `juntos:models` + on-the-fly `.rb` transformation |
| `.juntos/config/routes.js` | On-the-fly transformation of `config/routes.rb` |
| `.juntos/lib/rails.js` | Virtual module `juntos:rails` |
| `.juntos/lib/active_record.mjs` | Virtual module `juntos:active-record` |
| `.juntos/db/migrate/*.js` | Virtual module `juntos:migrations` + on-the-fly transformation |
| `.juntos/app/views/**/*.js` | Virtual module `juntos:views/*` + on-the-fly ERB transformation |

### Infrastructure Now Available

The following Vite plugins handle all transformation at dev/build time:

1. **`juntos-ruby`** - Transforms `.rb` files to JavaScript on-the-fly
   - Uses selfhost Ruby2JS transpiler (JavaScript-based)
   - Applies Rails filters for models, controllers, routes, migrations, seeds

2. **`juntos-erb`** - Transforms `.erb` files to JavaScript on-the-fly
   - Parses ERB templates
   - Currently outputs JSX-like render functions
   - **Key for SFC work**: Could be extended to output Astro/Vue/Svelte templates

3. **`juntos-virtual`** - Provides virtual modules
   - `juntos:rails` - Target-specific runtime (browser, node, cloudflare)
   - `juntos:active-record` - Database adapter with injected config
   - `juntos:models` - Registry of all model classes
   - `juntos:migrations` - Registry of all migrations
   - `juntos:views/*` - Unified view exports per resource
   - `juntos:application-record` - Base class for models

4. **Selfhost Ruby2JS** - The transpiler itself runs in JavaScript
   - Located in `demo/selfhost/`
   - Used by Vite plugins for on-the-fly transformation
   - No Ruby runtime needed at build time

### How This Enables SFC Triple-Target

**Models are framework-agnostic**: The `juntos:models` virtual module and Ruby model transformation work regardless of target framework. Astro/Vue/Svelte apps can use the same Ruby models.

**ERB transformation is the key extension point**: The `juntos-erb` plugin already parses ERB and outputs JavaScript. For SFC frameworks:
- Same parsing logic
- Different output generators: `generateAstro()`, `generateVue()`, `generateSvelte()`

**Virtual modules can be framework-aware**: The `juntos:rails` virtual module already selects runtime by target (browser/node/cloudflare). It could also select by framework.

**The Vite plugin accepts options**: `juntos({ database, target, ... })` could accept a `framework` option:
```javascript
// vite.config.js for Astro output
export default defineConfig({
  plugins: juntos({ framework: 'astro' })
});
```

### Recommended Approach for Stage 1 (Updated)

Instead of building a separate Ruby-based transpiler (`astro_builder.rb`), extend the Vite-native infrastructure:

1. **Add output format generators to `juntos-erb`**:
   - `generateJsx()` (current)
   - `generateAstroTemplate()`
   - `generateVueTemplate()`
   - `generateSvelteTemplate()`

2. **Add `framework` option to `juntos()` plugin**:
   - Changes ERB output format
   - Changes file structure expectations
   - Changes entry point generation

3. **Create framework-specific project generators** (for `juntos convert`):
   - Generate `astro.config.mjs`, `package.json`, file structure
   - Similar to current deploy entry point generators

This approach:
- Reuses all existing transformation infrastructure
- Keeps everything in JavaScript (no Ruby runtime needed)
- Works with Vite's dev server for hot reload during development
- Is consistent with the "Vite-native" philosophy

### Files to Understand

Before resuming work, review these key files:

| File | Purpose |
|------|---------|
| `packages/ruby2js-rails/vite.mjs` | Main Vite plugin with all transformation logic |
| `packages/ruby2js-rails/rails_base.js` | Base runtime (Router, Application, helpers) |
| `packages/ruby2js-rails/targets/*/rails.js` | Target-specific runtimes |
| `packages/ruby2js-rails/adapters/*.mjs` | Database adapters (Dexie, D1, SQLite, etc.) |
| `demo/selfhost/ruby2js.mjs` | Selfhost transpiler entry point |
| `lib/ruby2js/erb_to_jsx.rb` | Ruby ERB→JSX compiler (reference for JS port) |

---

## Approach

**Stage 0**: Hand-craft target applications equivalent to the Rails blog (using ruby2js-rails infrastructure)
**Stage 1**: Build transpiler that produces Stage 0 output from Rails source (real-time included via model broadcasts)
**Stage 2**: Expand target/database combinations

---

## Key Architectural Insight: Worker-in-Browser Pattern

**Discovery (Jan 2026)**: Edge functions (Cloudflare Workers, Vercel Edge) use standard Web APIs (`Request` → `Response`) - the same APIs available in browsers. This means:

1. **Same code runs everywhere**: Build for Cloudflare → runs on edge OR in browser
2. **Turbo provides the glue**: Same event hooks (`turbo:before-fetch-request`) that work for Rails work for any edge worker
3. **No architectural split**: Instead of separate browser (SPA/islands) vs server (SSR) architectures, use ONE architecture

### Proof of Concept Results

- Astro SSR builds to Cloudflare Worker (`_worker.js`)
- Worker can be bundled for browser (~530KB with esbuild)
- Only two shims needed: `cloudflare:workers` (empty), `caches` (browsers have natively)
- Worker renders HTML correctly when called as a function
- Same Turbo integration pattern as Rails blog

### What This Changes

| Before | After |
|--------|-------|
| Browser target needs React islands for interactivity | Browser runs the SSR worker locally |
| Separate architectures for browser vs server | One architecture: edge SSR |
| Heavy client-side rendering for CRUD | Standard HTML with Turbo enhancement |
| Framework-specific browser adaptations | Generic worker-in-browser shim |

### The Pattern

```
┌─────────────────────────────────────────────────────────────┐
│  Turbo intercepts navigation/forms                          │
│                         │                                   │
│           ┌─────────────┴─────────────┐                    │
│           ▼                           ▼                    │
│   ┌───────────────┐           ┌───────────────┐           │
│   │ Edge Runtime  │           │ Browser       │           │
│   │ (Cloudflare)  │           │ (Worker-in-   │           │
│   │               │           │  browser)     │           │
│   │ worker.fetch()│           │ worker.fetch()│           │
│   └───────────────┘           └───────────────┘           │
│           │                           │                    │
│           ▼                           ▼                    │
│   ┌───────────────┐           ┌───────────────┐           │
│   │ D1 Database   │           │ IndexedDB     │           │
│   └───────────────┘           └───────────────┘           │
└─────────────────────────────────────────────────────────────┘

Same SSR code, same HTML output, same Turbo integration.
Only the database adapter changes.
```

### Implications for Stage 0

Instead of:
- Astro pages + React islands for browser interactivity
- Complex state management in islands
- Client-side data fetching

Use:
- Idiomatic Astro SSR (standard links, forms)
- Build for Cloudflare
- Browser target runs the worker locally with Turbo

This produces more idiomatic framework code and less custom infrastructure.

---

## Combination Triage (Revised)

### Dimensions

- **Framework (-f)**: astro, vue, svelte, rails
- **Target (-t)**: browser, node, cloudflare
- **Database (-d)**: dexie, sqlite3, d1

### Key Insight: Browser = Edge + Dexie

With the worker-in-browser pattern, the browser target is just the edge build running locally:
- **Build**: Target Cloudflare (produces `_worker.js`)
- **Runtime**: Worker runs in browser, Turbo intercepts navigation
- **Database**: Swap D1 → IndexedDB (Dexie)

This means browser and cloudflare targets share 95% of code.

### Priority Matrix (Revised)

#### Tier 1: Primary Focus

| Framework | Target | Database | Notes |
|-----------|--------|----------|-------|
| astro | cloudflare | d1 | Reference build - idiomatic SSR |
| astro | browser | dexie | Same worker, different DB adapter |
| rails | browser | dexie | Current behavior (baseline) |
| rails | node | sqlite3 | Current behavior (baseline) |

**Strategy**: Build Astro for Cloudflare first, then add browser shim.

#### Tier 2: Extend to Other Frameworks

| Framework | Target | Database | Notes |
|-----------|--------|----------|-------|
| svelte | cloudflare | d1 | SvelteKit cloudflare adapter |
| svelte | browser | dexie | Same worker-in-browser pattern |
| vue | cloudflare | d1 | Nuxt cloudflare adapter |
| vue | browser | dexie | Same worker-in-browser pattern |

Same pattern applies to all frameworks that target Cloudflare.

#### Tier 3: Node Targets

| Framework | Target | Database | Notes |
|-----------|--------|----------|-------|
| astro | node | sqlite3 | Astro node adapter |
| svelte | node | sqlite3 | SvelteKit node adapter |
| vue | node | sqlite3 | Nuxt node target |

Node targets use different adapters but same application code.

### Initial Scope (Revised)

**Stage 0 focuses on Astro + Cloudflare:**
1. Build idiomatic Astro SSR for Cloudflare
2. Add worker-in-browser shim with Turbo integration
3. Verify same app runs on edge AND in browser

This proves the pattern before extending to Vue/Svelte.

---

## Stage 0: Hand-Craft Equivalent Applications

### Goal

Create idiomatic SFC applications that match the Rails blog functionality:
- Articles: index, show, new, edit, delete
- Comments: nested under articles, create, delete
- Shared layout with navigation
- Standard HTML forms and links (Turbo-enhanced)
- Same database schema, different adapters per target

### 0.1 Astro Blog (Cloudflare Target)

Create `test/astro-blog-v3/` with idiomatic Astro SSR:

```
src/
├── layouts/
│   └── Layout.astro             # Main layout with Turbo
├── pages/
│   ├── index.astro              # Landing page
│   ├── about.astro              # Static about page
│   └── articles/
│       ├── index.astro          # Article list (SSR)
│       ├── new.astro            # New article form
│       ├── [id].astro           # Show article + comments
│       └── [id]/
│           └── edit.astro       # Edit article form
├── models/
│   ├── article.rb               # Ruby model (transpiled at build)
│   └── comment.rb               # Ruby model (transpiled at build)
└── lib/
    └── active_record.mjs        # Copied from ruby2js-rails/adapters
```

**Key approach: Reuse ruby2js-rails infrastructure**

Instead of writing new adapters and Turbo integration:
- **Models**: Ruby files, transpiled by ruby2js (same as Rails blog)
- **Adapters**: Import from `ruby2js-rails/adapters/` (Dexie, D1, SQLite)
- **Turbo integration**: Reuse pattern from `targets/browser/rails.js`
- **Flash messages**: Already handled by existing infrastructure

This means:
- No new Dexie adapter code needed
- No new Turbo event interception code needed
- Stage 1 transpiler only converts views/controllers (models stay Ruby)
- Same battle-tested infrastructure across Rails and Astro demos

### 0.1.1 Browser Shim

For browser target, reuse existing infrastructure:

```
browser/
├── bundle-for-browser.mjs       # esbuild bundler (already created)
└── boot.js                      # Initialize worker + Turbo interception
```

The boot script:
1. Imports bundled worker
2. Uses Turbo event interception pattern from ruby2js-rails
3. Adapter swap happens at build time (D1 → Dexie)

### 0.2 Vue Blog

Create `test/vue-blog/create-vue-blog`:

```
src/
├── App.vue.rb                  # Root component with router-view
├── layouts/
│   └── MainLayout.vue.rb       # Main layout
├── views/
│   ├── Home.vue.rb             # Landing page
│   ├── About.vue.rb            # Static about
│   └── articles/
│       ├── Index.vue.rb        # Article list
│       ├── Show.vue.rb         # Show + comments
│       ├── New.vue.rb          # New form
│       └── Edit.vue.rb         # Edit form
├── components/
│   ├── ArticleCard.vue.rb      # Article preview
│   ├── ArticleForm.vue.rb      # Shared form
│   ├── CommentList.vue.rb      # Comments
│   └── CommentForm.vue.rb      # Add comment
├── models/
│   ├── article.rb
│   └── comment.rb
├── router/
│   └── index.js                # Vue Router config
└── lib/
    └── db.js
```

### 0.3 Svelte Blog

Create `test/svelte-blog/create-svelte-blog`:

```
src/
├── routes/
│   ├── +layout.svelte.rb       # Main layout
│   ├── +page.svelte.rb         # Landing
│   ├── about/
│   │   └── +page.svelte.rb     # Static about
│   └── articles/
│       ├── +page.svelte.rb     # Article list
│       ├── new/
│       │   └── +page.svelte.rb # New form
│       └── [id]/
│           ├── +page.svelte.rb # Show + comments
│           └── edit/
│               └── +page.svelte.rb # Edit form
├── lib/
│   ├── components/
│   │   ├── ArticleCard.svelte.rb
│   │   ├── ArticleForm.svelte.rb
│   │   ├── CommentList.svelte.rb
│   │   └── CommentForm.svelte.rb
│   ├── models/
│   │   ├── article.rb
│   │   └── comment.rb
│   └── db.js
```

### Stage 0 Validation

Each app must:
- [ ] Build successfully (`npm run build`)
- [ ] Run in dev mode (`npm run dev`)
- [ ] Create, read, update, delete articles
- [ ] Create, delete comments on articles
- [ ] Persist data in IndexedDB (survives refresh)
- [ ] Use transpiled model classes (Article, Comment)

---

## Stage 1: Build the Transpiler

### Key Insight: Models Stay as Ruby

Since Astro (and Vue/Svelte) will use the same ruby2js-rails infrastructure:
- **Models**: Copy directly from Rails (`app/models/*.rb` → `src/models/*.rb`)
- **Adapters**: Already exist in ruby2js-rails package
- **Turbo/Flash**: Already working infrastructure

**The transpiler only needs to convert:**
1. Controllers → page frontmatter (data fetching)
2. Views (ERB) → framework templates (Astro/Vue/Svelte)
3. Routes → file-based routing structure

### 1.1 Add Framework Option to Vite Plugin

**Updated approach (Vite-native)**: Instead of a Ruby-based converter, extend the existing Vite plugin.

Update `packages/ruby2js-rails/vite.mjs`:

```javascript
export function juntos(options = {}) {
  const {
    appRoot = process.cwd(),
    database,
    target,
    framework = 'rails',  // NEW: 'rails', 'astro', 'vue', 'svelte'
  } = options;

  // Framework affects:
  // 1. ERB output format (JSX vs Astro vs Vue vs Svelte templates)
  // 2. File structure expectations
  // 3. Entry point generation
  // ...
}
```

### 1.2 Extend ERB Transformer for Multiple Output Formats

The `juntos-erb` plugin currently outputs JSX. Add framework-specific generators:

```javascript
// In vite.mjs or a new erb-transforms.mjs file

function transformErb(erbCode, options) {
  const ast = parseErb(erbCode);  // Shared parsing logic

  switch (options.framework) {
    case 'astro':
      return generateAstroTemplate(ast);
    case 'vue':
      return generateVueTemplate(ast);
    case 'svelte':
      return generateSvelteTemplate(ast);
    default:
      return generateJsx(ast);  // Current behavior
  }
}
```

### 1.3 Create Framework Project Generator

For `juntos convert --framework astro`, generate a complete project:

```javascript
// packages/ruby2js-rails/convert.mjs

export async function convertToFramework(sourceDir, outputDir, framework) {
  // 1. Generate framework config (astro.config.mjs, etc.)
  await generateFrameworkConfig(outputDir, framework);

  // 2. Copy models as-is (Ruby files, transpiled at build time)
  await copyModels(sourceDir, outputDir, framework);

  // 3. Convert views to framework templates
  await convertViews(sourceDir, outputDir, framework);

  // 4. Generate routes/pages from controllers
  await generatePages(sourceDir, outputDir, framework);

  // 5. Generate package.json with framework dependencies
  await generatePackageJson(outputDir, framework);
}
```

### 1.4 (Legacy) Ruby-based Converter

The existing `lib/ruby2js/rails/astro_builder.rb` (1,130 lines) can serve as a reference implementation, but the Vite-native approach is preferred for:
- Consistency with the rest of the build system
- Hot reload during development
- No Ruby runtime requirement at build time

### 1.3 Mapping Rules

#### Rails Controller → SFC

```ruby
# Rails: app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  def index
    @articles = Article.all
  end

  def show
    @article = Article.find(params[:id])
    @comments = @article.comments
  end
end
```

Becomes (Astro):
```ruby
# src/pages/articles/index.astro.rb
import Article, from: '../models/article.rb'

@articles = await Article.all
__END__
<Layout>
  {articles.map(article => <ArticleCard article={article} />)}
</Layout>
```

Becomes (Vue):
```ruby
# src/views/articles/Index.vue.rb
import Article, from: '../../models/article.rb'

@articles = ref([])

onMounted -> {
  Article.all.then { |data| @articles = data }
}
__END__
<template>
  <MainLayout>
    <ArticleCard v-for="article in articles" :key="article.id" :article="article" />
  </MainLayout>
</template>
```

Becomes (Svelte):
```ruby
# src/routes/articles/+page.svelte.rb
import Article, from: '$lib/models/article.rb'

@articles = []

onMount -> {
  Article.all.then { |data| @articles = data }
}
__END__
<script>
  // Generated setup code
</script>

{#each articles as article (article.id)}
  <ArticleCard {article} />
{/each}
```

#### Rails View → SFC Template

| ERB | Astro | Vue | Svelte |
|-----|-------|-----|--------|
| `<%= @var %>` | `{var}` | `{{ var }}` | `{var}` |
| `<% if cond %>...<% end %>` | `{cond && (...)}` | `<div v-if="cond">` | `{#if cond}...{/if}` |
| `<% @items.each do \|i\| %>` | `{items.map(i => ...)}` | `v-for="i in items"` | `{#each items as i}` |
| `<%= link_to text, path %>` | `<a href={path}>{text}</a>` | `<router-link :to="path">` | `<a href={path}>{text}</a>` |
| `<%= render partial %>` | `<Component />` | `<Component />` | `<Component />` |
| `<%= form_with ... %>` | `<form>` + islands | `<form @submit>` | `<form on:submit>` |

### 1.4 Integration

Update `SelfhostBuilder` to use framework converter when `-f` flag is set.

### 1.5 Real-Time Updates (Included)

Since models copy as-is with their broadcast callbacks:
```ruby
class Article < ApplicationRecord
  broadcasts_to ->(_article) { "articles" }, inserts_by: :prepend
```

Real-time should work automatically via:
- `broadcast_append_to`, `broadcast_replace_to`, `broadcast_remove_to` (already in ActiveRecordBase)
- BroadcastChannel API (works in browser)
- Turbo Stream rendering (already in ruby2js-rails)

**If framework-specific issues arise**, fall back to:

| Framework | Mechanism | Implementation |
|-----------|-----------|----------------|
| Astro | Turbo Streams | Same as Rails (Turbo handles DOM updates) |
| Vue | Turbo Streams or reactive | Turbo for SSR pages, reactive for SPA mode |
| Svelte | Turbo Streams or stores | Turbo for SSR pages, stores for SPA mode |

### Stage 1 Validation

- [ ] `-f astro` produces working Astro app
- [ ] `-f vue` produces working Vue app
- [ ] `-f svelte` produces working Svelte app
- [ ] CRUD works in all frameworks
- [ ] Real-time updates work (create in one tab → appears in another)
- [ ] CI passes

---

## Stage 2: Expand Combinations

### 2.1 Node Targets

Add SSR support:
- Astro node adapter
- Vue SSR (or Nuxt)
- SvelteKit node adapter

### 2.2 Edge Targets

Add edge deployment:
- Astro cloudflare adapter
- SvelteKit cloudflare adapter
- D1 database integration

### 2.3 Additional Databases

- sqlite3 for node targets
- D1 for cloudflare targets
- Neon/Turso for vercel targets

---

## Existing Building Blocks

### Transformers

| Source | Transformer | Output | Status | Notes |
|--------|-------------|--------|--------|-------|
| `.astro.rb` | AstroComponentTransformer | `.astro` | ✓ Wired | Primary for Stage 0 |
| `.vue.rb` | VueComponentTransformer | `.vue` | ✓ Wired | Stage 0.2 |
| `.svelte.rb` | SvelteComponentTransformer | `.svelte` | ✓ Wired | Stage 0.3 |
| `.erb.rb` | ErbFileTransformer | `.jsx` | ✓ Wired | For React islands if needed |
| `.jsx.rb` | React+JSX filters | `.jsx` | ✓ Wired | |
| `.html.erb` | ErbCompiler | JS string | ✓ Wired | Stage 1 transpiler |

### Integration Packages

| Package | Status |
|---------|--------|
| `ruby2js-astro` | ✓ Complete |
| `ruby2js-svelte` | ✓ Complete |
| `vite-plugin-ruby2js` | ✓ Complete |

### Database Adapters

| Adapter | Browser | Node | Edge |
|---------|---------|------|------|
| dexie | ✓ | - | - |
| sqlite3 | - | ✓ | - |
| d1 | - | - | ✓ |

### Worker-in-Browser Infrastructure (New)

| Component | Status | Notes |
|-----------|--------|-------|
| Browser adapter for Astro | ✓ Complete | `browser-adapter.mjs` + `browser-server.mjs` |
| esbuild bundler for worker | ✓ Complete | Bundles `dist/server/entry.mjs` (~770KB) |
| Browser shell | ✓ Complete | `public/index.html` with navigation/form handling |
| Dexie adapter | ✓ Complete | Native API, no SQL parsing needed |
| `ruby2jsModels` plugin | ✓ Complete | Framework-agnostic model/migration transpilation |
| Noop image service | ✓ Complete | Avoids sharp/Node.js dependencies |

### From Existing Astro Blog (Recyclable)

- Dexie database setup pattern (`lib/db.js`)
- Layout patterns
- CSS/styling
- Model transpilation approach

### From Existing Astro Blog (Discard)

- Heavy React islands approach → use SSR + worker-in-browser instead
- Hand-written model shortcuts → replace with transpiled models
- ISR implementation → replace with standard SSR

---

## Rails Blog Source (Reference)

```
/tmp/blog/
├── app/
│   ├── models/
│   │   ├── article.rb          # has_many :comments, validates
│   │   └── comment.rb          # belongs_to :article
│   ├── controllers/
│   │   ├── articles_controller.rb  # CRUD actions
│   │   └── comments_controller.rb  # Create/destroy
│   └── views/
│       ├── articles/
│       │   ├── index.html.erb
│       │   ├── show.html.erb
│       │   ├── new.html.erb
│       │   ├── edit.html.erb
│       │   ├── _form.html.erb
│       │   └── _article.html.erb
│       ├── comments/
│       │   ├── _comment.html.erb
│       │   └── _form.html.erb
│       └── layouts/
│           └── application.html.erb
├── config/
│   └── routes.rb
└── db/
    ├── migrate/
    │   ├── *_create_articles.rb
    │   └── *_create_comments.rb
    └── seeds.rb
```

---

## Success Criteria

### Stage 0
- [x] Astro blog runs in browser (worker-in-browser pattern)
- [x] CRUD works: create, read, update, delete articles
- [x] Comments work: create, delete nested under articles
- [x] Data persists in IndexedDB via Dexie
- [x] Uses ruby2js-rails infrastructure (adapters, models)
- [x] Validation errors display correctly (Rails-style full_message)
- [ ] Astro blog builds for Cloudflare (D1 adapter) - optional, browser-first approach
- [ ] Vue blog follows same pattern
- [ ] Svelte blog follows same pattern

### Stage 1 (Transpiler + Real-Time)
- [ ] `-f astro` produces Astro app matching Stage 0
- [ ] `-f vue` produces Vue app matching Stage 0
- [ ] `-f svelte` produces Svelte app matching Stage 0
- [ ] Default (`-f rails`) works as before
- [ ] Real-time updates work (models broadcast, Turbo Streams update DOM)
- [ ] CI passes

### Stage 2
- [ ] Node targets work with sqlite3
- [ ] Additional edge platforms (Vercel, Deno Deploy)

---

## Open Questions

1. **Shared database schema**: Should all three SFC apps share exact same schema as Rails blog, or can there be minor differences?

2. **Model location**: In SFC apps, where do models live? `src/models/`, `src/lib/models/`, imported from package?

3. ~~**Form handling**: Rails has `form_with` helpers. How should forms work in each SFC framework?~~
   **RESOLVED**: Use standard HTML forms. Turbo handles form submission the same way it does for Rails.

4. **Flash messages**: Rails has flash. What's the equivalent pattern in each framework? (Cookies + Turbo should work)

5. **Routing params**: Rails has `params[:id]`. Each framework handles route params differently - document the mapping.

6. ~~**Bundle size**: What's acceptable for the browser worker bundle? Current PoC is ~530KB for minimal Astro.~~
   **RESOLVED**: 126KB gzipped (minified) is acceptable. Comparable to other SSR frameworks.

7. ~~**Database adapter injection**: How to cleanly swap D1 ↔ Dexie at build time?~~
   **RESOLVED**: Use existing ruby2js-rails adapter infrastructure. Same pattern as Rails blog demo.

---

## Notes

- Stage 0 is essential - concrete targets before automation
- **Worker-in-browser pattern is key** - same SSR code runs on edge and in browser
- Turbo provides navigation/form handling - no need for framework-specific solutions
- Database adapter is the only target-specific code
- Build for Cloudflare first, add browser shim second
- Real-time is Stage 2, after basic CRUD works
- **Reuse ruby2js-rails infrastructure** - adapters, Turbo integration, flash messages already exist
- Models stay as Ruby across all frameworks - only views/controllers need conversion

## Proof of Concept Completed (Jan 2026)

- [x] Astro SSR builds to Cloudflare Worker
- [x] Worker bundles for browser with esbuild
- [x] Worker renders HTML when called as function
- [x] Only minimal shims needed (cloudflare:workers, caches)
- [x] Full Turbo integration (turbo:before-fetch-request interception)

## Stage 0.1 Progress (Jan 2026)

Created `test/astro-blog-v3/` with idiomatic Astro SSR:

- [x] Astro project with Cloudflare adapter
- [x] Layout with Turbo script loading
- [x] Article and Comment models (TypeScript) - *to be replaced with Ruby*
- [x] Database adapter (D1 for edge) - *to be replaced with ruby2js-rails adapter*
- [x] CRUD pages: articles index, show, new, edit
- [x] Comments functionality (create, delete)
- [x] Build succeeds for Cloudflare (produces `_worker.js/`)
- [x] Browser bundler with esbuild (412KB minified, 126KB gzipped)
- [x] Node.js shims for fs, path, child_process, etc.
- [x] Test script validates worker renders HTML

**Revised approach: Reuse ruby2js-rails infrastructure**

Instead of hand-written TypeScript models and custom adapters:
- Use Ruby models (transpiled at build time)
- Use existing adapters from `ruby2js-rails/adapters/`
- Use existing Turbo integration pattern from `targets/browser/rails.js`

**Completed:**
- [x] Replace TypeScript models with Ruby models
- [x] Create `ruby2jsModels` Vite plugin (framework-agnostic model/migration transpilation)
- [x] Wire up ruby2js-rails Dexie adapter via bridge files
- [x] Wire up Turbo event interception
- [x] Browser bundler copies integration files to dist/
- [x] **Simplify to browser-only adapter** (removed Cloudflare dependency)
  - Created `browser-adapter.mjs` - minimal Astro adapter
  - Created `browser-server.mjs` - exports `fetch(request) -> Response`
  - Uses noop image service (avoids sharp/Node.js dependencies)
  - Direct esbuild bundling of `dist/server/entry.mjs` (~770KB)
- [x] **Full CRUD workflow verified in browser mode**
  - Create, read, update, delete articles
  - Create, delete comments
  - Data persists in IndexedDB via Dexie
  - Navigation and form submission handled by browser shell
- [x] **Validation errors working** (Rails-style `error.full_message` pattern)
- [x] Integration test passing (`test/integration/astro_blog.test.mjs`)

**Current state:**
- Browser-only Astro blog fully functional
- Same Ruby model code as Rails blog
- Uses ruby2js-rails Dexie adapter (native API, no SQL parsing)
- Worker-in-browser pattern working without Cloudflare

**Strategic decision:** Move to Stage 1 (transpiler) now while Astro context is fresh. The remaining Stage 0 items are lower-risk and can be addressed after the transpiler works.

**Deferred (lower priority):**
- [ ] Add seed data for initial testing (currently starts empty)
- [ ] Verify real-time broadcasts work (BroadcastChannel API)
- [ ] Vue blog (needed before `-f vue` transpiler target)
- [ ] Svelte blog (needed before `-f svelte` transpiler target)

---

## New Insight: Pluggable View Rendering (Jan 2026)

### Discovery: Views Can Declare Their Rendering Strategy

While implementing SSR hydration for React views, we discovered that different view types need different rendering approaches. This led to a `renderView` helper that detects view type at runtime:

```javascript
function renderView(View, props) {
  return View.constructor.name === "AsyncFunction"
    ? View(props)                              // ERB: async, returns string
    : React.createElement(View, props);        // React: needs createElement for hooks
}
```

### Why This Matters for SFC Targets

The same pattern applies to framework targets:

| View Type | Detection | Rendering |
|-----------|-----------|-----------|
| ERB | `AsyncFunction` | Call directly → string |
| React/JSX | Regular function | `React.createElement()` |
| Astro | `View._astro` or convention | Call directly → string (SSR) |
| Vue | `View._vue` or `<template>` | `createApp()` or SSR render |
| Svelte | `View._svelte` | `render()` or SSR |

### Self-Describing Views

Instead of the framework guessing view types, views could declare their rendering strategy:

```javascript
// View declares its own strategy
function Show({ workflow_id }) { /* ... */ }
Show.renderStrategy = 'react';

async function render$1({ workflows }) { /* ... */ }
render$1.renderStrategy = 'string';

// Astro component
export function ArticleCard({ article }) { /* ... */ }
ArticleCard.renderStrategy = 'astro';
```

The `renderView` dispatcher becomes extensible:

```javascript
const strategies = {
  string: (View, props) => View(props),
  react: (View, props) => React.createElement(View, props),
  astro: (View, props) => renderAstroComponent(View, props),
  vue: (View, props) => renderVueComponent(View, props),
  svelte: (View, props) => renderSvelteComponent(View, props),
  stream: (View, props) => renderToStream(View, props),
};

function renderView(View, props) {
  const strategy = View.renderStrategy || detectStrategy(View);
  return strategies[strategy](View, props);
}
```

### Implications for Stage 1

When converting Rails to Astro/Vue/Svelte:

1. **Views get tagged with their strategy** during transpilation
2. **Mixed views are possible** - same app could have ERB partials and React islands
3. **New frameworks can be added** without modifying core rendering logic
4. **Runtime detection as fallback** - `AsyncFunction` check, template inspection, etc.

### Integration with Hydration

The recent hydration work (`data-juntos-view`, `data-juntos-props`) also applies:

| Framework | SSR Output | Hydration Target |
|-----------|------------|------------------|
| React | `<div data-juntos-view="/path">...</div>` | `hydrateRoot()` |
| Astro | Native `<astro-island>` | Astro's hydration |
| Vue | `<div data-v-app>...</div>` | `createSSRApp().mount()` |
| Svelte | Component markup | `hydrate()` |

**Key learning**: Only serializable props can be passed for hydration. Views should accept IDs and fetch data, not receive full model objects.

---

## Updated Feasibility Assessment (Jan 2026)

### What's More Feasible Than Expected

1. **Pluggable rendering** - The `renderView` pattern makes multi-framework support cleaner than anticipated
2. **Hydration props** - Serializing primitive props (IDs) and fetching data works well
3. **Dual bundle support** - SSR + client hydration now working for Node target
4. **ERB/JSX coexistence** - Same controller can render both view types

### What's Harder Than Expected

1. **React hooks in SSR** - Required `React.createElement()` wrapper, not direct function calls
2. **Circular references** - ActiveRecord objects can't be serialized; must pass IDs
3. **Async view detection** - ERB views are async (for partials), React views are sync
4. **Framework-specific hydration** - Each framework has different hydration APIs

### Revised Approach Recommendations

1. **Start with rendering strategy tags** - Add `renderStrategy` property during transpilation before tackling full SFC conversion

2. **Unify hydration wrapper pattern** - The `data-juntos-*` attributes could become framework-agnostic, with framework-specific hydration code

3. **Views fetch their own data** - Rather than controllers preloading everything, views should accept minimal props (IDs) and fetch asynchronously. This:
   - Avoids serialization issues
   - Works consistently across SSR and client
   - Matches modern patterns (React Server Components, Astro islands)

4. **ERB as universal partial format** - ERB templates compile to async string functions that work anywhere. They could be the "lowest common denominator" for shared partials across frameworks.

---

## Deferred Items (Lower Priority)

- [ ] Add seed data for initial testing (currently starts empty)
- [ ] Verify real-time broadcasts work (BroadcastChannel API)
- [ ] Vue blog (needed before `-f vue` transpiler target)
- [ ] Svelte blog (needed before `-f svelte` transpiler target)

---

**Now: Stage 1 - Astro Transpiler**

Goal: `bin/juntos build -f astro` produces the same output as hand-crafted `test/astro-blog-v3/`

The transpiler converts:
1. **Models** - Copy as-is (already Ruby, transpiled at build time)
2. **Controllers** - Extract data fetching → Astro page frontmatter
3. **Views (ERB)** - Convert to Astro templates
4. **Routes** - Map to file-based routing structure
5. **Layout** - Convert to `src/layouts/Layout.astro`

**New consideration**: Add `renderStrategy` tags to generated views for future multi-framework coexistence.
