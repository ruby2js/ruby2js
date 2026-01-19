---
order: 645
title: ISR (Caching)
top_section: Juntos
category: juntos
---

# ISR (Incremental Static Regeneration)

Stale-while-revalidate caching for dynamic data with fresh reads.

{% toc %}

## Overview

ISR provides automatic caching with background revalidation. Cached data is served immediately while fresh data is fetched in the background, ensuring fast responses without stale content.

```ruby
# Fetch posts with 60-second cache
posts = await withRevalidate('posts:all', 60, -> { Post.all })
```

**How it works:**

1. **Fresh (within TTL):** Return cached data immediately
2. **Stale (past TTL):** Return cached data, fetch fresh in background
3. **Missing:** Fetch fresh data, cache it, return

## API

### withRevalidate(key, ttlSeconds, fetcher)

Cache data with automatic background revalidation.

```ruby
import { withRevalidate } from '../lib/isr.js'

# Basic usage
posts = await withRevalidate('posts:all', 60, -> { Post.all })

# With parameters in the key
post = await withRevalidate("post:#{slug}", 300, -> { Post.findBy(slug: slug) })

# Longer TTL for expensive queries
stats = await withRevalidate('dashboard:stats', 3600, -> { compute_stats() })
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `key` | String | Unique cache key |
| `ttlSeconds` | Number | Time-to-live in seconds |
| `fetcher` | Function | Async function that returns fresh data |

### invalidate(key)

Remove a specific key from the cache, forcing fresh fetch on next request.

```ruby
import { invalidate } from '../lib/isr.js'

# Invalidate after mutation
post.save().then do
  invalidate('posts:all')
  invalidate("post:#{post.slug}")
end
```

### invalidateAll()

Clear the entire cache. Useful for logout or major data changes.

```ruby
import { invalidateAll } from '../lib/isr.js'

def handleLogout()
  invalidateAll()
  navigate('/login')
end
```

## Pragma Syntax (Planned)

For page-level caching, use the revalidate pragma:

```ruby
# Pragma: revalidate 60

@posts = Post.published.order(date: :desc)
__END__
<Layout>
  {posts.map { |p| <Card post={p} /> }}
</Layout>
```

This is equivalent to wrapping the page data in `withRevalidate`.

## Per-Target Implementation

ISR adapts to each deployment target:

| Target | Cache Layer | Implementation |
|--------|-------------|----------------|
| Browser | In-memory | JavaScript Map with TTL |
| Node.js | In-memory | JavaScript Map with TTL |
| Vercel | Native ISR | `revalidate` export |
| Cloudflare | Cache API | Edge caching with `stale-while-revalidate` |

### Browser / Node.js

In-memory cache using JavaScript `Map`:

```javascript
// lib/isr.js
const cache = new Map();

export async function withRevalidate(key, ttlSeconds, fetcher) {
  const cached = cache.get(key);
  const now = Date.now();

  if (cached && now < cached.staleAt) {
    return cached.data; // Fresh
  }

  if (cached) {
    // Stale - return cached, revalidate in background
    fetcher().then(data => {
      cache.set(key, { data, staleAt: now + ttlSeconds * 1000 });
    });
    return cached.data;
  }

  // Missing - fetch fresh
  const data = await fetcher();
  cache.set(key, { data, staleAt: now + ttlSeconds * 1000 });
  return data;
}
```

### Vercel

Native ISR via `revalidate` export:

```javascript
export const revalidate = 60; // seconds

export async function getStaticProps() {
  const posts = await Post.all();
  return { props: { posts } };
}
```

### Cloudflare

Cache API with `stale-while-revalidate`:

```javascript
const cache = caches.default;

async function withRevalidate(key, ttl, fetcher) {
  const cacheKey = new Request(`https://cache/${key}`);
  const cached = await cache.match(cacheKey);

  if (cached) {
    // Return cached, revalidate in background
    ctx.waitUntil(revalidate(cacheKey, ttl, fetcher));
    return cached.json();
  }

  const data = await fetcher();
  await cache.put(cacheKey, new Response(JSON.stringify(data), {
    headers: { 'Cache-Control': `max-age=${ttl}` }
  }));
  return data;
}
```

## Usage Patterns

### List with Create/Update/Delete

Invalidate on mutations to ensure list stays current:

```ruby
import { withRevalidate, invalidate } from '../lib/isr.js'

def PostList()
  posts, setPosts = useState([])

  loadPosts = -> {
    withRevalidate('posts:all', 60, -> { Post.all }).then { |data| setPosts(data) }
  }

  # Listen for changes
  useEffect -> {
    handler = -> { invalidate('posts:all'); loadPosts.() }
    window.addEventListener('post-created', handler)
    window.addEventListener('post-updated', handler)
    window.addEventListener('post-deleted', handler)
    -> {
      window.removeEventListener('post-created', handler)
      window.removeEventListener('post-updated', handler)
      window.removeEventListener('post-deleted', handler)
    }
  }, []

  # ...
end
```

### Related Queries

Invalidate related caches together:

```ruby
def invalidate_post_caches(post)
  invalidate('posts:all')
  invalidate("post:#{post.slug}")
  invalidate("category:#{post.category_id}:posts")
end
```

### Cache Key Conventions

Use consistent key patterns:

| Pattern | Example | Use Case |
|---------|---------|----------|
| `resource:all` | `posts:all` | Full collection |
| `resource:id` | `post:123` | Single record by ID |
| `resource:slug` | `post:getting-started` | Single record by slug |
| `parent:id:children` | `user:5:posts` | Scoped collection |
| `page:path` | `page:/about` | Page-level cache |

## Working Example

The [Astro Blog demo](/docs/juntos/demos/astro-blog) demonstrates ISR with:

- PostList using `withRevalidate` for 60-second caching
- Cache invalidation on create/update/delete events
- Custom events for cross-component communication

## Future Enhancements

| Target | Current | Future |
|--------|---------|--------|
| Browser | In-memory | Service Worker + Cache API |
| Node.js | In-memory | Redis adapter |
| Edge | Cache API | Durable Objects for coordination |

The architecture supports these upgrades without changing application code.
