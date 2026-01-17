# Framework Parity Implementation Plan

This plan establishes Ruby2JS as a credible alternative to modern JavaScript frameworks by demonstrating that the architecture generalizes across platforms and frameworks.

## Goal

Move from "we could do X" (claim) to "here's X working on multiple platforms/frameworks" (proof). Once patterns are demonstrated twice, "adding another is incremental" becomes self-evident.

## Core Insight

Every feature is a **transpilation task**. Ruby2JS handles transformation; platforms handle caching; frameworks handle reactivity. We don't rebuild what others have built—we transform Ruby into forms that leverage existing infrastructure.

```
┌─────────────────────────────────────────────────┐
│              Ruby2JS's job:                     │
│         Mechanical transformation               │
│    Ruby syntax → Target framework syntax        │
└─────────────────────────────────────────────────┘
                      │
     ┌────────────────┼────────────────┐
     ▼                ▼                ▼
┌─────────┐    ┌───────────┐    ┌───────────┐
│ Parsing │    │ Platforms │    │Frameworks │
│  Prism  │    │ Vercel    │    │ React     │
│         │    │ Cloudflare│    │ Vue       │
│         │    │           │    │ Svelte    │
└─────────┘    └───────────┘    └───────────┘
  handles        handles          handles
  Ruby AST       caching          reactivity
                 edge compute     rendering
```

## Feature Summary

| Feature | Effort | Adds | Transpilation Task |
|---------|--------|------|-------------------|
| File-based routing | Days | Familiar DX for JS framework users | File path → route config |
| `__END__` templates | Days | Cleaner single-file components | Extract via `data_loc`, pass to template compiler |
| ISR caching (×2) | Days each | Performance optimization | Wrap platform cache APIs |
| Vue syntax + target | Days | Vue developers feel at home | Ruby → Vue SFC |
| Svelte syntax + target | Days | Svelte developers feel at home | Ruby → Svelte component |

**Total estimated effort:** 3-4 weeks of focused work.

---

## File Naming Conventions

Ruby2JS follows Rails' compound extension pattern: `name.output.processor`. The processor (rightmost extension) indicates how the file is processed; the output extension indicates what it produces.

### Extension Mapping

| Extension | Processor | Output | Template Syntax | Use Case |
|-----------|-----------|--------|-----------------|----------|
| `.jsx.rb` | Ruby2JS + React filter | `.js` | JSX via `%x{}` blocks | React components |
| `.vue.rb` | Ruby2JS + Vue filter | `.vue` | Vue template after `__END__` | Vue SFCs |
| `.svelte.rb` | Ruby2JS + Svelte filter | `.svelte` | Svelte template after `__END__` | Svelte components |
| `.erb.rb` | Ruby2JS | `.js` | ERB after `__END__` | Server-rendered pages |

### Examples

```ruby
# app/components/Counter.jsx.rb → Counter.js
export default
def Counter(initial: 0)
  count, setCount = useState(initial)
  %x{<button onClick={() => setCount(count + 1)}>Count: {count}</button>}
end
```

```ruby
# app/pages/posts/[id].vue.rb → [id].vue
@post = nil

def mounted
  @post = await Post.find(params[:id])
end
__END__
<article v-if="post">
  <h1>{{ post.title }}</h1>
</article>
```

```ruby
# app/pages/posts/[id].svelte.rb → [id].svelte
@post = nil

def on_mount
  @post = await Post.find(params[:id])
end
__END__
{#if post}
  <article><h1>{post.title}</h1></article>
{/if}
```

### Rails Integration (Zeitwerk)

Rails' Zeitwerk autoloader loads all `.rb` files and interprets filenames as constant names. Files like `Counter.jsx.rb` would fail with "wrong constant name Counter.jsx".

The Ruby2JS Railtie configures Zeitwerk to ignore these compound extensions:

```ruby
# lib/ruby2js/rails.rb
initializer "ruby2js.zeitwerk_ignore", before: :set_autoload_paths do |app|
  %w[app/components app/views app/javascript app/pages].each do |dir|
    full_path = ::Rails.root.join(dir)
    next unless full_path.exist?

    Dir.glob(full_path.join("**/*.{jsx,vue,svelte,erb}.rb")).each do |file|
      Rails.autoloaders.main.ignore(file)
    end
  end
end
```

This is automatic when using `ruby2js-rails`. No user configuration required.

---

## Phase 1: Foundation

### 1.1 `__END__` Template Extraction

**What exists:** Prism parser provides `data_loc` with location and content of everything after `__END__`.

**What to build:**
- Modify `Ruby2JS.convert` to optionally return both transpiled JS and template content
- Add option to specify template type (erb, vue, svelte)
- Pass template to appropriate compiler based on type

**File format:**
```ruby
# app/pages/blog/[slug].erb.rb
@post = Post.find(params[:slug])
__END__
<article>
  <h1><%= @post.title %></h1>
  <%= @post.body %>
</article>
```

**Implementation:**
```ruby
# In lib/ruby2js.rb, modify parse_with_prism:
def self.parse_with_prism(source, file=nil, line=1)
  result = Prism.parse(source, filepath: file || '(string)')
  # ... existing parsing ...

  # Extract template if __END__ present
  template = nil
  if result.data_loc
    template = result.data_loc.slice
    # Remove __END__ marker from template content
    template = template.sub(/\A__END__\r?\n/, '')
  end

  [ast, comments, template]
end
```

**Definition of done:**
- [ ] `Ruby2JS.convert` accepts `template: :erb | :vue | :svelte` option
- [ ] Returns `{js:, template:}` when template option specified
- [ ] Template content extracted correctly (without `__END__` marker)
- [ ] Source maps work for Ruby portion

### 1.2 File-Based Routing

**What exists:**
- Routes filter parses Rails routes DSL (`lib/ruby2js/filter/rails/routes.rb`)
- Generates Router configuration and path helpers

**What to build:**
- File scanner that discovers pages in `app/pages/` directory
- Convention parser for dynamic segments: `[slug]` → `:slug`, `[...rest]` → `*rest`
- Route config generator from file structure

**Conventions (matching Next.js/SvelteKit):**
```
app/pages/
  index.rb           → /
  about.rb           → /about
  blog/
    index.rb         → /blog
    [slug].rb        → /blog/:slug
    [...rest].rb     → /blog/*rest
```

**Implementation:**
```ruby
# lib/ruby2js/file_router.rb
module Ruby2JS
  class FileRouter
    def initialize(pages_dir)
      @pages_dir = pages_dir
    end

    def discover_routes
      routes = []
      Dir.glob(File.join(@pages_dir, '**/*.rb')).each do |file|
        path = file_to_route_path(file)
        routes << { file: file, path: path }
      end
      routes
    end

    def file_to_route_path(file)
      relative = file.sub(@pages_dir, '').sub(/\.rb$/, '')
      relative
        .gsub(/\/index$/, '')           # index.rb → /
        .gsub(/\[\.\.\.(\w+)\]/, '*\1') # [...rest] → *rest
        .gsub(/\[(\w+)\]/, ':\1')       # [slug] → :slug
        .then { |p| p.empty? ? '/' : p }
    end
  end
end
```

**Definition of done:**
- [ ] `FileRouter.discover_routes` returns route configs from file structure
- [ ] Dynamic segments parsed correctly
- [ ] Integrates with existing Router infrastructure
- [ ] Works with `juntos build`

---

## Phase 2: ISR Caching

Implement ISR on two platforms to prove the abstraction generalizes.

### 2.1 ISR Adapter Interface

**Design:**
```ruby
# Common interface for all ISR adapters
module Ruby2JS
  module ISR
    class Base
      # Serve with caching
      # - context: request context
      # - cache_key: URL or custom key
      # - options: { revalidate: seconds }
      # - block: renders the content
      def self.serve(context, cache_key, options = {}, &block)
        raise NotImplementedError
      end

      # On-demand revalidation
      def self.revalidate(path)
        raise NotImplementedError
      end
    end
  end
end
```

**Usage in pages:**
```ruby
# Pragma: revalidate 60

@posts = Post.all
__END__
<ul>
  <% @posts.each do |post| %>
    <li><%= post.title %></li>
  <% end %>
</ul>
```

### 2.2 Vercel ISR Adapter

**What exists:** `targets/vercel-edge/rails.js` with Router and Application classes.

**What to build:** ISR support using Vercel's caching infrastructure.

**Implementation:**
```javascript
// packages/ruby2js-rails/targets/vercel-edge/isr.mjs

export class ISRCache {
  // Vercel Edge uses Cache-Control headers
  // The platform handles stale-while-revalidate automatically
  static async serve(context, renderFn, options = {}) {
    const revalidate = options.revalidate || 60;

    const html = await renderFn(context);

    return new Response(html, {
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': `s-maxage=${revalidate}, stale-while-revalidate=86400`
      }
    });
  }

  // On-demand revalidation via Vercel API
  static async revalidate(path) {
    // Vercel automatically handles this when using their SDK
    // For manual control, use their revalidation API
    const url = `https://api.vercel.com/v1/invalidate?path=${encodeURIComponent(path)}`;
    await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.VERCEL_TOKEN}`
      }
    });
  }
}
```

**Definition of done:**
- [ ] Pages with `# Pragma: revalidate N` get cached
- [ ] Stale content served while regenerating
- [ ] On-demand revalidation endpoint works
- [ ] Example app demonstrating ISR

### 2.3 Cloudflare ISR Adapter

**What exists:** `targets/cloudflare/rails.js` with Worker pattern and Durable Objects.

**What to build:** ISR using Cloudflare Cache API.

**Implementation:**
```javascript
// packages/ruby2js-rails/targets/cloudflare/isr.mjs

export class ISRCache {
  static async serve(context, renderFn, options = {}) {
    const cache = caches.default;
    const cacheKey = new Request(context.request.url);
    const revalidate = options.revalidate || 60;

    // Check cache
    let response = await cache.match(cacheKey);

    if (response) {
      // Check if stale
      const age = parseInt(response.headers.get('age') || '0');
      if (age < revalidate) {
        return response;
      }

      // Stale - serve and regenerate in background
      context.waitUntil(this.regenerate(context, cacheKey, renderFn, revalidate));
      return response;
    }

    // Cache miss - generate and cache
    return await this.regenerate(context, cacheKey, renderFn, revalidate);
  }

  static async regenerate(context, cacheKey, renderFn, revalidate) {
    const cache = caches.default;
    const html = await renderFn(context);

    const response = new Response(html, {
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': `s-maxage=${revalidate}`
      }
    });

    context.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  }

  // On-demand revalidation
  static async revalidate(path) {
    const cache = caches.default;
    await cache.delete(new Request(path));
  }
}
```

**Definition of done:**
- [ ] Same pragma syntax works on Cloudflare
- [ ] Cache API correctly stores/retrieves pages
- [ ] Background regeneration works via `waitUntil`
- [ ] On-demand revalidation clears cache

---

## Phase 3: Template Syntaxes

### 3.1 Vue Template Syntax Parser

**What exists:**
- ERB compiler (`lib/ruby2js/rails/erb_compiler.rb`) - pattern to follow
- Vue filter that converts Phlex to Vue SFCs

**What to build:** Parser for Vue-style template syntax.

**Syntax to support:**
```vue
<div>
  <h1>{{ title }}</h1>
  <ul>
    <li v-for="item in items" :key="item.id">
      {{ item.name }}
    </li>
  </ul>
  <p v-if="showDescription">{{ description }}</p>
  <button @click="handleClick">Click me</button>
</div>
```

**Implementation approach:**
1. Parse HTML structure (can use simple regex or lightweight HTML parser)
2. Extract `{{ expression }}` interpolations → transpile Ruby expressions
3. Handle `v-for`, `v-if` directives
4. Handle `@event` and `:bind` shorthand
5. Output valid Vue template with JS expressions

```ruby
# lib/ruby2js/vue_template_compiler.rb
class VueTemplateCompiler
  def initialize(template, transpiler)
    @template = template
    @transpiler = transpiler  # Ruby2JS converter for expressions
  end

  def compile
    result = @template.dup

    # Replace {{ rubyExpr }} with {{ jsExpr }}
    result.gsub!(/\{\{\s*(.+?)\s*\}\}/) do |match|
      ruby_expr = $1
      js_expr = @transpiler.convert_expression(ruby_expr)
      "{{ #{js_expr} }}"
    end

    # Handle v-for="item in collection"
    # Collection might be a Ruby expression
    result.gsub!(/v-for="(\w+)\s+in\s+(.+?)"/) do |match|
      var = $1
      ruby_collection = $2
      js_collection = @transpiler.convert_expression(ruby_collection)
      "v-for=\"#{var} in #{js_collection}\""
    end

    result
  end
end
```

**Definition of done:**
- [ ] `{{ expression }}` with Ruby expressions works
- [ ] `v-for` with Ruby collections works
- [ ] `v-if` with Ruby conditions works
- [ ] Event handlers reference transpiled methods
- [ ] Source maps point to original template

### 3.2 Svelte Template Syntax Parser

**Syntax to support:**
```svelte
<div>
  <h1>{title}</h1>
  <ul>
    {#each items as item (item.id)}
      <li>{item.name}</li>
    {/each}
  </ul>
  {#if show_description}
    <p>{description}</p>
  {/if}
  <button on:click={handle_click}>Click me</button>
</div>
```

**Implementation approach:**
1. Tokenize: find `{...}` boundaries (handle nested braces, strings)
2. Parse blocks: `{#if}`, `{:else}`, `{/if}`, `{#each}`, `{/each}`
3. Extract Ruby expressions, transpile to JS
4. Reassemble valid Svelte template

```ruby
# lib/ruby2js/svelte_template_compiler.rb
class SvelteTemplateCompiler
  def initialize(template, transpiler)
    @template = template
    @transpiler = transpiler
  end

  def compile
    result = []
    pos = 0

    while pos < @template.length
      # Find next {
      brace_start = @template.index('{', pos)

      if brace_start.nil?
        result << @template[pos..-1]
        break
      end

      # Add text before brace
      result << @template[pos...brace_start] if brace_start > pos

      # Find matching }
      brace_end = find_matching_brace(@template, brace_start)
      content = @template[(brace_start + 1)...brace_end]

      # Process based on content type
      result << process_brace_content(content)

      pos = brace_end + 1
    end

    result.join
  end

  private

  def find_matching_brace(str, start)
    depth = 1
    pos = start + 1
    in_string = nil

    while pos < str.length && depth > 0
      char = str[pos]

      if in_string
        in_string = nil if char == in_string && str[pos - 1] != '\\'
      elsif char == '"' || char == "'" || char == '`'
        in_string = char
      elsif char == '{'
        depth += 1
      elsif char == '}'
        depth -= 1
      end

      pos += 1
    end

    pos - 1
  end

  def process_brace_content(content)
    case content
    when /^#each\s+(.+?)\s+as\s+(\w+)/
      collection = @transpiler.convert_expression($1)
      "{#each #{collection} as #{$2}}"
    when /^#if\s+(.+)$/
      condition = @transpiler.convert_expression($1)
      "{#if #{condition}}"
    when /^[#:\/]/
      # Block markers - pass through
      "{#{content}}"
    else
      # Expression - transpile
      js_expr = @transpiler.convert_expression(content)
      "{#{js_expr}}"
    end
  end
end
```

**Definition of done:**
- [ ] `{expression}` with Ruby expressions works
- [ ] `{#each}` / `{/each}` blocks work
- [ ] `{#if}` / `{:else}` / `{/if}` blocks work
- [ ] Nested blocks handled correctly
- [ ] Event handlers (`on:click={method}`) work
- [ ] Source maps point to original template

---

## Phase 4: Framework Targets

### 4.1 Vue Target (Complete)

**What exists:**
- Vue filter converts Phlex to Vue SFC (`lib/ruby2js/filter/vue.rb`)
- Handles `v-for`, `v-if`, props, event handlers

**What to build:**
- Integration with `__END__` template extraction
- Full component transformation (script + template)
- Vue Router integration for file-based routing
- Vite plugin configuration

**Component structure:**
```ruby
# Input: app/pages/posts/[id].vue.rb
@post = nil

def mounted
  @post = await Post.find(params[:id])
end

def delete_post
  await @post.destroy
  router.push('/posts')
end
__END__
<article v-if="post">
  <h1>{{ post.title }}</h1>
  <p>{{ post.body }}</p>
  <button @click="deletePost">Delete</button>
</article>
<p v-else>Loading...</p>
```

```vue
<!-- Output: app/pages/posts/[id].vue (generated) -->
<script setup>
import { ref, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { Post } from '@/models/post'

const router = useRouter()
const route = useRoute()
const post = ref(null)

onMounted(async () => {
  post.value = await Post.find(route.params.id)
})

async function deletePost() {
  await post.value.destroy()
  router.push('/posts')
}
</script>

<template>
  <article v-if="post">
    <h1>{{ post.title }}</h1>
    <p>{{ post.body }}</p>
    <button @click="deletePost">Delete</button>
  </article>
  <p v-else>Loading...</p>
</template>
```

**Definition of done:**
- [ ] Full page components transform correctly
- [ ] Instance variables → `ref()` reactive state
- [ ] Methods → functions
- [ ] Lifecycle hooks map (mounted → onMounted, etc.)
- [ ] Vue Router integration for navigation
- [ ] Example app works end-to-end

### 4.2 Svelte Target (New)

**What to build:** Complete Svelte transformation.

**Component structure:**
```ruby
# Input: app/pages/posts/[id].svelte.rb
@post = nil

def on_mount
  @post = await Post.find(params[:id])
end

def delete_post
  await @post.destroy
  goto('/posts')
end
__END__
{#if post}
  <article>
    <h1>{post.title}</h1>
    <p>{post.body}</p>
    <button on:click={delete_post}>Delete</button>
  </article>
{:else}
  <p>Loading...</p>
{/if}
```

```svelte
<!-- Output: app/pages/posts/[id].svelte (generated) -->
<script>
  import { onMount } from 'svelte'
  import { goto } from '$app/navigation'
  import { page } from '$app/stores'
  import { Post } from '$lib/models/post'

  let post = null

  onMount(async () => {
    post = await Post.find($page.params.id)
  })

  async function deletePost() {
    await post.destroy()
    goto('/posts')
  }
</script>

{#if post}
  <article>
    <h1>{post.title}</h1>
    <p>{post.body}</p>
    <button on:click={deletePost}>Delete</button>
  </article>
{:else}
  <p>Loading...</p>
{/if}
```

**Key mappings:**
| Ruby | Svelte |
|------|--------|
| `@variable` | `let variable` (reactive by default) |
| `def on_mount` | `onMount(() => {...})` |
| `params[:id]` | `$page.params.id` |
| `goto(path)` | `goto(path)` |
| `def method` | `function method() {...}` |

**Implementation:**
```ruby
# lib/ruby2js/filter/svelte.rb
module Ruby2JS
  module Filter
    module Svelte
      include SEXP

      def initialize(node)
        super
        @svelte_mode = false
        @svelte_ivars = Set.new
        @svelte_methods = []
      end

      # Transform class into Svelte component
      def on_class(node)
        # ... extract ivars, methods, lifecycle hooks
        # ... generate script section
        # ... combine with template from __END__
      end

      # Instance variables → let declarations
      def on_ivasgn(node)
        return super unless @svelte_mode
        var_name = node.children[0].to_s[1..-1]  # Remove @
        @svelte_ivars << var_name
        s(:let, var_name, process(node.children[1]))
      end

      # Method definitions → functions
      def on_def(node)
        return super unless @svelte_mode
        name = node.children[0]

        # Map lifecycle hooks
        case name
        when :on_mount
          # Wrap in onMount()
        when :on_destroy
          # Wrap in onDestroy()
        else
          @svelte_methods << name
          # Regular function
        end
      end
    end
  end
end
```

**Definition of done:**
- [ ] Instance variables → reactive `let` declarations
- [ ] Methods → functions
- [ ] Lifecycle hooks mapped correctly
- [ ] SvelteKit routing integration ($page, goto)
- [ ] Template syntax processed correctly
- [ ] Example app works end-to-end

---

## Phase 5: Documentation

### 5.1 "Coming From" Guides

Create welcome documentation for developers from each ecosystem:

```
docs/src/_docs/coming-from/
  react.md
  vue.md
  svelte.md
  nextjs.md
  astro.md
  rails.md
```

**Each guide includes:**
1. "What you know" - familiar concepts
2. "How it maps" - Ruby equivalents
3. "Quick start" - 5-minute working example
4. "Key differences" - gotchas and adjustments

**Example structure for `vue.md`:**

```markdown
# Coming from Vue

If you know Vue, you'll feel at home with Ruby2JS targeting Vue.

## What You Know → What You Write

| Vue | Ruby2JS |
|-----|---------|
| `ref(0)` | `@count = 0` |
| `{{ count }}` | `{{ count }}` |
| `v-for="item in items"` | `v-for="item in items"` |
| `@click="handler"` | `@click="handler"` |
| `onMounted(() => {})` | `def mounted` |

## Quick Start

1. Create a new project:
   ```bash
   juntos new myapp --target=vue
   ```

2. Create a component:
   ```ruby
   # app/pages/counter.rb
   @count = 0

   def increment
     @count += 1
   end
   __END__
   <button @click="increment">
     Count: {{ count }}
   </button>
   ```

3. Run it:
   ```bash
   juntos dev
   ```

## The Ruby Advantage

- Less ceremony: no `ref()`, no `.value`
- Familiar syntax: instance variables are reactive state
- Same deployment: Vercel, Cloudflare, Node, browser
```

### 5.2 Architecture Documentation

Document the transformation architecture so the pattern is clear:

```markdown
# How Ruby2JS Targets Work

Ruby2JS doesn't implement frameworks—it transforms to them.

## The Pattern

1. **Parse** Ruby source with Prism
2. **Transform** AST based on target framework
3. **Output** framework-native code
4. **Let the framework** handle rendering/reactivity

## Adding a New Target

A target needs:
1. Filter module (`lib/ruby2js/filter/{framework}.rb`)
2. Template compiler (if custom syntax)
3. Build integration (Vite config)
4. Runtime adapter (if targeting edge/server)

Each is typically 100-300 lines of transformation rules.
```

---

## Implementation Order

**Dependencies:**

```
Phase 1 (Foundation)
  ├── 1.1 __END__ extraction (no deps)
  └── 1.2 File-based routing (no deps)

Phase 2 (ISR) - can parallel with Phase 1
  ├── 2.1 ISR interface (no deps)
  ├── 2.2 Vercel adapter (needs 2.1)
  └── 2.3 Cloudflare adapter (needs 2.1)

Phase 3 (Syntaxes) - needs 1.1
  ├── 3.1 Vue syntax (needs 1.1)
  └── 3.2 Svelte syntax (needs 1.1)

Phase 4 (Targets) - needs Phase 3
  ├── 4.1 Vue target (needs 3.1)
  └── 4.2 Svelte target (needs 3.2)

Phase 5 (Docs) - needs Phase 4
  └── 5.1-5.2 Documentation (needs working examples)
```

**Suggested execution:**

| Week | Tasks |
|------|-------|
| 1 | 1.1 `__END__` + 1.2 File routing + 2.1 ISR interface |
| 2 | 2.2 Vercel ISR + 2.3 Cloudflare ISR |
| 3 | 3.1 Vue syntax + 3.2 Svelte syntax |
| 4 | 4.1 Vue target + 4.2 Svelte target |
| 5 | 5.1 Coming-from guides + 5.2 Architecture docs |

---

## Success Criteria

**Proof points achieved:**

- [ ] ISR works on 2 platforms (Vercel, Cloudflare) with same Ruby code
- [ ] Reactivity works with 3 frameworks (React, Vue, Svelte)
- [ ] Template syntax works with 3 styles (ERB, Vue, Svelte)
- [ ] File-based routing works across all targets
- [ ] Documentation welcomes developers from 6 ecosystems

**Credibility statement becomes true:**

> "Ruby2JS supports multiple deployment targets (edge, browser, server), multiple UI frameworks (React, Vue, Svelte), and multiple template syntaxes. Adding another platform or framework is incremental—the architecture is proven."
