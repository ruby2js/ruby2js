# @ruby2js/rollup-plugin

Integration between Rollup and Ruby2JS

## Installation

```bash
npm install --save-dev @ruby2js/rollup-plugin
# or
yarn add -D @ruby2js/rollup-plugin
```

## Usage (basic)

```js
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

```
import { nodeResolve } from '@rollup/plugin-node-resolve';
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

    ruby2js({
      eslevel: 2021,
      filters: ['lit-element', 'esm', 'functions']
    })
  ]
}
```

## Usage (react)

```js
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

```
import { nodeResolve } from '@rollup/plugin-node-resolve';
import ruby2js from '@ruby2js/rollup-plugin';

const env = process.env.NODE_ENV || 'development';

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
