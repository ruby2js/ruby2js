---
order: 680
title: Coming from Astro
top_section: Juntos
category: juntos/coming-from
hide_in_toc: true
---

# Coming from Astro

If you know Astro, you'll appreciate Ruby2JS's approach to multi-framework components with a focus on minimal JavaScript.

{% toc %}

## What You Know → What You Write

| Astro | Ruby2JS |
|-------|---------|
| `.astro` components | `.astro.rb` components |
| `---` frontmatter | Ruby code before `__END__` |
| `{expression}` | `{ruby_expression}` (auto-converted) |
| `{items.map(i => <jsx>)}` | `{items.map { \|i\| <jsx> }}` |
| `client:load` | Preserved |
| File-based routing | Same convention |

## The `.astro.rb` Format

Write Astro components in Ruby. The format mirrors Astro's structure:

```ruby
# src/pages/posts/[slug].astro.rb
@post = Post.find_by(slug: params[:slug])
@related = Post.where(category: @post.category).limit(3)
__END__
<Layout title={post.title}>
  <article>
    <h1>{post.title}</h1>
    <div set:html={post.body} />
  </article>

  <aside>
    <h2>Related Posts</h2>
    <ul>
      {related.map { |p| <li><a href={"/posts/#{p.slug}"}>{p.title}</a></li> }}
    </ul>
  </aside>
</Layout>
```

This compiles to a standard `.astro` file:

```astro
---
import { Post } from '../models/post'

const { slug } = Astro.params
const post = Post.findBy({slug: slug})
const related = Post.where({category: post.category}).limit(3)
---

<Layout title={post.title}>
  <article>
    <h1>{post.title}</h1>
    <div set:html={post.body} />
  </article>

  <aside>
    <h2>Related Posts</h2>
    <ul>
      {related.map(p => <li><a href={`/posts/${p.slug}`}>{p.title}</a></li>)}
    </ul>
  </aside>
</Layout>
```

## Template Syntax

### Ruby Blocks → Arrow Functions

The key transformation: Ruby blocks with JSX become JavaScript arrow functions:

```ruby
# Ruby syntax in template
{posts.map { |post| <Card post={post} /> }}

# Becomes JavaScript
{posts.map(post => <Card post={post} />)}
```

This works for all iteration patterns:

```ruby
{items.each { |item| <li>{item.name}</li> }}      # → items.map(...)
{users.select { |u| u.active }}                    # → users.filter(...)
{data.map { |d, idx| <Row data={d} index={idx} /> }}
```

### Snake Case → Camel Case

Ruby conventions automatically convert to JavaScript:

```ruby
# Ruby (snake_case)
@user_name = "Alice"
@is_loading = false
__END__
<p show_loading={is_loading}>{user_name}</p>

# JavaScript (camelCase)
const userName = "Alice"
const isLoading = false
---
<p showLoading={isLoading}>{userName}</p>
```

### Astro Directives Preserved

All Astro-specific attributes work as expected:

```ruby
__END__
<Counter initial={count} client:load />
<Chart data={data} client:visible />
<ReactComponent client:only="react" />
<div set:html={raw_content} />
<pre is:raw>{code}</pre>
```

## Instance Variables and Params

### Instance Variables → Const

Instance variables in the Ruby code become `const` declarations:

```ruby
@title = "Hello"
@count = 0
@posts = Post.all
__END__
<h1>{title}</h1>
```

### Route Params with `@@` Sigil

Use the `@@` sigil for concise route parameter access:

```ruby
# src/pages/posts/[id].astro.rb
@post = Post.find(@@id)
__END__
<h1>{post.title}</h1>
```

Becomes:

```astro
---
const post = Post.find(Astro.params.id)
---
<h1>{post.title}</h1>
```

The `@@` sigil automatically converts snake_case to camelCase:

| Ruby | JavaScript |
|------|------------|
| `@@id` | `Astro.params.id` |
| `@@user_id` | `Astro.params.userId` |
| `@@post_slug` | `Astro.params.postSlug` |

### Explicit Params Access

You can also access params explicitly via `Astro.params`:

```ruby
# src/pages/posts/[id].astro.rb
@id = Astro.params[:id]
@post = Post.find(@id)
__END__
<h1>{post.title}</h1>
```

## Model Imports

Model references are automatically detected and imported:

```ruby
@post = Post.find(1)
@comments = Comment.where(post_id: @post.id)
__END__
...
```

Generates:

```javascript
import { Post } from '../models/post'
import { Comment } from '../models/comment'
```

## Component Patterns

### Layout Component

```ruby
# src/pages/index.astro.rb
@title = "Home"
@description = "Welcome to my site"
__END__
<Layout title={title} description={description}>
  <main>
    <h1>Welcome</h1>
  </main>
</Layout>
```

### Named Slots

```ruby
__END__
<Layout>
  <div slot="sidebar">
    {sidebar_content}
  </div>
  <main>
    Main content
  </main>
</Layout>
```

### Interactive Islands

```ruby
@initial_count = 5
__END__
<Counter initial={initial_count} client:load />
<HeavyChart data={chart_data} client:visible />
```

## Methods → Functions

Methods defined in Ruby become JavaScript functions:

```ruby
def format_date(date)
  date.strftime("%Y-%m-%d")
end
__END__
<time>{format_date(post.created_at)}</time>
```

## Multi-Framework Components

Use `.astro.rb` for pages, and framework-specific extensions for components:

```
src/
  pages/
    index.astro.rb         # Astro page (Ruby)
    posts/[slug].astro.rb  # Dynamic route (Ruby)
  components/
    Counter.jsx.rb         # React island (Ruby)
    Form.vue.rb            # Vue island (Ruby)
    Animation.svelte.rb    # Svelte island (Ruby)
```

## Why Ruby2JS for Astro?

Astro's content-focused approach pairs well with Rails' data patterns:

### Full-Stack Ruby

Same language in your Astro frontmatter and your backend. Rails models work directly:

```ruby
# Backend model (Rails)
class Post < ApplicationRecord
  scope :published, -> { where(published: true) }
  scope :featured, -> { where(featured: true) }
end

# Astro page (Ruby2JS)
@posts = Post.published.order(date: :desc)
@featured = Post.featured.limit(3)
```

### Built-in ORM

Direct database access in frontmatter—no API endpoints, no fetch:

```ruby
# Instead of:
# const posts = await fetch('api/posts').then(r => r.json())

# Write:
@posts = Post.published.order(date: :desc).limit(10)
@categories = Category.with_post_counts
@author = User.find_by(slug: @@author)
```

### Rails Ecosystem

ActiveRecord queries, associations, scopes—all in your Astro pages:

```ruby
@post = Post.find_by(slug: @@slug)
@comments = @post.comments.includes(:author)
@related = Post.where(category: @post.category).limit(3)
```

### Syntax Benefits

Ruby syntax in your frontmatter:

```ruby
# String interpolation
{"Hello, #{user.name}!"}

# Blocks in templates
{posts.map { |p| <Card post={p} /> }}
```

## File Extensions

| Astro | Ruby2JS |
|-------|---------|
| `.astro` | `.astro.rb` |
| `.jsx` | `.jsx.rb` |
| `.vue` | `.vue.rb` |
| `.svelte` | `.svelte.rb` |

## Deployment

Ruby2JS supports the same deployment targets:

- **Vercel Edge** - `packages/ruby2js-rails/targets/vercel-edge/`
- **Cloudflare Workers** - `packages/ruby2js-rails/targets/cloudflare/`
- **Node.js** - `packages/ruby2js-rails/targets/node/`

## Migration Path

1. **Rename files**: `.astro` → `.astro.rb`
2. **Move frontmatter**: `---` block → Ruby code before `__END__`
3. **Convert expressions**: JavaScript → Ruby syntax
4. **Add models**: Replace API calls with direct database access

## Next Steps

- **[Vue Components](/docs/juntos/coming-from/vue)** - Vue component support
- **[Svelte Components](/docs/juntos/coming-from/svelte)** - Svelte component support
- **[React Components](/docs/juntos/coming-from/react)** - React component support
