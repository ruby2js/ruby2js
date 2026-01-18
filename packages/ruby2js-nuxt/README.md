# ruby2js-nuxt

Nuxt module for Ruby2JS - write Vue components in Ruby.

## Installation

```bash
npm install ruby2js-nuxt ruby2js vite-plugin-ruby2js
```

## Usage

Add the module to your `nuxt.config.ts`:

```ts
export default defineNuxtConfig({
  modules: ['ruby2js-nuxt'],
  ruby2js: {
    // options (optional)
  }
});
```

## Writing Components

Create `.vue.rb` files with Ruby code before `__END__` and Vue template after:

```ruby
# pages/index.vue.rb
@count = 0

def increment
  @count += 1
end
__END__
<template>
  <button @click="increment">Count: {{ count }}</button>
</template>
```

This transforms to:

```vue
<script setup>
import { ref } from 'vue';

const count = ref(0);

function increment() {
  count.value += 1;
}
</script>

<template>
  <button @click="increment">Count: {{ count }}</button>
</template>
```

## Features

### Instance Variables → Refs

```ruby
@count = 0           # → const count = ref(0)
@items = []          # → const items = ref([])
@user = null         # → const user = ref(null)
```

### Route Params with `@@` Sigil

```ruby
# pages/posts/[id].vue.rb
@post = null

def mounted
  @post = await fetch("/api/posts/#{@@id}").then { |r| r.json }
end
```

Transforms to:

```vue
<script setup>
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();
const post = ref(null);

onMounted(async () => {
  post.value = await fetch(`/api/posts/${route.params.id}`).then(r => r.json());
});
</script>
```

### Lifecycle Hooks

```ruby
def mounted
  # runs when component mounts
end

def unmounted
  # runs when component is destroyed
end
```

### Ruby Blocks → Arrow Functions

```ruby
@items.map { |item| <li>{{ item.name }}</li> }
# → items.map(item => <li>{{ item.name }}</li>)
```

### Snake Case → Camel Case

```ruby
@user_name = "Alice"      # → const userName = ref("Alice")
@is_loading = true        # → const isLoading = ref(true)
```

## Nuxt Page Routes

Nuxt supports custom page extensions. With the module, `.vue.rb` files work as pages:

```
pages/
├── index.vue.rb           # → /
├── about.vue.rb           # → /about
└── posts/
    ├── index.vue.rb       # → /posts
    └── [id].vue.rb        # → /posts/:id
```

## Options

```ts
export default defineNuxtConfig({
  modules: ['ruby2js-nuxt'],
  ruby2js: {
    eslevel: 2022,    // ES level to target (default: 2022)
    camelCase: true   // Convert snake_case to camelCase (default: true)
  }
});
```

## How It Works

The module:
1. Adds `.vue.rb` to Nuxt's page extensions
2. Registers vite-plugin-ruby2js for transformation
3. Watches for changes during development

Because Nuxt supports custom extensions and uses Vite, the transformation happens in-memory during the build - no file duplication needed.

## License

MIT
