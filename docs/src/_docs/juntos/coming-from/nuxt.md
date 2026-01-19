---
order: 688
title: Coming from Nuxt
top_section: Juntos
category: juntos/coming-from
hide_in_toc: true
---

If you know Nuxt, you'll appreciate Ruby2JS's Vue component support combined with ActiveRecord-like queries for content.

{% toc %}

## What You Know → What You Write

| Nuxt | Ruby2JS |
|------|---------|
| `.vue` components | `.vue.rb` components |
| `@nuxt/content` | Content adapter with `virtual:content` |
| `queryContent()` | `Post.where(...).order(...)` |
| Composition API | Same, with Ruby syntax |
| Auto-imports | Explicit imports (Ruby style) |

## Quick Start

Add Ruby2JS to your Nuxt config:

```javascript
// nuxt.config.ts
export default defineNuxtConfig({
  vite: {
    plugins: [
      // Add via dynamic import to avoid module issues
    ]
  },
  hooks: {
    'vite:extendConfig': async (config) => {
      const ruby2js = (await import('vite-plugin-ruby2js')).default;
      const content = (await import('@ruby2js/content-adapter/vite')).default;
      config.plugins.push(ruby2js());
      config.plugins.push(content({ dir: 'content' }));
    }
  }
});
```

## Content Collections

### Directory Structure

```
content/
  posts/
    hello-world.md
    getting-started.md
  authors/
    alice.md
components/
  PostList.vue.rb
  AuthorCard.vue.rb
pages/
  index.vue.rb
  posts/
    [slug].vue.rb
```

### Querying Content

```ruby
# components/RecentPosts.vue.rb
import { Post } from 'virtual:content'

@posts = Post.where(draft: false).order(date: :desc).limit(5)
__END__
<div>
  <h2>Recent Posts</h2>
  <article v-for="post in posts" :key="post.slug">
    <NuxtLink :to="`/posts/${post.slug}`">
      {{ post.title }}
    </NuxtLink>
  </article>
</div>
```

### Comparison: queryContent vs Content Adapter

```javascript
// Nuxt Content
const { data } = await useAsyncData('posts', () =>
  queryContent('posts')
    .where({ draft: false })
    .sort({ date: -1 })
    .limit(5)
    .find()
);
```

```ruby
# Ruby2JS Content Adapter
import { Post } from 'virtual:content'

@posts = Post.where(draft: false).order(date: :desc).limit(5)
```

Same result, Rails-like syntax.

## Vue Components in Ruby

### Script Setup

```ruby
# components/PostCard.vue.rb
@props = { post: Object }
@emit = [:click]

def handle_click
  emit('click', @post)
end
__END__
<article class="post-card" @click="handleClick">
  <h2>{{ post.title }}</h2>
  <time>{{ post.date }}</time>
  <p>{{ post.excerpt }}</p>
</article>
```

### Composables

```ruby
# composables/usePosts.rb
import { Post } from 'virtual:content'

def use_posts(options = {})
  posts = ref([])
  loading = ref(true)

  fetch_posts = -> {
    loading.value = true
    query = Post.where(draft: false)
    query = query.where(category: options[:category]) if options[:category]
    query = query.order(date: :desc)
    query = query.limit(options[:limit]) if options[:limit]
    posts.value = query.toArray()
    loading.value = false
  }

  onMounted { fetch_posts.() }

  { posts: posts, loading: loading, refresh: fetch_posts }
end
```

### Using Composables

```ruby
# pages/index.vue.rb
import { use_posts } from '~/composables/usePosts'

{ posts, loading } = use_posts(limit: 10)
__END__
<div>
  <div v-if="loading">Loading...</div>
  <div v-else>
    <PostCard v-for="post in posts" :key="post.slug" :post="post" />
  </div>
</div>
```

## Dynamic Routes

### Post Page

```ruby
# pages/posts/[slug].vue.rb
import { Post } from 'virtual:content'

@route = useRoute()
@post = Post.find(@route.params[:slug])
__END__
<article v-if="post">
  <h1>{{ post.title }}</h1>
  <time>{{ post.date }}</time>
  <div v-html="post.body"></div>
</article>
<div v-else>Post not found</div>
```

### Generate Static Paths

```ruby
# pages/posts/[slug].vue.rb
import { Post } from 'virtual:content'

# For static generation
def generate_static_params
  Post.where(draft: false).toArray().map { |p| { slug: p.slug } }
end
```

## Query API

Full ActiveRecord-like query interface:

```ruby
import { Post, Author, Tag } from 'virtual:content'

# Basic queries
Post.all
Post.where(draft: false)
Post.where(author: 'alice')

# Chaining
Post.where(draft: false)
    .where(category: 'tutorials')
    .order(date: :desc)
    .limit(10)

# Relationships
post = Post.find('hello-world')
post.author         # Author object
post.author.name    # "Alice"
post.tags           # Array of Tag objects

# Aggregates
Post.count
Post.where(published: true).count
Post.exists?
```

## Server Routes

```ruby
# server/api/posts.rb
import { Post } from 'virtual:content'

def handler(event)
  query = get_query(event)

  posts = Post.where(draft: false)
  posts = posts.where(category: query[:category]) if query[:category]
  posts = posts.order(date: :desc)
  posts = posts.limit(query[:limit].to_i) if query[:limit]

  posts.toArray()
end

export default define_event_handler(handler)
```

## Why Ruby2JS for Nuxt?

### Familiar Rails Patterns

If you know Rails, you know the query syntax:

```ruby
Post.where(published: true).order(created_at: :desc).limit(10)
```

### Cleaner Component Code

Ruby syntax in Vue components:

```ruby
# Blocks for iteration
posts.map { |p| p.title }

# String interpolation
"Hello, #{user.name}!"

# snake_case (auto-converted to camelCase)
@is_loading = true
```

### Unified Content Layer

Query markdown content like a database. No separate API endpoints needed for content:

```ruby
# Direct queries in components
@featured = Post.where(featured: true).limit(3)
@recent = Post.where(draft: false).order(date: :desc).limit(5)
@by_author = Post.where(author: current_author.slug)
```

## Configuration

```javascript
// nuxt.config.ts
export default defineNuxtConfig({
  modules: [
    // Your other modules
  ],

  hooks: {
    'vite:extendConfig': async (config) => {
      const ruby2js = (await import('vite-plugin-ruby2js')).default;
      const content = (await import('@ruby2js/content-adapter/vite')).default;

      config.plugins = config.plugins || [];
      config.plugins.push(ruby2js({
        filters: ['Functions', 'ESM', 'CamelCase']
      }));
      config.plugins.push(content({
        dir: 'content'
      }));
    }
  }
});
```

## Migration Path

1. **Add dependencies**: `npm install vite-plugin-ruby2js @ruby2js/content-adapter`
2. **Configure Nuxt**: Add Vite plugins via hooks
3. **Create content**: Add markdown files to `content/` directory
4. **Write components**: Create `.vue.rb` files for Ruby Vue components
5. **Replace queries**: Swap `queryContent()` with content adapter queries

Existing Vue components and Nuxt features continue to work unchanged.

## Next Steps

- **[Coming from Vue](/docs/juntos/coming-from/vue)** - Vue component patterns
- **[Coming from VitePress](/docs/juntos/coming-from/vitepress)** - Vue documentation sites
- **[Coming from 11ty](/docs/juntos/coming-from/eleventy)** - Liquid templates

🧪 **Feedback requested** — [Share your experience](https://github.com/ruby2js/ruby2js/discussions)
