---
order: 126
title: esbuild
top_section: Introduction
category: integrations
---

# esbuild Integration

Ruby2JS provides an esbuild plugin for fast builds of CLI tools, serverless functions, and other non-web projects. For web applications with hot module replacement, see the [Vite integration](/docs/vite) instead.

{% toc %}

## Installation

```bash
npm install esbuild-plugin-ruby2js ruby2js
```

Or install from the beta release:

```bash
npm install https://www.ruby2js.com/releases/esbuild-plugin-ruby2js-beta.tgz
npm install https://www.ruby2js.com/releases/ruby2js-beta.tgz
```

## Basic Usage

```javascript
// build.mjs
import * as esbuild from 'esbuild';
import ruby2js from 'esbuild-plugin-ruby2js';

await esbuild.build({
  entryPoints: ['src/cli.rb'],
  plugins: [ruby2js()],
  bundle: true,
  platform: 'node',
  outfile: 'dist/cli.js'
});
```

```ruby
# src/cli.rb
def main
  args = process.argv.slice(2)
  puts "Hello, #{args[0] || 'World'}!"
end

main
```

Run your build:

```bash
node build.mjs
node dist/cli.js Alice  # => Hello, Alice!
```

## Options

```javascript
ruby2js({
  // Filters to apply (default: ['Functions', 'ESM', 'Return'])
  filters: ['Functions', 'ESM', 'Return', 'CamelCase'],

  // ES level target (default: 2022)
  eslevel: 2022,

  // Patterns to exclude from transformation
  exclude: ['vendor/'],

  // Auto-export all top-level functions and classes
  autoexports: true
})
```

See [Options](/docs/options) for the full list of Ruby2JS options.

## Use Cases

### CLI Tools

Write Node.js command-line tools in Ruby syntax:

```ruby
# src/cli.rb
require 'fs'
require 'path'

def main
  command = process.argv[2]

  case command
  when 'init'
    fs.writeFileSync('config.json', '{}')
    puts 'Initialized config.json'
  when 'version'
    puts '1.0.0'
  else
    puts "Usage: mycli [init|version]"
  end
end

main
```

```javascript
// build.mjs
await esbuild.build({
  entryPoints: ['src/cli.rb'],
  plugins: [ruby2js({ filters: ['Functions', 'CJS', 'Return'] })],
  bundle: true,
  platform: 'node',
  outfile: 'dist/cli.js'
});
```

### AWS Lambda

Write Lambda handlers in Ruby syntax:

```ruby
# src/handler.rb
export async def handler(event, context)
  name = event.dig(:queryStringParameters, :name) || 'World'

  {
    statusCode: 200,
    body: JSON.stringify({ message: "Hello, #{name}!" })
  }
end
```

```javascript
// build.mjs
await esbuild.build({
  entryPoints: ['src/handler.rb'],
  plugins: [ruby2js()],
  bundle: true,
  platform: 'node',
  target: 'node18',
  outfile: 'dist/handler.js'
});
```

### Build Scripts

Write custom build tools:

```ruby
# scripts/generate.rb
require 'fs'
require 'path'
require 'glob'

def generate_index
  files = glob.sync('src/**/*.rb')

  content = files.map do |file|
    name = path.basename(file, '.rb')
    "export * from './#{file}'"
  end.join("\n")

  fs.writeFileSync('src/index.js', content)
  puts "Generated index with #{files.length} exports"
end

generate_index
```

### With tsup

[tsup](https://tsup.egoist.dev/) is a popular esbuild-based bundler for npm packages:

```javascript
// tsup.config.js
import { defineConfig } from 'tsup';
import ruby2js from 'esbuild-plugin-ruby2js';

export default defineConfig({
  entry: ['src/index.rb'],
  esbuildPlugins: [ruby2js({ autoexports: true })],
  format: ['esm', 'cjs'],
  dts: false,
  outDir: 'dist'
});
```

## Comparison with Vite

| Feature | esbuild | Vite |
|---------|---------|------|
| Build Speed | Fastest | Fast |
| Hot Module Replacement | No | Yes |
| Dev Server | No | Built-in |
| Source Maps | No | Yes |
| Framework Presets | No | Yes |

**Use esbuild for:** CLI tools, Lambda functions, build scripts, backend services, npm packages.

**Use Vite for:** Web applications, SPAs, projects needing HMR and a dev server. See the [Vite integration](/docs/vite).

## Next Steps

- [Filters](/docs/filters/) — Available transformation filters
- [Options](/docs/options) — All configuration options
- [ESM Filter](/docs/filters/esm) — ES module imports and exports
- [CJS Filter](/docs/filters/cjs) — CommonJS require and exports
