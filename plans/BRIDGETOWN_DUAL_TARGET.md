# Bridgetown Dual-Target Demo

A speculative plan for enabling Bridgetown sites to run on both Bridgetown (Ruby) and Astro (JavaScript) from the same source files.

**Status:** Exploratory - revisit after ASTRO_BLOG_DEMO.md Phase 7 is complete

## Context

### The Relationship

- Jared White (Bridgetown maintainer) is the #2 contributor to Ruby2JS
- Bridgetown already supports Ruby2JS as a frontend option via esbuild
- These are complementary projects in the same ecosystem, not competitors

### The Precedent

The `test/blog/create-blog` demo shows a Rails app that runs on both:
- **Rails** (Ruby): `bin/rails server`
- **Juntos** (JavaScript): `bin/juntos dev -d dexie`

Same source files, different runtimes. Could the same be done for Bridgetown?

## Vision

```
Same Ruby/ERB source files
            ↓
    ┌───────┴───────┐
    │               │
Bridgetown      Astro + Ruby2JS
(Ruby SSG)      (JavaScript SSG)
    │               │
    ├─ Traditional  ├─ Edge (Cloudflare, Vercel)
    │  hosting      ├─ Browser-only (no server)
    │               └─ Hybrid SSR
```

A Bridgetown site author could:
1. Develop locally with Bridgetown (familiar Ruby tooling)
2. Deploy traditionally (GitHub Pages, Netlify static)
3. **OR** transpile to Astro for edge deployment
4. Same source files, same content, different runtimes

This reframes "Coming from Bridgetown" from a migration guide into a **deployment option**.

## What Would Need Transpilation

| Bridgetown | Astro + Ruby2JS |
|------------|-----------------|
| ERB layouts (`src/_layouts/*.erb`) | Astro layouts (`.astro.erb.rb`) |
| ERB partials/components | Astro components |
| Ruby helpers | Ruby2JS helper functions |
| `bridgetown.config.yml` | `astro.config.mjs` |
| Markdown + front matter | Content Collections (nearly identical) |
| Ruby plugins | Vite/Astro plugins (case-by-case) |

## Dependencies

### Required: Phase 7 of ASTRO_BLOG_DEMO.md

Phase 7 implements the ERB → pnode transformer for Preact islands:
- XML parser for well-formed HTML
- ERB expression handling (`<%= %>`, `<% %>`)
- Control flow mapping (`if/else`, `each` → `map`)
- pnode AST generation

This infrastructure is the foundation for full-page ERB → Astro transformation.

### Would Need Extension

| Phase 7 Provides | Bridgetown Demo Needs |
|------------------|----------------------|
| `.erb.rb` → Preact islands | `.erb` → Astro pages |
| Island-scoped templates | Full layout templates |
| Component output | Page + layout output |
| Preact/React target | Astro target |

## Minimal Demo Structure

```
bridgetown-dual/
├── src/
│   ├── _layouts/
│   │   └── default.erb
│   ├── _components/
│   │   └── post_card.erb
│   ├── _posts/
│   │   ├── 2024-01-01-first-post.md
│   │   └── 2024-01-02-second-post.md
│   └── index.erb
├── bridgetown.config.yml
└── bin/
    ├── bridgetown          # Run with Bridgetown (Ruby)
    └── astro               # Run with Astro (JavaScript)
```

### Demo Script

```bash
test/bridgetown-dual/create-bridgetown-dual my-site
cd my-site

# Run with Bridgetown
bin/bridgetown start

# Run with Astro (transpiled)
bin/astro dev
```

## Technical Approach

### ERB → Astro Page Transformation

Extend Phase 7's ERB parser to output Astro format:

```erb
<!-- Bridgetown: src/_layouts/default.erb -->
<!DOCTYPE html>
<html>
<head>
  <title><%= data.title %></title>
</head>
<body>
  <%= yield %>
</body>
</html>
```

```ruby
# Astro: src/layouts/default.astro.erb.rb
@title = Astro.props[:title]
__END__
<!DOCTYPE html>
<html>
<head>
  <title><%= title %></title>
</head>
<body>
  <slot />
</body>
</html>
```

### Content Collections Compatibility

Bridgetown markdown:
```markdown
---
layout: post
title: My First Post
date: 2024-01-01
---
Content here...
```

Astro Content Collections:
```markdown
---
title: My First Post
date: 2024-01-01
---
Content here...
```

Mapping is straightforward. Layout is handled differently (Astro uses explicit layout in page, not front matter).

### Helper Mapping

| Bridgetown Helper | Ruby2JS Equivalent |
|-------------------|-------------------|
| `link_to` | `<a href={...}>` |
| `image_tag` | `<img src={...}>` |
| `render` | Component import |
| `data.site.title` | Config import |
| `yield` | `<slot />` |

## Benefits

### For Bridgetown Users

- Edge deployment without rewriting
- Browser-only deployment option
- Access to Astro ecosystem (islands, View Transitions)
- Keep using familiar ERB syntax

### For Ruby2JS

- Larger potential user base
- Validates ERB transformation capabilities
- Strengthens Bridgetown partnership
- Demonstrates "Ruby everywhere" vision

### For the Ruby Community

- More deployment options for Ruby-authored sites
- Edge computing becomes accessible
- Reduces "rewrite in JavaScript" pressure

## Open Questions

1. **Plugin compatibility**: How many Bridgetown plugins could be transpiled vs. need Astro equivalents?

2. **Dynamic features**: Bridgetown supports dynamic routes and SSR. How do these map to Astro?

3. **Resource system**: Bridgetown has a resource system. Does it have an Astro equivalent?

4. **Liquid templates**: Bridgetown supports Liquid. Focus on ERB only, or support both?

5. **Two-way sync**: Could changes in Astro format be synced back to Bridgetown format?

## Collaboration Approach

Jared White is the #2 contributor to Ruby2JS but prefers not to work with LLMs. Suggested approach:

1. Build the demo independently
2. Present the working demo to Jared
3. Discuss technical merits and UX without focusing on how it was built
4. If compelling, collaborate on refinements and documentation

## Success Criteria

- [ ] Same Bridgetown site builds and runs on Bridgetown
- [ ] Same source files transpile and run on Astro
- [ ] Output is visually identical
- [ ] Edge deployment works (Cloudflare or Vercel)
- [ ] No manual translation required

## Timeline

**Prerequisites:**
- ASTRO_BLOG_DEMO.md Phase 7 complete (ERB → pnode transformer)

**Then:**
1. Extend ERB parser for full pages (not just islands)
2. Build layout transformation
3. Build helper mappings
4. Create demo script
5. Test with representative Bridgetown site
6. Document and discuss with Jared

---

*This plan is exploratory. It may be picked up after Phase 7 or archived if the approach proves impractical.*
