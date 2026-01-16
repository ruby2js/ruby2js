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

## Ruby in Astro Files

Astro files have three places for code. All three should support Ruby:

### 1. Frontmatter

```astro
---
#!ruby
# Server-side, runs at build/request time
filters = Filter.all.order(:name)
current = filters.find { |f| f.slug == Astro.params.slug }
related = filters.select { |f| f.category == current.category }
---
```

### 2. Template Expressions

```astro
<Layout title={current.name}>
  <nav>
    {filters.map { |f| <FilterLink filter={f} active={f == current} /> }}
  </nav>

  <main>
    <h1>{current.name}</h1>
    <p>{current.description}</p>

    {current.examples.map { |ex|
      <Example ruby={ex.ruby} js={ex.js} />
    }}
  </main>
</Layout>
```

### 3. Client Scripts

```astro
<script lang="ruby">
  # Client-side, runs in browser
  document.querySelectorAll('.copy-button').forEach do |btn|
    btn.addEventListener('click') do |e|
      navigator.clipboard.writeText(btn.dataset.code)
      btn.textContent = 'Copied!'
    end
  end
</script>
```

### Implementation Approach

The existing `ErbCompiler.js` extracts Ruby from ERB and compiles it. A similar `AstroCompiler.js` would:

1. Detect `#!ruby` shebang in frontmatter
2. Extract and compile frontmatter Ruby → JS
3. Detect Ruby in `{...}` expressions (heuristics or explicit marker)
4. Detect `<script lang="ruby">` tags
5. Reassemble into valid Astro with JS

This becomes a Vite plugin that runs before Astro's own processing.

### Compiler Implementation

A new `AstroCompiler` is needed (not a reuse of `ErbCompiler`):

| ERB | Astro |
|-----|-------|
| `<% %>` delimiters | `---` frontmatter, `{...}` expressions, `<script>` tags |
| Single buffer output | Three outputs: frontmatter JS, template, client script |
| Simple tag matching | Brace-matching parser for nested `{...}` |

**Reference:** `lib/ruby2js/rails/erb_compiler.rb` for position mapping and source map patterns.

**Approach:** Build `AstroCompiler` separately, then refactor common utilities (position mapping, string escaping) into shared code if patterns emerge.

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
- [ ] Ruby frontmatter for data fetching
- [ ] Interactive transpiler demos (selfhost)
- [ ] Responsive design, dark mode
- [ ] Basic navigation, table of contents

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
│   │   ├── index.astro       # Home page (Ruby frontmatter)
│   │   ├── docs/[...slug].astro
│   │   └── api/              # API routes for AI, user data
│   ├── components/
│   │   ├── Transpiler.astro  # Interactive demo
│   │   ├── Search.astro      # AI search
│   │   └── ...
│   └── layouts/
│       └── DocsLayout.astro
├── functions/                 # Cloudflare Workers
│   ├── search.js             # Vectorize queries
│   ├── ai.js                 # Workers AI
│   └── user.js               # D1 user data
└── wrangler.toml             # Cloudflare config
```

### Vite Plugin: vite-plugin-astro-ruby

```javascript
// Processes .astro files before Astro's compiler
export default function astroRuby() {
  return {
    name: 'astro-ruby',
    enforce: 'pre',
    transform(code, id) {
      if (!id.endsWith('.astro')) return;
      if (!hasRuby(code)) return;

      return {
        code: compileRubyInAstro(code),
        map: generateSourceMap(code)
      };
    }
  };
}
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
- [ ] Ruby frontmatter working in Astro files
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

### File-Level Ruby Opt-In

The `#!ruby` shebang in frontmatter applies to the **entire file**:

```astro
---
#!ruby
# Shebang here means ALL code in this file is Ruby
posts = Post.all
---

<Layout>
  {posts.map { |post| <Card post={post} /> }}  <!-- Ruby -->

  <script>
    # Also Ruby
    document.querySelector('button').addEventListener('click') { |e| ... }
  </script>
</Layout>
```

**Escape hatch:** Import external JS files when needed:

```astro
<script src="/js/third-party.js"></script>
```

This is simpler than per-expression detection and follows the principle of least surprise.

---

## Design Decisions (continued)

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
- Existing ERB compiler: `demo/selfhost/ErbCompiler.js`
