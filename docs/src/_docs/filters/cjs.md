---
order: 13
title: CommonJS
top_section: Filters
category: cjs
---

The **CJS** filter maps export statements to their CommonJS counterparts.

* `export def f` to `exports.f =`
* `export async def f` to `exports.f = async`
* `export v =` to `exports.v =`
* `export default proc` to `module.exports =`
* `export default async proc` to `module.exports = async`
* `export default` to `module.exports =`

## \_\_FILE\_\_

Ruby's `__FILE__` constant is converted to `__filename`, which is available in Node.js CommonJS modules:

```ruby
__FILE__
# => __filename

puts __FILE__
# => puts(__filename)
```

## \_\_dir\_\_

Ruby's `__dir__` method is converted to `__dirname`, which is available in Node.js CommonJS modules:

```ruby
__dir__
# => __dirname

puts __dir__
# => puts(__dirname)
```

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/cjs_spec.rb).
{% endrendercontent %}