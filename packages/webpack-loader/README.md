# @ruby2js/webpack-loader

[![npm][npm]][npm-url]
[![node][node]][node-url]

**This package is deprecated and will no longer be supported in future versions of Ruby2JS.**

Webpack loader to compile [Ruby2JS](https://www.ruby2js.com) (`.js.rb`) files to JavaScript.

## Installation

```bash
npm install --save-dev @ruby2js/webpack-loader
# or
yarn add -D @ruby2js/webpack-loader
```

## Documentation

* Visit **[ruby2js.com](https://www.ruby2js.com/)** for detailed instructions and examples.
Users of Ruby on Rails may wish to start with the [Rails
introduction](https://www.ruby2js.com/examples/rails/) which describes how to
use the rake tasks provided to get up and running quickly.

## Configuration

There are multiple ways to configure webpack (e.g., `webpack.config.js`,
command line options, or using the
[node interface](https://webpack.js.org/api/node/).  Ruby2JS options can be
placed inline within this configuration, or separately in a `rb2js.config.rb`
file or provided via a `RUBY2JS_OPTIONS` environment variable.  Examples of
each are provided below:

### `webpack.config.js`

```javascript
module.exports = {
  entry: "./main.js.rb",

  output: {
    path: __dirname,
    filename: "main.[contenthash].js"
  },

  resolve: {
    extensions: [".rb.js", ".rb"]
  },

  module: {
    rules: [
      {
        test: /\.js\.rb$/,
        use: [
          {
            loader: '@ruby2js/webpack-loader',
            options: {
              eslevel: 2021,
              filters: ['functions']
            }
          },
        ]
      },
    ]
  }
}
```

See [Ruby2JS Options](https://www.ruby2js.com/docs/options) docs for a list of available options.

### `rb2js.config.rb`

```ruby
require "ruby2js/filter/functions"

module Ruby2JS
  class Loader
    def self.options
      {eslevel: 2021}
    end
  end
end
```

### `RUBY2JS_OPTIONS` environment variable

```
export RUBY2JS_OPTIONS='{"eslevel": 2021, "filters": ["functions"]}'
```

## Testing

```
git clone https://github.com/ruby2js/ruby2js.git
cd ruby2js/packages/webpack-loader
yarn install
yarn prepare-release
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

[npm]: https://img.shields.io/npm/v/@ruby2js/webpack-loader.svg
[npm-url]: https://npmjs.com/package/@ruby2js/webpack-loader
[node]: https://img.shields.io/node/v/@ruby2js/webpack-loader.svg
[node-url]: https://nodejs.org
