---
order: 612
title: Vite Configuration
top_section: Juntos
category: juntos
---

# Juntos + Vite

Juntos uses Vite as its build tool. When you run `juntos install`, a `vite.config.js` is created automatically. This page covers how to customize the Vite configuration.

{% toc %}

## Default Setup

After running `juntos install`, your `dist/vite.config.js` looks like:

```javascript
import { juntos } from 'ruby2js-rails/vite';

export default juntos({
  database: 'dexie',
  target: 'browser',
  appRoot: '..'  // Source files are in parent directory
});
```

The CLI commands use this configuration automatically:

```bash
bin/juntos dev    # Runs Vite dev server
bin/juntos build  # Runs Vite build
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

On build start, the preset runs the same transformations as the Ruby transpiler:

- **Models** — ActiveRecord classes with associations, validations, callbacks
- **Controllers** — Action methods, before_action, params handling
- **Views** — ERB templates compiled to JavaScript functions
- **Routes** — `routes.rb` → `routes.js` with path helpers
- **Migrations** — Schema changes for the target database
- **Stimulus** — Controllers transpiled with HMR support

### Hot Module Replacement

During development, file changes trigger different behaviors:

| File Type | Behavior |
|-----------|----------|
| Stimulus controllers | Hot swap (no reload) |
| RBX components | React HMR |
| ERB views | Module refresh |
| Plain Ruby files | Module refresh |
| Models | Full page reload |
| Rails controllers | Full page reload |
| Routes | Full page reload |

Models, Rails controllers, and routes trigger full reloads because they have complex dependencies. Everything else updates instantly without losing page state.

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

## Adding Custom Plugins

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

## Running Vite Directly

You can bypass the CLI and run Vite directly:

```bash
cd dist
npx vite          # Development server
npx vite build    # Production build
npx vite preview  # Preview production build
```

This is useful for debugging or when integrating with other tools.

## Opting Out of Vite

To use the legacy dev server instead of Vite:

1. Delete `dist/vite.config.js`
2. Run `bin/juntos dev` — it will fall back to the legacy server

The legacy server uses full page reloads instead of HMR.

## Next Steps

- [Vite Integration](/docs/vite) — Core plugin documentation
- [Architecture](/docs/juntos/architecture) — What gets generated
- [Deployment](/docs/juntos/deploying/) — Platform-specific guides
