# @ruby2js/esbuild-plugin

[![npm][npm]][npm-url]
[![node][node]][node-url]

An [esbuild](https://esbuild.github.io) plugin to compile [Ruby2JS](https://www.ruby2js.com) (`.js.rb`) files to JavaScript.

## Installation

```bash
npm install --save-dev @ruby2js/esbuild-plugin
# or
yarn add -D @ruby2js/esbuild-plugin
```

You will also need Ruby installed and the Ruby2JS gem present in your project's Gemfile.

## Documentation

esbuild doesn't have a configuration format per se, so you'll need to create a JavaScript file which uses esbuild's Build API if you don't have one already.

Here's an example of a simple one you might use in a Rails app:

```js
// esbuild.config.js
const path = require("path")

const watch = process.argv.includes("--watch")
const minify = process.argv.includes("--minify")

require("esbuild").build({
  entryPoints: ["application.js"],
  bundle: true,
  outdir: path.join(process.cwd(), "app/assets/builds"),
  absWorkingDir: path.join(process.cwd(), "app/javascript"),
  publicPath: "/assets",
  watch,
  minify,
  plugins: [],
}).catch(() => process.exit(1))
```

However your esbuild configuration is set up, you'll need to add the `ruby2js` plugin to your plugins array:

```js
const ruby2js = require("@ruby2js/esbuild-plugin")

// later in the build config:
  plugins: [
    ruby2js()
  ]
```

Then simply run the config script (aka `yarn node esbuild.config.js`) to compile your Ruby2JS files to a JavaScript output bundle.

The Ruby2JS build process will look for a `config/ruby2js.rb` file to set configuration options. Alternatively, you can use a "magic comment" such as `# ruby2js: preset` at the top of `.rb.js` files to use the standard preset configuration.

See [Ruby2JS Options](https://www.ruby2js.com/docs/options) docs for a list of available options.

## Testing

```
git clone https://github.com/ruby2js/ruby2js.git
cd ruby2js/packages/esbuild-plugin
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

[npm]: https://img.shields.io/npm/v/@ruby2js/esbuild-plugin.svg
[npm-url]: https://npmjs.com/package/@ruby2js/esbuild-plugin
[node]: https://img.shields.io/node/v/@ruby2js/esbuild-plugin.svg
[node-url]: https://nodejs.org
