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

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/cjs_spec.rb).
{% endrendercontent %}