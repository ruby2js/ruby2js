# Plan: SFC Triple-Target Demo

## Goal

Transpile the Rails blog demo to three SFC frameworks (Astro, Vue, Svelte), proving the mechanical transformation principle from VISION.md.

## Approach

**Stage 0**: Hand-craft target applications equivalent to the Rails blog
**Stage 1**: Build transpiler that produces Stage 0 output from Rails source
**Stage 2**: Add real-time updates
**Stage 3**: Expand target/database combinations

---

## Combination Triage

### Dimensions

- **Framework (-f)**: astro, vue, svelte, rails
- **Target (-t)**: browser, node, cloudflare, vercel
- **Database (-d)**: dexie, sqlite3, d1, neon, turso

### Priority Matrix

#### Tier 1: Should Definitely Work (Initial Focus)

| Framework | Target | Database | Notes |
|-----------|--------|----------|-------|
| astro | browser | dexie | Static site + IndexedDB, simplest starting point |
| vue | browser | dexie | SPA + IndexedDB |
| svelte | browser | dexie | SvelteKit SPA + IndexedDB |
| rails | browser | dexie | Current behavior (string templates + RPC) |
| rails | node | sqlite3 | Current behavior (server-side rendering) |

These combinations use proven infrastructure and should work with minimal new code.

#### Tier 2: Should Work with Investigation

| Framework | Target | Database | Notes |
|-----------|--------|----------|-------|
| astro | node | sqlite3 | Astro SSR mode |
| astro | cloudflare | d1 | Astro + Cloudflare adapter |
| svelte | node | sqlite3 | SvelteKit node adapter |
| svelte | cloudflare | d1 | SvelteKit cloudflare adapter |
| vue | node | sqlite3 | Vue SSR (Nuxt-style or custom) |
| rails | cloudflare | d1 | Current infrastructure |

These require understanding framework-specific SSR/edge patterns.

#### Tier 3: Needs Research

| Framework | Target | Database | Notes |
|-----------|--------|----------|-------|
| vue | cloudflare | d1 | Vue on edge - Nuxt or custom? |
| astro | vercel | neon | Astro + Vercel + Postgres |
| svelte | vercel | neon | SvelteKit + Vercel + Postgres |

Edge + Postgres combinations need connection pooling investigation.

#### Tier 4: Likely Impractical

| Framework | Target | Database | Why |
|-----------|--------|----------|-----|
| * | browser | sqlite3 | SQLite needs server (unless sql.js WASM) |
| * | browser | d1 | D1 is Cloudflare-only |
| * | browser | neon/turso | Need server for connection |

Browser target requires client-side database (dexie) or RPC to server.

### Initial Scope

**Stage 0-1 focuses on Tier 1:**
- All frameworks with browser + dexie
- Rails with node + sqlite3 (baseline)

This proves the concept with the simplest viable combinations.

---

## Stage 0: Hand-Craft Equivalent Applications

### Goal

Create three hand-crafted SFC applications that match the Rails blog functionality:
- Articles: index, show, new, edit, delete
- Comments: nested under articles, create, delete
- Shared layout with navigation
- Same Dexie database schema
- Same transpiled model classes (not shortcuts)

### 0.1 Astro Blog

Create `test/astro-blog-v2/create-astro-blog`:

```
src/
├── layouts/
│   └── Layout.astro.rb         # Main layout
├── pages/
│   ├── index.astro.rb          # Landing page
│   ├── about.astro.rb          # Static about page
│   └── articles/
│       ├── index.astro.rb      # Article list
│       ├── new.astro.rb        # New article form (island)
│       ├── [id].astro.rb       # Show article + comments
│       └── [id]/
│           └── edit.astro.rb   # Edit article form (island)
├── islands/
│   ├── ArticleList.erb.rb      # Interactive article list
│   ├── ArticleForm.erb.rb      # Article create/edit form
│   ├── CommentList.erb.rb      # Comments for an article
│   └── CommentForm.erb.rb      # Add comment form
├── models/
│   ├── article.rb              # Transpiled from Rails
│   └── comment.rb              # Transpiled from Rails
└── lib/
    └── db.js                   # Dexie setup (shared)
```

**Key difference from existing astro-blog:** Uses transpiled models, not hand-written shortcuts.

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
        # Read Rails source, produce Astro output
        # - app/views/*.html.erb → src/pages/*.astro.rb or src/islands/*.erb.rb
        # - app/controllers/*.rb → frontmatter in pages
        # - app/models/*.rb → src/models/*.rb (copy)
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

---

## Stage 2: Real-Time Updates

### Goal

Add real-time updates equivalent to Rails Turbo Streams.

### Approach Per Framework

| Framework | Mechanism | Implementation |
|-----------|-----------|----------------|
| Astro | Islands + WebSocket | Island subscribes to WS, re-renders on message |
| Vue | Reactive + WebSocket | Composable that updates reactive refs on WS message |
| Svelte | Stores + WebSocket | Store subscribes to WS, components react to store |
| Rails | Turbo Streams | Current implementation |

### Shared Infrastructure

```javascript
// lib/realtime.js - Shared WebSocket client
export function subscribe(channel, callback) {
  const ws = new WebSocket(wsUrl);
  ws.onmessage = (e) => {
    const data = JSON.parse(e.data);
    if (data.channel === channel) {
      callback(data.payload);
    }
  };
  return () => ws.close();
}
```

### Stage 2 Validation

- [ ] Create article in one tab → appears in another tab
- [ ] Delete article → removed in other tabs
- [ ] Same for comments
- [ ] Works across all three frameworks

---

## Stage 3: Expand Combinations

### 3.1 Node Targets

Add SSR support:
- Astro node adapter
- Vue SSR (or Nuxt)
- SvelteKit node adapter

### 3.2 Edge Targets

Add edge deployment:
- Astro cloudflare adapter
- SvelteKit cloudflare adapter
- D1 database integration

### 3.3 Additional Databases

- sqlite3 for node targets
- D1 for cloudflare targets
- Neon/Turso for vercel targets

---

## Existing Building Blocks

### Transformers

| Source | Transformer | Output | Status |
|--------|-------------|--------|--------|
| `.astro.rb` | AstroComponentTransformer | `.astro` | ✓ Wired |
| `.vue.rb` | VueComponentTransformer | `.vue` | ✓ Wired |
| `.svelte.rb` | SvelteComponentTransformer | `.svelte` | ✓ Wired |
| `.erb.rb` | ErbPnodeTransformer | `.jsx` | ✓ Wired |
| `.jsx.rb` | React+JSX filters | `.jsx` | ✓ Wired |
| `.html.erb` | ErbCompiler | JS string | ✓ Wired |

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

### From Existing Astro Blog (Recyclable)

- Dexie database setup pattern (`lib/db.js`)
- Island component structure
- Layout patterns
- Some CSS/styling

### From Existing Astro Blog (Discard)

- Hand-written model shortcuts → replace with transpiled models
- ISR implementation → replace with adapter-based approach

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
- [ ] Astro blog v2 runs with transpiled models
- [ ] Vue blog runs with transpiled models
- [ ] Svelte blog runs with transpiled models
- [ ] All have CRUD for articles and comments
- [ ] All use same Dexie schema

### Stage 1
- [ ] `-f astro` produces Astro app matching Stage 0
- [ ] `-f vue` produces Vue app matching Stage 0
- [ ] `-f svelte` produces Svelte app matching Stage 0
- [ ] Default (`-f rails`) works as before
- [ ] CI passes

### Stage 2
- [ ] Real-time updates work in Astro
- [ ] Real-time updates work in Vue
- [ ] Real-time updates work in Svelte

### Stage 3
- [ ] Node targets work with sqlite3
- [ ] Edge targets work with D1

---

## Open Questions

1. **Shared database schema**: Should all three SFC apps share exact same Dexie schema as Rails blog, or can there be minor differences?

2. **Model location**: In SFC apps, where do models live? `src/models/`, `src/lib/models/`, imported from package?

3. **Form handling**: Rails has `form_with` helpers. How should forms work in each SFC framework? Native forms with handlers?

4. **Flash messages**: Rails has flash. What's the equivalent pattern in each framework?

5. **Routing params**: Rails has `params[:id]`. Each framework handles route params differently - document the mapping.

---

## Notes

- Stage 0 is essential - concrete targets before automation
- Recyclable pieces from astro-blog: patterns, not code
- Database models must be transpiled, not shortcuts
- Real-time is Stage 2, after basic CRUD works
- Tier 1 combinations first, expand later
