Example usage:

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
