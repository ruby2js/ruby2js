---
order: 550
title: Coming from Astro
top_section: Coming From
category: coming-from
---

# Coming from Astro

If you know Astro, you'll appreciate Ruby2JS's approach to multi-framework components with a focus on minimal JavaScript.

{% toc %}

## What You Know → What You Write

| Astro | Ruby2JS |
|-------|---------|
| `.astro` components | `.erb.rb` pages (server) |
| React/Vue/Svelte islands | `.jsx.rb`, `.vue.rb`, `.svelte.rb` |
| `---` frontmatter | Ruby code before `__END__` |
| `{expression}` | `<%= expression %>` (ERB) |
| File-based routing | Same convention |
| `client:load` | Automatic hydration |

## Quick Start

**1. Server-rendered page with Ruby:**

```ruby
# app/pages/posts/[slug].erb.rb
@post = Post.find_by(slug: params[:slug])
@related = Post.where(category: @post.category).limit(3)
__END__
<!DOCTYPE html>
<html>
<head>
  <title><%= @post.title %></title>
</head>
<body>
  <article>
    <h1><%= @post.title %></h1>
    <%= @post.body %>
  </article>

  <aside>
    <h2>Related Posts</h2>
    <ul>
      <% @related.each do |post| %>
        <li><a href="/posts/<%= post.slug %>"><%= post.title %></a></li>
      <% end %>
    </ul>
  </aside>
</body>
</html>
```

**2. Interactive component (island):**

```ruby
# app/components/Counter.jsx.rb
export default
def Counter(initial: 0)
  count, setCount = useState(initial)

  %x{
    <button onClick={() => setCount(count + 1)}>
      Count: {count}
    </button>
  }
end
```

**3. Use the component in your page:**

```erb
<body>
  <h1>Welcome</h1>

  <!-- Interactive island -->
  <div data-component="Counter" data-props='{"initial": 5}'></div>

  <!-- Rest is static HTML -->
  <footer>Static content</footer>
</body>
```

## Content Collections

### Blog with Markdown

```ruby
# app/pages/blog/[slug].erb.rb
@post = Content.find('blog', params[:slug])
@prev_post = Content.prev('blog', @post)
@next_post = Content.next('blog', @post)
__END__
<article>
  <h1><%= @post.title %></h1>
  <time><%= @post.date.strftime('%B %d, %Y') %></time>

  <%= @post.content %>

  <nav class="pagination">
    <% if @prev_post %>
      <a href="/blog/<%= @prev_post.slug %>">← <%= @prev_post.title %></a>
    <% end %>
    <% if @next_post %>
      <a href="/blog/<%= @next_post.slug %>"><%= @next_post.title %> →</a>
    <% end %>
  </nav>
</article>
```

### Dynamic Routes

```
app/pages/
  blog/
    index.erb.rb       → /blog
    [slug].erb.rb      → /blog/:slug
  docs/
    [...path].erb.rb   → /docs/*path
```

## Multi-Framework Islands

Use the right framework for each component:

```ruby
# React for complex state
# app/components/DataTable.jsx.rb
export default
def DataTable(data:, columns:)
  # Complex sorting, filtering, pagination...
end

# Vue for form handling
# app/components/ContactForm.vue.rb
@name = ""
@email = ""
@submitted = false

def submit
  # Form logic...
end
__END__
<form @submit.prevent="submit">
  <!-- Vue template -->
</form>

# Svelte for animations
# app/components/AnimatedList.svelte.rb
@items = []

def on_mount
  # Animation setup...
end
__END__
{#each items as item (item.id)}
  <div transition:slide>{item.name}</div>
{/each}
```

## The Ruby Advantage

### Server-Side Logic

```ruby
# Astro frontmatter
---
const posts = await fetch('api/posts').then(r => r.json())
const featured = posts.filter(p => p.featured)
---

# Ruby2JS
@posts = Post.all
@featured = @posts.select { |p| p.featured }
```

### String Interpolation

```ruby
# Astro
{`Hello, ${user.name}!`}

# Ruby2JS (ERB)
Hello, <%= user.name %>!

# Ruby2JS (component)
"Hello, #{user[:name]}!"
```

### Built-in ORM

```ruby
# Direct database access in page logic
@posts = Post.published.order(date: :desc).limit(10)
@categories = Category.with_post_counts

# No separate API needed for server-rendered content
```

## ISR and Caching

Like Astro's hybrid rendering:

```ruby
# Pragma: revalidate 3600

# This page regenerates every hour
@posts = Post.published.limit(20)
__END__
<ul>
  <% @posts.each do |post| %>
    <li><%= post.title %></li>
  <% end %>
</ul>
```

## Key Differences

### Template Syntax

Astro uses `{expression}`, Ruby2JS uses ERB for server pages:

```erb
<!-- Astro -->
<h1>{post.title}</h1>
{#if post.featured}
  <span class="featured">★</span>
{/if}

<!-- Ruby2JS (ERB) -->
<h1><%= @post.title %></h1>
<% if @post.featured %>
  <span class="featured">★</span>
<% end %>
```

### Component Scripts

Astro has frontmatter, Ruby2JS has `__END__`:

```ruby
# Astro
---
const data = await fetch('...').then(r => r.json())
---
<div>{data.title}</div>

# Ruby2JS
@data = fetch_data
__END__
<div><%= @data[:title] %></div>
```

### File Extensions

| Astro | Ruby2JS |
|-------|---------|
| `.astro` | `.erb.rb` (server) |
| `.jsx` | `.jsx.rb` |
| `.vue` | `.vue.rb` |
| `.svelte` | `.svelte.rb` |

## Deployment

Ruby2JS supports the same deployment targets:

```ruby
# Vercel Edge
# packages/ruby2js-rails/targets/vercel-edge/

# Cloudflare Workers
# packages/ruby2js-rails/targets/cloudflare/

# Node.js
# packages/ruby2js-rails/targets/node/
```

## Migration Path

1. **Start with pages**: Convert `.astro` to `.erb.rb`
2. **Keep components**: React/Vue/Svelte components stay similar
3. **Update imports**: Use Ruby2JS conventions
4. **Add models**: Replace API calls with direct database access

## Next Steps

- **[ERB Templates](/docs/filters/erb)** - Server-side templating
- **[React Filter](/docs/filters/react)** - React component support
- **[Vue Filter](/docs/filters/vue)** - Vue component support
- **[Deployment](/docs/juntos/deployment)** - Edge and server deployment
