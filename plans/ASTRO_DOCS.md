# Ruby2JS Documentation on Astro + Cloudflare

A documentation site rebuild that dogfoods Ruby2JS while showcasing Astro and Cloudflare platform integration.

## Strategic Context

**The current site (Bridgetown)** works well as static documentation with interactive demos. But it doesn't demonstrate the full vision: Ruby as a first-class language across the modern JavaScript ecosystem.

**The new site (Astro + Cloudflare)** would be a living example of everything Ruby2JS enables:
- Ruby frontmatter in Astro files
- Ruby template expressions
- Ruby client-side scripts
- Cloudflare edge deployment with D1, Workers AI, Vectorize
- The same docs you read are the proof that it works

**Dogfooding value:** Building this will stress-test and improve the Astro integration, reveal gaps, and create a compelling showcase.

---

## Current State

| Aspect | Bridgetown |
|--------|------------|
| Framework | Bridgetown (Ruby SSG) |
| Content | Markdown + ERB |
| Hosting | Static (GitHub Pages or similar) |
| Interactive demos | Opal-based (~5MB) + Selfhost (~200KB) |
| Search | None or basic |
| Personalization | None |
| User data | None |

## Already Implemented

The core components for Astro with Ruby are now complete:

| Component | Location | Status |
|-----------|----------|--------|
| Astro Filter | `lib/ruby2js/filter/astro.rb` | ✅ Converts Phlex → Astro |
| Astro Template Compiler | `lib/ruby2js/astro_template_compiler.rb` | ✅ Ruby→JS in templates |
| Astro Component Transformer | `lib/ruby2js/astro_component_transformer.rb` | ✅ `.astro.rb` → `.astro` |
| Vue Template Compiler | `lib/ruby2js/vue_template_compiler.rb` | ✅ Expression conversion |
| Vue Component Transformer | `lib/ruby2js/vue_component_transformer.rb` | ✅ `.vue.rb` → `.vue` |
| Svelte Template Compiler | `lib/ruby2js/svelte_template_compiler.rb` | ✅ Expression conversion |
| Svelte Component Transformer | `lib/ruby2js/svelte_component_transformer.rb` | ✅ `.svelte.rb` → `.svelte` |
| Vite Plugin | `packages/vite-plugin-ruby2js/` | ✅ Transforms .rb → .js |
| Cloudflare Workers | `packages/ruby2js-rails/targets/cloudflare/` | ✅ Full Worker/D1/DO support |
| ISR Adapters | `packages/ruby2js-rails/targets/*/isr.mjs` | ✅ Vercel + Cloudflare |

## Target State

| Aspect | Astro + Cloudflare |
|--------|-------------------|
| Framework | Astro with Ruby integration |
| Content | Markdown Content Collections + Ruby frontmatter |
| Hosting | Cloudflare Pages + Workers |
| Interactive demos | Selfhost transpiler (same) |
| Search | AI-powered semantic search (Vectorize + Workers AI) |
| Personalization | Bookmarks, progress, history (D1) |
| User data | D1, with real-time sync via Durable Objects |

---

## Ruby in Astro Files: `.astro.rb` Format

The implemented approach uses `.astro.rb` files, matching the pattern established for Vue (`.vue.rb`) and Svelte (`.svelte.rb`):

### File Format

```ruby
# src/pages/posts/[slug].astro.rb
@post = Post.find_by(slug: params[:slug])
@comments = @post.comments
__END__
<Layout title={post.title}>
  <article>
    <h1>{post.title}</h1>
    <div set:html={post.body} />
  </article>
  <section>
    <h2>Comments</h2>
    {comments.map { |comment|
      <Comment comment={comment} />
    }}
  </section>
</Layout>
```

### Key Transformations

| Ruby | JavaScript |
|------|------------|
| `@variable` | `const variable` |
| `params[:id]` | `Astro.params.id` |
| `snake_case` | `camelCase` |
| `{items.map { \|i\| <jsx> }}` | `{items.map(i => <jsx>)}` |
| `{items.select { \|i\| cond }}` | `{items.filter(i => cond)}` |
| Model references | Auto-imported |

### Astro Directives Preserved

All Astro-specific attributes work unchanged:
- `client:load`, `client:visible`, `client:idle`, `client:only`
- `set:html={expr}`, `set:text={expr}`
- `is:raw`, `is:inline`

---

## Cloudflare Platform Integration

### Services Used

| Service | Purpose |
|---------|---------|
| **Pages** | Hosting, builds |
| **Workers** | Server-side rendering, API routes |
| **D1** | User data (bookmarks, progress, community examples) |
| **KV** | Caching (page renders, API responses) |
| **Vectorize** | Semantic search embeddings |
| **Workers AI** | Search queries, AI assistant |
| **Durable Objects** | Real-time features |
| **R2** | User-uploaded code snippets, assets |

### Ruby DSLs for Cloudflare

Expose Cloudflare services with Ruby-friendly APIs:

```ruby
# D1 via ActiveRecord patterns (already exists)
Bookmark.create(user_id: current_user.id, page: Astro.url.pathname)

# KV
KV.get("page:#{slug}:rendered")
KV.put("page:#{slug}:rendered", html, ttl: 1.hour)

# Vectorize
embedding = AI.embed(query)
results = Vectorize.query(embedding, limit: 10)

# Workers AI
summary = AI.summarize(content)
answer = AI.ask("How do I use the functions filter?", context: docs)

# R2
R2.put("examples/#{id}.rb", code)
url = R2.url("examples/#{id}.rb")
```

---

## Features

### Phase 1: Core Documentation

Parity with current site, plus Ruby-in-Astro:

- [ ] All existing docs migrated to Astro Content Collections
- [x] Astro template compiler (Ruby expressions → JS)
- [x] Astro component transformer (`.astro.rb` → `.astro`)
- [x] Interactive transpiler demos (selfhost) - already exists
- [ ] Responsive design, dark mode
- [ ] Basic navigation, table of contents

**Prerequisites implemented:**
- [x] Vite plugin for .rb files
- [x] Astro filter (Phlex → Astro)
- [x] Template expression compilers (Vue, Svelte, Astro)
- [x] Component transformers (Vue, Svelte, Astro)

### Phase 2: AI-Powered Search

Semantic search that understands intent:

- [ ] Index all docs into Vectorize on build
- [ ] Search UI with instant results
- [ ] "How do I..." queries find relevant pages
- [ ] Search analytics (what are people looking for?)

### Phase 3: Personalization

User accounts and saved state:

- [ ] GitHub OAuth (or anonymous local storage)
- [ ] Bookmarked pages
- [ ] Reading progress through tutorials
- [ ] Recently viewed
- [ ] "Continue where you left off"

### Phase 4: Community Examples

User-contributed content:

- [ ] Submit Ruby → JS examples
- [ ] Tag by filter, use case, framework
- [ ] Voting (helpful / not helpful)
- [ ] Moderation queue
- [ ] "Community Examples" section on each filter page

### Phase 5: AI Assistant

Contextual help:

- [ ] "Explain this conversion" button on examples
- [ ] "Ask a question" chat interface
- [ ] Context-aware (knows which page you're on)
- [ ] Suggests related docs

### Phase 6: Real-Time Features

Social/collaborative:

- [ ] "X developers reading docs" presence
- [ ] Live collaborative transpiler sessions
- [ ] Comments/discussions on pages
- [ ] Notifications for replies

---

## Technical Architecture

```
docs/
├── astro.config.mjs          # Astro config with Ruby plugin
├── src/
│   ├── content/
│   │   ├── docs/             # Markdown content (migrated from Bridgetown)
│   │   ├── filters/          # Filter documentation
│   │   └── demos/            # Demo descriptions
│   ├── pages/
│   │   ├── index.astro.rb    # Home page (Ruby)
│   │   ├── docs/[...slug].astro.rb
│   │   └── api/              # API routes for AI, user data
│   ├── components/
│   │   ├── Transpiler.astro.rb  # Interactive demo
│   │   ├── Search.astro.rb      # AI search
│   │   └── ...
│   └── layouts/
│       └── DocsLayout.astro.rb
├── functions/                 # Cloudflare Workers
│   ├── search.js             # Vectorize queries
│   ├── ai.js                 # Workers AI
│   └── user.js               # D1 user data
└── wrangler.toml             # Cloudflare config
```

### Vite Plugin Integration

The existing `vite-plugin-ruby2js` needs an extension to handle `.astro.rb` files:

```javascript
// vite.config.mjs
import ruby2js from 'vite-plugin-ruby2js';

export default {
  plugins: [
    ruby2js({
      // Handles .astro.rb → .astro transformation
      astro: true
    })
  ]
};
```

---

## Migration Path

### Content Migration

Bridgetown Markdown → Astro Content Collections:

| Bridgetown | Astro |
|------------|-------|
| `docs/src/_docs/*.md` | `src/content/docs/*.md` |
| Front matter (YAML) | Front matter (YAML, same) |
| ERB includes | Astro components |
| `{% toc %}` | `<TableOfContents />` |
| Live demos | Same (selfhost transpiler) |

Most content migrates as-is. ERB helpers become Astro components.

### URL Preservation

Keep existing URLs working:

```javascript
// astro.config.mjs
export default defineConfig({
  redirects: {
    '/docs/filters/functions': '/docs/filters/functions',  // same
    // Add redirects for any changed paths
  }
});
```

---

## Build & Deploy

### Local Development

```bash
npm run dev          # Astro dev server
npm run build        # Production build
npm run preview      # Preview production build
```

### Cloudflare Deployment

```bash
npm run deploy       # wrangler pages deploy
```

Or automatic via GitHub Actions on push to main.

### Environment Variables

```bash
# .dev.vars (local) / Cloudflare dashboard (production)
D1_DATABASE_ID=xxx
VECTORIZE_INDEX=ruby2js-docs
AI_GATEWAY=xxx
```

---

## Success Criteria

### Phase 1 (Core)
- [ ] All existing docs accessible at same URLs
- [x] Ruby template expressions working in Astro files
- [x] `.astro.rb` → `.astro` transformation working
- [ ] Interactive demos functional
- [ ] Page load faster than current site
- [ ] Lighthouse score 90+

### Phase 2 (Search)
- [ ] Semantic search returns relevant results
- [ ] Search latency < 200ms
- [ ] Search analytics dashboard

### Phase 3 (Personalization)
- [ ] Users can bookmark pages
- [ ] Progress persists across sessions
- [ ] Works without login (local storage fallback)

### Phase 4 (Community)
- [ ] Users can submit examples
- [ ] Moderation workflow functional
- [ ] Examples appear on filter pages

### Phase 5 (AI)
- [ ] AI explains conversions accurately
- [ ] Chat interface responsive
- [ ] Cost per query acceptable

### Phase 6 (Real-time)
- [ ] Presence indicator works
- [ ] Collaborative sessions functional
- [ ] Comments with real-time updates

---

## Cost Estimate

Based on Cloudflare free tiers and moderate traffic:

| Phase | Expected Cost |
|-------|---------------|
| Phase 1-2 | Free |
| Phase 3-4 | Free (within D1 free tier) |
| Phase 5 | $0-5/month (Workers AI usage) |
| Phase 6 | $0-5/month (Durable Objects) |

**Total: Free to ~$10/month** even with significant traffic.

---

## Design Decisions

### File-Based Ruby Components (`.astro.rb`)

Following the established pattern for Vue and Svelte:

```ruby
# Ruby code (frontmatter equivalent)
@posts = Post.all
__END__
<!-- Astro template with Ruby expressions -->
{posts.map { |post| <Card post={post} /> }}
```

This approach:
- Keeps Ruby code separate from template
- Uses familiar `__END__` convention
- Matches `.vue.rb` and `.svelte.rb` patterns
- Allows full Ruby syntax in the code section

### Anonymous by Default

Docs sites don't ask for login. The pattern:

| Feature | Storage | Login Required? |
|---------|---------|-----------------|
| Bookmarks | Local Storage | No |
| Reading progress | Local Storage | No |
| Preferences | Local Storage | No |
| Sync across devices | D1 | Optional (GitHub OAuth) |
| Submit examples | D1 | Yes (GitHub OAuth) |
| Comments | D1 | Yes (GitHub OAuth) |

Default experience is fully functional with no login. GitHub OAuth only for features that inherently need identity.

### Opal Demo

The Opal-based demo becomes redundant once selfhost covers all filters. Current status tracked in `demo/selfhost/spec_manifest.json`:
- **Ready:** 24 specs (core, functions, ESM, Rails, Stimulus, ERB, JSX, etc.)
- **Partial:** 14 specs (React, Phlex, Lit, Astro, Vue, Alpine, Turbo, etc.)

Once partial specs complete, Opal demo can be retired. This is progress-dependent, not a decision.

---

## Open Questions

1. **Content freeze**: When to freeze Bridgetown content and migrate?

2. **Parallel operation**: Run both sites during transition? Subdomain for new site?

---

## References

- [Astro Documentation](https://docs.astro.build/)
- [Cloudflare Pages](https://developers.cloudflare.com/pages/)
- [Cloudflare D1](https://developers.cloudflare.com/d1/)
- [Cloudflare Vectorize](https://developers.cloudflare.com/vectorize/)
- [Cloudflare Workers AI](https://developers.cloudflare.com/workers-ai/)
- Current site: https://www.ruby2js.com/
- Astro Template Compiler: `lib/ruby2js/astro_template_compiler.rb`
- Astro Component Transformer: `lib/ruby2js/astro_component_transformer.rb`
