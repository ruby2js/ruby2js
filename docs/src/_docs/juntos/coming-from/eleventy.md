---
order: 686
title: Coming from 11ty
top_section: Juntos
category: juntos/coming-from
hide_in_toc: true
---

If you know 11ty, you'll appreciate Ruby2JS's ActiveRecord-like queries over your content collections.

{% toc %}

## What You Know → What You Write

| 11ty | Ruby2JS |
|------|---------|
| `_data/posts.js` | `_data/site.js` with `createCollection` |
| `{% raw %}{% for post in posts %}{% endraw %}` | Same (Liquid unchanged) |
| JavaScript data files | Content adapter scans markdown |
| Manual filtering | `Post.where(draft: false)` |
| `collection.getFilteredByTag()` | `Post.where(tag: 'ruby')` |
| Computed data | Relationships resolve automatically |

## Quick Start

Install the content adapter:

```bash
npm install @ruby2js/content-adapter
```

Create a data file that loads your content:

```javascript
// src/_data/site.js
import fs from 'fs';
import path from 'path';
import matter from 'gray-matter';
import { marked } from 'marked';
import { createCollection } from '@ruby2js/content-adapter';

export default function() {
  const posts = loadMarkdownFiles('content/posts');
  return {
    posts,
    Post: createCollection('posts', posts)
  };
}
```

Use it in templates:

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

## The Content Adapter

### ActiveRecord-like Queries

The content adapter provides familiar Rails query methods over your markdown files:

```javascript
// In your data file
const Post = createCollection('posts', posts);

// These queries work:
Post.where({ draft: false })
Post.where({ author: 'alice' }).order({ date: 'desc' })
Post.find('hello-world')  // by slug
Post.find_by({ title: 'Welcome' })
Post.first()
Post.last()
Post.count()
Post.limit(10).offset(5)
```

### Relationships

Define relationships between collections:

```javascript
const Author = createCollection('authors', authors);
const Post = createCollection('posts', posts);

Post.belongsTo('author', Author);

// Now post.author resolves automatically
const post = Post.first();
console.log(post.author.name);  // "Alice"
```

### Convention-Based Inference

If your post has `author: alice` and you have an `authors/alice.md` file, the relationship is inferred automatically.

## Content Structure

```
content/
  posts/
    2024-01-15-welcome.md
    2024-01-20-getting-started.md
  authors/
    alice.md
    bob.md
src/
  _data/
    site.js
  _includes/
    layout.liquid
  index.liquid
```

### Markdown with Front Matter

```markdown
---
title: Welcome to the Blog
date: 2024-01-15
author: alice
draft: false
tags: [ruby, javascript]
---

Your content here...
```

### Slug Extraction

Slugs are extracted from filenames automatically:

| Filename | Slug |
|----------|------|
| `2024-01-15-hello-world.md` | `hello-world` |
| `alice.md` | `alice` |

## Query API Reference

| Method | Description |
|--------|-------------|
| `where(conditions)` | Filter by attributes |
| `where().not(conditions)` | Exclude by attributes |
| `order({ field: 'asc' })` | Sort results |
| `limit(n)` | Limit result count |
| `offset(n)` | Skip first n records |
| `find(slug)` | Find by slug |
| `find_by(conditions)` | Find first matching |
| `first()` / `last()` | Get first/last record |
| `count()` | Count records |
| `exists()` | Check if any exist |
| `toArray()` | Execute and return array |

## Why Ruby2JS for 11ty?

### Familiar Query Syntax

Instead of writing custom JavaScript filter logic:

```javascript
// Before: Custom filtering
const published = posts.filter(p => !p.draft)
  .sort((a, b) => new Date(b.date) - new Date(a.date))
  .slice(0, 10);
```

Write Rails-style queries:

```javascript
// After: ActiveRecord-like
Post.where({ draft: false }).order({ date: 'desc' }).limit(10)
```

### Automatic Relationships

No manual data joining:

```javascript
// Before: Manual lookup
const authorData = authors.find(a => a.slug === post.author);

// After: Automatic resolution
post.author.name  // Just works
```

### Same Collections, More Power

Your existing content structure works unchanged. The adapter adds query capabilities without requiring migration.

## Full Data File Example

```javascript
// src/_data/site.js
import fs from 'fs';
import path from 'path';
import matter from 'gray-matter';
import { marked } from 'marked';
import { createCollection } from '@ruby2js/content-adapter';

const contentDir = path.resolve(process.cwd(), 'content');

function loadCollection(name) {
  const dir = path.join(contentDir, name);
  if (!fs.existsSync(dir)) return [];

  return fs.readdirSync(dir)
    .filter(f => f.endsWith('.md'))
    .map(f => {
      const content = fs.readFileSync(path.join(dir, f), 'utf-8');
      const { data, content: body } = matter(content);
      const slug = f.replace(/^\d{4}-\d{2}-\d{2}-/, '').replace('.md', '');
      return { ...data, slug, body: marked(body) };
    });
}

export default function() {
  const posts = loadCollection('posts');
  const authors = loadCollection('authors');

  const Post = createCollection('posts', posts);
  const Author = createCollection('authors', authors);

  // Wire relationships
  Post.belongsTo('author', Author);

  return { posts, authors, Post, Author };
}
```

## Template Examples

### List Published Posts

```liquid
{% raw %}{% for post in site.posts %}
  {% unless post.draft %}
    <article>
      <h2><a href="/posts/{{ post.slug }}/">{{ post.title }}</a></h2>
      <time>{{ post.date | date: "%B %d, %Y" }}</time>
      <p>{{ post.excerpt }}</p>
    </article>
  {% endunless %}
{% endfor %}{% endraw %}
```

### Posts by Tag

```liquid
{% raw %}{% assign ruby_posts = site.posts | where: "tags", "ruby" %}
{% for post in ruby_posts %}
  <li>{{ post.title }}</li>
{% endfor %}{% endraw %}
```

### Author Page

```liquid
{% raw %}{% assign author = site.authors | where: "slug", page.author | first %}
<div class="author">
  <h2>{{ author.name }}</h2>
  <p>{{ author.bio }}</p>
</div>{% endraw %}
```

## Migration Path

1. **Install adapter**: `npm install @ruby2js/content-adapter`
2. **Create data file**: Add `src/_data/site.js` with content loading
3. **Update templates**: Reference `site.posts`, `site.authors`, etc.
4. **Add queries**: Use `site.Post.where(...)` for complex filtering

Your existing markdown files and Liquid templates require no changes.

## Next Steps

- **[Coming from VitePress](/docs/juntos/coming-from/vitepress)** - Vue-based SSG
- **[Coming from Nuxt](/docs/juntos/coming-from/nuxt)** - Vue full-stack framework
- **[Coming from Bridgetown](/docs/juntos/coming-from/bridgetown)** - Ruby SSG

🧪 **Feedback requested** — [Share your experience](https://github.com/ruby2js/ruby2js/discussions)
