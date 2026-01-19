# SSG Targets

Add static site generators to Juntos's list of transformation targets. Ruby authoring with ActiveRecord queries, deploying to Astro, Nuxt, SvelteKit, VitePress, and 11ty.

**Status:** Design validated, ready for implementation

## Vision

Juntos reimplements proven Rails patterns but doesn't reinvent reactivity, bundling, or platform integration. Those come from Vue, Svelte, React, Vite, Capacitor, and the rest of the JavaScript ecosystem.

**The same principle applies to static site generation.** Don't build an SSG. Transform Ruby into forms that SSGs consume.

```
┌─────────────────────────────────────────┐
│           Ruby Authoring Layer          │
│                                         │
│  Content:   posts/*.md (front matter)   │
│  Queries:   Post.where(...).order(...)  │
│  Templates: .vue.rb / .svelte.rb /      │
│             .astro.rb / .liquid.rb      │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│         Vite Transformation Layer       │
│                                         │
│  vite-plugin-ruby2js:                   │
│    - Ruby → JavaScript                  │
│    - ActiveRecord → JS query API        │
│    - Template compilation               │
│    - Content collection loading         │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│      Native SSG Format (Output)         │
│                                         │
│  .astro / .vue / .svelte / .liquid      │
│  + JavaScript data (collections)        │
└─────────────────────────────────────────┘
                    ↓
┌───────┬───────┬──────────┬──────────┬───────┐
│ Astro │ Nuxt  │ SvelteKit│ VitePress│  11ty │
└───────┴───────┴──────────┴──────────┴───────┘
```

Ruby2JS's core competency is transformation. The SSG provides static site generation, content processing, routing, and deployment. Vite provides bundling, HMR, and the plugin pipeline. Ruby2JS transforms Ruby authoring into forms that leverage both.

## Why This Works

All target SSGs use Vite (or can integrate with it):

| SSG | Vite | Status |
|-----|------|--------|
| Astro | ✅ Default | Already supported |
| Nuxt 3 | ✅ Default | Already supported |
| SvelteKit | ✅ Default | Already supported |
| VitePress | ✅ Default | Vue templates work |
| 11ty | ⚠️ Optional | Needs Liquid compiler |

The Vite plugin is the universal integration point. SSGs see their native formats.

## What Exists

| Component | Status |
|-----------|--------|
| vite-plugin-ruby2js | ✅ Complete |
| Vue template compiler | ✅ Complete |
| Svelte template compiler | ✅ Complete |
| Astro template compiler | ✅ Complete |
| ERB compiler | ✅ Complete |
| ActiveRecord (databases) | ✅ Complete |

## What's Needed

| Component | Effort | Precedent |
|-----------|--------|-----------|
| Content scanner | Small | Directory walking exists |
| ActiveRecord content adapter | Medium | Same pattern as Dexie, D1 adapters |
| Liquid template compiler | Medium | Same pattern as Vue, Svelte, Astro |
| SSG integration glue | Small | Vite plugin infrastructure exists |

## Package Architecture

The content adapter is a separate package with no coupling to `vite-plugin-ruby2js`:

```
@ruby2js/content-adapter
├── index.js              # Runtime: createCollection, query API
└── vite.js               # Build-time: Vite plugin for scanning content/
```

**User's Vite config:**

```javascript
import ruby2js from 'vite-plugin-ruby2js';
import content from '@ruby2js/content-adapter/vite';

export default {
  plugins: [
    ruby2js(),
    content({ dir: 'content' })
  ]
}
```

**Why separate:**

- **No coupling** — Two independent Vite plugins that work together
- **Clear responsibility** — Content scanning/querying is distinct from Ruby→JS transformation
- **Independent versioning** — Can release fixes without touching the Vite plugin
- **Smaller footprint** — Users not doing SSG work don't pull in gray-matter, markdown parser, etc.

**Integration point:** The `virtual:content` module exports collection classes that Ruby code imports and queries—standard JavaScript imports, nothing special.

## The ActiveRecord Content Adapter

Content collections are just another ActiveRecord backend. The same query API that works across Dexie, SQLite, D1, Neon, and Turso also works over markdown files.

### Content Structure

```
content/
  posts/
    2024-01-01-hello.md
    2024-01-02-world.md
  authors/
    alice.md
    bob.md
```

### Front Matter → Attributes

```markdown
---
title: Hello World
date: 2024-01-01
author: alice
tags: [ruby, javascript]
draft: false
---

Content here...
```

### Query API

```ruby
# Same syntax as database queries
Post.where(draft: false).order(date: :desc).limit(10)
Post.find_by(slug: 'hello-world')
post.author  # Resolves relationship to Author record
```

### Adapter Scope

The content adapter implements the Dexie-compatible subset of ActiveRecord:

| Method | Supported |
|--------|-----------|
| `where(hash)` | ✅ |
| `where.not(hash)` | ✅ |
| `order(column: direction)` | ✅ |
| `limit` / `offset` | ✅ |
| `find` / `find_by` | ✅ |
| `first` / `last` / `count` | ✅ |
| `includes` (eager load) | ✅ |
| Associations | ✅ |
| Raw SQL | ❌ (no SQL backend) |

This is the same constraint as Dexie/IndexedDB—if it works there, it works here.

### Build Strategy: Build-Time Materialization

Content is scanned and materialized at build time, not runtime:

```
content/posts/*.md
       ↓ (Vite build)
JavaScript module with records array
       ↓
ActiveRecord-like API filters in-memory
```

This matches how SSGs work—all content is known at build time. The Dexie adapter already proves the array-filtering approach works.

### Conventions

**Directory → Class name:** Pluralized directory name becomes singularized class name (standard Rails inflection):

```
content/posts/    → Post
content/authors/  → Author
content/tags/     → Tag
```

**Slug from filename:** The filename (without date prefix and extension) becomes the `slug` attribute:

```
2024-01-01-hello-world.md → slug: "hello-world"
alice.md                  → slug: "alice"
```

### Relationship Resolution

Relationships are inferred by convention. When an attribute name matches a collection name:

```yaml
# content/posts/hello.md
author: alice           # → Author.find_by(slug: "alice")
tags: [ruby, javascript] # → Tag.where(slug: ["ruby", "javascript"])
```

- Singular attribute (`author`) → `belongsTo` (returns one record)
- Plural attribute (`tags`) → `hasMany` (returns array)

### Generated Output

The Vite plugin provides a virtual module `virtual:content` (following the convention of `astro:content`, etc.):

```javascript
// virtual:content
import { createCollection } from '@ruby2js/content-adapter';

export const Post = createCollection('posts', [
  { slug: "hello-world", title: "Hello World", date: "2024-01-01", author: "alice", body: "<p>...</p>" },
  { slug: "another-post", title: "Another Post", date: "2024-01-02", author: "bob", body: "<p>...</p>" }
]);

export const Author = createCollection('authors', [
  { slug: "alice", name: "Alice", bio: "..." },
  { slug: "bob", name: "Bob", bio: "..." }
]);

// Relationship wiring
Post.belongsTo('author', Author);
Post.hasMany('tags', Tag);
```

### Importing Collections

Ruby code uses explicit imports (matching the majority of frameworks):

```ruby
import { Post, Author } from 'virtual:content'

Post.where(draft: false).order(date: :desc).limit(10)
post.author  # Resolves via belongsTo
```

Transforms to JavaScript that queries these in-memory collections. Auto-import could be added later as an enhancement.

## The Liquid Template Compiler

Liquid uses a regular, parseable syntax:

| Syntax | Purpose |
|--------|---------|
| `{{ expr }}` | Output expression |
| `{% tag %}` | Logic/control flow |
| `{{ expr \| filter }}` | Filters |

### Transformation

```liquid
<!-- Input: Liquid + Ruby -->
{% for post in posts.where(draft: false).order(date: :desc) %}
  <h2>{{ post.title }}</h2>
  <time>{{ post.published_at.strftime("%B %d, %Y") }}</time>
{% endfor %}
```

```liquid
<!-- Output: Liquid + JavaScript -->
{% for post in posts.filter(p => !p.draft).sort((a,b) => b.date - a.date) %}
  <h2>{{ post.title }}</h2>
  <time>{{ post.publishedAt.toLocaleDateString("en-US", {month: "long", day: "numeric", year: "numeric"}) }}</time>
{% endfor %}
```

### Implementation Pattern

Same as Vue, Svelte, Astro compilers:
1. Parse template to find expression boundaries
2. Extract Ruby expressions
3. Transform via Ruby2JS
4. Reassemble valid output

Liquid's delimiters (`{{ }}`, `{% %}`) are unambiguous. The parser is straightforward.

## Implementation Phases

### Phase 1: Content Adapter

1. **Content scanner** — Walk directories, discover markdown files
2. **Front matter parser** — Extract YAML metadata (use gray-matter or equivalent)
3. **Markdown renderer** — Convert body to HTML
4. **Collection builder** — Build in-memory "table" of records
5. **ActiveRecord adapter** — Implement query interface over collections

**Output:** `Post.where(...).order(...)` works over markdown files.

### Phase 2: Liquid Compiler

1. **Liquid parser** — Tokenize `{{ }}` and `{% %}` blocks
2. **Expression extractor** — Identify Ruby expressions
3. **Transformer** — Ruby2JS conversion
4. **Reassembler** — Output valid Liquid

**Output:** `.liquid.rb` files transform to `.liquid` files.

### Phase 3: 11ty Integration

1. **Vite + 11ty setup** — Configure 11ty to use Vite
2. **Content loading** — Feed collections into 11ty data
3. **Template transformation** — `.liquid.rb` in Vite pipeline
4. **End-to-end test** — Build a site with Ruby authoring

**Output:** Working 11ty site authored in Ruby.

### Phase 4: Documentation

1. **Coming from 11ty** — Guide for 11ty developers
2. **Coming from VitePress** — Guide for VitePress developers
3. **Coming from Nuxt** — Guide for Nuxt developers (content focus)
4. **Coming from Bridgetown** — Guide for Bridgetown developers
5. **Update index** — Add SSG category to Coming From index

**Output:** Framework list grows from 6 to 10.

## New "Coming From" Guides

### Expanded Framework List

| Category | Frameworks |
|----------|------------|
| **Component** | React, Vue, Svelte |
| **Full-stack** | Next.js, Astro |
| **SSG/Content** | 11ty, VitePress, Nuxt |
| **Ruby** | Rails, Bridgetown |

### Guide Structure

Each SSG guide follows the established pattern:

1. **What You Know → What You Write** — Mapping table
2. **Quick Start** — 5-minute working example
3. **The Ruby Advantage** — ActiveRecord queries over content
4. **Template Syntax** — How Ruby maps to native templates
5. **Key Differences** — Gotchas and adjustments

### Example: Coming from 11ty

| 11ty | Ruby2JS |
|------|---------|
| `_data/posts.js` | `Post.where(...).order(...)` |
| `{{ post.title }}` | `{{ post.title }}` (same) |
| `{% for post in posts %}` | `{% for post in posts.published.recent %}` |
| Nunjucks/Liquid | Liquid + Ruby expressions |
| JavaScript data files | Ruby data files (`.rb`) |

**Value prop:** ActiveRecord queries over your content. Filter, sort, paginate, relate—with Ruby syntax.

## Demo Site

A reference implementation using the author's blog (intertwingly.net) structure:

```
demo/ssg/
├── content/
│   └── posts/
│       └── *.md
├── src/
│   ├── _data/
│   │   └── posts.rb          # Post.published.order(date: :desc)
│   ├── _includes/
│   │   └── layout.liquid.rb  # Ruby expressions in Liquid
│   └── index.liquid.rb
├── .eleventy.js
├── vite.config.js
└── package.json
```

Demonstrates:
- ActiveRecord queries over markdown content
- Liquid templates with Ruby expressions
- Vite transformation pipeline
- 11ty as the SSG

## Success Criteria

- [ ] `Post.where(draft: false).order(date: :desc)` works over markdown files
- [ ] `.liquid.rb` transforms to `.liquid` via Vite
- [ ] Demo site builds with 11ty
- [ ] "Coming from 11ty" guide complete
- [ ] "Coming from VitePress" guide complete
- [ ] "Coming from Bridgetown" guide complete
- [ ] Framework count in docs: 6 → 10

## Alignment

This plan follows the Juntos philosophy:

> Juntos reimplements proven Rails patterns but doesn't reinvent reactivity, bundling, or platform integration. Those come from Vue, Svelte, React, Vite, Capacitor, and the rest of the JavaScript ecosystem.

**Extended:**

> Juntos reimplements proven Rails patterns but doesn't reinvent static site generation. That comes from Astro, Nuxt, SvelteKit, VitePress, and 11ty. You get Rails' developer experience with the SSG ecosystem's reach.

Ruby2JS's core competency is transformation. This is more of the same.
