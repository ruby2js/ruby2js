---
order: 125
title: Vite
top_section: Introduction
category: integrations
---

# Vite Integration

Ruby2JS provides first-class Vite support through `vite-plugin-ruby2js`. Transform Ruby files to JavaScript with hot module replacement, source maps, and framework-specific presets.

{% toc %}

## Installation

```bash
npm install https://www.ruby2js.com/releases/vite-plugin-ruby2js-beta.tgz
```

The plugin depends on `ruby2js` which will be installed automatically.

## Basic Usage

```javascript
// vite.config.js
import { defineConfig } from 'vite';
import ruby2js from 'vite-plugin-ruby2js';

export default defineConfig({
  plugins: [ruby2js()]
});
```

Now you can import `.rb` files directly:

```javascript
// main.js
import { add, greet } from './math.rb';

console.log(add(2, 3));      // 5
console.log(greet('World')); // "Hello, World!"
```

```ruby
# math.rb
export def add(a, b)
  a + b
end

export def greet(name)
  "Hello, #{name}!"
end
```

## Options

```javascript
ruby2js({
  // Filters to apply (default: ['Functions', 'ESM', 'Return'])
  filters: ['Functions', 'ESM', 'Return', 'CamelCase'],

  // ES level target (default: 2022)
  eslevel: 2022,

  // Glob patterns to exclude
  exclude: ['**/vendor/**']
})
```

See [Options](/docs/options) for the full list of Ruby2JS options.

## Presets

Presets bundle common configurations for specific use cases.

### Rails Preset

For Rails apps using Stimulus and ERB:

```javascript
import { rails } from 'vite-plugin-ruby2js/presets/rails';

export default defineConfig({
  plugins: [rails()]
});
```

Features:
- Stimulus controller transformation
- ERB template support
- Hot module replacement for controllers
- Path aliases (`@controllers`, `@models`, `@views`)

```javascript
rails({
  eslevel: 2022,      // ES level (default: 2022)
  hmr: true,          // Enable Stimulus HMR (default: true)
  aliases: {}         // Additional path aliases
})
```

### Juntos Preset

For full Rails app transformation with [Juntos](/docs/juntos/):

```javascript
import { juntos } from 'ruby2js-rails/vite';

export default juntos({
  database: 'dexie',
  target: 'browser'
});
```

This preset transforms entire Rails applications—models, controllers, views, routes—to run in browsers or JavaScript runtimes. See [Juntos + Vite](/docs/juntos/vite) for details.

### Framework Presets (Coming Soon)

Future versions will add presets for:

- **Vue** — `<script lang="ruby">` in `.vue` files
- **Svelte** — `<script lang="ruby">` in `.svelte` files
- **Astro** — `#!ruby` frontmatter in `.astro` files

## Source Maps

Source maps are generated automatically, allowing you to debug Ruby code directly in browser DevTools. The original `.rb` file appears in the Sources panel with correct line numbers.

## Hot Module Replacement

The Rails preset includes HMR for Stimulus controllers. When you edit a `*_controller.rb` file:

1. The file is re-transpiled
2. The controller is unregistered from Stimulus
3. The updated controller is registered
4. No full page reload required

## RBX Files (Ruby + JSX)

The Juntos preset supports `.rbx` files—Ruby with embedded JSX:

```ruby
# components/Counter.rbx
export default
def Counter(initial: 0)
  count, setCount = useState(initial)

  %x{
    <button onClick={() => setCount(count + 1)}>
      Count: {count}
    </button>
  }
end
```

RBX files are processed with the React filter and support:
- JSX via `%x{}` blocks
- React hooks
- Component exports

## Comparison with esbuild

| Feature | Vite | esbuild |
|---------|------|---------|
| Hot Module Replacement | Yes | No |
| Dev Server | Built-in | No |
| Source Maps | Yes | No |
| Framework Presets | Yes | No |
| Build Speed | Fast | Fastest |

**Use Vite for:** Web applications, SPAs, projects needing HMR and dev server.

**Use esbuild for:** CLI tools, Lambda functions, build scripts, backend services. See the [esbuild integration](/docs/esbuild) for details.

## Next Steps

- [Juntos + Vite](/docs/juntos/vite) — Full Rails app transformation
- [Filters](/docs/filters/) — Available transformation filters
- [Options](/docs/options) — All configuration options
