# Plan: juntos eject --framework

## Summary

Extend the existing `npx juntos eject` command with a `--framework` option that outputs idiomatic framework code instead of "Rails patterns in JavaScript."

This plan coordinates two existing plans:
- `sfc-triple-target.md` - Views and controllers → framework components
- `drizzle-transpilation.md` - Models → framework stores + Drizzle persistence

## Current State

Three commands serve different purposes:

| Command | Purpose | Output |
|---------|---------|--------|
| `juntos build -t X` | Production deployment | Bundled, minified, platform-specific |
| `juntos eject` | Debugging, inspection | Unbundled JS mirroring source structure |
| `juntos eject --framework X` | **New** - idiomatic framework code | Framework-native patterns |

**`juntos deploy`** (build + deploy) continues unchanged. ISR, edge functions, platform configs all work.

**`juntos eject`** (current) outputs unbundled "Rails-in-JS":
- Models as JS classes extending `ApplicationRecord`
- Controllers as JS classes with Rails-like methods
- Views as JS render functions (ERB-style)
- Runtime adapters for database access

This is valuable for debugging - when bundled output behaves unexpectedly, inspect the intermediate JS. It also enables migration if you want to continue development in JavaScript.

**`juntos eject --framework`** (this plan) adds a new option that outputs idiomatic framework code - not "Rails patterns in JS" but code a framework developer would recognize and maintain.

## Goal

Add `--framework <target>` option that outputs native framework code:

```bash
npx juntos eject --framework react
```

| Current Output (RBX) | `--framework react` Output |
|----------------------|---------------------------|
| `def Index()` | `function Index()` |
| `x, setX = useState([])` | `const [x, setX] = useState([])` |
| `%x{ <div>...</div> }` | `return (<div>...</div>)` |
| `notes_path.get()` | `notesPath.get()` (or React Query) |
| ApplicationRecord + adapters | Drizzle queries (optional) |

A React developer unfamiliar with Ruby should be able to:
1. Read the code and understand it immediately
2. Modify it using standard React patterns
3. Never know it was generated from Ruby

## Relationship to Deploy

`eject --framework` and `deploy` serve different needs:

| Scenario | Use |
|----------|-----|
| Production deployment, Ruby stays source | `juntos deploy -d neon` |
| Debug transpilation issues | `juntos eject` (current) |
| Hand off to JS team | `juntos eject --framework react` |
| Migrate away from Ruby source | `juntos eject --framework react` |

Most users will use `deploy` and never eject. The `--framework` option exists for:
- **Peace of mind** - knowing you *can* eject removes adoption friction
- **Team transitions** - hand off to developers who don't know Ruby/Rails
- **Validation** - if it ejects cleanly, the transpilation is sound

## First Target Decision

### Why React First

The current system **already uses React**:
- RBX files (`.jsx.rb`) transpile to React components
- Dual bundle mode provides RSC-like SSR + hydration
- Path helper RPC is Server Functions-style data fetching
- JsonStreamProvider is React Context for subscriptions
- `# Pragma: browser` handles code splitting

Ejecting to React is primarily **syntax transformation**, not paradigm shift:

| Current (RBX) | Ejected (React) |
|---------------|-----------------|
| `def Index()` | `function Index()` |
| `notes, setNotes = useState([])` | `const [notes, setNotes] = useState([])` |
| `%x{ <div>...</div> }` | `return <div>...</div>` |
| `notes_path.get()` | Keep or convert to React Query |
| `JsonStreamProvider` | Keep as-is |

**React output example:**
```jsx
// src/views/notes/Index.jsx
import { useState, useEffect } from 'react'
import { notesPath, notePath } from '../paths'

export default function Index() {
  const [notes, setNotes] = useState([])
  const [searchQuery, setSearchQuery] = useState("")

  useEffect(() => {
    const params = searchQuery.length > 0 ? { q: searchQuery } : {}
    notesPath.get(params).json(data => setNotes(data))
  }, [searchQuery])

  const handleCreate = () => {
    notesPath.post({ note: { title: "Untitled", body: "" } })
      .json(note => setNotes([note, ...notes]))
  }

  // ... rest of component
}
```

**Progression:**
```
React (closest to current) → Astro (SSR, has reference) → Vue (different paradigm)
```

### Astro Second

After React, Astro is natural:
- `test/astro-blog-v3` exists as working reference
- File-based routing matches Rails conventions
- Can embed React components as islands (reuse React eject work)
- Proves the edge deployment story

### Vue Third

Vue requires more transformation:
- JSX → Vue templates (`v-for`, `v-if`, `{{ }}`)
- useState/useEffect → Composition API (`ref`, `onMounted`)
- React Context → Pinia stores
- React Router → Vue Router

Still valuable - large ecosystem, "production credible" - but more work.

## Architecture

The extraction and transformation pipeline already exists. This plan adds **alternative emitters**:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Rails Source                              │
│  (models, views, controllers, routes, schema)                   │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│              Existing Ruby2JS Pipeline                           │
│  • AST parsing (Prism)                                          │
│  • Filter chain (rails/model, rails/controller, erb, etc.)      │
│  • Semantic understanding (associations, validations, routes)   │
└─────────────────────┬───────────────────────────────────────────┘
                      │
          ┌──────────┴──────────┐
          ▼                     ▼
┌─────────────────┐   ┌─────────────────────────────────────────┐
│ Current Emitter │   │ New Framework Emitters                   │
│ (Rails-in-JS)   │   │ • React: idiomatic JSX (first target)   │
│                 │   │ • Astro: .astro files + React islands    │
│                 │   │ • Vue: SFCs + Pinia + Vue Router        │
│                 │   │ • Alpine: templates + Alpine.store       │
└─────────────────┘   └─────────────────────────────────────────┘
```

### Mapping Details

**RBX → React (syntax transformation):**
```ruby
# app/views/notes/Index.jsx.rb (current)
import React, [useState, useEffect], from: 'react'
import [notes_path], from: '/config/paths.js'

export default def Index()
  notes, setNotes = useState([])

  useEffect(-> {
    notes_path.get.json { |data| setNotes(data) }
  }, [])

  %x{
    <div>
      {notes.map(note => <div key={note.id}>{note.title}</div>)}
    </div>
  }
end
```
→
```jsx
// src/views/notes/Index.jsx (ejected)
import { useState, useEffect } from 'react'
import { notesPath } from '../paths'

export default function Index() {
  const [notes, setNotes] = useState([])

  useEffect(() => {
    notesPath.get().json(data => setNotes(data))
  }, [])

  return (
    <div>
      {notes.map(note => <div key={note.id}>{note.title}</div>)}
    </div>
  )
}
```

**Path helpers stay similar:**
```ruby
# Current
notes_path.get(q: searchQuery)
note_path(id).patch(note: updates)
```
→
```javascript
// Ejected - same pattern, JS syntax
notesPath.get({ q: searchQuery })
notePath(id).patch({ note: updates })
```

**Models → Keep or convert to Drizzle:**

Option A - Keep ApplicationRecord pattern (minimal change):
```javascript
// src/models/Article.js
import { ApplicationRecord } from '../lib/ApplicationRecord'

export class Article extends ApplicationRecord {
  static tableName = 'articles'
  static associations = { comments: { type: 'has_many', model: 'Comment' } }
}
```

Option B - Convert to Drizzle + hooks (idiomatic React):
```javascript
// src/hooks/useArticles.js
import { useState, useEffect } from 'react'
import { db, eq } from '../db'
import { articles } from '../schema'

export function useArticles() {
  const [items, setItems] = useState([])

  const all = async () => {
    const data = await db.select().from(articles)
    setItems(data)
    return data
  }

  const create = async (attrs) => {
    const [record] = await db.insert(articles).values(attrs).returning()
    setItems(prev => [record, ...prev])
    return record
  }

  return { items, all, create }
}
```

**JsonStreamProvider stays as-is:**
```jsx
// Already idiomatic React - just copy to ejected project
<JsonStreamProvider stream={`workflow_${workflow.id}`}>
  <WorkflowCanvas />
</JsonStreamProvider>
```

## Implementation Phases

Since React patterns already exist, phases focus on syntax transformation and optional Drizzle conversion.

### Phase 1: React Syntax Emitter (Week 1)
- [ ] RBX (`.jsx.rb`) → idiomatic JSX (`.jsx`)
- [ ] `def ComponentName()` → `function ComponentName()`
- [ ] `x, setX = useState()` → `const [x, setX] = useState()`
- [ ] `%x{ ... }` → `return ( ... )`
- [ ] Ruby blocks → arrow functions
- [ ] Test: Notes demo components transpile correctly

### Phase 2: Path Helpers + Routing (Week 1)
- [ ] Extract path helper definitions to standalone `paths.js`
- [ ] Convert `snake_case` to `camelCase`
- [ ] Generate React Router config from `routes.rb`
- [ ] Test: navigation and RPC calls work

### Phase 3: Project Scaffold (Week 2)
- [ ] Generate `package.json` (React, React Router, Vite)
- [ ] Generate `vite.config.js`
- [ ] Copy runtime helpers (JsonStreamProvider, BroadcastChannel, etc.)
- [ ] Generate `main.jsx` with router setup
- [ ] Test: `npm install && npm run dev` works

### Phase 4: Drizzle Integration (Week 2-3, optional)
- [ ] `db/schema.rb` → Drizzle schema
- [ ] Model classes → Drizzle queries or React hooks
- [ ] Decide: keep ApplicationRecord pattern vs pure Drizzle
- [ ] Test: CRUD operations work

### Phase 5: Blog Demo End-to-End (Week 3)
- [ ] Eject blog demo (ERB views, not RBX)
- [ ] ERB → React components (more transformation needed)
- [ ] Turbo Streams → JsonStreamProvider pattern
- [ ] Test: full CRUD, real-time sync

### Phase 6: Polish + Documentation (Week 4)
- [ ] Generated README with instructions
- [ ] Handle edge cases
- [ ] Clean up output code style
- [ ] Test: ejected app indistinguishable from hand-written React

### Future: Astro Target
- [ ] React components → Astro pages with React islands
- [ ] File-based routing (simpler than React Router)
- [ ] Compare against `test/astro-blog-v3` reference

### Future: Vue Target
- [ ] React → Vue Composition API
- [ ] useState/useEffect → ref/onMounted
- [ ] JSX → Vue templates
- [ ] React Router → Vue Router
- [ ] JsonStreamProvider → Pinia + subscription

## Success Criteria

1. **Works:** `juntos eject --framework react` on notes demo produces running app
2. **Complete:** CRUD operations work, path helper RPC functions
3. **Reactive:** JsonStreamProvider + broadcast sync works
4. **Idiomatic:** A React developer would recognize it as "normal React"
5. **Minimal runtime:** Only lightweight helpers (JsonStreamProvider, paths), no ApplicationRecord
6. **Documented:** Generated README explains how to run and modify
7. **Blog demo:** ERB-based blog also ejects successfully (harder case)

## Test Strategy

**Phase 1: Notes demo (RBX → React)**

The notes demo is already React-based, making it the ideal first test:

```bash
# Create notes demo, eject, verify
npx github:ruby2js/juntos --demo notes
cd notes
npx juntos eject --framework react --output ../ejected-notes
cd ../ejected-notes
npm install
npm run dev
# Verify: CRUD, search, path helper RPC
```

**Phase 2: Workflow demo (complex React)**

Tests dual bundle, JsonStreamProvider, third-party React libraries:

```bash
npx github:ruby2js/juntos --demo workflow
cd workflow
npx juntos eject --framework react --output ../ejected-workflow
# Verify: React Flow works, real-time collaboration
```

**Phase 3: Blog demo (ERB → React)**

The harder case - ERB templates must become React components:

```bash
npx github:ruby2js/juntos --demo blog
cd blog
npx juntos eject --framework react --output ../ejected-blog
# Verify: CRUD, comments, Turbo-style broadcasts
```

**Automated verification (later):**
- Playwright tests against ejected apps
- Compare behavior to original running in Juntos

## Dependencies

**Already exists (in Ruby2JS/Juntos):**
- AST parsing (Prism)
- RBX filter (React components in Ruby)
- Model filter (associations, validations, callbacks, broadcasts_to)
- Controller filter (before_action, params, flash)
- ERB filter (template parsing)
- Route parsing
- Path helper RPC infrastructure
- JsonStreamProvider (React Context for subscriptions)
- Dual bundle mode (SSR + hydration)
- Schema/migration parsing
- `juntos eject` command infrastructure

**From `drizzle-transpilation.md` (optional, for deeper eject):**
- Drizzle query emitter (replaces adapter calls)
- Drizzle schema emitter (from schema.rb)
- IndexedDB helper (Drizzle-compatible API)

**New for this plan:**
- React syntax emitter (RBX → idiomatic JSX)
- React Router config generator
- Project scaffold templates (package.json, vite.config.js, main.jsx)
- Generated README template

**Future (Vue target):**
- Vue SFC emitter (from ERB or React)
- Vue Router emitter
- Pinia store emitter

## Open Questions

1. **Model layer depth:** Keep ApplicationRecord pattern (minimal change) or convert to Drizzle/hooks (more idiomatic)?

2. **Path helpers:** Keep as-is (they're already JS-like) or convert to React Query/SWR patterns?

3. **ERB views:** For blog demo, how to convert ERB to React? Generate class components, functional components, or custom hooks?

4. **Turbo Streams → React:** Convert `broadcasts_to` to JsonStreamProvider pattern, or something else?

5. **TypeScript:** Generate `.jsx` or `.tsx`? Types would help but add complexity.

6. **Styling:** Keep Tailwind classes as-is? Copy CSS? Generate CSS modules?

7. **Assets:** Copy `app/assets` as-is? Or expect user to handle separately?

8. **Incremental adoption:** Can you eject one component at a time, or is it all-or-nothing?

## Target Progression

```
React (first)     Closest to current - syntax transformation only
    │
    ├──→ Astro    File-based routing, can reuse React components as islands
    │
    └──→ Vue      Different paradigm - templates, Composition API, Pinia
            │
            └──→ Alpine    Similar to Vue templates, simpler store pattern
```

| Framework | Transformation Complexity | Notes |
|-----------|---------------------------|-------|
| React | Low | RBX already is React; change syntax only |
| Astro | Low-Medium | File-based routing, React islands, existing reference |
| Vue | Medium | Templates differ from JSX, Composition API differs from hooks |
| Alpine | Medium | Similar to Vue templates, needs routing solution |
| Svelte | Medium | Different template syntax, different reactivity model |

Shared across all:
- Drizzle queries (identical output)
- Drizzle schema (identical output)
- BroadcastChannel integration
- Extraction pipeline (already exists)
