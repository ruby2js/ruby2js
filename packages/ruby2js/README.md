# @ruby2js/ruby2js

[![npm][npm]][npm-url]
[![node][node]][node-url]

Ruby2JS is an extensible Ruby to modern JavaScript transpiler.

## Example usage

```javascript
import { Ruby2JS } from '@ruby2js/ruby2js';

console.log(
  Ruby2JS.convert(
    '"2A".to_i(16)',
    {filters: ['functions']}
  ).toString()
)
```

An example of all supported options:

```javascript
{
  autoexports: true,
  autoimports: {"[:LitElement]": "lit-element"},
  comparison: "identity",
  defs: {A: ["x", "@y"]},
  eslevel: 2021,
  exclude: ["each"],
  filters: ["functions"],
  include: ["class"],
  include_all: true,
  include_only: ["max"],
  import_from_skypack: true,
  or: "nullish",
  require_recurse: true,
  strict: true,
  template_literal_tags: ["color"],
  underscored_private: true,
  width: 40
}
```

## Documentation

* Visit **[ruby2js.com](https://www.ruby2js.com/)** for detailed instructions and examples.
* Read the main monorepo [CHANGELOG](https://github.com/ruby2js/ruby2js/blob/master/CHANGELOG.md)
  for information on what's new in this package.

## Testing

```
git clone https://github.com/ruby2js/ruby2js.git
cd ruby2js/packages/ruby2js
bundle install
yarn install
yarn build
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
