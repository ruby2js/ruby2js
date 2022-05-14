# @ruby2js/rollup-plugin

[![npm][npm]][npm-url]
[![node][node]][node-url]

Integration between Rollup and Ruby2JS

## Installation

```bash
npm install --save-dev @ruby2js/rollup-plugin
# or
yarn add -D @ruby2js/rollup-plugin
```

## Documentation

* Visit **[ruby2js.com](https://www.ruby2js.com/)** for detailed instructions and examples.
* See [Ruby2JS Options](https://www.ruby2js.com/docs/options) docs for a list of available options.

Below are some example configurations using some popular libraries.  Other
than the differences in filters, the differences are to make the library
themselves work with rollup.

## Usage (basic)

```javascript
// rollup.config.js
import ruby2js from '@ruby2js/rollup-plugin';

export default {
  input: 'index.js.rb',

  output: {
    file: 'bundle.js',
    format: 'iife'
  },

  plugins: [
    ruby2js({
      eslevel: 2021,
      filters: ['esm', 'functions']
    })
  ]
}
```

## Usage (lit-element)

```javascript
// rollup.config.js
import { nodeResolve } from '@rollup/plugin-node-resolve';
import ruby2js from '@ruby2js/rollup-plugin';

export default {
  input: 'index.js.rb',

  output: {
    file: 'bundle.js',
    format: 'iife'
  },

  plugins: [
    nodeResolve(),

    ruby2js({
      eslevel: 2021,
      filters: ['lit-element', 'esm', 'functions']
    })
  ]
}
```

## Usage (react)

```javascript
// rollup.config.js
import { nodeResolve } from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';
import replace from '@rollup/plugin-replace';
import ruby2js from '@ruby2js/rollup-plugin';

const env = process.env.NODE_ENV || 'development';

export default {
  input: 'index.js.rb',

  output: {
    file: 'bundle.js',
    format: 'iife'
  },

  plugins: [
    nodeResolve(),

    commonjs(),

    replace({
      preventAssignment: true,
      values: {
        'process.env.NODE_ENV': JSON.stringify(env)
      }
    }),

    ruby2js({
      eslevel: 2021,
      filters: ['react', 'esm', 'functions']
    })
  ]
}
```

## Usage (stimulus)

```javascript
import { nodeResolve } from '@rollup/plugin-node-resolve';
import ruby2js from '@ruby2js/rollup-plugin';

export default {
  input: 'index.js.rb',

  output: {
    file: 'bundle.js',
    format: 'iife'
  },

  context: 'window',

  plugins: [
    nodeResolve(),

    ruby2js({
      eslevel: 2021,
      filters: ['stimulus', 'esm', 'functions']
    })
  ]
}
```

## Testing

```
git clone https://github.com/ruby2js/ruby2js.git
cd ruby2js/packages/rollup-plugin
yarn install
yarn test
```

## Contributing

1. Fork it (https://github.com/ruby2js/ruby2js/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

MIT

[npm]: https://img.shields.io/npm/v/@ruby2js/ruby2js.svg
[npm-url]: https://npmjs.com/package/@ruby2js/ruby2js
[node]: https://img.shields.io/node/v/@ruby2js/ruby2js.svg
[node-url]: https://nodejs.org
