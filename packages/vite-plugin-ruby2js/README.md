# vite-plugin-ruby2js

Vite plugin that transforms Ruby files to JavaScript using [Ruby2JS](https://www.ruby2js.com/).

## Installation

```bash
npm install vite-plugin-ruby2js
```

## Basic Usage

```javascript
// vite.config.js
import { defineConfig } from 'vite';
import ruby2js from 'vite-plugin-ruby2js';

export default defineConfig({
  plugins: [ruby2js()]
});
```

Now you can import `.rb` files in your project:

```javascript
import { greet } from './hello.rb';
```

```ruby
# hello.rb
def greet(name)
  "Hello, #{name}!"
end
```

## Options

```javascript
ruby2js({
  // Filters to apply (default: ['functions', 'esm', 'return'])
  filters: ['functions', 'esm', 'return'],

  // ES level to target (default: 2022)
  eslevel: 2022,

  // Glob patterns to exclude
  exclude: ['**/vendor/**']
})
```

## Rails Preset

For Rails/Stimulus applications with HMR support:

```javascript
// vite.config.js
import { defineConfig } from 'vite';
import { rails } from 'vite-plugin-ruby2js/presets/rails';

export default defineConfig({
  plugins: [rails()]
});
```

### Features

- **Stimulus filter**: Transforms Ruby classes to Stimulus controllers
- **HMR**: Edit a controller, see instant updates without page refresh
- **Path aliases**: `@controllers`, `@models`, `@views`

### Rails Preset Options

```javascript
rails({
  // ES level (default: 2022)
  eslevel: 2022,

  // Enable HMR for Stimulus controllers (default: true)
  hmr: true,

  // Custom path aliases
  aliases: {
    '@components': 'app/javascript/components'
  }
})
```

## Source Maps

Source maps are generated automatically, allowing you to debug Ruby code directly in browser DevTools.

## License

MIT
