---
order: 4
title: CommonJS
top_section: Filters
category: cjs
---

The <a href="https://github.com/rubys/ruby2js/blob/master/spec/cjs">cjs</a> filter maps export statements to their CommonJS counterparts.

* `export def f` to `exports.f =`
* `export async def f` to `exports.f = async`
* `export v =` to `exports.v =`
* `export default proc` to `module.exports =`
* `export default async proc` to `module.exports = async`
* `export default` to `module.exports =`