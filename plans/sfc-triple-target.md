# Plan: SFC Triple-Target Demo

## Goal

Take the existing Rails blog demo and transpile it to three SFC syntaxes (Astro, Vue, Svelte), proving the mechanical transformation principle from VISION.md.

## Input

The existing blog demo (generated via `test/blog/create-blog`):
- Models: `article.rb`, `comment.rb` → already transpile to JS
- Controllers: `articles_controller.rb`, `comments_controller.rb` → already transpile to JS
- Views: ERB templates → verified JSX-compatible (well-formed)
- Adapters: sqlite3, dexie, d1 → already work

## Output

Three parallel builds, each producing a working blog:

```
bin/juntos build -d dexie -f astro    → Astro components
bin/juntos build -d dexie -f vue      → Vue SFCs
bin/juntos build -d dexie -f svelte   → Svelte components
```

All three:
- Use the same transpiled models
- Use the same database adapter
- Render the same blog UI
- Run via Vite

---

## Current State Analysis

### What Exists

| Component | Location | Status |
|-----------|----------|--------|
| `AstroComponentTransformer` | `packages/ruby2js-rails/dist/astro_component_transformer.mjs` | Defined, not wired |
| `AstroTemplateCompiler` | `packages/ruby2js-rails/dist/astro_template_compiler.mjs` | Defined, not wired |
| `VueComponentTransformer` | `packages/ruby2js-rails/dist/vue_component_transformer.mjs` | Defined, not wired |
| `VueTemplateCompiler` | `packages/ruby2js-rails/dist/vue_template_compiler.mjs` | Defined, not wired |
| `SvelteComponentTransformer` | `packages/ruby2js-rails/dist/svelte_component_transformer.mjs` | Defined, not wired |
| `SvelteTemplateCompiler` | `packages/ruby2js-rails/dist/svelte_template_compiler.mjs` | Defined, not wired |
| `ErbCompiler` | `packages/ruby2js-rails/lib/erb_compiler.js` | Active - produces string templates |
| juntos CLI | `lib/ruby2js/cli/juntos.rb` | Has `-d` and `-t`, no `-f` |

### What's Missing

1. **CLI flag**: `-f` / `--framework` option to select output format
2. **Build wiring**: Connect framework transformers to `SelfhostBuilder` and Vite plugin
3. **Framework routing**: Logic to select transformer based on `-f` flag
4. **Vite configs**: Framework-specific Vite configurations (plugins, etc.)

### Current Build Flow

```
ERB template
    ↓
ErbCompiler (erb_compiler.js)
    ↓
Ruby code (_buf << "..." pattern)
    ↓
Ruby2JS transpiler
    ↓
JavaScript (string concatenation)
```

### Target Build Flow

```
ERB template
    ↓
[Framework]TemplateCompiler
    ↓
[Framework]-specific syntax
    ↓
Ruby2JS transpiler (for script section)
    ↓
Complete SFC (.astro / .vue / .svelte)
```

---

## Implementation Steps

### Phase 1: CLI and Configuration

**1.1 Add `-f` / `--framework` flag to juntos CLI**

File: `lib/ruby2js/cli/juntos.rb`

```ruby
# In parse_common_options:
when '-f', '--framework'
  options[:framework] = args[i + 1]
  i += 2

# In apply_common_options:
ENV['JUNTOS_FRAMEWORK'] = options[:framework] if options[:framework]
```

Valid values: `rails` (default, current behavior), `astro`, `vue`, `svelte`

**1.2 Update build options**

Files: `lib/ruby2js/cli/build.rb`, `lib/ruby2js/cli/build_helper.rb`

Pass `framework` option through to builder.

### Phase 2: Build System Wiring

**2.1 Create framework selector**

File: `packages/ruby2js-rails/lib/framework_selector.mjs` (new)

```javascript
import { AstroComponentTransformer } from '../dist/astro_component_transformer.mjs';
import { VueComponentTransformer } from '../dist/vue_component_transformer.mjs';
import { SvelteComponentTransformer } from '../dist/svelte_component_transformer.mjs';
import { ErbCompiler } from './erb_compiler.js';

export function getTransformer(framework) {
  switch (framework) {
    case 'astro': return AstroComponentTransformer;
    case 'vue': return VueComponentTransformer;
    case 'svelte': return SvelteComponentTransformer;
    case 'rails':
    default: return ErbCompiler;
  }
}
```

**2.2 Update SelfhostBuilder**

File: `packages/ruby2js-rails/build.mjs`

- Read `JUNTOS_FRAMEWORK` environment variable
- Use `getTransformer()` to select appropriate compiler
- Adjust output paths based on framework (`.astro`, `.vue`, `.svelte`)

**2.3 Update Vite plugin**

File: `packages/ruby2js-rails/vite.mjs`

- Pass framework option through configuration
- Select appropriate file extensions for watch/transform
- May need framework-specific Vite plugins:
  - Astro: `@astrojs/vite-plugin-astro` (or none if static)
  - Vue: `@vitejs/plugin-vue`
  - Svelte: `@sveltejs/vite-plugin-svelte`

### Phase 3: Validate Existing Transformers

**3.1 Test AstroComponentTransformer**

- Does it handle the blog's ERB patterns?
- Does output compile with Astro?
- Fix any gaps

**3.2 Test VueComponentTransformer**

- Does it handle the blog's ERB patterns?
- Does output compile with Vue?
- Fix any gaps

**3.3 Test SvelteComponentTransformer**

- Does it handle the blog's ERB patterns?
- Does output compile with Svelte?
- Fix any gaps

### Phase 4: Framework-Specific Vite Configs

**4.1 Astro configuration**

May need minimal config since Astro has its own build, or may work as static components.

**4.2 Vue configuration**

```javascript
import vue from '@vitejs/plugin-vue';

export default {
  plugins: [vue(), /* ruby2js plugin */]
}
```

**4.3 Svelte configuration**

```javascript
import { svelte } from '@sveltejs/vite-plugin-svelte';

export default {
  plugins: [svelte(), /* ruby2js plugin */]
}
```

### Phase 5: Integration Testing

**5.1 Create test script**

```bash
#!/bin/bash
# test/integration/sfc_triple_target.sh

# Generate blog
cd /tmp && rm -rf blog
curl -sL .../create-blog | bash -s blog
cd blog

# Test each framework
for framework in astro vue svelte; do
  echo "Testing $framework..."
  bin/juntos build -d dexie -f $framework
  # Verify output exists and is valid
done
```

**5.2 Add to CI**

Extend existing integration tests to cover framework outputs.

---

## Potential Adjustments

### Things That May Need Changing

1. **Existing transformers** - May have bugs or missing patterns when tested against real ERB
2. **Test expectations** - If transformer output format changes, update expected results
3. **Demo structure** - May need adjustment to work with multiple frameworks
4. **Unused code** - If transformers have dead code paths, remove them

### Things That Must Keep Working

1. **CI must pass** - All existing tests continue to work
2. **Existing demos** - Blog demo with `-f rails` (default) works as before
3. **Database adapters** - All adapters work with all frameworks

### Acceptable Changes

- Revising expected test output if the new output is correct
- Modifying demos to demonstrate framework flexibility
- Removing code that was speculative but doesn't fit the architecture
- Simplifying transformers if they're over-engineered

---

## ERB → SFC Transformation Examples

### Input (ERB)

```erb
<% if notice.present? %>
  <p class="notice"><%= notice %></p>
<% end %>

<% @articles.each do |article| %>
  <div class="article">
    <h2><%= link_to article.title, article %></h2>
  </div>
<% end %>
```

### Output: Astro

```astro
---
import { Article } from '../models/article.js';
const articles = await Article.all();
const notice = Astro.props.notice;
---

{notice && (
  <p class="notice">{notice}</p>
)}

{articles.map(article => (
  <div class="article">
    <h2><a href={`/articles/${article.id}`}>{article.title}</a></h2>
  </div>
))}
```

### Output: Vue

```vue
<script setup>
import { ref, onMounted } from 'vue';
import { Article } from '../models/article.js';

const articles = ref([]);
const props = defineProps(['notice']);

onMounted(async () => {
  articles.value = await Article.all();
});
</script>

<template>
  <p v-if="props.notice" class="notice">{{ props.notice }}</p>

  <div v-for="article in articles" :key="article.id" class="article">
    <h2><router-link :to="`/articles/${article.id}`">{{ article.title }}</router-link></h2>
  </div>
</template>
```

### Output: Svelte

```svelte
<script>
import { onMount } from 'svelte';
import { Article } from '../models/article.js';

export let notice;
let articles = [];

onMount(async () => {
  articles = await Article.all();
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

---

## Success Criteria

### Phase 1-2 (CLI and Wiring)
- [ ] `-f astro|vue|svelte|rails` flag works
- [ ] `JUNTOS_FRAMEWORK` env var propagates through build
- [ ] Framework selector returns correct transformer

### Phase 3-4 (Transformers and Vite)
- [ ] Astro transformer produces valid `.astro` files
- [ ] Vue transformer produces valid `.vue` files
- [ ] Svelte transformer produces valid `.svelte` files
- [ ] Each integrates with framework's Vite plugin

### Phase 5 (Integration)
- [ ] `bin/juntos build -d dexie -f astro` produces working blog
- [ ] `bin/juntos build -d dexie -f vue` produces working blog
- [ ] `bin/juntos build -d dexie -f svelte` produces working blog
- [ ] CI passes
- [ ] Existing demos unchanged (default behavior preserved)

---

## Follow-on: Turbo Streams / Real-time Updates

Deferred to separate iteration. Feasibility assessment:

| Framework | Approach | Feasibility |
|-----------|----------|-------------|
| Astro | Islands + WebSocket DOM updates | Medium |
| Vue | Native reactivity + WebSocket | High |
| Svelte | Stores + WebSocket | High |

Will assess after Phase 5 completes successfully.

---

## Notes

- This plan aligns with VISION.md: use existing infrastructure, don't hard-code
- The transformers exist - the work is wiring, not creation
- If transformers have bugs, fix them rather than working around
- Preserve optionality: same source → multiple outputs
