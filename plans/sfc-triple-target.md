# Plan: SFC Triple-Target Demo

## Goal

Transpile the Rails blog demo to three SFC frameworks (Astro, Vue, Svelte), proving the mechanical transformation principle from VISION.md.

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

### 1.1 Add Framework Flag

Update `lib/ruby2js/cli/juntos.rb`:

```ruby
# Add to parse_common_options:
when '-f', '--framework'
  options[:framework] = args[i + 1]
  i += 2

# Valid values: astro, vue, svelte, rails (default)
ENV['JUNTOS_FRAMEWORK'] = options[:framework] if options[:framework]
```

### 1.2 Create Framework Converter

New file: `lib/ruby2js/rails/framework_converter.rb`

```ruby
module Ruby2JS
  module Rails
    class FrameworkConverter
      def initialize(framework:, source_dir:, output_dir:)
        @framework = framework
        @source_dir = source_dir
        @output_dir = output_dir
      end

      def convert
        case @framework
        when 'astro' then convert_to_astro
        when 'vue' then convert_to_vue
        when 'svelte' then convert_to_svelte
        else convert_to_rails # default
        end
      end

      private

      def convert_to_astro
        # Models: copy as-is (transpiled at build time)
        copy_models('src/models')

        # Views + Controllers → Astro pages
        # - app/views/articles/index.html.erb + index action → src/pages/articles/index.astro
        convert_views_to_astro_pages

        # Layout → src/layouts/Layout.astro
        convert_layout
      end

      # Similar for vue, svelte, rails
    end
  end
end
```

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

**Now: Stage 1 - Astro Transpiler**

Goal: `bin/juntos build -f astro` produces the same output as hand-crafted `test/astro-blog-v3/`

The transpiler converts:
1. **Models** - Copy as-is (already Ruby, transpiled at build time)
2. **Controllers** - Extract data fetching → Astro page frontmatter
3. **Views (ERB)** - Convert to Astro templates
4. **Routes** - Map to file-based routing structure
5. **Layout** - Convert to `src/layouts/Layout.astro`
