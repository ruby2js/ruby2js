---
order: 12
title: Combiner
top_section: Filters
category: combiner
---

The **Combiner** filter merges reopened modules and classes into a single definition.

Ruby allows reopening modules and classes to add methods across multiple files or locations:

```ruby
module Foo
  def bar; end
end

module Foo
  def baz; end
end
```

JavaScript doesn't support this pattern. The Combiner filter merges all definitions with the same name into a single definition:

```javascript
const Foo = {
  bar() {},
  baz() {}
}
```

## Usage

This filter is **not** included in the default filter set. It's primarily useful when:

- Using the [Require](require) filter to inline multiple files that define the same module/class
- Self-hosting scenarios where Ruby source is split across files but needs to compile to a single JavaScript output

When using with the Require filter, Combiner should be applied **after** Require so that inlined files get their classes/modules merged with the main file.

```ruby
Ruby2JS.convert(source, filters: [:require, :combiner])
```

## Features

- Merges multiple definitions of the same module or class
- Handles nested module/class definitions
- Reorders class bodies to put class variable assignments (`@@var`) before methods (required for JavaScript's evaluation order)

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/combiner_spec.rb).
{% endrendercontent %}
