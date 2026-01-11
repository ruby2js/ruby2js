---
order: 612
title: Using Vite
top_section: Juntos
category: juntos
---

# Juntos + Vite

Use Vite directly with the `juntos()` preset for full control over your build process. This is an alternative to the [Juntos CLI](/docs/juntos/cli)—same transformations, but you manage Vite yourself.

{% toc %}

## When to Use Vite Directly

| Use Case | Recommended Approach |
|----------|---------------------|
| Quick start, standard setup | Juntos CLI (`bin/juntos dev`) |
| Custom Vite plugins needed | Vite + juntos preset |
| Integrating with existing Vite project | Vite + juntos preset |
| Non-standard build requirements | Vite + juntos preset |
| Just want it to work | Juntos CLI |

## Installation

Ensure you have the required packages:

```bash
npm install vite vite-plugin-ruby2js ruby2js-rails ruby2js
```

## Configuration

Create a `vite.config.js` in your Rails app root:

```javascript
import { juntos } from 'ruby2js-rails/vite';

export default juntos({
  database: 'dexie',
  target: 'browser'
});
```

Then run Vite directly:

```bash
npx vite          # Development server
npx vite build    # Production build
```

## Options

```javascript
juntos({
  // Database adapter (required)
  database: 'dexie',    // dexie, sqljs, sqlite, pg, neon, d1, etc.

  // Build target (default: derived from database)
  target: 'browser',    // browser, node, electron, capacitor, vercel, cloudflare

  // Broadcast adapter for Turbo Streams (optional)
  broadcast: null,      // supabase, pusher, or null for WebSocket

  // Application root (default: process.cwd())
  appRoot: '/path/to/rails/app',

  // Enable Stimulus HMR (default: true)
  hmr: true,

  // ES level (default: 2022)
  eslevel: 2022
})
```

### Database + Target Combinations

| Database | Valid Targets |
|----------|--------------|
| `dexie` | browser, capacitor |
| `sqljs` | browser, capacitor |
| `sqlite` / `better_sqlite3` | node, bun, electron |
| `pg` | node, bun, deno, electron |
| `neon` | vercel, vercel-edge |
| `d1` | cloudflare |

## What the Preset Does

The `juntos()` preset returns an array of Vite plugins:

| Plugin | Purpose |
|--------|---------|
| `vite-plugin-ruby2js` | Core `.rb` → `.js` transformation |
| `juntos-rbx` | `.rbx` files (Ruby + JSX) with React filter |
| `juntos-structure` | Models, controllers, views, routes transformation |
| `juntos-config` | Platform-specific Vite/Rollup configuration |
| `juntos-hmr` | Stimulus controller hot module replacement |

### Structural Transforms

On build start, the preset runs the same transformations as `bin/juntos build`:

- **Models** — ActiveRecord classes with associations, validations, callbacks
- **Controllers** — Action methods, before_action, params handling
- **Views** — ERB templates compiled to JavaScript functions
- **Routes** — `routes.rb` → `routes.js` with path helpers
- **Migrations** — Schema changes for the target database
- **Stimulus** — Controllers transpiled with HMR support

## RBX Files

`.rbx` files combine Ruby and JSX for React components:

```ruby
# app/components/WorkflowCanvas.rbx
import ReactFlow, [Background, Controls], from: 'reactflow'
import 'reactflow/dist/style.css'

export default
def WorkflowCanvas(initialNodes:, initialEdges:)
  nodes, setNodes, onNodesChange = useNodesState(initialNodes)
  edges, setEdges, onEdgesChange = useEdgesState(initialEdges)

  %x{
    <div style={{ width: '100%', height: '600px' }}>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        fitView
      >
        <Background />
        <Controls />
      </ReactFlow>
    </div>
  }
end
```

RBX files are automatically processed with the React filter.

## Configuration Loading

The preset reads configuration from multiple sources:

1. **Options passed to `juntos()`** — highest priority
2. **Environment variables** — `JUNTOS_DATABASE`, `JUNTOS_TARGET`
3. **`config/ruby2js.yml`** — project-level defaults
4. **`config/database.yml`** — database adapter detection

```yaml
# config/ruby2js.yml
default:
  eslevel: 2022

controllers:
  filters:
    - rails/controller
    - functions
```

## Combining with Other Plugins

Since `juntos()` returns a plugin array, combine with other Vite plugins:

```javascript
import { juntos } from 'ruby2js-rails/vite';
import react from '@vitejs/plugin-react';

export default {
  plugins: [
    ...juntos({ database: 'dexie' }),
    react()
  ]
};
```

## Path Aliases

The preset configures these aliases automatically:

| Alias | Path |
|-------|------|
| `@controllers` | `app/javascript/controllers` |
| `@models` | `app/models` |
| `@views` | `app/views` |
| `components` | `app/components` |

## Migrating from CLI

To migrate from `bin/juntos dev` to Vite directly:

1. Create `vite.config.js` as shown above
2. Add Vite scripts to `package.json`:
   ```json
   {
     "scripts": {
       "dev": "vite",
       "build": "vite build"
     }
   }
   ```
3. Run `npm run dev` instead of `bin/juntos dev`

Database commands still use the CLI:
```bash
bin/juntos db:migrate
bin/juntos db:seed
```

## Next Steps

- [Vite Integration](/docs/vite) — Core plugin documentation
- [Architecture](/docs/juntos/architecture) — What gets generated
- [Deployment](/docs/juntos/deploying/) — Platform-specific guides
