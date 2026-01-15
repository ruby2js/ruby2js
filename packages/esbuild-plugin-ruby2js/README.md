# esbuild-plugin-ruby2js

An [esbuild](https://esbuild.github.io/) plugin that transforms Ruby files to JavaScript using [Ruby2JS](https://www.ruby2js.com/).

## Installation

```bash
npm install esbuild-plugin-ruby2js ruby2js
```

## Usage

### Basic

```javascript
import * as esbuild from 'esbuild';
import ruby2js from 'esbuild-plugin-ruby2js';

await esbuild.build({
  entryPoints: ['src/index.rb'],
  plugins: [ruby2js()],
  bundle: true,
  outfile: 'dist/index.js'
});
```

### With Options

```javascript
import ruby2js from 'esbuild-plugin-ruby2js';

await esbuild.build({
  entryPoints: ['src/cli.rb'],
  plugins: [
    ruby2js({
      filters: ['Functions', 'ESM', 'Return', 'CamelCase'],
      eslevel: 2022,
      exclude: ['vendor/']
    })
  ],
  bundle: true,
  platform: 'node',
  outfile: 'dist/cli.js'
});
```

### With tsup

```javascript
// tsup.config.js
import { defineConfig } from 'tsup';
import ruby2js from 'esbuild-plugin-ruby2js';

export default defineConfig({
  entry: ['src/index.rb'],
  esbuildPlugins: [ruby2js()],
  format: ['esm'],
  outDir: 'dist'
});
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `filters` | `string[]` | `['Functions', 'ESM', 'Return']` | Ruby2JS filters to apply |
| `eslevel` | `number` | `2022` | ECMAScript level to target |
| `exclude` | `string[]` | `[]` | Patterns to exclude from transformation |

Additional Ruby2JS options can be passed directly and will be forwarded to the converter.

## Available Filters

- `Functions` - Maps Ruby methods to JS equivalents (`.map`, `.select` → `.filter`, etc.)
- `ESM` - ES6 module imports/exports
- `CJS` - CommonJS require/module.exports
- `Return` - Implicit returns
- `CamelCase` - Convert snake_case to camelCase
- `Stimulus` - Stimulus controller patterns

See [Ruby2JS Filters](https://www.ruby2js.com/docs/filters) for the complete list.

## Example

**Input (src/greet.rb):**

```ruby
def greet(name)
  puts "Hello, #{name}!"
end

export default :greet
```

**Output:**

```javascript
function greet(name) {
  console.log(`Hello, ${name}!`)
}

export default greet
```

## Use Cases

- **CLI tools** - Write Node.js CLIs in Ruby syntax
- **AWS Lambda** - Ruby-syntax Lambda handlers deployed as JavaScript
- **Build scripts** - Custom build tools and code generators
- **Backend services** - Express/Fastify/Hono servers in Ruby syntax

## License

MIT
