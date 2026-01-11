# Unified Views

## Executive Summary

**Write Ruby views once, deploy to any frontend framework.**

### Value Proposition

| Capability | Rails Today | Juntos Unified Views |
|------------|-------------|----------------------|
| Phlex → React components | Rewrite required | Same source, new target |
| Switch frameworks (React↔Vue↔Svelte) | Rewrite all views | Change one config line |
| Web + mobile + desktop | Separate codebases | Same views everywhere |
| Multi-framework app | Not practical | Astro islands |
| Progressive enhancement | Turbo/Stimulus | htmx/Alpine (works today) |
| ERB templates | Rails only | Works with Hotwire (SSR strings) |

### Assessment

| Dimension | Rating | Rationale |
|-----------|--------|-----------|
| **Effort** | Moderate | Building on proven patterns (Phlex→React exists); delegating to battle-tested tools (esbuild, framework compilers) |
| **Risk** | Small | Core concept proven; generating standard formats (JSX, Vue SFC, Astro); framework compilers do the hard work |
| **Reward** | Immense | Unprecedented in Ruby ecosystem; eliminates framework lock-in; enables true write-once-deploy-anywhere |

### MVP Scope

| Target | Support Level | Notes |
|--------|---------------|-------|
| React/Preact | Full | Phlex→React exists, RBX for JSX syntax |
| Lit | Full | ~20 lines change from SSR strings |
| Astro | Full | Simpler than Vue, multi-framework escape hatch |
| Vue | Substantial | Core patterns work, defer v-model/slots |
| htmx/Alpine | Works today | Just HTML attributes |
| ERB | SSR only | String output for Hotwire (cannot target React) |

### Estimated Timeline to MVP

| Phase | Scope | Effort |
|-------|-------|--------|
| 1. Unified signature | Props pattern change | Small |
| 2. Lit target | Tagged template literals | Trivial |
| 3-4. RBX + JSX | New file formats, esbuild integration | Small |
| 5. Import resolution | Component path rewriting | Medium |
| 6. Astro target | Frontmatter + JSX-style template | Medium |
| 7. Vue target | SFC generation | Medium |
| 8. Unified module | Combined exports, source maps | Medium |

**Rough estimate: 3-6 weeks** depending on focus and parallelization. Each phase is independently deliverable.

### Why Now

1. **Phlex→React already works** — core concept is proven
2. **Framework compilers are mature** — Vue, Svelte, Astro handle the hard parts
3. **Juntos targets are ready** — Node, Bun, Deno, Edge, Browser, Capacitor, Electron all work
4. **Market timing** — React fatigue is real; developers want framework flexibility

---

## Overview

Unify ERB, Phlex, React/JSX, and RBX views under a single component model with a consistent calling convention. Views become interchangeable functions that take props and return renderable content.

**Key insight:** A Juntos application starts with ERB/Phlex (server-rendered strings), then can either:
1. Add progressive enhancement (htmx, Alpine.js) while keeping SSR strings
2. Adopt a component framework (React, Vue, Svelte, Astro) for full client-side interactivity

The same Ruby views compile to the chosen target format.

```
                              ┌─────────────────────────────────────┐
                              │         Juntos Application          │
                              │                                     │
                              │   ERB (.html.erb)                   │
                              │   Phlex (.rb)                       │
                              │   RBX (.rbx)                        │
                              │                                     │
                              └──────────────┬──────────────────────┘
                                             │
                                             ▼
                      ┌──────────────────────────────────────────────┐
                      │                Build Target                   │
                      └──────────────────────────────────────────────┘
                                             │
       ┌─────────────────────────────────────┼─────────────────────────────────┐
       │                                     │                                 │
       ▼                                     ▼                                 ▼
 ┌───────────┐                    ┌───────────────────┐              ┌─────────────────┐
 │    SSR    │                    │  SSR + Enhancement│              │ Component Framework│
 │  (None)   │                    │  (htmx, Alpine)   │              │                 │
 └─────┬─────┘                    └────────┬──────────┘              └────────┬────────┘
       │                                   │                                  │
       ▼                                   ▼                          ┌───────┴───────┐
   Strings                        Strings + hx-*/x-* attrs            │               │
       │                                   │               ┌──────────┼───────────────┼──────────┐
       │                                   │               ▼          ▼               ▼          ▼
       │                                   │            React    Vue/Svelte       Astro      Solid
       │                                   │            Preact                               Lit
       │                                   │               │          │               │          │
       └───────────────────────────────────┴───────────────┴──────────┴───────────────┴──────────┘
                                                           │
                                                           ▼
                                                     JavaScript
                                                     Application
```

## Core Insight

All view formats describe the same thing—UI structure with dynamic data:

| Format | Input | Syntax | Output |
|--------|-------|--------|--------|
| ERB | props | `<%= %>` template | strings (Hotwire) |
| Phlex | props | Ruby DSL (`div`, `form`) | string or framework component |
| RBX | props | Ruby + JSX (`%x{}`) | React element |
| JSX | props | JavaScript + JSX | React element |

Phlex parses to an intermediate pnode AST representation. The framework target determines how that AST is serialized—strings, React elements, Vue SFCs, Svelte components, or Astro components.

**ERB limitation:** ERB uses string concatenation and allows arbitrary HTML fragments (e.g., a closing `</div>` tag without its opening tag in a conditional block). This is incompatible with React's tree-based model, so ERB stays SSR-only. For React output, use Phlex or RBX.

The unification enables:
- Start with SSR (strings), graduate to a framework when needed
- Switch frameworks without rewriting views
- Full access to chosen framework's ecosystem
- Write once in Ruby, deploy anywhere

## Framework Targets

### None (SSR Only)
Default mode. Views return strings, server renders HTML directly.

```ruby
# Input (Phlex)
div(class: "card") { h1 { @title } }
```

```javascript
// Output
export function render({title}) {
  return `<div class="card"><h1>${title}</h1></div>`;
}
```

### React
Views become React function components.

```javascript
// Output
export function render({title}) {
  return React.createElement('div', {className: 'card'},
    React.createElement('h1', null, title)
  );
}
```

### Vue
Views become Vue Single File Components.

```vue
<!-- Output: Component.vue -->
<template>
  <div class="card">
    <h1>{{ title }}</h1>
  </div>
</template>

<script setup>
defineProps(['title'])
</script>
```

### Svelte
Views become Svelte components.

```svelte
<!-- Output: Component.svelte -->
<script>
  export let title;
</script>

<div class="card">
  <h1>{title}</h1>
</div>
```

### Astro
Views become Astro components (with optional client hydration).

```astro
<!-- Output: Component.astro -->
---
const { title } = Astro.props;
---

<div class="card">
  <h1>{title}</h1>
</div>
```

### Solid.js
JSX-based like React, but with fine-grained reactivity (no virtual DOM).

```javascript
// Output (nearly identical to React)
export function render({title}) {
  return <div class="card"><h1>{title}</h1></div>;
}
```

If React is supported, Solid is low-effort—same JSX output, different runtime imports.

### Preact
Already supported via the existing React filter's Preact mode. 3KB React alternative.

```javascript
// Output (same as React, different imports)
import { h } from 'preact';
export function render({title}) {
  return h('div', {class: 'card'}, h('h1', null, title));
}
```

### Lit
Web Components with tagged template literals. Minimal change from SSR strings.

```javascript
// Output
import { html, LitElement } from 'lit';
export function render({title}) {
  return html`<div class="card"><h1>${title}</h1></div>`;
}
```

Nearly identical to SSR string output—just add `html` tag and import.

### htmx (Progressive Enhancement)
**Not a framework target—works with SSR strings directly.**

htmx adds interactivity via HTML attributes. No compilation needed, just allow `hx-*` attributes in ERB/Phlex:

```erb
<%# ERB with htmx attributes %>
<button hx-post="/clicked" hx-swap="outerHTML">
  Click Me
</button>
```

```ruby
# Phlex with htmx attributes
button("hx-post": "/clicked", "hx-swap": "outerHTML") { "Click Me" }
```

Output is still plain HTML strings—htmx runs client-side. This is additive to SSR, not a replacement.

### Alpine.js (Progressive Enhancement)
**Not a framework target—works with SSR strings directly.**

Like htmx, Alpine adds interactivity via attributes (`x-*`):

```erb
<%# ERB with Alpine attributes %>
<div x-data="{ open: false }">
  <button @click="open = !open">Toggle</button>
  <div x-show="open">Content</div>
</div>
```

```ruby
# Phlex with Alpine attributes
div("x-data": "{ open: false }") do
  button("@click": "open = !open") { "Toggle" }
  div("x-show": "open") { "Content" }
end
```

Output is still plain HTML strings. Alpine is "Tailwind for JavaScript"—progressive enhancement without a build step.

## Framework Composition

Not all frameworks are mutually exclusive. Understanding composition rules helps users make informed choices.

### Always Additive (combine with anything)

**htmx + Alpine.js**
Both work via HTML attributes on SSR strings. Use together freely:
```yaml
views:
  framework: none  # or any framework
  enhancement:
    htmx: true
    alpine: true
```

**Lit / Web Components**
Web Components are framework-agnostic. Lit components can be embedded in React, Vue, Svelte, or plain HTML:
```yaml
views:
  framework: react
  web_components: true  # Lit components alongside React
```

### Multi-Framework Host

**Astro (Islands Architecture)**
Astro is specifically designed to host components from multiple frameworks:
```yaml
views:
  framework: astro
  astro:
    # Astro can render islands using any of these
    integrations: [react, vue, svelte, solid]
```

Each "island" can be a different framework. Astro handles hydration. This is the escape hatch for teams that want flexibility or are migrating between frameworks.

### Mutually Exclusive (pick one)

These frameworks each manage their own component tree and can't share DOM ownership:

| Framework | Conflicts With |
|-----------|----------------|
| React | Vue, Svelte, Solid (direct mixing) |
| Vue | React, Svelte, Solid (direct mixing) |
| Svelte | React, Vue, Solid (direct mixing) |
| Solid | React, Vue, Svelte (direct mixing) |

**Exception:** Use Astro to host multiple frameworks via islands architecture.

### Composition Matrix

| Primary | + htmx/Alpine | + Lit | + React | + Vue | + Svelte |
|---------|---------------|-------|---------|-------|----------|
| None (SSR) | Yes | Yes | — | — | — |
| React | Yes | Yes | — | via Astro | via Astro |
| Vue | Yes | Yes | via Astro | — | via Astro |
| Svelte | Yes | Yes | via Astro | via Astro | — |
| Astro | Yes | Yes | Yes | Yes | Yes |
| Lit | Yes | — | Yes | Yes | Yes |

**Key insight:** Astro is the "universal adapter" for multi-framework apps. Choose Astro if you want React AND Vue AND Svelte components in the same application.

## Template Syntax Mapping

ERB/Phlex constructs map mechanically to each framework:

### Interpolation

| Source | React | Vue | Svelte | Astro |
|--------|-------|-----|--------|-------|
| `<%= expr %>` | `{expr}` | `{{ expr }}` | `{expr}` | `{expr}` |
| `@foo` | `props.foo` | `foo` | `foo` | `Astro.props.foo` |

### Conditionals

| Source | React | Vue | Svelte | Astro |
|--------|-------|-----|--------|-------|
| `<% if cond %>...<% end %>` | `{cond && ...}` | `v-if="cond"` | `{#if cond}...{/if}` | `{cond && ...}` |
| `<% if cond %>...<% else %>...<% end %>` | `{cond ? ... : ...}` | `v-if`/`v-else` | `{#if}...{:else}...{/if}` | `{cond ? ... : ...}` |

### Loops

| Source | React | Vue | Svelte | Astro |
|--------|-------|-----|--------|-------|
| `<% arr.each do \|x\| %>` | `{arr.map(x => ...)}` | `v-for="x in arr"` | `{#each arr as x}` | `{arr.map(x => ...)}` |

### Events

| Source | React | Vue | Svelte | Astro |
|--------|-------|-----|--------|-------|
| `onclick: handler` | `onClick={handler}` | `@click="handler"` | `on:click={handler}` | `onclick={handler}` |

### Components

| Source | React | Vue | Svelte | Astro |
|--------|-------|-----|--------|-------|
| `render Card.new(title: x)` | `<Card title={x} />` | `<Card :title="x" />` | `<Card {title} />` | `<Card title={x} />` |

## Unified Function Signature

### Current (ERB)
```javascript
export function render($context, { articles }) { ... }
```

### Proposed (All Formats)
```javascript
export function render({ $context, articles }) { ... }
```

Single destructured object parameter—same as React/Vue/Svelte props:
```jsx
function ArticleIndex({ $context, articles }) { ... }
```

### Call Site Changes

**Controller:**
```javascript
// Before
return ArticleViews.index(context, {articles})

// After
return ArticleViews.index({$context: context, articles})
```

**Partial rendering:**
```javascript
// Before
_article_module.render($context, {article})

// After
_article_module.render({$context, article})
```

## Router Integration

The router's `htmlResponse` becomes the decision point:

```javascript
static htmlResponse(context, content) {
  let html;

  if (typeof content === 'string') {
    // SSR mode, Phlex (string mode)
    html = content;
  } else {
    // React element (Phlex+React, RBX, JSX)
    html = ReactDOMServer.renderToString(content);
  }

  return new Response(App.wrapInLayout(context, html), ...);
}
```

For Vue/Svelte/Astro targets, the build produces a full SPA/SSG application using that framework's tooling. The router integration differs per framework.

## Target-Aware Rendering (MVP Default)

The rendering strategy adapts automatically based on the deployment target:

| Target Category | Targets | Default Strategy | Why |
|-----------------|---------|------------------|-----|
| **Server** | Node, Bun, Deno, Cloudflare, Vercel, Fly | SSR + hydration | Fast first paint, SEO, network latency |
| **Browser** | sql.js, Dexie, PGlite | CSR | No server, everything local |
| **Mobile** | Capacitor | CSR | WebView renders locally |
| **Desktop** | Electron | CSR | No network latency, simpler architecture |

### Server Targets: SSR + Hydration

```
┌─────────────────────────────────────────────────────────────────┐
│                           Server                                 │
│                                                                  │
│  1. Controller fetches data                                     │
│  2. View renders to React element                               │
│  3. ReactDOMServer.renderToString() → HTML                      │
│  4. Serialize props for client                                  │
│  5. Send HTML + props + hydration script                        │
│                                                                  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼ (over network)
                         ┌──────────────┐
                         │   Browser    │
                         │              │
                         │ 1. Display   │  ← Instant (HTML ready)
                         │    HTML      │
                         │ 2. Load JS   │
                         │ 3. Hydrate   │  ← Attach event handlers
                         │              │
                         └──────────────┘
```

**Benefits:** Fast first paint, SEO-friendly, optimizes for network latency.

### Browser/Capacitor/Electron: CSR (Client-Side Rendering)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Browser / WebView / Electron                  │
│                                                                  │
│  1. Load app.js                                                 │
│  2. Controller fetches data (IndexedDB, SQLite, IPC)            │
│  3. View renders to React element                               │
│  4. createRoot().render() → DOM                                 │
│                                                                  │
│  No network latency = no need for SSR complexity                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Benefits:** Simpler architecture, no hydration mismatch risk, natural for local apps.

### Implementation in Router

```javascript
static async renderView(context, content) {
  if (typeof content === 'string') {
    // SSR strings — same for all targets
    return this.stringResponse(context, content);
  }

  // React element — strategy depends on target
  if (this.isServerTarget()) {
    return this.ssrWithHydration(context, content);
  } else {
    // Browser, Capacitor, Electron — CSR
    return this.clientSideRender(context, content);
  }
}

static ssrWithHydration(context, content) {
  const html = ReactDOMServer.renderToString(content);
  const props = context.viewProps;

  const fullHtml = App.wrapInLayout(context, `
    <div id="root">${html}</div>
    <script>window.__PROPS__ = ${JSON.stringify(props)}</script>
    <script type="module">
      import { hydrateRoot } from 'react-dom/client';
      import App from './app.js';
      hydrateRoot(document.getElementById('root'), App(window.__PROPS__));
    </script>
  `);

  return new Response(fullHtml, ...);
}

static clientSideRender(context, content) {
  // For CSR targets, return minimal shell
  // React renders entirely client-side
  const props = context.viewProps;

  const fullHtml = App.wrapInLayout(context, `
    <div id="root"></div>
    <script>window.__PROPS__ = ${JSON.stringify(props)}</script>
    <script type="module">
      import { createRoot } from 'react-dom/client';
      import App from './app.js';
      createRoot(document.getElementById('root')).render(App(window.__PROPS__));
    </script>
  `);

  return fullHtml;  // No Response wrapper for browser target
}
```

### What Stays The Same Across All Targets

| Layer | Identical? |
|-------|------------|
| ERB/Phlex source | ✓ |
| Generated React/Vue components | ✓ |
| Controller logic | ✓ |
| View props signature | ✓ |
| Router API | ✓ |
| Model layer | ✓ |

**Write once, deploy everywhere.** Only the rendering path adapts.

## File Formats

### ERB (`.html.erb`)
Template syntax for HTML-heavy views:
```erb
<div class="articles">
  <% articles.each do |article| %>
    <%= render article %>
  <% end %>
</div>
```

### Phlex (`.rb` in `app/components/`)
Ruby DSL, targets any framework:
```ruby
class Index < Phlex::HTML
  def initialize($context:, articles:)
    @articles = articles
  end

  def view_template
    div(class: "articles") do
      @articles.each do |article|
        render ArticleCard.new(article: article)
      end
    end
  end
end
```

### RBX (`.rbx`)
Ruby syntax producing React components:
```ruby
import ArticleCard from 'components/ArticleCard'

export default
def Index({$context, articles})
  %x{
    <div className="articles">
      {articles.map(article =>
        <ArticleCard key={article.id} article={article} />
      )}
    </div>
  }
end
```

### JSX (`.jsx`)
Standard React/JSX (passthrough via esbuild):
```jsx
import ArticleCard from 'components/ArticleCard';

export default function Index({ $context, articles }) {
  return (
    <div className="articles">
      {articles.map(article =>
        <ArticleCard key={article.id} article={article} />
      )}
    </div>
  );
}
```

### Vue SFC (`.vue`)
Standard Vue (passthrough via vue-compiler):
```vue
<template>
  <div class="articles">
    <ArticleCard v-for="article in articles" :key="article.id" :article="article" />
  </div>
</template>

<script setup>
import ArticleCard from '@/components/ArticleCard.vue';
defineProps(['$context', 'articles']);
</script>
```

### Svelte (`.svelte`)
Standard Svelte (passthrough via svelte compiler):
```svelte
<script>
  import ArticleCard from '$lib/components/ArticleCard.svelte';
  export let $context;
  export let articles;
</script>

<div class="articles">
  {#each articles as article (article.id)}
    <ArticleCard {article} />
  {/each}
</div>
```

## Directory Structure

```
app/
  components/                    # Shared components
    Button.rb                    # Phlex (compiles to any target)
    Card.rb
    Modal/
      index.rb
      Overlay.rb
  views/
    articles/                    # Resource views
      Index.rb                   # or .html.erb, .jsx, .vue, .svelte
      Show.rb
      _ArticleCard.rb            # Local component (underscore prefix)
    layouts/
      Application.rb
```

## Import Resolution

Bare specifiers resolved by builder:

```ruby
# Source
import Button from 'components/Button'
import Card from 'components/Card'

# Resolved (from app/views/articles/)
import Button from '../../components/Button.js'
import Card from '../../components/Card.js'
```

Builder scans `app/components/` at build time and rewrites imports.

## Build Pipeline

### By Source Format

| Source | Tool | Intermediate | Framework Targets |
|--------|------|--------------|-------------------|
| `.html.erb` | Ruby2JS (ERB filter) | strings | SSR only (Hotwire) |
| `.rb` (Phlex) | Ruby2JS (Phlex filter) | pnode AST | Any |
| `.rbx` | Ruby2JS (React filter) | React JS | React/Preact |
| `.jsx` / `.tsx` | esbuild | React JS | React/Preact |
| `.vue` | vue-compiler-sfc | Vue JS | Vue |
| `.svelte` | svelte/compiler | Svelte JS | Svelte |

### By Target Framework

Phlex produces pnode AST, then serializes based on target. ERB produces strings (SSR only):

| Target | Phlex Serialization | ERB Serialization |
|--------|---------------------|-------------------|
| None (SSR) | Template literal strings | Template literal strings |
| React | React.createElement calls | N/A (use Phlex or RBX) |
| Vue | `.vue` SFC text | N/A (use Phlex) |
| Svelte | `.svelte` text | N/A (use Phlex) |
| Astro | `.astro` text | N/A (use Phlex) |

### Unified AST Flow

```
ERB Source (.html.erb)                  Phlex Source (.rb)
        │                                       │
        ▼                                       ▼
   ERB Filter                            Phlex Filter
        │                                       │
        ▼                                       ▼
Template literal strings                  pnode AST
        │                                       │
        ▼                        ┌──────────────┼──────────────────┐
   SSR only                      │              │                  │
   (Hotwire)                     ▼              ▼                  ▼
                           String Mode    React Mode       Vue/Svelte/Astro Mode
                                 │              │                  │
                                 ▼              ▼                  ▼
                              `<div>`    createElement()      .vue/.svelte/.astro
                                 │              │                  │
                                 ▼              ▼                  ▼
                               Done           Done          Framework Compiler
                                                                   │
                                                                   ▼
                                                             JavaScript
```

**Why ERB can't target React:** ERB templates use string concatenation, allowing arbitrary HTML fragments. A conditional block might contain just a closing `</div>` tag without its opening tag. This is valid for string output but incompatible with React's tree model which requires complete elements.

### Builder Implementation

```ruby
def transpile_views(framework:)
  case framework
  when :none, :react
    # Direct JS output
    transpile_erb_files(erb_files, filters: framework_filters(framework))
    transpile_phlex_files(rb_files, filters: framework_filters(framework))
    transpile_jsx_files(jsx_files) if framework == :react

  when :vue
    # Generate .vue files, then compile
    generate_vue_sfcs(erb_files + rb_files)
    compile_vue_files(vue_files)

  when :svelte
    # Generate .svelte files, then compile
    generate_svelte_components(erb_files + rb_files)
    compile_svelte_files(svelte_files)

  when :astro
    # Generate .astro files, integrate with Astro build
    generate_astro_components(erb_files + rb_files)
    # Astro handles its own build
  end
end

def framework_filters(framework)
  case framework
  when :none
    [:erb, :helpers, :functions, :return]
  when :react
    [:erb, :helpers, :react, :functions, :return]
  end
end
```

## Phlex Multi-Target

Phlex parses to an intermediate pnode AST. The framework target determines serialization.

### Phlex (Existing + Extended)

The Phlex filter already supports React output. Extend for all targets:

```ruby
# String output (SSR)
Ruby2JS.convert(source, filters: [:phlex])

# React output (existing)
Ruby2JS.convert(source, filters: [:phlex, :react])

# Vue output (new)
Ruby2JS.convert(source, filters: [:phlex, :vue])

# Svelte output (new)
Ruby2JS.convert(source, filters: [:phlex, :svelte])
```

### ERB (SSR Only)

ERB stays string-output only. Its string concatenation model allows arbitrary HTML fragments that are incompatible with tree-based frameworks:

```erb
<%# This is valid ERB but can't become React %>
<% if show_wrapper %>
  <div class="wrapper">
<% end %>
  <p>Content</p>
<% if show_wrapper %>
  </div>
<% end %>
```

The opening and closing `<div>` tags are in separate conditional blocks—valid for string concatenation, impossible for React's element tree.

```ruby
# String output (SSR) - only mode for ERB
Ruby2JS.convert(erb_source, filters: [:erb, :helpers])

# For React output, use Phlex or RBX instead
```

### Same Phlex Source, Any Framework

```ruby
# app/views/articles/Index.rb
class Index < Phlex::HTML
  def view_template
    div(class: "articles") do
      h1 { "Articles" }
      articles.each do |article|
        div(class: "card") do
          h2 { article.title }
          p { article.body }
        end
      end
    end
  end
end
```

| Target | Output |
|--------|--------|
| None (SSR) | `` `<div class="articles">...${articles.map(article => `<div>...`)}` `` |
| React | `React.createElement('div', {className: 'articles'}, ...)` |
| Vue | `<template><div class="articles"><div v-for="article in articles">...` |
| Svelte | `<div class="articles">{#each articles as article}<div>...{/each}</div>` |

Same Phlex source, different output based on framework target.

## Configuration

```yaml
# config/ruby2js.yml
views:
  # Framework target (pick one)
  framework: none      # SSR only (strings) - default
  # framework: react   # React SPA
  # framework: preact  # Preact (3KB React alternative)
  # framework: solid   # Solid.js (fine-grained reactivity)
  # framework: lit     # Lit (Web Components)
  # framework: vue     # Vue SPA
  # framework: svelte  # Svelte SPA
  # framework: astro   # Astro (SSG/SSR hybrid)

  # Progressive enhancement (works with SSR strings)
  # These are additive, not exclusive
  enhancement:
    htmx: true         # Allow hx-* attributes
    alpine: true       # Allow x-* attributes

  # Import resolution
  components_path: app/components
  resolve_imports: true

  # Framework-specific options
  react:
    jsx_runtime: automatic  # React 17+
  vue:
    script_setup: true      # Use <script setup>
  svelte:
    runes: true             # Svelte 5 runes
  astro:
    client_directive: load  # client:load, client:idle, etc.
```

## Implementation Phases

### MVP Scope

**Full support (no open questions):**
- React — Phlex→React exists, RBX for JSX syntax, SSR + hydration
- Preact — Already supported via React filter, SSR + hydration
- Lit — Trivial change from SSR strings (Phlex only), SSR + hydration
- Astro — Simpler than Vue (frontmatter + JSX-style template), islands architecture

**Substantial support (core patterns work):**
- Vue — SFC generation (Phlex only), SSR + hydration, defer advanced features

**Works today (no changes needed):**
- htmx — Just HTML attributes, works with SSR
- Alpine.js — Just HTML attributes, works with SSR
- ERB — SSR string output for Hotwire (cannot target React/Vue/etc.)

**Rendering strategy (MVP default — target-aware):**
- Server targets (Node, Bun, Deno, Edge): SSR + hydration
- Browser/Capacitor/Electron targets: CSR (client-side rendering)
- No configuration needed — adapts automatically to deployment target
- Same views work everywhere, only rendering path changes

---

### Phase 1: Unified Signature ✓
- [x] Change ERB filter to use single destructured object
- [x] Update `erb_render_extra_args` to return kwarg instead of positional arg
- [x] Update partial render calls in helpers filter
- [x] Update controller filter for new calling convention

### Phase 2: Lit Target ✓
- [x] Add Lit mode to Phlex filter (html`` tagged template)
- [x] Add `lit` import generation
- [x] Handle loops (.each → .map with html`` body)

### Phase 3: RBX Support ✓
- [x] Add `.rbx` file detection to builder
- [x] Create RBX transpilation options (React filter)
- [x] Create rbx2_js converter (direct JSX → React.createElement)
- [x] Add :jsraw node type for verbatim JS output
- [x] Test RBX → React element output

### Phase 4: JSX Passthrough ✓
- [x] Add `.jsx`/`.tsx` detection to builder
- [x] Integrate esbuild for JSX transpilation (with fallback warning)
- [x] Support both `.jsx` and `.tsx` extensions

### Phase 5: Import Resolution ✓
- [x] Build component map at build time (scans app/components/)
- [x] Rewrite bare specifiers in ESM filter (resolve_component_import)
- [x] Support `components/Name` convention (maps to relative paths)

### Phase 6: Astro Target (Full Support)
- [ ] Create Astro serializer for pnode AST
- [ ] Phlex + Astro filter → `.astro` output (frontmatter + template)
- [ ] Integrate with Astro build pipeline
- [ ] Template uses JSX-style `{expr}` (same as React, simpler than Vue)
- [ ] Support client directives as passthrough attributes

### Phase 7: Vue Target (Substantial Support)
- [ ] Create Vue serializer for pnode AST
- [ ] Phlex + Vue filter → `.vue` SFC output
- [ ] Integrate vue-compiler-sfc in builder
- [ ] Core patterns: props, v-if, v-for, @events

### Phase 8: Unified Views Module
- [ ] Generate combined module from mixed file types
- [ ] Handle naming conflicts
- [ ] Source maps for all formats

---

### Future Exploration

### Phase 9: Solid.js Target
- [ ] Add Solid.js mode (JSX output, different imports)
- [ ] Handle Solid-specific reactivity patterns
- [ ] Low effort if React works

### Phase 10: Svelte Target
- [ ] Create Svelte serializer for pnode AST
- [ ] Phlex + Svelte filter → `.svelte` output
- [ ] Integrate svelte/compiler in builder

### Phase 11: Advanced Framework Features
- [ ] Vue: v-model, slots, scoped styles, Composition API
- [ ] Svelte: reactive declarations, transitions, stores, runes
- [ ] Astro: island framework integrations (React+Vue+Svelte in same app)

### Phase 12: Alternative Rendering Strategies
MVP uses target-aware defaults (SSR for servers, CSR for browser/mobile/desktop). Future phases add flexibility to override these defaults:

**Force CSR on server targets:**
- [ ] Server sends minimal HTML shell + JS bundle
- [ ] Browser renders everything
- [ ] Use case: simpler server, API-only backend
- [ ] Requires bundling story (esbuild integration)

**Force SSR on Electron:**
- [ ] Main process renders HTML
- [ ] Renderer process hydrates
- [ ] Use case: sharing exact code path with web deployment
- [ ] Adds complexity, rarely needed

**SSG (Static Site Generation):**
- [ ] Render HTML at build time, not request time
- [ ] Deploy as static files (CDN-friendly)
- [ ] Hydrate on client if needed
- [ ] Good for content sites, blogs, docs

**Per-route/per-component strategies:**
- [ ] Mix SSR, CSR, SSG within same app
- [ ] Configure rendering strategy per route
- [ ] Astro-style islands for non-Astro frameworks

**Configuration (future — override target defaults):**
```yaml
views:
  framework: react

  # Override target-aware default
  rendering: auto         # Default (MVP) — SSR for servers, CSR for local
  # rendering: ssr        # Force SSR (even on Electron)
  # rendering: csr        # Force CSR (even on Node)
  # rendering: ssg        # Static generation

  # Per-route overrides (future)
  routes:
    /blog/*: ssg
    /app/*: ssr
    /dashboard/*: csr
```

## Benefits

1. **Start simple** — ERB/Phlex with SSR, no framework overhead
2. **Graduate when ready** — Add a framework when you need interactivity
3. **No lock-in** — Switch frameworks without rewriting views
4. **Full ecosystem** — Access all framework libraries and tooling
5. **Developer choice** — Use preferred syntax per component
6. **Type safety** — TypeScript via `.tsx` files
7. **Performance** — Each framework's optimized compiler

## Open Questions

### MVP (No Open Questions)
- **React/Preact**: Fully understood, Phlex→React exists
- **Lit**: Trivial transformation from SSR strings
- **Astro**: Simpler than Vue—frontmatter + JSX-style template, client directives are just attributes
- **htmx/Alpine**: Work today with SSR, just HTML attributes

### Vue (Substantial Support)
Core patterns have no open questions. Deferred:
- `v-model` — Two-way binding syntax in Ruby?
- Slots — How to express `<slot>` in ERB/Phlex?
- Scoped styles — Where do CSS rules originate?
- Composition API — `ref()`, `computed()` in Ruby?

### Future Frameworks
**Svelte:**
- Reactive declarations (`$:`, `$state` in Svelte 5)
- Two-way bindings (more pervasive than Vue)
- Transitions/animations (Svelte-specific)
- Stores (state management)

**Solid.js:**
- Fine-grained reactivity primitives
- createSignal, createEffect in Ruby?
- Low effort for basic support (JSX output)

### Future: Astro Multi-Framework Islands
Basic Astro support has no open questions. For advanced multi-framework islands:
- How to specify which island uses which framework in ERB/Phlex?
- Integration between Ruby2JS and Astro's framework integrations
- This is configuration/tooling, not transformation complexity

### General (All Frameworks)
- Routing integration (framework-specific routers)
- Hot reload during development
- Source maps across transformations
