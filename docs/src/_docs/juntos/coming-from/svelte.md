---
order: 678
title: Coming from Svelte
top_section: Juntos
category: juntos/coming-from
hide_in_toc: true
---

If you know Svelte, Ruby2JS provides the same reactive simplicity with Ruby syntax for your component logic.

{% toc %}

## What You Know → What You Write

| Svelte | Ruby2JS |
|--------|---------|
| `let count = 0` | `@count = 0` |
| `{count}` | `{count}` |
| `{#each items as item}` | `{#each items as item}` |
| `{#if condition}` | `{#if condition}` |
| `on:click={handler}` | `on:click={handler}` |
| `onMount(() => {})` | `def on_mount` |
| `$page.params.id` | `@@id` |

## Quick Start

**1. Create a component:**

```ruby
# app/pages/counter.svelte.rb
@count = 0

def increment
  @count += 1
end
__END__
<div>
  <p>Count: {count}</p>
  <button on:click={increment}>+1</button>
</div>
```

**2. The generated Svelte component:**

```svelte
<script>
let count = 0

function increment() {
  count += 1
}
</script>

<div>
  <p>Count: {count}</p>
  <button on:click={increment}>+1</button>
</div>
```

## Component Patterns

### Data Fetching with Lifecycle

```ruby
# app/pages/posts/[id].svelte.rb
@post = nil
@loading = true

def on_mount
  id = @@id
  fetch("/api/posts/#{id}")
    .then(->(r) { r.json })
    .then(->(data) {
      @post = data
      @loading = false
    })
end

def delete_post
  @post.destroy
  goto('/posts')
end
__END__
{#if loading}
  <p>Loading...</p>
{:else}
  <article>
    <h1>{post.title}</h1>
    {@html post.body}
    <button on:click={deletePost}>Delete</button>
  </article>
{/if}
```

### Forms and Binding

```ruby
@name = ""
@email = ""
@agreed = false

def submit
  return unless @agreed
  data = { name: @name, email: @email }
  fetch('/api/signup', method: 'POST', body: JSON.stringify(data))
end
__END__
<form on:submit|preventDefault={submit}>
  <input bind:value={name} placeholder="Name">
  <input bind:value={email} type="email" placeholder="Email">
  <label>
    <input type="checkbox" bind:checked={agreed}>
    I agree to the terms
  </label>
  <button type="submit" disabled={!agreed}>Sign Up</button>
</form>
```

### Each Blocks with Index and Key

```ruby
@items = [
  { id: 1, name: "Apple" },
  { id: 2, name: "Banana" },
  { id: 3, name: "Cherry" }
]

def remove(id)
  @items = @items.reject { |i| i[:id] == id }
end
__END__
<ul>
  {#each items as item, index (item.id)}
    <li>
      {index + 1}. {item.name}
      <button on:click={() => remove(item.id)}>Remove</button>
    </li>
  {/each}
</ul>
```

## SvelteKit Integration

Ruby2JS automatically handles SvelteKit imports:

```ruby
# Navigation
def go_home
  goto('/')
end

def go_back
  goto(-1)
end

# Access page params with @@ sigil
def on_mount
  id = @@id  # Becomes $page.params.id
end
```

Generated code:

```javascript
import { goto } from '$app/navigation'
import { page } from '$app/stores'

function goHome() {
  goto('/')
}

onMount(() => {
  const id = $page.params.id
})
```

## Why Ruby2JS for Svelte?

Svelte already has clean syntax—so why add Ruby? The value isn't in syntax transformation, it's in what Ruby brings to the table:

### Full-Stack Ruby

Use the same language for your SvelteKit frontend and your backend. If you know Rails, you already know the patterns:

```ruby
# Backend model (Rails)
class Post < ApplicationRecord
  validates :title, presence: true
  has_many :comments
end

# Frontend component (Ruby2JS → Svelte)
@posts = Post.published.order(created_at: :desc)
```

### Built-in ORM

Direct database access in your components—no API endpoints, no fetch calls:

```ruby
# Instead of this:
def on_mount
  fetch('/api/posts')
    .then(->(r) { r.json })
    .then(->(data) { @posts = data })
end

# Write this:
@posts = Post.where(published: true).limit(10)
@categories = Category.with_post_counts
```

### Rails Ecosystem

ActiveRecord validations, associations, and query interface—all available in your Svelte components:

```ruby
@post = Post.find(@@id)
@comments = @post.comments.includes(:author)
@related = Post.where(category: @post.category).limit(3)
```

### Syntax Benefits

The syntax improvements are modest but add up:

```ruby
# Svelte lifecycle hooks need imports
import { onMount, onDestroy } from 'svelte'
onMount(() => { /* setup */ })

# Ruby2JS - just define methods
def on_mount
  # setup
end
```

## Template Syntax

The template stays Svelte—you're just writing the script in Ruby:

### Conditionals

```svelte
{#if loading}
  <p>Loading...</p>
{:else if error}
  <p>Error: {error.message}</p>
{:else}
  <p>Ready!</p>
{/if}
```

### Loops

```svelte
{#each items as item (item.id)}
  <Item {item} />
{/each}

{#each items as item, index}
  <p>{index}: {item}</p>
{/each}
```

### Await Blocks

```svelte
{#await fetchData}
  <p>Loading...</p>
{:then data}
  <p>{data.message}</p>
{:catch error}
  <p>Error: {error}</p>
{/await}
```

## Lifecycle Hook Mapping

| Svelte | Ruby2JS Method |
|--------|----------------|
| `onMount` | `def on_mount` |
| `onDestroy` | `def on_destroy` |
| `beforeUpdate` | `def before_update` |
| `afterUpdate` | `def after_update` |

## Key Differences

### Snake Case Conversion

Ruby's `snake_case` becomes JavaScript's `camelCase`:

```ruby
@user_name = "Sam"           # → let userName
def handle_click; end        # → function handleClick()

# In template, snake_case is converted:
{user_name}                  # Converted to {userName}
on:click={handle_click}      # Converted to on:click={handleClick}
```

### File Extension

Use `.svelte.rb` for Svelte components:

```
app/pages/
  index.svelte.rb     → index.svelte
  about.svelte.rb     → about.svelte
  posts/
    [id].svelte.rb    → [id].svelte
```

### Reactive Declarations

Svelte's `$:` reactive declarations are handled through methods:

```ruby
# Instead of: $: doubled = count * 2
@count = 0

def doubled
  @count * 2
end
```

Or with explicit reactive blocks in the template:

```svelte
{@const doubled = count * 2}
<p>Doubled: {doubled}</p>
```

## Next Steps

- **[Svelte Template Compiler](/docs/filters/svelte)** - Full Svelte support documentation
- **[File-Based Routing](/docs/juntos/routing)** - SvelteKit-style routing
- **[User's Guide](/docs/users-guide/introduction)** - General Ruby2JS patterns
