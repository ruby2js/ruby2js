---
order: 682
title: Architecture
top_section: Juntos
category: juntos/coming-from
hide_in_toc: true
---

Ruby2JS doesn't implement frameworks—it transforms Ruby into framework-native code. Each target framework handles its own reactivity, rendering, and runtime behavior.

{% toc %}

## The Core Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│                        Ruby Source                               │
│    @count = 0                                                    │
│    def increment; @count += 1; end                               │
│    __END__                                                       │
│    <button on:click={increment}>{count}</button>                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │   Ruby2JS Parser  │
                    │      (Prism)      │
                    └─────────┬─────────┘
                              │
                    ┌─────────┴─────────┐
                    │   Ruby AST +      │
                    │   Template        │
                    └─────────┬─────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
       ┌───────────┐   ┌───────────┐   ┌───────────┐
       │Vue Filter │   │ Svelte    │   │ React     │
       │           │   │ Filter    │   │ Filter    │
       └─────┬─────┘   └─────┬─────┘   └─────┬─────┘
              │               │               │
              ▼               ▼               ▼
       ┌───────────┐   ┌───────────┐   ┌───────────┐
       │Vue SFC    │   │ Svelte    │   │ React     │
       │           │   │ Component │   │ Component │
       └───────────┘   └───────────┘   └───────────┘
```

## Key Insight

Ruby2JS is a **transpiler**, not a runtime. Each piece of the transformation:

| Component | Ruby2JS Responsibility | Framework Responsibility |
|-----------|----------------------|-------------------------|
| Parsing | Extract Ruby code + template | — |
| AST Transform | Map Ruby patterns to JS patterns | — |
| Template | Convert expressions to framework syntax | Compile and render |
| Reactivity | Generate proper declarations | Handle state updates |
| Routing | Discover file-based routes | Handle navigation |
| Caching | Generate cache headers/calls | Store and serve |

## Transformation Layers

### 1. Parser Layer

```ruby
source = <<~RUBY
  @post = nil
  def on_mount
    @post = Post.find(params[:id])
  end
  __END__
  <h1>{post.title}</h1>
RUBY

ast, comments, template = Ruby2JS.parse(source)
# ast → Ruby AST for code portion
# template → "<h1>{post.title}</h1>"
```

### 2. Filter Layer

Filters transform AST nodes based on the target:

```ruby
# Svelte filter transforms instance variables
class SvelteFilter
  def on_ivasgn(node)
    # @count = 0 → let count = 0
    var_name = node.children[0].to_s[1..-1]
    s(:let, var_name, process(node.children[1]))
  end
end

# Vue filter transforms to refs
class VueFilter
  def on_ivasgn(node)
    # @count = 0 → const count = ref(0)
    var_name = node.children[0].to_s[1..-1]
    s(:const, var_name, s(:call, nil, :ref, process(node.children[1])))
  end
end
```

### 3. Template Compiler Layer

Each framework has its own template syntax:

```ruby
# Vue: {{ expression }}
VueTemplateCompiler.compile("{{ user_name }}")
# → "{{ userName }}"

# Svelte: {expression}
SvelteTemplateCompiler.compile("{user_name}")
# → "{userName}"
```

### 4. Component Transformer Layer

Combines script and template into complete component:

```ruby
VueComponentTransformer.transform(source)
# Returns: Result(sfc:, script:, template:, imports:, errors:)

SvelteComponentTransformer.transform(source)
# Returns: Result(component:, script:, template:, imports:, errors:)
```

## Adding a New Target

A new framework target needs:

### 1. Filter Module

```ruby
# lib/ruby2js/filter/myframework.rb
module Ruby2JS
  module Filter
    module MyFramework
      include SEXP

      # Transform instance variables
      def on_ivasgn(node)
        # ...
      end

      # Transform method definitions
      def on_def(node)
        # ...
      end

      # Transform lifecycle hooks
      def on_send(node)
        # ...
      end
    end
  end
end
```

### 2. Template Compiler (if custom syntax)

```ruby
# lib/ruby2js/myframework_template_compiler.rb
module Ruby2JS
  class MyFrameworkTemplateCompiler
    def self.compile(template, options = {})
      new(template, options).compile
    end

    def compile
      # Convert Ruby expressions in template to JavaScript
      # Convert snake_case to camelCase
      # Handle framework-specific directives
    end
  end
end
```

### 3. Component Transformer

```ruby
# lib/ruby2js/myframework_component_transformer.rb
module Ruby2JS
  class MyFrameworkComponentTransformer
    LIFECYCLE_HOOKS = {
      on_mount: :frameworkMount,
      # ...
    }.freeze

    def transform
      # 1. Parse Ruby code
      # 2. Analyze for imports needed
      # 3. Transform script
      # 4. Compile template
      # 5. Combine into component format
    end
  end
end
```

### 4. Build Integration

```javascript
// Vite plugin, webpack loader, etc.
export function myframeworkPlugin() {
  return {
    transform(code, id) {
      if (id.endsWith('.myfw.rb')) {
        return transformWithRuby2JS(code, { target: 'myframework' })
      }
    }
  }
}
```

## Transformation Examples

### Instance Variables

| Ruby | Vue | Svelte | React |
|------|-----|--------|-------|
| `@count = 0` | `const count = ref(0)` | `let count = 0` | `const [count, setCount] = useState(0)` |
| `@count += 1` | `count.value += 1` | `count += 1` | `setCount(c => c + 1)` |

### Lifecycle Hooks

| Ruby | Vue | Svelte |
|------|-----|--------|
| `def mounted` | `onMounted(() => {})` | — |
| `def on_mount` | — | `onMount(() => {})` |
| `def unmounted` | `onUnmounted(() => {})` | — |
| `def on_destroy` | — | `onDestroy(() => {})` |

### Routing

| Ruby | Vue | Svelte |
|------|-----|--------|
| `params[:id]` | `route.params.id` | `$page.params.id` |
| `router.push('/path')` | `router.push('/path')` | `goto('/path')` |

## Platform Adapters

For deployment platforms, adapters wrap platform-specific APIs:

```javascript
// Vercel Edge ISR
export class ISRCache {
  static async serve(context, renderFn, options = {}) {
    return new Response(await renderFn(context), {
      headers: {
        'Cache-Control': `s-maxage=${options.revalidate}`
      }
    })
  }
}

// Cloudflare Workers ISR
export class ISRCache {
  static async serve(context, renderFn, options = {}) {
    const cache = caches.default
    // Use Cloudflare Cache API
  }
}
```

The Ruby code remains identical—only the adapter changes.

## File Naming Conventions

Ruby2JS follows Rails' compound extension pattern: `name.output.processor`. The rightmost extension indicates how the file is processed; the preceding extension indicates what it produces.

| Extension | Output | Template Location | Use Case |
|-----------|--------|-------------------|----------|
| `.jsx.rb` | `.js` | JSX via `%x{}` blocks | React components |
| `.vue.rb` | `.vue` | After `__END__` | Vue SFCs |
| `.svelte.rb` | `.svelte` | After `__END__` | Svelte components |
| `.astro.rb` | `.astro` | After `__END__` | Astro components |
| `.erb.rb` | `.js` | ERB after `__END__` | Server-rendered pages |

### Directory Structure

```
app/
  pages/
    index.vue.rb        → index.vue
    about.svelte.rb     → about.svelte
    posts/
      [id].astro.rb     → [id].astro
  components/
    Counter.jsx.rb      → Counter.js
    Form.vue.rb         → Form.vue
```

### Rails Integration (Zeitwerk)

Rails' Zeitwerk autoloader would normally try to load `Counter.jsx.rb` as a Ruby constant. The Ruby2JS Railtie automatically configures Zeitwerk to ignore these compound extensions—no user configuration required.

## Design Principles

1. **No Runtime Library**: Generated code runs without Ruby2JS at runtime
2. **Idiomatic Output**: Code looks like it was written by a framework expert
3. **Framework Ownership**: Reactivity, rendering, routing are framework concerns
4. **Mechanical Transformation**: Each Ruby pattern maps to a specific JS pattern
5. **Incremental Addition**: New targets follow established patterns

## What Ruby2JS Doesn't Do

- **Execute Ruby**: No Ruby runtime in the browser
- **Implement Reactivity**: Frameworks handle state updates
- **Bundle Code**: Use Vite, webpack, esbuild, etc.
- **Handle Routing**: Framework routers manage navigation
- **Cache Pages**: Platform adapters manage caching

This separation of concerns means Ruby2JS stays focused on one thing: transforming Ruby syntax into framework-native JavaScript.

## Framework Integrations

Each framework has its preferred way to handle custom file types:

| Framework | Integration Type | Watch Mode | Status |
|-----------|-----------------|------------|--------|
| **SvelteKit** | Preprocessor (`extensions` config) | Native HMR | Implemented |
| **Nuxt** | Module (adds Vite plugin) | Native HMR | Implemented |
| **Astro** | Integration (file watcher) | Page reload | Implemented |
| **Vite** | Plugin (`vite-plugin-ruby2js`) | Native HMR | Implemented |

🧪 **Feedback requested** — [Share your experience](https://github.com/ruby2js/ruby2js/discussions)
