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

### Route Params

Access route parameters via `params`:

```ruby
# src/pages/posts/[id].astro.rb
@id = params[:id]
@post = Post.find(@id)
__END__
<h1>{post.title}</h1>
```

Becomes:

```astro
---
const { id } = Astro.params
const post = Post.find(id)
---
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

## The Ruby Advantage

### Server-Side Logic

```ruby
# Astro (JavaScript)
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

# Ruby2JS
{"Hello, #{user.name}!"}
```

### Built-in ORM

```ruby
# Direct database access in page logic
@posts = Post.published.order(date: :desc).limit(10)
@categories = Category.with_post_counts

# No separate API needed for server-rendered content
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

- **[Vue Components](/docs/coming-from/vue)** - Vue component support
- **[Svelte Components](/docs/coming-from/svelte)** - Svelte component support
- **[React Components](/docs/coming-from/react)** - React component support
