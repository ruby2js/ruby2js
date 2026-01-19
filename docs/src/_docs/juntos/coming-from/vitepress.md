---
order: 687
title: Coming from VitePress
top_section: Juntos
category: juntos/coming-from
hide_in_toc: true
---

If you know VitePress, you'll appreciate Ruby2JS's Vue template support combined with ActiveRecord-like content queries.

{% toc %}

## What You Know → What You Write

| VitePress | Ruby2JS |
|-----------|---------|
| `.md` with Vue components | Same, plus `.vue.rb` components |
| `{% raw %}{{ frontmatter.title }}{% endraw %}` | Same (Vue syntax unchanged) |
| `data/*.js` loaders | Content adapter via `virtual:content` |
| Custom Vue components | `.vue.rb` components with Ruby |
| Vite plugins | Add `vite-plugin-ruby2js` + `content-adapter/vite` |

## Quick Start

Add Ruby2JS to your VitePress config:

```javascript
// .vitepress/config.js
import ruby2js from 'vite-plugin-ruby2js';
import content from '@ruby2js/content-adapter/vite';

export default {
  vite: {
    plugins: [
      ruby2js(),
      content({ dir: 'content' })
    ]
  }
}
```

Create a Ruby Vue component:

```ruby
# components/PostList.vue.rb
@posts = []

def mounted
  @posts = Post.where(draft: false).order(date: :desc).limit(5)
end
__END__
<div>
  <article v-for="post in posts" :key="post.slug">
    <h2>{{ post.title }}</h2>
    <time>{{ post.date }}</time>
  </article>
</div>
```

## Content Collections

### Directory Structure

```
content/
  posts/
    getting-started.md
    advanced-usage.md
  authors/
    alice.md
docs/
  index.md
  guide/
    introduction.md
.vitepress/
  config.js
  theme/
    index.js
```

### Importing Collections

Use the `virtual:content` module in your components:

```ruby
# components/RecentPosts.vue.rb
import { Post } from 'virtual:content'

@recent = Post.where(draft: false).order(date: :desc).limit(5)
__END__
<aside class="recent-posts">
  <h3>Recent Posts</h3>
  <ul>
    <li v-for="post in recent" :key="post.slug">
      <a :href="`/posts/${post.slug}`">{{ post.title }}</a>
    </li>
  </ul>
</aside>
```

### In Data Loaders

Use the content adapter in VitePress data loaders:

```javascript
// posts/[slug].paths.js
import { Post } from 'virtual:content';

export default {
  paths() {
    return Post.where({ draft: false }).toArray().map(post => ({
      params: { slug: post.slug },
      content: post
    }));
  }
}
```

## Vue Components in Ruby

### Script Setup Style

```ruby
# components/PostCard.vue.rb
@props = { post: Object }

def formatted_date
  @post.date.to_date.strftime("%B %d, %Y")
end
__END__
<article class="post-card">
  <h2>{{ post.title }}</h2>
  <time>{{ formatted_date() }}</time>
  <p>{{ post.excerpt }}</p>
</article>
```

### Reactive State

```ruby
# components/SearchPosts.vue.rb
import { Post } from 'virtual:content'

@query = ""
@results = []

def search
  return @results = [] if @query.length < 2
  @results = Post.where(title: @query).limit(10).toArray()
end
__END__
<div class="search">
  <input v-model="query" @input="search" placeholder="Search posts...">
  <ul v-if="results.length">
    <li v-for="post in results" :key="post.slug">
      <a :href="`/posts/${post.slug}`">{{ post.title }}</a>
    </li>
  </ul>
</div>
```

## Query API

The content adapter provides ActiveRecord-like queries:

```ruby
import { Post, Author } from 'virtual:content'

# Filtering
Post.where(draft: false)
Post.where(author: 'alice')
Post.where().not(draft: true)

# Ordering
Post.order(date: :desc)
Post.order(title: :asc)

# Pagination
Post.limit(10).offset(20)

# Finding
Post.find('hello-world')  # by slug
Post.find_by(title: 'Welcome')
Post.first
Post.last

# Counting
Post.count
Post.where(draft: false).count

# Chaining
Post.where(draft: false)
    .where(author: 'alice')
    .order(date: :desc)
    .limit(5)
```

## Theme Customization

### Custom Layout

```ruby
# .vitepress/theme/Layout.vue.rb
import { Post } from 'virtual:content'

@recent_posts = Post.where(draft: false).order(date: :desc).limit(3)
__END__
<div class="layout">
  <header>
    <nav>
      <a href="/">Home</a>
      <a href="/guide/">Guide</a>
    </nav>
  </header>

  <main>
    <Content />
  </main>

  <aside>
    <h3>Recent Posts</h3>
    <ul>
      <li v-for="post in recentPosts" :key="post.slug">
        <a :href="`/posts/${post.slug}`">{{ post.title }}</a>
      </li>
    </ul>
  </aside>
</div>
```

### Theme Setup

```javascript
// .vitepress/theme/index.js
import DefaultTheme from 'vitepress/theme';
import PostList from './components/PostList.vue';
import PostCard from './components/PostCard.vue';

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component('PostList', PostList);
    app.component('PostCard', PostCard);
  }
}
```

## Why Ruby2JS for VitePress?

### Content as Data

Query your markdown content like a database:

```ruby
# Instead of manual file processing
Post.where(category: 'tutorials')
    .where(draft: false)
    .order(date: :desc)
```

### Relationships

Authors, tags, categories—all linked automatically:

```ruby
post = Post.find('getting-started')
post.author.name  # Resolves from authors collection
post.tags         # Array of Tag objects
```

### Ruby in Vue

Write Vue components with Ruby syntax:

```ruby
# Blocks become arrow functions
posts.map { |p| p.title }  # → posts.map(p => p.title)

# snake_case becomes camelCase
@is_loading  # → isLoading
```

## Vite Configuration

```javascript
// .vitepress/config.js
import { defineConfig } from 'vitepress';
import ruby2js from 'vite-plugin-ruby2js';
import content from '@ruby2js/content-adapter/vite';

export default defineConfig({
  title: 'My Docs',
  description: 'Documentation with Ruby2JS',

  vite: {
    plugins: [
      ruby2js({
        filters: ['Functions', 'ESM', 'CamelCase']
      }),
      content({
        dir: 'content'
      })
    ]
  }
});
```

## Migration Path

1. **Add plugins**: Install `vite-plugin-ruby2js` and `@ruby2js/content-adapter`
2. **Configure Vite**: Add plugins to `.vitepress/config.js`
3. **Create content**: Add markdown files to `content/` directory
4. **Write components**: Create `.vue.rb` files for Ruby Vue components
5. **Import collections**: Use `virtual:content` in components

Your existing VitePress markdown and Vue components continue to work unchanged.

## Next Steps

- **[Coming from Vue](/docs/juntos/coming-from/vue)** - Vue component patterns
- **[Coming from Nuxt](/docs/juntos/coming-from/nuxt)** - Full-stack Vue
- **[Coming from 11ty](/docs/juntos/coming-from/eleventy)** - Liquid templates

🧪 **Feedback requested** — [Share your experience](https://github.com/ruby2js/ruby2js/discussions)
