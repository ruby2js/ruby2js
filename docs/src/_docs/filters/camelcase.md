---
order: 3
title: camelCase
top_section: Filters
category: camelcase
---

The <a href="https://github.com/rubys/ruby2js/blob/master/lib/ruby2js/filter/camelCase.rb">camelCase</a> filter converts `underscore_case` (aka "snake case") to `camelCase`.

## Examples

```ruby
foo_bar = baz_qux
# becomes:
var fooBar = bazQux

foo_bar(baz_qux)
# becomes:
fooBar(bazQux)

def foo_bar(baz_qux = nil)
end
# becomes:
function fooBar(bazQux) {
  if (typeof bazQux === 'undefined') bazQux = null
}
```
