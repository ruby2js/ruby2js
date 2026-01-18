# ruby2js-svelte

SvelteKit preprocessor for Ruby2JS - write Svelte components in Ruby.

## Installation

```bash
npm install ruby2js-svelte ruby2js
```

## Usage

Add the preprocessor and extension to your `svelte.config.js`:

```js
import adapter from '@sveltejs/adapter-auto';
import { ruby2jsPreprocess } from 'ruby2js-svelte';

export default {
  preprocess: [ruby2jsPreprocess()],
  extensions: ['.svelte', '.svelte.rb'],
  kit: {
    adapter: adapter()
  }
};
```

## Writing Components

Create `.svelte.rb` files with Ruby code before `__END__` and Svelte template after:

```ruby
# src/routes/+page.svelte.rb
@count = 0

def increment
  @count += 1
end
__END__
<button on:click={increment}>
  Count: {count}
</button>
```

This transforms to:

```svelte
<script>
  let count = 0;

  function increment() {
    count += 1;
  }
</script>

<button on:click={increment}>
  Count: {count}
</button>
```

## Features

### Instance Variables → Reactive Let

```ruby
@count = 0           # → let count = 0
@items = []          # → let items = []
@user = null         # → let user = null
```

### Route Params with `@@` Sigil

```ruby
# src/routes/posts/[id]/+page.svelte.rb
@post = null

def on_mount
  @post = await fetch("/api/posts/#{@@id}").then { |r| r.json }
end
```

Transforms to:

```svelte
<script>
  import { page } from '$app/stores';
  import { onMount } from 'svelte';

  let post = null;

  onMount(async () => {
    post = await fetch(`/api/posts/${$page.params.id}`).then(r => r.json());
  });
</script>
```

### Lifecycle Hooks

```ruby
def on_mount
  # runs when component mounts
end

def on_destroy
  # runs when component is destroyed
end
```

### Ruby Blocks → Arrow Functions

```ruby
@items.map { |item| <li>{item.name}</li> }
# → items.map(item => <li>{item.name}</li>)
```

### Snake Case → Camel Case

```ruby
@user_name = "Alice"      # → let userName = "Alice"
@is_loading = true        # → let isLoading = true
```

## SvelteKit Page Routes

Unlike Astro, SvelteKit supports custom page extensions natively. With `.svelte.rb` in the `extensions` array, these files work as pages:

```
src/routes/
├── +page.svelte.rb           # → /
├── about/+page.svelte.rb     # → /about
└── posts/
    ├── +page.svelte.rb       # → /posts
    └── [id]/+page.svelte.rb  # → /posts/:id
```

## Options

```js
ruby2jsPreprocess({
  eslevel: 2022,    // ES level to target (default: 2022)
  camelCase: true   // Convert snake_case to camelCase (default: true)
})
```

## How It Works

The preprocessor:
1. Intercepts `.svelte.rb` files during Svelte compilation
2. Transforms Ruby code to JavaScript via Ruby2JS
3. Returns a standard Svelte component

Because SvelteKit supports custom extensions, no file duplication is needed - the transformation happens in-memory during the build.

## License

MIT
