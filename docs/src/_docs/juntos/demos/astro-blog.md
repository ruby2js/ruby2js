---
order: 660
title: Astro Blog Demo
top_section: Juntos
category: juntos/demos
hide_in_toc: true
---

A static blog built with Astro and Ruby2JS. Demonstrates `.astro.rb` pages, Preact islands in `.jsx.rb`, ActiveRecord patterns with IndexedDB, and ISR caching.

{% toc %}

## Create the App

[**Try it live**](https://ruby2js.github.io/ruby2js/astro-blog/) — no install required.

To run locally:

```bash
npx github:ruby2js/juntos --demo astro-blog
cd astro-blog
```

This creates an Astro app with:

- **Astro pages** — `.astro.rb` files with Ruby frontmatter
- **Preact islands** — `.jsx.rb` interactive components
- **ActiveRecord patterns** — Post model with IndexedDB backend
- **ISR caching** — Stale-while-revalidate for data fetching
- **Full CRUD** — Create, read, update, delete posts
- **View Transitions** — Smooth page navigation

## Run the App

```bash
npm run dev
```

Open http://localhost:4321. Browse posts. Create new ones. Edit and delete them. Data persists in IndexedDB.

## Architecture

```
src/
├── pages/
│   ├── index.astro.rb           # Home page (Ruby frontmatter)
│   └── posts/
│       └── index.astro.rb       # Post list page
├── islands/
│   ├── PostList.jsx.rb          # Interactive post list + inline detail (Preact)
│   ├── PostForm.jsx.rb          # Create/edit form (Preact)
│   ├── PostDetail.jsx.rb        # View/edit/delete (Preact)
│   └── Counter.jsx.rb           # Demo counter (Preact)
├── layouts/
│   └── Layout.astro             # Base layout
└── lib/
    ├── db.js                    # Dexie database + Post model
    └── isr.js                   # ISR cache utility
```

## Key Files

### Astro Pages (.astro.rb)

Ruby frontmatter with `__END__` template separator:

```ruby
# src/pages/posts/index.astro.rb
import Layout, from: '../layouts/Layout.astro'
import PostList, from: '../islands/PostList.jsx'
import PostForm, from: '../islands/PostForm.jsx'

@title = "Posts"
__END__
<Layout title={title}>
  <h1>Blog Posts</h1>
  <PostList client:load />
  <PostForm client:load />
</Layout>
```

### Preact Islands (.jsx.rb)

React/Preact components written in Ruby:

```ruby
# src/islands/PostList.jsx.rb
import ['useState', 'useEffect'], from: 'react'
import ['setupDatabase', 'Post'], from: '../lib/db.js'
import ['withRevalidate', 'invalidate'], from: '../lib/isr.js'
import PostDetail, from: './PostDetail.jsx'

def PostList()
  posts, setPosts = useState([])
  loading, setLoading = useState(true)
  selectedSlug, setSelectedSlug = useState(nil)

  loadPosts = -> {
    withRevalidate('posts:all', 60, -> { Post.all() }).then do |data|
      setPosts(data)
      setLoading(false)
    end
  }

  useEffect -> {
    setupDatabase().then { loadPosts.() }
  }, []

  # Show post detail inline when selected
  return %x{<PostDetail slug={selectedSlug} onBack={-> { setSelectedSlug(nil) }} />} if selectedSlug

  return %x{<div class="loading">Loading...</div>} if loading

  renderPost = ->(post) {
    %x{<article key={post.id}>
      <h3>
        <a href="#" onClick={->(e) { e.preventDefault(); setSelectedSlug(post.slug) }}>
          {post.title}
        </a>
      </h3>
    </article>}
  }

  %x{<div class="posts">{posts.map(renderPost)}</div>}
end

export default PostList
```

### Post Model

ActiveRecord-like patterns with Dexie (IndexedDB):

```javascript
// src/lib/db.js
export class Post {
  static async all() {
    const rows = await this.table.orderBy('createdAt').reverse().toArray();
    return rows.map(r => new Post(r));
  }

  static async find(id) {
    const row = await this.table.get(Number(id));
    return row ? new Post(row) : null;
  }

  static async findBy(conditions) {
    const row = await this.table.where(conditions).first();
    return row ? new Post(row) : null;
  }

  static async create(attrs) {
    const id = await this.table.add({ ...attrs, createdAt: new Date() });
    return new Post({ ...attrs, id });
  }

  async save() {
    this.updatedAt = new Date();
    await Post.table.put({ ...this });
    return this;
  }

  async destroy() {
    await Post.table.delete(this.id);
  }
}
```

### ISR Cache

Stale-while-revalidate caching:

```javascript
// src/lib/isr.js
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

export function invalidate(key) {
  cache.delete(key);
}
```

## What This Demo Shows

### Astro Integration

- `.astro.rb` format with Ruby frontmatter and HTML template
- `__END__` separator (like Ruby's DATA section)
- Automatic transpilation via Vite plugin
- View Transitions for SPA-like navigation

### Preact Islands

- `.jsx.rb` components with `client:load` hydration
- Ruby blocks transpile to arrow functions: `{ |x| ... }` → `x => ...`
- React hooks: `useState`, `useEffect`
- JSX via `%x{}` syntax

### ActiveRecord Patterns

- `Post.all`, `Post.find`, `Post.findBy`
- `Post.create`, `post.save`, `post.destroy`
- Familiar Rails model interface
- IndexedDB persistence via Dexie

### ISR Caching

- `withRevalidate(key, ttl, fetcher)` for data caching
- `invalidate(key)` on mutations
- Custom events for cross-component communication
- Background revalidation for fresh data

### Full CRUD

- **Create** — PostForm creates new posts
- **Read** — PostList displays all posts, PostDetail shows one
- **Update** — PostDetail enters edit mode with PostForm
- **Delete** — PostDetail with confirmation dialog

## Production Build

```bash
npm run build
```

Creates a static site in `dist/`. Deploy to any static hosting:

- **Netlify** — Drop the `dist/` folder
- **Vercel** — `vercel --prod` from project root
- **GitHub Pages** — Push `dist/` to gh-pages branch

## What Works Differently

- **No Rails** — Pure Astro with Ruby2JS transpilation
- **Client-side data** — IndexedDB instead of server database
- **Static generation** — Pages pre-render, islands hydrate
- **ISR in browser** — In-memory cache, not CDN-level

## Comparison with Blog Demo

| Feature | Blog Demo | Astro Blog Demo |
|---------|-----------|-----------------|
| Framework | Rails | Astro |
| Backend | Ruby + SQLite | None (client-side) |
| Frontend | ERB + Turbo | Preact islands |
| Data | Server database | IndexedDB |
| Deployment | Server required | Static hosting |
| Use case | Traditional web app | Content site with interactivity |

## Next Steps

- Read the [Coming from Astro](/docs/juntos/coming-from/astro) guide for syntax details
- Learn about [ISR caching](/docs/juntos/isr) for data fetching patterns
- Try the [Blog Demo](/docs/juntos/demos/blog) for server-side Rails patterns
