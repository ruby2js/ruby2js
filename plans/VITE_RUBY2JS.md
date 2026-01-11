# Ruby in the Modern Frontend Ecosystem

A Vite plugin that makes Ruby a first-class language in the standard frontend toolchain.

## Strategic Context

**Vite is not just a build tool—it's the infrastructure standard for modern frontend development.**

| Framework | Vite Status |
|-----------|-------------|
| Vue 3 / Nuxt 3 | Default (same creator) |
| Svelte / SvelteKit | Default |
| Astro | Built on Vite |
| Solid / SolidStart | Default |
| Qwik | Default |
| Remix | Migrated to Vite |
| Preact | Official preset |
| Lit | Recommended |

The notable exception is Next.js (uses Turbopack). But for the broader ecosystem, **Vite is the common denominator**.

A single `vite-plugin-ruby2js` automatically works everywhere Vite runs:
- `npm create vue@latest` → add plugin → Ruby in Vue
- `npm create svelte@latest` → add plugin → Ruby in Svelte
- `npm create astro@latest` → add plugin → Ruby in Astro

**This plan is not about "adding Vite as a feature." It's about making the strategic investments to plug Ruby into the ecosystem standard.**

---

## Blog Post Series Context

This is **Post 3** in a four-part series demonstrating Ruby2JS/Juntos capabilities:

| Post | Plan | Theme | Key Proof |
|------|------|-------|-----------|
| 1 | — | Patterns | Rails conventions transpile to JS |
| 2 | [HOTWIRE_TURBO.md](./HOTWIRE_TURBO.md) | Frameworks | Ruby becomes valid Stimulus/Turbo JS |
| **3** | **VITE_RUBY2JS.md** | **Ecosystem** | **Ruby joins the standard frontend toolchain** |
| 4 | [PHLEX_UNIFICATION.md](./PHLEX_UNIFICATION.md) | Portability | Same Ruby → any framework |

**Builds on Post 2:** Stimulus controllers work. Now Ruby works in *any* Vite-based project.

**This post proves:** Ruby is a first-class frontend language—not a Rails-only solution.

---

## Current State Assessment

### Selfhost Readiness by Ecosystem Value

The Vite plugin runs in Node/browser via the selfhost transpiler. Filter readiness determines what's possible:

| Tier | Purpose | Filters | Selfhost | Ecosystem Unlock |
|------|---------|---------|----------|------------------|
| **1 - Core** | Basic Ruby→JS | functions, esm, return, camelCase | ✅ Ready | Any Vite project |
| **2 - Rails** | Hotwire/Stimulus | stimulus, erb, rails_* | ✅ Ready | Rails-style apps |
| **3 - React** | React ecosystem | react, jsx, preact | ⚠️ Partial | React, Preact, Remix |
| **4 - Phlex** | Multi-framework | phlex | ⚠️ Partial | [UNIFIED_VIEWS](./UNIFIED_VIEWS.md) gateway |
| **5 - Frameworks** | Direct targets | vue, astro, lit | ⚠️ Partial | Vue, Astro, Lit |
| **6 - Enhancement** | Progressive | alpine, turbo | ⚠️ Partial | htmx/Alpine patterns |

### Key Insight

**Tiers 1-2 are ready.** A working Vite plugin with Rails/Stimulus support can ship immediately.

**Tier 3 (React) is the highest-value investment.** The React ecosystem is massive.

**Tier 4 (Phlex) is the force multiplier.** Once Phlex selfhost is ready, [UNIFIED_VIEWS.md](./UNIFIED_VIEWS.md) kicks in—same source targets React, Vue, Astro, Lit.

### Foundation Work Complete

The [UNIFIED_VIEWS.md](./UNIFIED_VIEWS.md) plan phases 1-8 are complete in Ruby:
- Unified function signature ✓
- Phlex pnode AST ✓
- Vue, Astro, Lit filters ✓ (Ruby CLI)
- RBX support ✓
- Import resolution ✓

The bottleneck is selfhost. The Ruby filters exist; they need to pass selfhost specs.

---

## Implementation Strategy

### Phase 1: Ship What's Ready

**Goal:** Working Vite plugin using ready selfhost filters.

| Task | Status |
|------|--------|
| Package structure (`packages/vite-plugin-ruby2js/`) | To build |
| Core plugin (`.rb` → `.js` transformation) | To build |
| Rails preset (stimulus, erb, rails filters) | To build |
| Source maps (Ruby visible in DevTools) | To build |
| Error handling (Ruby line numbers) | To build |
| HMR for Stimulus controllers | To build |

**Filters used:** functions, esm, return, camelCase, stimulus, erb, rails_* — all ✅ Ready

**Demo:** Existing chat app from Post 2. Edit `chat_controller.rb` → instant HMR update.

### Phase 2: Selfhost Investment — React

**Goal:** Unlock React ecosystem access.

| Task | Status |
|------|--------|
| Promote `react_spec.rb` to ready | To do |
| Promote `jsx_spec.rb` to ready | To do |
| Promote `preact_spec.rb` to ready | To do |

**Unlocks:** React, Preact, Remix, and most SPAs built on Vite.

### Phase 3: React Preset

**Goal:** Full React component authoring in Ruby.

| Task | Status |
|------|--------|
| React preset for Vite plugin | To build |
| RBX file support (`.rbx` → React) | To build |
| JSX passthrough (`.jsx`/`.tsx` via esbuild) | To build |

**Depends on:** Phase 2 selfhost work.

### Phase 4: Selfhost Investment — Phlex

**Goal:** Unlock multi-framework targeting.

| Task | Status |
|------|--------|
| Promote `phlex_spec.rb` to ready | To do |

**Unlocks:** [UNIFIED_VIEWS.md](./UNIFIED_VIEWS.md) — same Phlex source targets React, Vue, Astro, Lit.

### Phase 5: Phlex Preset

**Goal:** Phlex components as portable ES modules.

| Task | Status |
|------|--------|
| Phlex preset for Vite plugin (`.phlex.rb`) | To build |
| Component composition detection | To build |
| Framework target selection (React, Vue, etc.) | To build |

**Depends on:** Phase 4 selfhost work.

### Phase 6: Selfhost Investment — Framework Filters

**Goal:** Enable direct framework output.

| Task | Status |
|------|--------|
| Promote `vue_spec.rb` to ready | To do |
| Promote `astro_spec.rb` to ready | To do |
| Promote `lit_spec.rb` to ready | To do |

**Unlocks:** Direct SFC generation without Phlex intermediate.

### Phase 7: Framework Presets

**Goal:** Native integration with each framework's ecosystem.

| Preset | Description | Depends On |
|--------|-------------|------------|
| Vue | Ruby in `<script>` blocks, Phlex → `.vue` SFC | Phase 6 |
| Astro | Ruby in frontmatter, Phlex → `.astro` | Phase 6 |
| Lit | Phlex → Web Components | Phase 6 |
| Svelte | Ruby in `<script>` blocks | New svelte filter needed |

---

## Architecture

### Package Structure

```
packages/vite-plugin-ruby2js/
├── package.json
├── src/
│   ├── index.ts           # Core plugin
│   ├── transform.ts       # Ruby → JS via selfhost
│   ├── hmr.ts             # HMR handling
│   ├── sourcemap.ts       # Source map generation
│   └── presets/
│       ├── rails.ts       # Rails/Stimulus (Phase 1)
│       ├── react.ts       # React/RBX (Phase 3)
│       ├── phlex.ts       # Phlex components (Phase 5)
│       ├── vue.ts         # Vue SFC (Phase 7)
│       └── astro.ts       # Astro (Phase 7)
└── README.md
```

### Transform Pipeline

```
Source File (.rb, .rbx, .phlex.rb)
     ↓
Preset (configure filters, extract from SFC if needed)
     ↓
Selfhost Transpiler (Ruby → JS)
     ↓
Source Map Generation
     ↓
HMR Wrapper
     ↓
Vite (serves in dev, bundles for prod)
```

### Package Dependencies

The Vite plugin depends on the existing `ruby2js` npm package, which provides the selfhost transpiler.

**Existing package hierarchy:**

```
vite-plugin-ruby2js (new)
  └── ruby2js (existing - converter + filters)
        └── @ruby/prism (parser)

ruby2js-rails (existing - Rails runtime)
  └── ruby2js
```

**Current distribution (beta):**

```json
{
  "dependencies": {
    "ruby2js": "https://www.ruby2js.com/releases/ruby2js-beta.tgz"
  }
}
```

**Future (stable release):**

```json
{
  "dependencies": {
    "ruby2js": "^6.0.0"
  }
}
```

The `ruby2js` package is built from `demo/selfhost/` and includes:
- Core converter (`ruby2js.js`)
- All filters (`filters/*.js`)
- CLI tool (`ruby2js-cli.js`)
- Depends on `@ruby/prism` for parsing

See [NPM_SELFHOST_MIGRATION.md](./NPM_SELFHOST_MIGRATION.md) for full package structure details.

**Transform implementation:**

```typescript
// packages/vite-plugin-ruby2js/src/transform.ts
import { Ruby2JS } from 'ruby2js';

export async function transform(code: string, options: TransformOptions) {
  return Ruby2JS.convert(code, {
    filters: options.filters,
    eslevel: options.eslevel ?? 2022,
    ...options.ruby2jsOptions
  });
}
```

No bundling required—the Vite plugin simply imports from the `ruby2js` dependency.

---

## Ruby Detection Strategy

A Juntos application can mix JavaScript, TypeScript, and Ruby components. Each context uses its native mechanism for language selection.

### Detection by Context

| Context | Ruby Signal | Example |
|---------|-------------|---------|
| Standalone file | File extension | `.rb`, `.rbx` |
| Vue `<script>` | `lang` attribute | `<script lang="ruby">` |
| Svelte `<script>` | `lang` attribute | `<script lang="ruby">` |
| Astro `<script>` | `lang` attribute | `<script lang="ruby">` |
| Astro frontmatter | Shebang | `#!ruby` |

### Standalone Files

Different extensions for different source languages:

| Language | Plain | With JSX |
|----------|-------|----------|
| JavaScript | `.js` | `.jsx` |
| TypeScript | `.ts` | `.tsx` |
| Ruby | `.rb` | `.rbx` |

### SFC Script Blocks (Vue, Svelte, Astro)

Follows the established `lang` attribute pattern (same as TypeScript):

```vue
<!-- Vue with Ruby -->
<script lang="ruby">
def increment
  @count += 1
end
</script>

<template>
  <button @click="increment">{{ count }}</button>
</template>
```

```svelte
<!-- Svelte with Ruby -->
<script lang="ruby">
count = 0

def increment
  count += 1
end
</script>

<button on:click={increment}>{count}</button>
```

A single project can mix languages:

```
src/components/
├── Button.vue          # <script> (JavaScript)
├── Card.vue            # <script lang="ts"> (TypeScript)
├── Modal.vue           # <script lang="ruby"> (Ruby)
└── Dialog.vue          # <script lang="ruby"> (Ruby)
```

### Astro Frontmatter

Astro frontmatter uses `---` fences without a `lang` attribute. Detection uses a shebang:

```astro
---
#!ruby
posts = Post.published.limit(10)
featured = posts.select { |p| p.featured? }
---

<Layout>
  {featured.map { |post| <Card post={post} /> }}
</Layout>
```

The `#!ruby` shebang is stripped during transformation—Astro never sees it.

**Why shebang?**
- `#` is not valid JavaScript at the start of a line (JS uses `//` for comments)
- Familiar convention from Unix scripts
- Visually distinct and self-documenting
- Any Ruby comment would work (`# lang: ruby`, `# ruby2js`), but `#!ruby` is canonical

**JavaScript frontmatter (default):**
```astro
---
const posts = await fetchPosts();
const featured = posts.filter(p => p.featured);
---
```

No shebang = JavaScript (the default).

### Implementation

The preset detects Ruby and transforms before the framework compiler sees it:

```typescript
// Vue preset detection
function isRubyScript(scriptContent: string, attrs: Record<string, string>): boolean {
  return attrs.lang === 'ruby';
}

// Astro frontmatter detection
function isRubyFrontmatter(content: string): boolean {
  const firstLine = content.trim().split('\n')[0];
  return firstLine.startsWith('#!ruby') || firstLine.startsWith('# lang: ruby');
}
```

---

## Core Plugin

```typescript
// packages/vite-plugin-ruby2js/src/index.ts
import type { Plugin } from 'vite';
import { Ruby2JS } from 'ruby2js';

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
    name: 'vite-plugin-ruby2js',

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
export { react } from './presets/react';
export { phlex } from './presets/phlex';
export { vue } from './presets/vue';
export { astro } from './presets/astro';
```

---

## Presets

### Rails Preset (Phase 1)

For Rails-style applications with Stimulus controllers, ERB views.

```javascript
// vite.config.js
import { defineConfig } from 'vite';
import { rails } from 'vite-plugin-ruby2js';

export default defineConfig({
  plugins: [rails()]
});
```

```typescript
// src/presets/rails.ts
import type { Plugin } from 'vite';
import ruby2js from '../index';

export function rails(options = {}): Plugin[] {
  return [
    ruby2js({
      filters: [
        'stimulus',
        'rails/helpers',
        'functions',
        'esm',
        'return'
      ],
      ...options
    }),

    {
      name: 'ruby2js-rails-hmr',
      handleHotUpdate({ file, server }) {
        if (file.endsWith('_controller.rb')) {
          server.ws.send({
            type: 'custom',
            event: 'ruby2js:stimulus-update',
            data: { file }
          });
          return []; // HMR handled, prevent full reload
        }
      }
    },

    {
      name: 'ruby2js-rails-config',
      config() {
        return {
          resolve: {
            alias: {
              '@controllers': 'app/javascript/controllers',
              '@models': 'app/models',
              '@views': 'app/views'
            }
          }
        };
      }
    }
  ];
}
```

### React Preset (Phase 3)

For React components in Ruby, including RBX files.

```javascript
// vite.config.js
import { defineConfig } from 'vite';
import { react } from 'vite-plugin-ruby2js';

export default defineConfig({
  plugins: [react()]
});
```

```typescript
// src/presets/react.ts
import type { Plugin } from 'vite';
import ruby2js from '../index';

export function react(options = {}): Plugin[] {
  return [
    // Handle .rb files with React filter
    ruby2js({
      filters: ['react', 'functions', 'esm', 'return'],
      ...options
    }),

    // Handle .rbx files (Ruby + JSX)
    {
      name: 'ruby2js-rbx',
      transform(code, id) {
        if (!id.endsWith('.rbx')) return null;

        return transform(code, {
          filters: ['react', 'functions', 'esm', 'return'],
          rbx: true, // Enable RBX mode
          ...options
        });
      }
    }
  ];
}
```

### Phlex Preset (Phase 5)

For Phlex components as portable modules.

```javascript
// vite.config.js
import { defineConfig } from 'vite';
import { phlex } from 'vite-plugin-ruby2js';

export default defineConfig({
  plugins: [phlex({ target: 'react' })] // or 'vue', 'astro', 'lit', 'ssr'
});
```

```typescript
// src/presets/phlex.ts
import type { Plugin } from 'vite';
import ruby2js from '../index';

type PhlexTarget = 'ssr' | 'react' | 'vue' | 'astro' | 'lit';

export function phlex(options: { target?: PhlexTarget } = {}): Plugin {
  const target = options.target ?? 'ssr';

  const targetFilters: Record<PhlexTarget, string[]> = {
    ssr: ['phlex', 'functions', 'esm', 'return'],
    react: ['phlex', 'react', 'functions', 'esm', 'return'],
    vue: ['phlex', 'vue', 'functions', 'esm', 'return'],
    astro: ['phlex', 'astro', 'functions', 'esm', 'return'],
    lit: ['phlex', 'lit', 'functions', 'esm', 'return'],
  };

  return ruby2js({
    filters: targetFilters[target],
    ...options
  });
}
```

### Vue Preset (Phase 7)

For Ruby in Vue Single File Components via `<script lang="ruby">`.

```javascript
// vite.config.js
import { defineConfig } from 'vite';
import { vue } from 'vite-plugin-ruby2js';
import vuePlugin from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [
    vue(),       // Must come BEFORE vuePlugin
    vuePlugin()
  ]
});
```

```typescript
// src/presets/vue.ts
import type { Plugin } from 'vite';
import { Ruby2JS } from 'ruby2js';

export function vue(options = {}): Plugin {
  return {
    name: 'ruby2js-vue',
    enforce: 'pre',  // Run BEFORE @vitejs/plugin-vue

    transform(code: string, id: string) {
      if (!id.endsWith('.vue')) return null;

      // Match all script blocks (regular and setup)
      const scriptRegex = /<script(\s[^>]*)?>([\\s\\S]*?)<\/script>/g;
      let result = code;
      let hasRuby = false;

      result = result.replace(scriptRegex, (match, attrs = '', content) => {
        // Check for lang="ruby"
        if (!attrs.includes('lang="ruby"')) return match;

        hasRuby = true;

        // Transform Ruby → JS
        const js = Ruby2JS.convert(content, {
          filters: ['functions', 'esm'],
          ...options
        });

        // Remove lang="ruby", keep other attrs (like "setup")
        const newAttrs = attrs.replace(/\s*lang="ruby"/, '');
        return `<script${newAttrs}>${js.toString()}</script>`;
      });

      return hasRuby ? result : null;
    }
  };
}
```

**Example Vue component:**

```vue
<script setup lang="ruby">
count = ref(0)

def increment
  count.value += 1
end
</script>

<template>
  <button @click="increment">Count: {{ count }}</button>
</template>
```

**After transformation (what @vitejs/plugin-vue sees):**

```vue
<script setup>
const count = ref(0);

function increment() {
  count.value++;
}
</script>

<template>
  <button @click="increment">Count: {{ count }}</button>
</template>
```

### Svelte Preset (Phase 7)

For Ruby in Svelte components via `<script lang="ruby">`.

```javascript
// vite.config.js
import { defineConfig } from 'vite';
import { svelte } from 'vite-plugin-ruby2js';
import sveltePlugin from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  plugins: [
    svelte(),       // Must come BEFORE sveltePlugin
    sveltePlugin()
  ]
});
```

```typescript
// src/presets/svelte.ts
import type { Plugin } from 'vite';
import { Ruby2JS } from 'ruby2js';

export function svelte(options = {}): Plugin {
  return {
    name: 'ruby2js-svelte',
    enforce: 'pre',  // Run BEFORE @sveltejs/vite-plugin-svelte

    transform(code: string, id: string) {
      if (!id.endsWith('.svelte')) return null;

      // Match script block
      const scriptRegex = /<script(\s[^>]*)?>([\\s\\S]*?)<\/script>/;
      const match = code.match(scriptRegex);

      if (!match) return null;

      const [fullMatch, attrs = '', content] = match;

      // Check for lang="ruby"
      if (!attrs.includes('lang="ruby"')) return null;

      // Transform Ruby → JS
      const js = Ruby2JS.convert(content, {
        filters: ['functions', 'esm'],
        ...options
      });

      // Remove lang="ruby"
      const newAttrs = attrs.replace(/\s*lang="ruby"/, '');
      const newScript = `<script${newAttrs}>${js.toString()}</script>`;

      return code.replace(fullMatch, newScript);
    }
  };
}
```

**Example Svelte component:**

```svelte
<script lang="ruby">
count = 0

def increment
  count += 1
end
</script>

<button on:click={increment}>Count: {count}</button>
```

### Astro Preset (Phase 7)

For Ruby in Astro components via `<script lang="ruby">` and `#!ruby` frontmatter.

```javascript
// vite.config.js
import { defineConfig } from 'vite';
import { astro } from 'vite-plugin-ruby2js';

export default defineConfig({
  plugins: [astro()]
});
```

```typescript
// src/presets/astro.ts
import type { Plugin } from 'vite';
import { Ruby2JS } from 'ruby2js';

export function astro(options = {}): Plugin {
  return {
    name: 'ruby2js-astro',
    enforce: 'pre',  // Run before Astro's Vite plugin

    transform(code: string, id: string) {
      if (!id.endsWith('.astro')) return null;

      let result = code;
      let hasRuby = false;

      // 1. Check frontmatter for #!ruby shebang
      const frontmatterRegex = /^---\n([\s\S]*?)\n---/;
      const fmMatch = result.match(frontmatterRegex);

      if (fmMatch) {
        const frontmatter = fmMatch[1];
        const firstLine = frontmatter.trim().split('\n')[0];

        if (firstLine.startsWith('#!ruby') || firstLine.startsWith('# lang: ruby')) {
          hasRuby = true;

          // Remove shebang line, transform rest
          const rubyCode = frontmatter.replace(/^#!ruby\n?|^# lang: ruby\n?/, '');
          const js = Ruby2JS.convert(rubyCode, {
            filters: ['functions', 'esm'],
            ...options
          });

          result = result.replace(frontmatterRegex, `---\n${js.toString()}\n---`);
        }
      }

      // 2. Check script tags for lang="ruby"
      const scriptRegex = /<script(\s[^>]*)?>([\\s\\S]*?)<\/script>/g;

      result = result.replace(scriptRegex, (match, attrs = '', content) => {
        if (!attrs.includes('lang="ruby"')) return match;

        hasRuby = true;

        const js = Ruby2JS.convert(content, {
          filters: ['functions', 'esm'],
          ...options
        });

        const newAttrs = attrs.replace(/\s*lang="ruby"/, '');
        return `<script${newAttrs}>${js.toString()}</script>`;
      });

      return hasRuby ? result : null;
    }
  };
}
```

**Example Astro component with Ruby frontmatter:**

```astro
---
#!ruby
posts = await fetch_posts()
featured = posts.select { |p| p.featured? }.first(3)
---

<Layout>
  {featured.map { |post| <Card post={post} /> }}
</Layout>
```

**Example Astro component with Ruby client script:**

```astro
---
const title = "My Page";
---

<h1>{title}</h1>

<script lang="ruby">
def handle_click(event)
  console.log("clicked", event.target)
end

document.querySelector("button")&.addEventListener("click", handle_click)
</script>
```

---

## Summary: Plugin Simplicity

The entire Vite integration is thin because complexity lives elsewhere:

| Layer | Responsibility | Complexity |
|-------|----------------|------------|
| `ruby2js` package | Transpile Ruby → JS | High (but already exists) |
| Framework plugins | Compile Vue/Svelte/Astro | High (but maintained by framework teams) |
| **vite-plugin-ruby2js** | **Wire them together** | **Low** |

**Core plugin:** ~30 lines — detect `.rb` files, call `Ruby2JS.convert()`

**Each preset:** ~40 lines — detect `lang="ruby"`, transform, pass to framework plugin

---

## HMR Runtime

Injected into the browser for Stimulus/Rails apps:

```typescript
// src/hmr-runtime.ts
if (import.meta.hot) {
  import.meta.hot.on('ruby2js:stimulus-update', async (data) => {
    // Re-register the updated controller
    const module = await import(data.file + '?t=' + Date.now());
    const controllerName = data.file
      .replace(/.*\//, '')
      .replace('_controller.rb', '')
      .replace(/_/g, '-');

    if (window.Stimulus) {
      // Stimulus handles controller replacement
      window.Stimulus.register(controllerName, module.default);
    }
  });
}
```

---

## Source Maps

All transformations generate source maps back to original Ruby:

```typescript
// src/sourcemap.ts
export function generateSourceMap(
  result: TransformResult,
  originalSource: string,
  filePath: string
) {
  const map = result.sourcemap;
  if (map) {
    map.sources = [filePath];
    map.sourcesContent = [originalSource];
  }
  return map;
}
```

Browser DevTools show Ruby source, breakpoints work on Ruby lines.

---

## Why This Matters

### For Rails Developers
- HMR with state preservation (no full page refresh)
- Modern build tooling (tree shaking, code splitting)
- Path to adding React/Vue interactivity without leaving Ruby

### For Frontend Developers
- Ruby's expressiveness in their framework of choice
- Gradual adoption (one component at a time)
- Same tooling they already know (Vite)

### For Everyone
- One language across the stack
- Portable components (Phlex works everywhere)
- No context switching between Ruby and JavaScript

---

## Developer Experience

| Feature | Without Vite | With Vite |
|---------|--------------|-----------|
| Hot reload | Full page refresh | HMR — state preserved |
| Rebuild speed | Full project | Module-level |
| Error display | Console only | Rich browser overlay |
| Debugging | Generated JS | Source maps to Ruby |
| Production | Manual optimization | Tree shaking, splitting |

---

## Success Criteria

### Phase 1 (Ship What's Ready)
1. `npm create vite` + plugin → Ruby files transform
2. Rails preset works with Stimulus controllers
3. HMR updates controllers without page refresh
4. Source maps show Ruby in DevTools
5. Production builds are optimized

### Phase 3 (React)
6. React components can be authored in Ruby
7. RBX files (Ruby + JSX) work seamlessly

### Phase 5 (Phlex)
8. Phlex components work as ES modules
9. Same Phlex source targets multiple frameworks

### Phase 7 (Frameworks)
10. Vue SFC `<script>` blocks accept Ruby
11. Astro frontmatter accepts Ruby

---

## Decisions Made

### Ruby Fallback (Open Question #1 — Resolved)

**Decision: No Ruby fallback. Selfhost-only.**

Rationale:
- Adding Ruby dependency defeats the purpose (pure JS toolchain)
- Forces prioritization of selfhost investment
- Cleaner user experience (no "works in dev, breaks in CI")
- Selfhost gaps are the critical path—address them directly

If a filter isn't ready in selfhost, it's not available in the Vite plugin until it is.

### Language Detection (Open Question #4 — Resolved)

**Decision: Use native detection mechanisms for each context.**

See [Ruby Detection Strategy](#ruby-detection-strategy) for full details.

| Context | Detection | Example |
|---------|-----------|---------|
| Standalone | File extension | `.rb`, `.rbx`, `.phlex.rb` |
| Vue/Svelte/Astro scripts | `lang` attribute | `<script lang="ruby">` |
| Astro frontmatter | Shebang | `#!ruby` |

This enables mixed-language projects: JavaScript, TypeScript, and Ruby components coexist in the same codebase. No new file extensions needed—`.vue` files can contain Ruby via `lang="ruby"`, following the same pattern as TypeScript.

---

## Open Questions

1. **Caching**: Disk cache for faster cold starts? Vite has built-in caching; may be sufficient.

2. **IDE support**: Syntax highlighting for Ruby in Vue/Svelte SFCs? Possible via VS Code language injection.

3. **Monorepo**: Multiple apps with shared Ruby components? Standard Vite monorepo patterns should work.

4. **Svelte filter**: Not yet implemented. Needs `reactive {}` DSL for `$:` declarations. Lower priority than React/Phlex.

---

## References

### Vite
- [Vite Plugin API](https://vitejs.dev/guide/api-plugin.html)
- [Vite HMR API](https://vitejs.dev/guide/api-hmr.html)

### Existing Packages
- [ruby2js package](https://www.ruby2js.com/releases/ruby2js-beta.tgz) — Selfhost transpiler + filters
- [ruby2js-rails package](https://www.ruby2js.com/releases/ruby2js-rails-beta.tgz) — Rails runtime adapters
- [NPM_SELFHOST_MIGRATION.md](./NPM_SELFHOST_MIGRATION.md) — Package structure documentation

### Related Plans
- [UNIFIED_VIEWS.md](./UNIFIED_VIEWS.md) — Multi-framework view targeting
- [HOTWIRE_TURBO.md](./HOTWIRE_TURBO.md) — Stimulus/Turbo integration (Post 2)

### Source
- [Selfhost source](../demo/selfhost/) — Transpiler built from here
- [Selfhost spec manifest](../demo/selfhost/spec_manifest.json) — Filter readiness tracking
- [ruby2js-rails source](../packages/ruby2js-rails/) — Rails runtime package
