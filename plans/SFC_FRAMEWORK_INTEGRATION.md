# SFC Framework Integration Plan: Vue, Svelte, Astro

## Status: Planning 📋

Use native framework compilers to parse single-file components, extract script sections, convert Ruby to JavaScript using self-hosted Ruby2JS, and let framework compilers handle the rest.

## Prerequisites

- [ ] Self-hosted `functions` filter
- [ ] Self-hosted `esm` filter  
- [ ] Option for plain `this.property` (no `_` or `#` prefix)

## Architecture

```
.vue / .svelte / .astro file
           ↓
Framework Compiler (parse)
           ↓
Component AST
           ↓
Extract script content
           ↓
Ruby2JS (self-hosted) → JavaScript
           ↓
Replace script in AST/source
           ↓
Framework Compiler (continues)
           ↓
Final output (JS + CSS + etc.)
```

## Framework Details

### Vue (.vue files)

**Compiler:** `@vue/compiler-sfc`

**Script locations:**
- `<script>` - Options API or Composition API
- `<script setup>` - Composition API with auto-imports

**Template expressions:** `{{ expression }}`, `:prop="expression"`, `@event="handler"`

**Example Ruby Vue component:**
```vue
<script setup>
count = ref(0)
doubled = computed { count.value * 2 }

def increment
  count.value += 1
end
</script>

<template>
  <button @click="increment">{{ count }} (doubled: {{ doubled }})</button>
</template>
```

**Converts to:**
```vue
<script setup>
const count = ref(0);
const doubled = computed(() => count.value * 2);

function increment() {
  count.value++
}
</script>
```

**Implementation notes:**
- Composition API works well (no `this.` needed)
- Options API needs plain `this.property` option
- Template expressions may need conversion too

---

### Svelte (.svelte files)

**Compiler:** `svelte/compiler` → `parse()`

**Script locations:**
- `<script>` - Component logic
- `<script context="module">` - Module-level code

**Template expressions:** `{expression}`, `on:event={handler}`

**Reactive declarations:** `$: derived = count * 2` (no Ruby equivalent)

**Example Ruby Svelte component:**
```svelte
<script>
count = 0

def increment
  count += 1
end

# Proposed convention for reactive declarations
reactive { doubled = count * 2 }
</script>

<button on:click={increment}>
  {count} (doubled: {doubled})
</button>
```

**Converts to:**
```svelte
<script>
let count = 0;

function increment() {
  count++
}

$: doubled = count * 2;
</script>
```

**Implementation notes:**
- Basic variables/functions convert cleanly
- Need DSL for `$:` reactive declarations
- Svelte stores (`$store`) need consideration

**Proposed reactive DSL:**
```ruby
reactive { doubled = count * 2 }     # → $: doubled = count * 2
reactive { console.log(count) }      # → $: console.log(count)
```

---

### Astro (.astro files)

**Compiler:** `@astrojs/compiler`

**Script locations:**
- Frontmatter (`---` fences) - Runs at build time
- `<script>` tags - Client-side JavaScript

**Template expressions:** `{expression}`

**Example Ruby Astro component:**
```astro
---
# Frontmatter (build-time)
title = "My Page"
posts = await fetch_posts()
featured = posts.select { |p| p.featured }.first(3)
---

<Layout title={title}>
  <h1>{title}</h1>
  <ul>
    {featured.map { |post| 
      <li><a href={post.url}>{post.title}</a></li>
    }}
  </ul>
</Layout>

<script>
  # Client-side interactivity
  def handle_click(event)
    console.log("clicked", event.target)
  end
  
  document.querySelector("button")&.addEventListener("click", handle_click)
</script>
```

**Implementation notes:**
- Cleanest integration point (clear script boundaries)
- Frontmatter is explicitly for logic
- Can use any UI framework for islands
- JSX-like syntax in templates

---

## Vite Plugin Architecture

All three frameworks use Vite. A unified plugin structure:

```javascript
// vite-plugin-ruby2js.mjs
import { convert } from '@anthropic/ruby2js';  // self-hosted package

export function ruby2js(options = {}) {
  return {
    name: 'ruby2js',
    enforce: 'pre',
    
    transform(code, id) {
      if (id.endsWith('.vue')) {
        return transformVue(code, options);
      }
      if (id.endsWith('.svelte')) {
        return transformSvelte(code, options);
      }
      if (id.endsWith('.astro')) {
        return transformAstro(code, options);
      }
    }
  }
}

async function transformVue(code, options) {
  const { parse } = await import('@vue/compiler-sfc');
  const { descriptor } = parse(code);
  
  let result = code;
  
  // Transform <script> block
  if (descriptor.script?.content) {
    const js = convert(descriptor.script.content, options);
    result = result.replace(descriptor.script.content, js);
  }
  
  // Transform <script setup> block
  if (descriptor.scriptSetup?.content) {
    const js = convert(descriptor.scriptSetup.content, options);
    result = result.replace(descriptor.scriptSetup.content, js);
  }
  
  // Optionally transform template expressions
  // (more complex - requires template AST walking)
  
  return result;
}

async function transformSvelte(code, options) {
  const { parse } = await import('svelte/compiler');
  const ast = parse(code);
  
  // ast.instance = <script> content
  // ast.module = <script context="module"> content
  
  if (ast.instance) {
    const scriptContent = code.slice(
      ast.instance.content.start,
      ast.instance.content.end
    );
    const js = convert(scriptContent, options);
    // Replace in source
  }
  
  return result;
}

async function transformAstro(code, options) {
  const { parse } = await import('@astrojs/compiler');
  const ast = await parse(code);
  
  // Extract frontmatter and script tags
  // Convert each Ruby section to JS
  
  return result;
}
```

## Template Expression Handling

Template expressions require additional work:

### Vue
```javascript
// Walk template AST
function walkVueTemplate(node, convert) {
  if (node.type === 'INTERPOLATION') {
    // {{ rubyExpression }} → {{ jsExpression }}
    node.content = convert(node.content);
  }
  if (node.props) {
    node.props.forEach(prop => {
      if (prop.type === 'DIRECTIVE') {
        // :value="rubyExpr" or @click="rubyExpr"
        prop.exp = convert(prop.exp);
      }
    });
  }
  node.children?.forEach(child => walkVueTemplate(child, convert));
}
```

### Svelte
```javascript
// Walk Svelte AST
function walkSvelteTemplate(node, convert) {
  if (node.type === 'MustacheTag') {
    // {rubyExpression} → {jsExpression}
  }
  if (node.type === 'EventHandler') {
    // on:click={rubyExpr}
  }
  // ... etc
}
```

## Instance Variable Handling

Current behavior:
- `underscored_private: true` → `@foo` becomes `this._foo`
- `underscored_private: false` → `@foo` becomes `this.#foo`

**Needed for Vue Options API:**
- New option: `plain_properties: true` → `@foo` becomes `this.foo`

```ruby
# Vue Options API style
{
  data: -> { { count: 0 } },
  methods: {
    increment: -> { @count += 1 }  # needs this.count, not this._count
  }
}
```

## Proposed DSL Extensions

### Svelte Reactive Declarations
```ruby
reactive { doubled = count * 2 }
# → $: doubled = count * 2

reactive { 
  if count > 10
    console.log("high count!")
  end
}
# → $: { if (count > 10) { console.log("high count!") } }
```

### Svelte Stores
```ruby
store_value = $count        # → let store_value = $count
$count = 5                  # → $count = 5 (store set)
```

## Implementation Phases

### Phase 1: Core Infrastructure
- [ ] Add `plain_properties` option to Ruby2JS
- [ ] Self-host `functions` filter
- [ ] Self-host `esm` filter
- [ ] Package self-hosted converter as npm module

### Phase 2: Vue Integration
- [ ] Create Vite plugin for .vue files
- [ ] Script block extraction and conversion
- [ ] Test with Composition API
- [ ] Test with Options API
- [ ] Template expression conversion (optional)

### Phase 3: Svelte Integration
- [ ] Create Vite plugin for .svelte files
- [ ] Script block extraction and conversion
- [ ] Implement `reactive {}` DSL
- [ ] Test basic components
- [ ] Store handling (optional)

### Phase 4: Astro Integration
- [ ] Create Vite plugin for .astro files
- [ ] Frontmatter conversion
- [ ] Client-side script conversion
- [ ] Test with various UI framework islands

### Phase 5: Polish
- [ ] Unified plugin with framework auto-detection
- [ ] Source maps support
- [ ] Error messages with original Ruby line numbers
- [ ] Documentation and examples
- [ ] npm package publication

## Testing Strategy

Each framework needs:
1. **Unit tests** - Script extraction/replacement
2. **Integration tests** - Full component compilation
3. **Example apps** - Real-world usage patterns

```
demo/
  vue-ruby/           # Vue + Ruby example app
  svelte-ruby/        # Svelte + Ruby example app  
  astro-ruby/         # Astro + Ruby example app
```

## Open Questions

1. **Template expressions** - Worth the complexity? Or just scripts?
2. **TypeScript** - Support `.vue` with `<script lang="ts">`?
3. **Hot reload** - Does HMR work correctly with transformation?
4. **IDE support** - Syntax highlighting for Ruby in SFC files?
5. **File extension** - `.vue` vs `.vue.rb` vs new extension?

## References

- [@vue/compiler-sfc](https://www.npmjs.com/package/@vue/compiler-sfc)
- [svelte/compiler](https://svelte.dev/docs/svelte-compiler)
- [@astrojs/compiler](https://www.npmjs.com/package/@astrojs/compiler)
- [Vite Plugin API](https://vitejs.dev/guide/api-plugin.html)
- [Self-hosted Ruby2JS](../demo/selfhost/)
