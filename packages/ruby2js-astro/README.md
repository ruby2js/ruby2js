# ruby2js-astro

Astro integration for Ruby2JS - write Astro components in Ruby.

## Installation

```bash
npm install ruby2js-astro
```

## Usage

Add the integration to your `astro.config.mjs`:

```js
import { defineConfig } from 'astro/config';
import ruby2js from 'ruby2js-astro';

export default defineConfig({
  integrations: [ruby2js()]
});
```

## Writing Components

Create `.astro.rb` files with Ruby code before `__END__` and Astro template after:

```ruby
# src/pages/index.astro.rb
@title = "My Site"
@posts = await Astro.glob("./posts/*.md")
@sorted = @posts.sort_by { |p| p.frontmatter.date }.reverse
__END__
<Layout title={title}>
  <h1>Recent Posts</h1>
  {sorted.map(post => <PostCard post={post} />)}
</Layout>
```

This transforms to:

```astro
---
const title = "My Site";
const posts = await Astro.glob("./posts/*.md");
const sorted = posts.slice().sort((a, b) => /* ... */).reverse();
---
<Layout title={title}>
  <h1>Recent Posts</h1>
  {sorted.map(post => <PostCard post={post} />)}
</Layout>
```

## Features

### Instance Variables → Constants

```ruby
@title = "Hello"      # → const title = "Hello"
@count = 42           # → const count = 42
```

### Route Params with `@@` Sigil

```ruby
# src/pages/posts/[id].astro.rb
@post = Post.find(@@id)   # → const post = Post.find(Astro.params.id)
```

### Ruby Blocks → Arrow Functions

```ruby
@posts.map { |p| <Card post={p} /> }
# → posts.map(p => <Card post={p} />)
```

### Snake Case → Camel Case

```ruby
@user_name = "Alice"      # → const userName = "Alice"
@is_loading = true        # → const isLoading = true
```

## How It Works

Unlike a Vite plugin alone, this integration:

1. **Transforms files before Astro sees them** - Astro only recognizes `.astro` files for page routing
2. **Watches for changes** - Re-transforms when you edit `.astro.rb` files during dev
3. **Integrates with Astro's build** - Ensures files are fresh before production builds

## Options

```js
ruby2js({
  eslevel: 2022,    // ES level to target (default: 2022)
  camelCase: true   // Convert snake_case to camelCase (default: true)
})
```

## Limitations

- Both `.astro.rb` and generated `.astro` files exist in your source tree
- This is due to Astro's architecture - page routing only recognizes `.astro` extension

Consider adding `*.astro` to `.gitignore` if you want to treat them as build artifacts:

```gitignore
# Generated from .astro.rb files
src/**/*.astro
!src/**/*.astro.rb
```

## License

MIT
