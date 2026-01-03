# Vite Ruby2JS Ecosystem

A unified Vite plugin that makes Ruby a first-class frontend language, targeting Rails-style apps, Vue, Svelte, Astro, and Phlex components.

## Blog Post Series Context

This is **Post 3** in a four-part series demonstrating Ruby2JS/Juntos capabilities:

| Post | Plan | Theme | Key Proof |
|------|------|-------|-----------|
| 1 | — | Patterns | Rails conventions transpile to JS |
| 2 | [HOTWIRE_TURBO.md](./HOTWIRE_TURBO.md) | Frameworks | Ruby becomes valid Stimulus/Turbo JS |
| **3** | **VITE_RUBY2JS.md** | **Tooling** | **Ruby as first-class frontend language** |
| 4 | [PHLEX_UNIFICATION.md](./PHLEX_UNIFICATION.md) | Portability | Same Ruby → Phlex JS or React |

**Builds on Post 2:** Stimulus controllers already work. Now we add HMR—edit a Ruby controller, see instant updates.

**This post proves:** Ruby integrates with modern frontend tooling (Vite) like any other language—HMR, source maps, tree shaking.

**Teaser for next post:** "HMR works for Stimulus. What about React components?"

---

## Next Iteration Scope (Post 3)

### In Scope

| Component | Description | Status |
|-----------|-------------|--------|
| Core Vite plugin | Basic `.rb` file transformation | To build |
| Rails preset | Juntos/Rails apps with HMR | To build |
| Source maps | Ruby visible in DevTools | To build |
| Error handling | Ruby line numbers in errors | To build |
| Production builds | Tree shaking, code splitting | To build |

### Demo

Use the existing **chat app** from Post 2. Add Vite configuration, show:
1. Edit `chat_controller.rb` → instant update without page refresh
2. Source maps show Ruby in browser DevTools
3. Production build is optimized

### Out of Scope (Future Iterations)

| Component | Description | Why Deferred |
|-----------|-------------|--------------|
| React preset | Phlex → React output | Depends on [PHLEX_UNIFICATION.md](./PHLEX_UNIFICATION.md) |
| Next.js preset | RSC directives + React | Depends on React preset + [VERCEL_TARGET.md](./VERCEL_TARGET.md) |
| Vue preset | Ruby in Vue SFCs | Framework complexity, uncertain audience |
| Svelte preset | Ruby in Svelte components | Needs `reactive {}` DSL |
| Astro preset | Ruby in Astro frontmatter | Lower priority |
| Phlex preset | Phlex components as ES modules | Depends on Phlex filter maturity |
| Advanced HMR | Controller/model-level updates | Core HMR first |

React/Next.js presets are Post 4 scope. Other presets remain future iterations.

---

## Vision

Today: "Ruby2JS lets you write Ruby instead of JavaScript"

With this plan: **Ruby becomes a universal frontend language** that targets any framework, any platform, with modern tooling.

```
┌─────────────────────────────────────────────────────────┐
│                    Vite Dev Server                       │
│              (HMR, fast builds, optimization)            │
├─────────────────────────────────────────────────────────┤
│              vite-plugin-ruby2js (core)                  │
│            (selfhost transpiler, source maps)            │
├──────────┬──────────┬──────────┬──────────┬─────────────┤
│  Rails   │   Vue    │  Svelte  │  Astro   │   Phlex     │
│  preset  │  preset  │  preset  │  preset  │   preset    │
└──────────┴──────────┴──────────┴──────────┴─────────────┘
```

## Why This Matters

### For Rails Developers
- HMR with state preservation (no full page refresh)
- Modern build tooling (tree shaking, code splitting)
- Path to adding Vue/Svelte interactivity without leaving Ruby

### For Frontend Developers
- Ruby's expressiveness in Vue/Svelte/Astro components
- Gradual adoption (one component at a time)
- Same tooling they already know (Vite)

### For Everyone
- One language across the stack
- Portable Phlex components (use anywhere)
- No context switching between Ruby and JavaScript

## Advantages

### Developer Experience

| Feature | Without Vite | With Vite |
|---------|--------------|-----------|
| Hot reload | Full page refresh | HMR — state preserved |
| Rebuild speed | Full project | Module-level |
| Error display | Console only | Rich browser overlay |
| CSS handling | Separate CLI | Built-in PostCSS |
| TypeScript | Not supported | Native support |

### Production Benefits

| Feature | Without Vite | With Vite |
|---------|--------------|-----------|
| Tree shaking | None | Automatic |
| Code splitting | None | Automatic |
| Minification | Optional | Built-in |
| Asset handling | Manual | Hashing, optimization |

### Ecosystem Access
- 500+ Vite plugins available
- Framework-agnostic architecture
- Native ES modules, import maps
- Standard compliance

## Prerequisites

The selfhost transpiler must handle the target files. Current status:

| Component | Status |
|-----------|--------|
| Core transpiler | ✅ Working |
| `functions` filter | ✅ Working |
| `esm` filter | ✅ Working |
| Rails filters | ✅ Working |
| Phlex filter | ✅ Beta |
| Lesser-used filters | ⏳ Parallel track |

## Architecture

### Package Structure

```
packages/vite-plugin-ruby2js/
├── package.json
├── src/
│   ├── index.ts           # Core plugin
│   ├── transform.ts       # Ruby → JS transformation
│   ├── hmr.ts            # HMR handling
│   ├── sourcemap.ts      # Source map generation
│   └── presets/
│       ├── rails.ts      # Rails/Juntos preset
│       ├── vue.ts        # Vue SFC preset
│       ├── svelte.ts     # Svelte SFC preset
│       ├── astro.ts      # Astro preset
│       └── phlex.ts      # Phlex component preset
└── README.md
```

### Transform Pipeline

```
Source File
     ↓
Preset (extract Ruby from SFC if needed)
     ↓
Selfhost Transpiler (Ruby → JS)
     ↓
Source Map Generation
     ↓
HMR Handling
     ↓
Vite (serves/bundles)
```

## Core Plugin

The foundation that all presets build on:

```typescript
// packages/vite-plugin-ruby2js/src/index.ts
import type { Plugin } from 'vite';
import { Ruby2JS } from 'ruby2js-selfhost';

export interface Ruby2JSOptions {
  filters?: string[];
  eslevel?: number;
  [key: string]: any;
}

export default function ruby2js(options: Ruby2JSOptions = {}): Plugin {
  const {
    filters = ['functions', 'esm', 'return'],
    eslevel = 2022,
    ...ruby2jsOptions
  } = options;

  return {
    name: 'ruby2js',

    transform(code: string, id: string) {
      if (!id.endsWith('.rb')) return null;

      const result = Ruby2JS.convert(code, {
        filters,
        eslevel,
        file: id,
        ...ruby2jsOptions
      });

      return {
        code: result.toString(),
        map: result.sourcemap
      };
    }
  };
}

// Re-export presets
export { rails } from './presets/rails';
export { vue } from './presets/vue';
export { svelte } from './presets/svelte';
export { astro } from './presets/astro';
export { phlex } from './presets/phlex';
```

## Presets

### Rails/Juntos Preset

For Rails-style applications with models, controllers, ERB views.

**Usage:**
```javascript
// vite.config.js
import { defineConfig } from 'vite';
import { rails } from 'vite-plugin-ruby2js';

export default defineConfig({
  plugins: [rails()]
});
```

**Implementation:**
```typescript
// src/presets/rails.ts
import type { Plugin } from 'vite';
import ruby2js from '../index';
import { transformErb } from '../transform';

export function rails(options = {}): Plugin[] {
  return [
    ruby2js({
      filters: [
        'rails/model',
        'rails/controller',
        'rails/helpers',
        'functions',
        'esm',
        'return'
      ],
      ...options
    }),

    {
      name: 'ruby2js-rails-erb',
      transform(code, id) {
        if (!id.endsWith('.erb')) return null;
        return transformErb(code, id, options);
      }
    },

    {
      name: 'ruby2js-rails-hmr',
      handleHotUpdate({ file, server }) {
        if (file.includes('/views/')) {
          server.ws.send({
            type: 'custom',
            event: 'ruby2js:view-update',
            data: { file }
          });
          return []; // Prevent full reload
        }
      }
    },

    {
      name: 'ruby2js-rails-config',
      config() {
        return {
          resolve: {
            alias: {
              '@models': 'app/models',
              '@controllers': 'app/controllers',
              '@views': 'app/views'
            }
          }
        };
      }
    }
  ];
}
```

**HMR Behavior:**
- View changes → Re-render current view (preserve model data)
- Controller changes → Re-run current action
- Model changes → Full reload (instances become stale)

---

### Vue Preset

For Ruby inside Vue single-file components.

**Usage:**
```javascript
// vite.config.js
import { defineConfig } from 'vite';
import { vue } from 'vite-plugin-ruby2js';
import vuePlugin from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue(), vuePlugin()]
});
```

**Example component:**
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
  count.value++;
}
</script>
```

**Implementation:**
```typescript
// src/presets/vue.ts
import type { Plugin } from 'vite';
import { Ruby2JS } from 'ruby2js-selfhost';

export function vue(options = {}): Plugin {
  return {
    name: 'ruby2js-vue',
    enforce: 'pre',

    async transform(code, id) {
      if (!id.endsWith('.vue')) return null;

      const { parse } = await import('@vue/compiler-sfc');
      const { descriptor } = parse(code);

      let result = code;

      // Transform <script> block
      if (descriptor.script?.content) {
        const js = Ruby2JS.convert(descriptor.script.content, {
          filters: ['functions', 'esm'],
          plain_properties: true, // this.foo not this._foo
          ...options
        });
        result = result.replace(descriptor.script.content, js.toString());
      }

      // Transform <script setup> block
      if (descriptor.scriptSetup?.content) {
        const js = Ruby2JS.convert(descriptor.scriptSetup.content, {
          filters: ['functions', 'esm'],
          ...options
        });
        result = result.replace(descriptor.scriptSetup.content, js.toString());
      }

      return result;
    }
  };
}
```

**Notes:**
- Composition API works cleanly (no `this.` needed)
- Options API needs `plain_properties: true` option
- Template expressions can optionally be converted

---

### Svelte Preset

For Ruby inside Svelte components.

**Usage:**
```javascript
// vite.config.js
import { defineConfig } from 'vite';
import { svelte } from 'vite-plugin-ruby2js';
import sveltePlugin from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  plugins: [svelte(), sveltePlugin()]
});
```

**Example component:**
```svelte
<script>
count = 0

def increment
  count += 1
end

# Reactive declaration
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
  count++;
}

$: doubled = count * 2;
</script>
```

**Implementation:**
```typescript
// src/presets/svelte.ts
import type { Plugin } from 'vite';
import { Ruby2JS } from 'ruby2js-selfhost';

export function svelte(options = {}): Plugin {
  return {
    name: 'ruby2js-svelte',
    enforce: 'pre',

    async transform(code, id) {
      if (!id.endsWith('.svelte')) return null;

      const { parse } = await import('svelte/compiler');
      const ast = parse(code);

      if (!ast.instance) return null;

      const scriptStart = ast.instance.content.start;
      const scriptEnd = ast.instance.content.end;
      const scriptContent = code.slice(scriptStart, scriptEnd);

      const js = Ruby2JS.convert(scriptContent, {
        filters: ['functions', 'svelte'], // svelte filter handles reactive {}
        ...options
      });

      return (
        code.slice(0, scriptStart) +
        js.toString() +
        code.slice(scriptEnd)
      );
    }
  };
}
```

**Proposed DSL for Svelte reactivity:**
```ruby
reactive { doubled = count * 2 }     # → $: doubled = count * 2
reactive { console.log(count) }      # → $: console.log(count)
```

---

### Astro Preset

For Ruby in Astro components (frontmatter and scripts).

**Usage:**
```javascript
// vite.config.js
import { defineConfig } from 'vite';
import { astro } from 'vite-plugin-ruby2js';

export default defineConfig({
  plugins: [astro()]
});
```

**Example component:**
```astro
---
# Frontmatter (build-time)
title = "My Page"
posts = await fetch_posts()
featured = posts.select { |p| p.featured }.first(3)
---

<Layout title={title}>
  <h1>{title}</h1>
  {featured.map { |post|
    <li><a href={post.url}>{post.title}</a></li>
  }}
</Layout>

<script>
  # Client-side
  def handle_click(event)
    console.log("clicked", event.target)
  end

  document.querySelector("button")&.addEventListener("click", handle_click)
</script>
```

**Implementation:**
```typescript
// src/presets/astro.ts
import type { Plugin } from 'vite';
import { Ruby2JS } from 'ruby2js-selfhost';

export function astro(options = {}): Plugin {
  return {
    name: 'ruby2js-astro',
    enforce: 'pre',

    async transform(code, id) {
      if (!id.endsWith('.astro')) return null;

      const { parse } = await import('@astrojs/compiler');
      const ast = await parse(code);

      let result = code;

      // Transform frontmatter (between --- fences)
      if (ast.frontmatter) {
        const js = Ruby2JS.convert(ast.frontmatter.content, {
          filters: ['functions', 'esm'],
          ...options
        });
        result = result.replace(ast.frontmatter.content, js.toString());
      }

      // Transform <script> tags
      // ... similar extraction and replacement

      return result;
    }
  };
}
```

**Notes:**
- Cleanest integration (clear script boundaries)
- Frontmatter is explicitly for build-time logic
- Works with any UI framework for islands

---

### Phlex Preset

For Phlex components as standalone files.

**Usage:**
```javascript
// vite.config.js
import { defineConfig } from 'vite';
import { phlex } from 'vite-plugin-ruby2js';

export default defineConfig({
  plugins: [phlex()]
});
```

**Example component:**
```ruby
# components/card.phlex.rb
class Card < Phlex::HTML
  def initialize(title:, items:)
    @title = title
    @items = items
  end

  def view_template
    div(class: "card") do
      h1 { @title }
      ul do
        @items.each do |item|
          li { item.name }
        end
      end
    end
  end
end
```

**With component composition:**
```ruby
# components/page.phlex.rb
class Page < Phlex::HTML
  def view_template
    render Header.new(title: @title)
    div { @content }
    render Footer.new
  end
end
```

**Output:**
```javascript
import Header from './header.phlex.rb';
import Footer from './footer.phlex.rb';

export function render({ content, title }) {
  let _phlex_out = "";
  _phlex_out += Header.render({ title });
  _phlex_out += `<div>${content}</div>`;
  _phlex_out += Footer.render({});
  return _phlex_out;
}
```

**Implementation:**
```typescript
// src/presets/phlex.ts
import type { Plugin } from 'vite';
import { Ruby2JS } from 'ruby2js-selfhost';

export function phlex(options = {}): Plugin {
  return {
    name: 'ruby2js-phlex',

    transform(code, id) {
      if (!id.endsWith('.phlex.rb')) return null;

      const js = Ruby2JS.convert(code, {
        filters: ['phlex', 'functions', 'esm'],
        ...options
      });

      // Analyze for component references
      // Add import statements
      // Export render function

      return {
        code: js.toString(),
        map: js.sourcemap
      };
    }
  };
}
```

**Why Phlex is strategic:**
- Users already chose Ruby for views — natural audience
- Pure Ruby (no template syntax to parse)
- Works with all other presets
- Components portable across frameworks

## Shared Infrastructure

### HMR Runtime

Injected into the browser for all presets:

```typescript
// src/hmr.ts
if (import.meta.hot) {
  // View updates (Rails, Phlex)
  import.meta.hot.on('ruby2js:view-update', async (data) => {
    const newModule = await import(data.file + '?t=' + Date.now());
    Application?.rerender?.(newModule.render);
  });

  // Controller updates (Rails)
  import.meta.hot.on('ruby2js:controller-update', async (data) => {
    const newController = await import(data.file + '?t=' + Date.now());
    Application?.rerunAction?.(newController);
  });

  // Component updates (Phlex)
  import.meta.hot.on('ruby2js:component-update', async (data) => {
    // Re-render components of this type
  });
}
```

### Source Maps

All presets generate source maps back to original Ruby:

```typescript
// src/sourcemap.ts
export function generateSourceMap(result, originalSource, filePath) {
  const map = result.sourcemap;
  map.sources = [filePath];
  map.sourcesContent = [originalSource];
  return map;
}
```

For SFCs, chain maps: Ruby in `<script>` → JS → final output.

### Instance Variable Handling

Different frameworks need different `@foo` behavior:

| Context | `@foo` becomes | Option |
|---------|----------------|--------|
| Juntos/Rails | `this._foo` | Default |
| Vue Options API | `this.foo` | `plain_properties: true` |
| Svelte | `foo` (module scope) | `no_this: true` |

## Use Cases Unlocked

### 1. Full-Stack Ruby SPA

```
app/
├── models/          # ActiveRecord patterns
├── controllers/     # Request handling
├── views/           # ERB templates
└── components/      # Interactive parts
    ├── search.vue       # Vue + Ruby
    ├── dashboard.svelte # Svelte + Ruby
    └── chart.phlex.rb   # Phlex component
```

### 2. Island Architecture

```astro
---
articles = Article.published.limit(10)
---

<!-- Static HTML (fast) -->
{articles.map { |a| <Card article={a} /> }}

<!-- Interactive island (Svelte + Ruby) -->
<Comments client:visible article={@article} />
```

### 3. Gradual Migration

| Week | Action |
|------|--------|
| 1 | Add Vite to existing Rails app |
| 2 | Convert one JS file to Ruby |
| 3 | Add Vue component in Ruby |
| 4 | Replace complex JS with Phlex |

### 4. Portable Component Library

```bash
npm install @acme/ruby-components
```

```ruby
# Works in any Vite project
import DataTable from "@acme/ruby-components/data_table.phlex.rb"
render DataTable.new(data: @users)
```

## Implementation Phases

### Phase 1: Core Plugin
- [ ] Package structure and build setup
- [ ] Basic `.rb` file transformation
- [ ] Source map generation
- [ ] Error handling with Ruby line numbers

### Phase 2: Rails Preset
- [ ] ERB file transformation
- [ ] Directory conventions and aliases
- [ ] View-level HMR
- [ ] Controller-level HMR
- [ ] Integration with existing Juntos apps

### Phase 3: Phlex Preset
- [ ] Component file transformation (`.phlex.rb`)
- [ ] Component composition detection
- [ ] ES module import generation
- [ ] HMR for component updates

### Phase 4: Vue Preset
- [ ] Script block extraction
- [ ] `<script setup>` support
- [ ] Composition API testing
- [ ] Options API with `plain_properties`
- [ ] Template expression conversion (optional)

### Phase 5: Svelte Preset
- [ ] Script block extraction
- [ ] `reactive {}` DSL for `$:` declarations
- [ ] Basic component testing
- [ ] Store handling (optional)

### Phase 6: Astro Preset
- [ ] Frontmatter extraction
- [ ] Client script extraction
- [ ] Island component testing
- [ ] Integration with other presets

### Phase 7: Polish
- [ ] Unified plugin with auto-detection
- [ ] Comprehensive source maps
- [ ] Documentation and examples
- [ ] npm package publication
- [ ] Demo applications

## Success Criteria

1. `vite dev` transforms Ruby files with HMR
2. Editing a view preserves application state
3. Vue/Svelte components work with Ruby scripts
4. Phlex components compose via ES imports
5. Source maps show original Ruby in DevTools
6. Production builds are optimized (tree shaking, splitting)
7. Migration from current Juntos dev server is seamless

## Open Questions

1. **Ruby fallback**: Shell out to Ruby CLI when selfhost lacks filter support?
2. **Caching**: Disk cache for faster cold starts?
3. **IDE support**: Syntax highlighting for Ruby in SFCs?
4. **File extensions**: `.vue` vs `.vue.rb` for Ruby Vue components?
5. **Monorepo**: Multiple apps with shared components?

## References

- [Vite Plugin API](https://vitejs.dev/guide/api-plugin.html)
- [Vite HMR API](https://vitejs.dev/guide/api-hmr.html)
- [@vue/compiler-sfc](https://www.npmjs.com/package/@vue/compiler-sfc)
- [svelte/compiler](https://svelte.dev/docs/svelte-compiler)
- [@astrojs/compiler](https://www.npmjs.com/package/@astrojs/compiler)
- [Ruby2JS Selfhost](../demo/selfhost/)
- [Phlex Filter](../lib/ruby2js/filter/phlex.rb)
