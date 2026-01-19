# Plan: SFC Triple-Target Demo

## Goal

Take the existing Rails blog demo and transpile it to three SFC syntaxes (Astro, Vue, Svelte), proving the mechanical transformation principle from VISION.md.

## Input

The existing blog demo at `/tmp/blog` (or generated via `test/blog/create-blog`):
- Models: `article.rb`, `comment.rb` → already transpile to JS
- Controllers: `articles_controller.rb`, `comments_controller.rb` → already transpile to JS
- Views: ERB templates → verified JSX-compatible (well-formed)
- Adapters: sqlite3, dexie, d1 → already work

## Output

Three parallel builds, each producing a working blog:

```
bin/juntos build -d dexie -f astro    → dist-astro/
bin/juntos build -d dexie -f vue      → dist-vue/
bin/juntos build -d dexie -f svelte   → dist-svelte/
```

All three:
- Use the same transpiled models
- Use the same database adapter
- Render the same blog UI
- Run via Vite

## Phase 1: ERB → SFC Template Transformation

### Astro Output

```astro
---
// frontmatter: transpiled controller action
import { Article } from '../models/article.js';
const articles = await Article.includes("comments").all();
---

{flash.notice && (
  <p class="notice">{flash.notice}</p>
)}

{articles.map(article => (
  <div class="article">
    <h2><a href={`/articles/${article.id}`}>{article.title}</a></h2>
  </div>
))}
```

### Vue Output

```vue
<script setup>
import { ref, onMounted } from 'vue';
import { Article } from '../models/article.js';

const articles = ref([]);
const notice = ref(null);

onMounted(async () => {
  articles.value = await Article.includes("comments").all();
});
</script>

<template>
  <p v-if="notice" class="notice">{{ notice }}</p>

  <div v-for="article in articles" :key="article.id" class="article">
    <h2><router-link :to="`/articles/${article.id}`">{{ article.title }}</router-link></h2>
  </div>
</template>
```

### Svelte Output

```svelte
<script>
import { onMount } from 'svelte';
import { Article } from '../models/article.js';

let articles = [];
let notice = null;

onMount(async () => {
  articles = await Article.includes("comments").all();
});
</script>

{#if notice}
  <p class="notice">{notice}</p>
{/if}

{#each articles as article (article.id)}
  <div class="article">
    <h2><a href={`/articles/${article.id}`}>{article.title}</a></h2>
  </div>
{/each}
```

## Transformation Mapping

| ERB | Astro | Vue | Svelte |
|-----|-------|-----|--------|
| `<% if cond %>` | `{cond && (...)}` | `v-if="cond"` | `{#if cond}` |
| `<% else %>` | ternary | `v-else` | `{:else}` |
| `<% end %>` | `}` | (implicit) | `{/if}` |
| `<% items.each do \|i\| %>` | `{items.map(i => ...)}` | `v-for="i in items"` | `{#each items as i}` |
| `<%= expr %>` | `{expr}` | `{{ expr }}` | `{expr}` |
| `<%= link_to ... %>` | `<a href={...}>` | `<router-link>` | `<a href={...}>` |
| `<%= form_with ... %>` | `<form>` | `<form>` | `<form>` |

## Phase 2: Vite Integration

Each framework has its own Vite plugin:

```javascript
// vite.config.js for Astro
import { defineConfig } from 'vite';
import astro from '@astrojs/vite-plugin-astro';

// vite.config.js for Vue
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

// vite.config.js for Svelte
import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
```

The `bin/juntos build -f <framework>` command:
1. Transpiles Ruby models/controllers (same for all)
2. Transforms ERB → framework-specific templates
3. Generates appropriate vite.config.js
4. Runs Vite build

## Phase 3 (Follow-on): Turbo Streams / Real-time Updates

### Feasibility Assessment

| Framework | Approach | Feasibility |
|-----------|----------|-------------|
| Astro | Islands with WebSocket, Turbo-style DOM updates | Medium - requires island boundaries |
| Vue | Native reactivity, WebSocket → reactive state | High - natural fit |
| Svelte | Native reactivity, WebSocket → stores | High - natural fit |

### Adaptation Strategy

**Option A: Preserve Turbo Streams protocol**
- WebSocket receives HTML fragments
- DOM manipulation (insert, replace, remove)
- Works identically across frameworks
- Astro: works out of the box
- Vue/Svelte: works but doesn't leverage reactivity

**Option B: Adapt to framework idioms**
- WebSocket receives JSON data
- Each framework handles updates natively
- Astro: island re-render
- Vue: reactive state update
- Svelte: store update

Recommendation: Start with Option A (simpler, proves concept), Option B as enhancement.

## File Structure

```
packages/ruby2js-rails/
├── lib/
│   └── erb_to_sfc/
│       ├── astro.rb      # ERB → Astro transformation
│       ├── vue.rb        # ERB → Vue transformation
│       └── svelte.rb     # ERB → Svelte transformation
├── targets/
│   ├── astro/
│   │   └── vite.config.js
│   ├── vue/
│   │   └── vite.config.js
│   └── svelte/
│       └── vite.config.js
```

## Implementation Steps

1. **Create ERB → Astro transformer**
   - Parse ERB (already done in erb2jsx)
   - Output Astro syntax
   - Test with blog views

2. **Create ERB → Vue transformer**
   - Same parse step
   - Output Vue SFC syntax
   - Test with blog views

3. **Create ERB → Svelte transformer**
   - Same parse step
   - Output Svelte syntax
   - Test with blog views

4. **Add `-f` flag to juntos CLI**
   - `-f astro` (default, current behavior)
   - `-f vue`
   - `-f svelte`

5. **Vite configs for each framework**
   - Use existing Vite infrastructure
   - Swap plugin based on framework

6. **Integration test**
   - Build blog with each framework
   - Verify all work with dexie adapter
   - Verify CRUD operations

## Success Criteria

- [ ] `bin/juntos build -d dexie -f astro` produces working blog
- [ ] `bin/juntos build -d dexie -f vue` produces working blog
- [ ] `bin/juntos build -d dexie -f svelte` produces working blog
- [ ] Same models/controllers used by all three
- [ ] All views render correctly (index, show, new, edit for articles and comments)

## Follow-on Success Criteria (Phase 3)

- [ ] Real-time updates work in at least one framework
- [ ] If feasible, real-time updates work in all three
- [ ] If not feasible for some, clear mechanical reason documented

## Notes

- This is a stepping stone to the store demo
- Proves VISION.md principle: one input → multiple outputs
- Some combinations may not work - document why if so
- Don't commit broken states; revert if Phase 3 doesn't pan out
