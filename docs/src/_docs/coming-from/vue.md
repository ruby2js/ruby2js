---
order: 520
title: Coming from Vue
top_section: Coming From
category: coming-from
---

# Coming from Vue

If you know Vue, you'll feel at home with Ruby2JS targeting Vue. The template syntax stays the same—you just write your script in Ruby.

{% toc %}

## What You Know → What You Write

| Vue (JavaScript) | Ruby2JS |
|-----------------|---------|
| `ref(0)` | `@count = 0` |
| `count.value` | `@count` (automatic) |
| `{{ count }}` | `{{ count }}` |
| `v-for="item in items"` | `v-for="item in items"` |
| `@click="handler"` | `@click="handler"` |
| `onMounted(() => {})` | `def mounted` |
| `computed(() => ...)` | Use methods or `$:` reactive |

## Quick Start

**1. Create a component:**

```ruby
# app/pages/counter.vue.rb
@count = 0

def increment
  @count += 1
end
__END__
<div>
  <p>Count: {{ count }}</p>
  <button @click="increment">+1</button>
</div>
```

**2. The generated Vue SFC:**

```vue
<script setup>
import { ref } from 'vue'

const count = ref(0)

function increment() {
  count.value += 1
}
</script>

<template>
  <div>
    <p>Count: {{ count }}</p>
    <button @click="increment">+1</button>
  </div>
</template>
```

## Component Patterns

### Data Fetching with Lifecycle Hooks

```ruby
# app/pages/posts/[id].vue.rb
@post = nil
@loading = true

def mounted
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
  router.push('/posts')
end
__END__
<div>
  <p v-if="loading">Loading...</p>
  <article v-else>
    <h1>{{ post.title }}</h1>
    <div v-html="post.body"></div>
    <button @click="deletePost">Delete</button>
  </article>
</div>
```

### Forms and v-model

```ruby
@name = ""
@email = ""
@message = ""

def submit
  data = { name: @name, email: @email, message: @message }
  fetch('/api/contact', method: 'POST', body: JSON.stringify(data))
end
__END__
<form @submit.prevent="submit">
  <input v-model="name" placeholder="Name">
  <input v-model="email" type="email" placeholder="Email">
  <textarea v-model="message"></textarea>
  <button type="submit">Send</button>
</form>
```

### Computed Properties

Use methods or Ruby2JS reactive statements:

```ruby
@items = []

# Methods work as computed when called in template
def total
  @items.map { |i| i[:price] }.sum
end

def filtered_items
  @items.select { |i| i[:active] }
end
__END__
<div>
  <ul>
    <li v-for="item in filteredItems" :key="item.id">
      {{ item.name }} - ${{ item.price }}
    </li>
  </ul>
  <p>Total: ${{ total }}</p>
</div>
```

## Vue Router Integration

Ruby2JS automatically handles Vue Router when you use routing functions:

```ruby
# Navigation
def go_home
  router.push('/')
end

def go_back
  router.back()
end

# Access route params with @@ sigil
def mounted
  id = @@id  # Becomes route.params.id
  query = route.query
end
```

Generated code:

```javascript
import { useRouter, useRoute } from 'vue-router'

const router = useRouter()
const route = useRoute()

function goHome() {
  router.push('/')
}

onMounted(() => {
  const id = route.params.id
})
```

## The Ruby Advantage

### No .value Ceremony

```ruby
# Vue 3 Composition API
const count = ref(0)
count.value += 1
console.log(count.value)

# Ruby2JS
@count = 0
@count += 1
console.log(@count)
```

### Cleaner Lifecycle Hooks

```ruby
# Vue
onMounted(() => {
  // setup
})

onUnmounted(() => {
  // cleanup
})

# Ruby2JS
def mounted
  # setup
end

def unmounted
  # cleanup
end
```

### Instance Variables Are Reactive State

```ruby
# All instance variables become refs automatically
@user = nil
@posts = []
@loading = true

# Nested updates just work
@user[:name] = "New Name"
@posts.push(new_post)
```

## Lifecycle Hook Mapping

| Vue Composition API | Ruby2JS Method |
|--------------------|----------------|
| `onMounted` | `def mounted` |
| `onUnmounted` | `def unmounted` |
| `onBeforeMount` | `def before_mount` |
| `onBeforeUnmount` | `def before_unmount` |
| `onUpdated` | `def updated` |
| `onBeforeUpdate` | `def before_update` |

## Key Differences

### Template Stays the Same

Your Vue template syntax is unchanged—directives, interpolation, and events all work identically:

```html
<!-- These are exactly the same in Vue and Ruby2JS -->
<div v-if="show">Visible</div>
<ul>
  <li v-for="item in items" :key="item.id">{{ item.name }}</li>
</ul>
<button @click="handleClick">Click</button>
<input :value="name" @input="name = $event.target.value">
```

### Snake Case Conversion

Ruby's `snake_case` becomes JavaScript's `camelCase`:

```ruby
@user_name = "Sam"           # → userName
def handle_click; end        # → handleClick()

# In template, either works:
{{ user_name }}              # Converted to {{ userName }}
{{ userName }}               # Works as-is
```

### File Extension

Use `.vue.rb` for Vue components:

```
app/pages/
  index.vue.rb        → index.vue
  about.vue.rb        → about.vue
  posts/
    [id].vue.rb       → [id].vue
```

## Next Steps

- **[Vue Filter](/docs/filters/vue)** - Full Vue filter documentation
- **[File-Based Routing](/docs/juntos/routing)** - Next.js-style routing
- **[User's Guide](/docs/users-guide/introduction)** - General Ruby2JS patterns
