---
order: 510
title: Running the Demo
top_section: Behind the Scenes
category: demo
---

**Ruby2JS** provides a web-based demo you can use to try out Ruby code and see how it converts to JavaScript. This is the same tool used for the [online demo](/demo?preset=true) and the interactive examples throughout this documentation.

## Running Locally

```
git clone https://github.com/ruby2js/ruby2js.git
cd ruby2js/docs
bundle install
bundle exec rake install   # install all dependencies
bundle exec rake           # build demo assets
bin/bridgetown start       # start the dev server
```

Then open http://localhost:4000 in your browser.

The demo provides a live editing experience — JavaScript output updates as you type Ruby code. Dropdowns let you change the ECMAScript level, filters, and options. A checkbox shows the Abstract Syntax Tree (AST).

## How It Works

The demo runs entirely in the browser with no server-side compilation. It uses a **selfhost** architecture: Ruby2JS transpiled by Ruby2JS itself into JavaScript.

The key components:

| File | Size | Purpose |
|------|------|---------|
| `ruby2js.js` | ~300KB | Core transpiler (converter, serializer, pipeline) |
| `prism_browser.js` | loader | Initializes the Prism Ruby parser |
| `prism.wasm` | ~730KB | Prism parser compiled to WebAssembly |
| `filters/*.js` | on-demand | Individual filters loaded as needed |

When you type Ruby code, the browser:

1. Parses it using [Prism](https://github.com/ruby/prism) (via WASM)
2. Converts the Prism AST to a parser-compatible AST
3. Runs any selected filters over the AST
4. Converts the AST to JavaScript

## Using Ruby2JS in Your Own Browser Code

You can import the transpiler directly from the Ruby2JS website:

```js
import { convert, initPrism } from
  'https://www.ruby2js.com/demo/selfhost/ruby2js.js';

// Initialize the Prism WASM parser (once)
await initPrism();

// Convert Ruby to JavaScript
let result = convert('puts "Hello, world!"', { eslevel: 2022 });
console.log(result.toString());
// => console.log("Hello, world!")
```

### Using Filters

Filters are loaded on-demand via dynamic import. Import the filter module first, then reference it by name:

```js
import { convert, initPrism } from
  'https://www.ruby2js.com/demo/selfhost/ruby2js.js';

await initPrism();

// Load the functions filter
await import(
  'https://www.ruby2js.com/demo/selfhost/filters/functions.js');

let result = convert(
  '[1,2,3].select { |n| n > 1 }',
  { eslevel: 2022, filters: ['functions'] }
);
console.log(result.toString());
// => [1, 2, 3].filter(n => n > 1)
```

### Available Filters

The following filters are available for browser use:

`functions` `esm` `return` `pragma` `camelCase` `stimulus` `active_support` `polyfill` `erb`

Rails filters: `rails/model` `rails/controller` `rails/routes` `rails/schema` `rails/seeds` `rails/logger` `rails/helpers`

### Notes

- **First load** fetches and compiles the ~730KB Prism WASM module. Subsequent conversions are fast.
- **No stability guarantee** — these URLs point to the latest development build and may change without notice.
- For production use, consider hosting the files yourself or using the [npm package](https://www.ruby2js.com/releases/ruby2js-beta.tgz) with a bundler.
