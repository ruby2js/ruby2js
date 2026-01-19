# Ruby2JS Vision: First Principles

This document captures the foundational principles that guide implementation choices. When hitting obstacles, refer back to these principles before changing direction.

## The Three Transpilation Truths

### 1. Ruby → JavaScript (Clean Subset)

A useful subset of Ruby transpiles cleanly to JavaScript. This subset excludes `method_missing` and exotic metaprogramming, but includes everything needed for typical Rails applications: models, controllers, validations, associations, callbacks.

**Implication:** Any Ruby pattern in this subset can run anywhere JavaScript runs.

### 2. ERB → JSX (Well-Formed Subset)

A useful subset of ERB transpiles cleanly to JSX. This subset requires well-formed templates where conditionals and loops wrap complete elements, not partial tags.

**Valid (JSX-compatible):**
```erb
<% if expanded %>
  <div class="expanded"><%= content %></div>
<% else %>
  <div><%= content %></div>
<% end %>
```

**Invalid (not JSX-compatible):**
```erb
<div>
<% if expanded %>
  </div><div class="expanded">
<% end %>
```

**Implication:** Most real-world ERB templates are already well-formed. The constraint is a discipline, not a capability loss.

### 3. MVC ≅ SFC (Isomorphic Patterns)

Rails MVC and Single File Components are the same concepts with different packaging:

| Rails MVC | SFC |
|-----------|-----|
| Controller action | Frontmatter |
| View template | Template section |
| `routes.rb` entry | File path |
| `@instance_variables` | `@instance_variables` |

**Implication:** A transpiler can accept either convention and produce equivalent output. Templates can be identical between controllers and SFC pages.

---

## The Core Insight

**Everything reduces to mechanical transformation.**

Once you accept the three truths above, "impossible" results become mundane:

| "Impossible" | Reality |
|--------------|---------|
| Full-stack Rails on a phone | Target Dexie adapter |
| Full-stack Rails on v8 isolate | Target D1 adapter |
| ISR anywhere | Adapter pattern, same API |
| Vue/Svelte/Astro output | Different template syntax, same logic |

The transpiler is a **universal adapter** between conventions, not a one-way compilation step.

---

## The Flexibility Matrix

### Input Conventions (accept any)
- Rails MVC (`app/controllers/`, `app/views/`)
- Astro SFC (`src/pages/*.astro.rb`)
- Vue SFC (`.vue.rb`)
- Hybrid (both in same project)

### Output Targets (produce any)
- Browser (Dexie/IndexedDB)
- Node.js (SQLite, PostgreSQL)
- Cloudflare Workers (D1)
- Vercel Edge (Neon, Turso)

### Framework Bindings (any JavaScript framework)
- Vanilla (string templates)
- React/Preact (JSX)
- Vue (Vue SFC)
- Svelte (Svelte components)
- Astro (Astro components)

**The constraint is only mechanical compatibility**, not conceptual limitation.

---

## Implementation Guidance

### Use Existing Infrastructure

Before building something new, check if the infrastructure already exists:

- **Database adapters** exist in `packages/ruby2js-rails/adapters/`
- **ISR adapters** exist in `packages/ruby2js-rails/targets/*/isr.mjs`
- **Target configurations** exist in `packages/ruby2js-rails/targets/`

If an adapter or pattern exists, **use it**. Don't hard-code what should be pluggable.

### Fix Bugs, Don't Pivot

When hitting an obstacle:

1. **First**: Is this a bug in the existing approach? Fix it.
2. **Second**: Is this a missing piece in existing infrastructure? Add it.
3. **Last resort**: Is the approach fundamentally wrong? Only then pivot.

**Anti-pattern:** Hitting a minor bug and building a "simpler" solution that abandons the architecture.

**Example:** The Astro blog demo hard-coded Dexie, ran only in browser, and used a custom ISR solution - when pluggable adapters for all three already existed. The right fix was to wire up the existing infrastructure, not bypass it.

### Preserve Optionality

Every implementation choice should preserve the flexibility matrix:

- Don't hard-code a database when adapters exist
- Don't hard-code a target when the build can be parameterized
- Don't hard-code a framework when the template transformation is mechanical

**Test:** Can the same source build for browser, Node, and edge? If not, something was hard-coded that shouldn't be.

### Constraints Are Mechanical

When a combination doesn't work, the reason should be mechanical:

- Non-well-formed ERB can't become JSX (tree structure required)
- `method_missing` can't transpile (no JS equivalent)
- Some Ruby pattern has no clean JS mapping

If the limitation isn't mechanical, it's probably an implementation gap, not a fundamental constraint.

---

## The Eject Test

The transpiled output should be:

1. **Readable** - A JavaScript developer can understand it
2. **Maintainable** - It can be modified without the transpiler
3. **Complete** - No Ruby dependencies at runtime

A developer can "eject" by taking the `dist/` directory and continuing in pure JavaScript. But they lose deployment optionality - the same source can no longer target different runtimes.

**Keeping the source = keeping optionality.**

---

## Summary

The vision is not "Ruby syntax for JavaScript developers."

The vision is **deployment optionality through mechanical transformation**:

- Same models work with any database adapter
- Same templates work with any framework binding
- Same code deploys to any JavaScript runtime
- Convention translation is mechanical, not magical

When implementation choices align with these principles, previously impossible results become mundane. When they don't, we end up rebuilding infrastructure that already exists.
