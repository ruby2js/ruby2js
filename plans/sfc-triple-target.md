# Plan: SFC Triple-Target

## Goal

Extend Juntos to output framework-specific components (React, Astro, Vue, Svelte) from Rails ERB templates, proving the mechanical transformation principle from VISION.md: **MVC ≅ SFC**.

---

## Current State (January 2026)

### Infrastructure Complete

The Vite-native refactoring is complete. All transformation happens on-the-fly:

| Component | Status | Notes |
|-----------|--------|-------|
| `juntos-ruby` plugin | ✅ | Transforms `.rb` files on-the-fly |
| `juntos-erb` plugin | ✅ | Transforms `.erb` files to async string functions |
| Virtual modules | ✅ | `juntos:rails`, `juntos:models`, `juntos:migrations`, `juntos:views/*` |
| Dual-bundle (SSR + hydration) | ✅ | `createDualBundlePlugin` for Node targets |
| JavaScript CLI | ✅ | `npx juntos` with extensible options |
| WebContainers support | ✅ | Virtual browser entry, SPA fallback |

### Stage 0 Astro Blog Complete

`test/astro-blog-v3/` demonstrates the worker-in-browser pattern:
- Browser-only Astro SSR (no Cloudflare dependency)
- Ruby models transpiled at build time
- Dexie adapter for IndexedDB
- Full CRUD verified
- Integration test passing

### Two ERB Transformation Modes

Ruby2JS has two ERB transformers:

1. **Async string functions** (current default):
   ```javascript
   async function render(article) {
     return `<div>${article.title}</div>`;
   }
   ```
   - Works for any ERB (even malformed HTML)
   - Runtime calls function, awaits, inserts as innerHTML

2. **True React components** (available but not default):
   ```javascript
   function Article({ article }) {
     return <div>{article.title}</div>;
   }
   ```
   - Only works for well-formed XML
   - Compatible with react-refresh HMR
   - Preserves React state across updates

---

## Implementation Phases

### Phase 1: Framework Option Infrastructure

Add `framework` option to the Vite plugin:

```javascript
// vite.config.js
export default defineConfig({
  plugins: juntos({
    database: 'dexie',
    framework: 'react'  // NEW: 'rails' (default), 'react', 'astro', 'vue', 'svelte'
  })
});
```

**Tasks:**
- [ ] Add `framework` option to `juntos()` in `vite.mjs`
- [ ] Pass framework to ERB transformer
- [ ] Add `--framework` / `-f` flag to CLI

**Files to modify:**
- `packages/ruby2js-rails/vite.mjs`
- `packages/ruby2js-rails/cli.mjs`

---

### Phase 2: React Framework Target

Implement `--framework react` as a stepping stone:

1. Try to parse ERB as well-formed XML
2. If successful → output true React component (enables react-refresh HMR)
3. If not → fall back to async string function (current behavior)
4. Tag output with `renderStrategy` property

**Why React first:**
- Smallest delta from current behavior
- Proves the "try component, fallback to string" pattern
- Enables HMR for well-formed templates without breaking malformed ones
- Same runtime, just different view output

**Output format:**
```javascript
// Well-formed ERB → React component
function ArticleCard({ article }) {
  return <div className="article">
    <h1>{article.title}</h1>
    <p>{article.body}</p>
  </div>;
}
ArticleCard.renderStrategy = 'react';

// Malformed ERB → string function (fallback)
async function render(article) {
  return `<div class="article">...`;
}
render.renderStrategy = 'string';
```

**Tasks:**
- [ ] Add well-formed XML detection to ERB transformer
- [ ] Add React component output generator
- [ ] Add `renderStrategy` tagging
- [ ] Verify react-refresh HMR works for React components
- [ ] Verify string fallback still works

**Files to modify:**
- `packages/ruby2js-rails/vite.mjs` (ERB transform logic)
- `lib/ruby2js/filter/erb.rb` (if Ruby-side changes needed)

---

### Phase 3: Astro Framework Target

Implement `--framework astro` to produce Astro components:

**ERB → Astro template mapping:**
| ERB | Astro |
|-----|-------|
| `<%= @var %>` | `{var}` |
| `<% if cond %>...<% end %>` | `{cond && (...)}` |
| `<% @items.each do \|i\| %>` | `{items.map(i => ...)}` |
| `<%= link_to text, path %>` | `<a href={path}>{text}</a>` |
| `<%= render partial %>` | `<Component />` |

**Output structure:**
```
src/
├── layouts/
│   └── Layout.astro
├── pages/
│   └── articles/
│       ├── index.astro
│       ├── new.astro
│       ├── [id].astro
│       └── [id]/edit.astro
├── components/
│   ├── ArticleCard.astro
│   └── CommentForm.astro
└── models/
    ├── article.rb          # Copied as-is, transpiled at build
    └── comment.rb
```

**Tasks:**
- [ ] Add Astro template output generator
- [ ] Map Rails routes → file-based routing structure
- [ ] Convert controllers → page frontmatter (data fetching)
- [ ] Handle partials → components
- [ ] Test against Stage 0 Astro blog as reference

**Validation:** Output should match hand-crafted `test/astro-blog-v3/`

---

### Phase 4: Vue Framework Target

Implement `--framework vue`:

**ERB → Vue template mapping:**
| ERB | Vue |
|-----|-----|
| `<%= @var %>` | `{{ var }}` |
| `<% if cond %>...<% end %>` | `<div v-if="cond">` |
| `<% @items.each do \|i\| %>` | `v-for="i in items"` |
| `<%= link_to text, path %>` | `<router-link :to="path">` |

**Tasks:**
- [ ] Add Vue SFC output generator
- [ ] Create Stage 0 Vue blog for reference
- [ ] Map routes → Vue Router config
- [ ] Test CRUD workflow

---

### Phase 5: Svelte Framework Target

Implement `--framework svelte`:

**ERB → Svelte template mapping:**
| ERB | Svelte |
|-----|--------|
| `<%= @var %>` | `{var}` |
| `<% if cond %>...<% end %>` | `{#if cond}...{/if}` |
| `<% @items.each do \|i\| %>` | `{#each items as i}` |
| `<%= link_to text, path %>` | `<a href={path}>{text}</a>` |

**Tasks:**
- [ ] Add Svelte SFC output generator
- [ ] Create Stage 0 Svelte blog for reference
- [ ] Map routes → SvelteKit file structure
- [ ] Test CRUD workflow

---

## Key Architectural Insights

### Worker-in-Browser Pattern

Edge functions (Cloudflare Workers) use standard Web APIs (`Request` → `Response`) - the same APIs available in browsers. This means:

```
┌─────────────────────────────────────────────────────────────┐
│  Turbo intercepts navigation/forms                          │
│                         │                                   │
│           ┌─────────────┴─────────────┐                    │
│           ▼                           ▼                    │
│   ┌───────────────┐           ┌───────────────┐           │
│   │ Edge Runtime  │           │ Browser       │           │
│   │ (Cloudflare)  │           │ (Worker-in-   │           │
│   │ worker.fetch()│           │  browser)     │           │
│   └───────────────┘           └───────────────┘           │
│           │                           │                    │
│           ▼                           ▼                    │
│   ┌───────────────┐           ┌───────────────┐           │
│   │ D1 Database   │           │ IndexedDB     │           │
│   └───────────────┘           └───────────────┘           │
└─────────────────────────────────────────────────────────────┘

Same SSR code, same HTML output, same Turbo integration.
Only the database adapter changes.
```

### Pluggable View Rendering

Views declare their rendering strategy:

```javascript
const strategies = {
  string: (View, props) => View(props),           // ERB async functions
  react: (View, props) => React.createElement(View, props),
  astro: (View, props) => renderAstroComponent(View, props),
  vue: (View, props) => renderVueComponent(View, props),
  svelte: (View, props) => renderSvelteComponent(View, props),
};

function renderView(View, props) {
  const strategy = View.renderStrategy || detectStrategy(View);
  return strategies[strategy](View, props);
}
```

This enables:
- Mixed views in same app (ERB partials + React islands)
- New frameworks added without modifying core
- Runtime detection as fallback

### Models Stay as Ruby

Across all framework targets:
- **Models**: Copy as-is (`app/models/*.rb` → `src/models/*.rb`)
- **Adapters**: Reuse from `ruby2js-rails/adapters/`
- **Turbo integration**: Same pattern everywhere

The transpiler only converts **views** and **controllers**. Models are framework-agnostic.

---

## Bundle Architecture Question

Two approaches exist:

| Approach | Description | Example |
|----------|-------------|---------|
| Heavy server, light client | Same code runs everywhere, adapters swap | Remix, current Juntos |
| Separate client/server bundles | Clear boundary, code duplication | Next.js |

**Current state:** Juntos uses "heavy server, light client" - the dual-bundle plugin generates client.js only when RPC/hydration is needed.

**Future option:** `--bundle-strategy` flag could let users choose. This is orthogonal to `--framework` and can be addressed later.

---

## Success Criteria

### Phase 1 (Infrastructure)
- [ ] `--framework` option accepted by CLI and Vite plugin
- [ ] Option flows through to ERB transformer

### Phase 2 (React)
- [ ] Well-formed ERB → React component with HMR
- [ ] Malformed ERB → string function fallback
- [ ] No breaking changes to existing apps
- [ ] `renderStrategy` tagging works

### Phase 3 (Astro)
- [ ] `juntos build -f astro` produces working Astro app
- [ ] Output matches Stage 0 reference (`test/astro-blog-v3/`)
- [ ] CRUD works, data persists

### Phase 4-5 (Vue/Svelte)
- [ ] Each framework target produces working app
- [ ] Same features as Astro target

---

## Files Reference

| File | Purpose |
|------|---------|
| `packages/ruby2js-rails/vite.mjs` | Main Vite plugin, ERB transformation |
| `packages/ruby2js-rails/cli.mjs` | JavaScript CLI |
| `packages/ruby2js-rails/rails_base.js` | Runtime with `renderView` |
| `lib/ruby2js/filter/erb.rb` | Ruby ERB filter (reference) |
| `test/astro-blog-v3/` | Stage 0 Astro reference |

---

## Open Questions

1. **Partial handling**: Should partials always stay as string functions (universal), or convert to framework components?

2. **Layout strategy**: Rails layouts use `yield`. Astro/Vue/Svelte use slots. Mapping is straightforward but needs verification.

3. **Form helpers**: `form_with`, `button_to` etc. - convert to framework idioms or keep as HTML with Turbo?

4. **HMR scope**: With `--framework react`, only React component views get true HMR. Is this clear enough to users?
