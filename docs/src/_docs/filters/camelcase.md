---
order: 12
title: camelCase
top_section: Filters
category: camelcase
---

The **camelCase** filter converts `underscore_case` (aka "snake case") to `camelCase`.

## Examples

```ruby
foo_bar = baz_qux
# becomes:
let fooBar = bazQux

foo_bar(baz_qux)
# becomes:
fooBar(bazQux)

def foo_bar(baz_qux = nil)
end
# becomes:
function fooBar(bazQux=null) {}
```

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/camelcase_spec.rb).
{% endrendercontent %}
