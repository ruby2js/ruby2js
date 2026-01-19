---
order: 655
title: SSG Blog Demo
top_section: Juntos
category: juntos/demos
hide_in_toc: true
---

A minimal static blog built with 11ty and Ruby2JS. Start simple - markdown content with ActiveRecord-like queries. No JavaScript required.

{% toc %}

## The Simple Path

This demo shows progressive disclosure: you don't need to learn everything to get started.

| What You Need | What You Get |
|---------------|--------------|
| Markdown files | Blog posts |
| YAML front matter | Queryable attributes |
| Liquid templates | Static pages |
| Content adapter | Rails-like queries |

No React. No islands. No ISR caching. Just content and queries.

## Create the App

```bash
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/ssg-blog/create-ssg-blog | bash -s ssg-blog
cd ssg-blog
```

This creates an 11ty site with:

- **Markdown content** in `content/posts/` and `content/authors/`
- **Liquid templates** in `src/`
- **Content adapter** for ActiveRecord-like queries
- **Zero client-side JavaScript**

## Run the App

```bash
npm run dev
```

Open http://localhost:8080. Browse posts. That's it.

## Architecture

```
ssg-blog/
├── content/
│   ├── posts/
│   │   ├── 2024-01-15-welcome.md
│   │   └── 2024-01-20-getting-started.md
│   └── authors/
│       └── sam.md
├── src/
│   ├── _data/
│   │   └── site.js          # Content adapter setup
│   ├── _includes/
│   │   └── layout.liquid    # Base layout
│   ├── index.liquid         # Home page
│   └── about.liquid         # About page
├── eleventy.config.js
└── package.json
```

## Key Files

### Content with Front Matter

```markdown
---
title: Welcome to the Blog
date: 2024-01-15
author: sam
tags: [ruby, javascript]
draft: false
excerpt: An introduction to Ruby2JS.
---

Your content here...
```

### Data File (site.js)

The content adapter scans your markdown and creates queryable collections:

```javascript
import { createCollection } from '@ruby2js/content-adapter';

// Automatically scans content/ directories
// Creates: site.posts (array) and site.Post (queryable)
```

### Liquid Templates

Standard 11ty Liquid templates with content data:

```liquid
{% raw %}{% for post in site.posts %}
  {% unless post.draft %}
  <article>
    <h2>{{ post.title }}</h2>
    <time>{{ post.date | date: "%B %d, %Y" }}</time>
  </article>
  {% endunless %}
{% endfor %}{% endraw %}
```

## Query API

The content adapter provides ActiveRecord-like queries:

```javascript
// In data files or build scripts
site.Post.where({ draft: false })
site.Post.where({ author: 'sam' }).order({ date: 'desc' })
site.Post.find('welcome')
site.Post.count()
```

## What This Demo Shows

### Minimal Complexity

- No JavaScript framework (React, Vue, Preact)
- No client-side hydration
- No build-time islands
- Just markdown → HTML

### Familiar Tools

- 11ty (static site generator)
- Liquid (template language)
- Markdown (content format)
- YAML (front matter)

### One New Concept

The content adapter. That's it. Everything else is standard 11ty.

```javascript
import { createCollection } from '@ruby2js/content-adapter';
```

## Production Build

```bash
npm run build
```

Creates a static site in `_site/`. Deploy anywhere:

- **Netlify** — Drop the `_site/` folder
- **GitHub Pages** — Push `_site/` to gh-pages branch
- **Any static host** — It's just HTML files

## Comparison with Astro Blog Demo

| Feature | SSG Blog | Astro Blog |
|---------|----------|------------|
| Framework | 11ty | Astro |
| Templates | Liquid | `.astro.rb` |
| Interactivity | None | Preact islands |
| Data storage | Build-time only | IndexedDB |
| JavaScript | Zero | Islands hydrate |
| Complexity | Minimal | Full-featured |
| Use case | Content sites | Interactive apps |

**Start here**, then move to Astro when you need interactivity.

## When to Use This Demo

Choose SSG Blog when:

- You have a content-focused site (blog, docs, portfolio)
- You don't need client-side interactivity
- You want the simplest possible setup
- You're new to Ruby2JS

Choose [Astro Blog](/docs/juntos/demos/astro-blog) when:

- You need interactive components
- You want client-side data persistence
- You're building an app, not just a site

## Next Steps

- Read the [Coming from 11ty](/docs/juntos/coming-from/eleventy) guide for more patterns
- Try the [Astro Blog Demo](/docs/juntos/demos/astro-blog) when ready for interactivity
- Explore the [Content Adapter](/docs/juntos/content-adapter) documentation
