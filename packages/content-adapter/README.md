# @ruby2js/content-adapter

ActiveRecord-like query API over markdown content collections. Designed for static site generators.

## Installation

```bash
npm install @ruby2js/content-adapter
```

## Usage

### Vite Plugin

```javascript
// vite.config.js
import ruby2js from 'vite-plugin-ruby2js';
import content from '@ruby2js/content-adapter/vite';

export default {
  plugins: [
    ruby2js(),
    content({ dir: 'content' })
  ]
}
```

### Content Structure

```
content/
  posts/
    2024-01-01-hello-world.md
    2024-01-15-getting-started.md
  authors/
    alice.md
    bob.md
```

Each markdown file has YAML front matter:

```markdown
---
title: Hello World
date: 2024-01-01
author: alice
draft: false
tags: [ruby, javascript]
---

Your content here...
```

### Querying Content

```ruby
import { Post, Author } from 'virtual:content'

# ActiveRecord-like queries
Post.where(draft: false).order(date: :desc).limit(10)
Post.find_by(slug: 'hello-world')
Post.where(author: 'alice').count

# Relationships resolve automatically
post = Post.first
post.author.name  # => "Alice"
```

## Query API

| Method | Description |
|--------|-------------|
| `where(hash)` | Filter by conditions |
| `where.not(hash)` | Exclude by conditions |
| `order(column: direction)` | Sort (`:asc` or `:desc`) |
| `limit(n)` | Limit results |
| `offset(n)` | Skip first n records |
| `find(slug)` | Find by slug |
| `find_by(hash)` | Find first matching |
| `first` / `last` | Get first/last record |
| `count` | Count records |
| `exists?` | Check if any records exist |
| `toArray()` | Execute query, return array |

## Conventions

### Directory → Class Name

Pluralized directory names become singularized class names:

- `content/posts/` → `Post`
- `content/authors/` → `Author`
- `content/categories/` → `Category`

### Slug from Filename

The slug is extracted from the filename, removing date prefixes:

- `2024-01-01-hello-world.md` → `slug: "hello-world"`
- `alice.md` → `slug: "alice"`

### Automatic Relationships

Relationships are inferred by convention:

- `author: alice` + `authors/` collection → `belongsTo` (singular → plural)
- `tags: [a, b]` + `tags/` collection → `hasMany` (array attribute)

## Liquid Template Compiler

The Vite plugin also transforms `.liquid.rb` files, converting Ruby expressions to JavaScript.

### Input (index.liquid.rb)

```liquid
{% for post in published_posts %}
  <article>
    <h2>{{ post.title }}</h2>
    <time>{{ post.published_at }}</time>
    {% if post.featured %}
      <span class="featured">Featured</span>
    {% endif %}
  </article>
{% endfor %}
```

### Output (index.liquid)

```liquid
{% for post in publishedPosts %}
  <article>
    <h2>{{ post.title }}</h2>
    <time>{{ post.publishedAt }}</time>
    {% if post.featured %}
      <span class="featured">Featured</span>
    {% endif %}
  </article>
{% endfor %}
```

### Supported Transformations

| Liquid Syntax | Ruby → JavaScript |
|--------------|-------------------|
| `{{ expr }}` | snake_case → camelCase |
| `{% for x in collection %}` | Collection expressions converted |
| `{% if condition %}` | Conditions converted |
| `{% elsif condition %}` | Conditions converted |
| `{% unless condition %}` | Conditions converted |
| `{% case expr %}` | Expression converted |
| `{% when value %}` | Values converted |
| `{% assign var = expr %}` | Expression converted |

Liquid filters (e.g., `{{ title | escape }}`) are preserved.

### Programmatic Usage

```javascript
import { compileLiquid } from '@ruby2js/content-adapter/liquid';

const result = await compileLiquid(template, { eslevel: 2022 });
console.log(result.template);  // Compiled Liquid
console.log(result.errors);    // Any conversion errors
```

## License

MIT
