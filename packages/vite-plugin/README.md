# @ruby2js/vite-plugin

Integration between Vite and Ruby2JS

## Description

Since Vite supports both rollup and vite plugins, this plugin can be used
interchangeably with the [Ruby2JS Rollup
plugin](https://www.npmjs.com/package/@ruby2js/rollup-plugin) with if there
the use of a refresh plugin is not needed.

What this plugin does is integrate Ruby2JS with the refresh process.  In order
to do this, the refresh plugin you would normally use needs to be passed as an
option to the Ruby2JS plugin rather than included as a separate plugin.  An
example of this usage follows below.

## Installation

```bash
npm install --save-dev @ruby2js/vite-plugin
# or
yarn add -D @ruby2js/vite-plugin
```

## Usage

The following is a example of a `vite.config.js` file configured for use with
the React refresh plugin.  Note the addition of `.rb` and `.js.rb` extensions
to `resolve.extensions` and the passing of the `reactRefresh` plugin as a
`refresh` option to the `@ruby2js/vite-plugin`.

```javascript
import { defineConfig } from 'vite'
import reactRefresh from '@vitejs/plugin-react-refresh'
import ruby2js from '@ruby2js/vite-plugin';

export default defineConfig({
  resolve: {
    extensions: ['.rb', '.js.rb'].concat(
      ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']
    )
  },

  plugins: [
    ruby2js({
      refresh: reactRefresh(),
      eslevel: 2021,
      autoexports: 'default',
      filters: ['react', 'esm', 'functions']
    })
  ]
})
```
