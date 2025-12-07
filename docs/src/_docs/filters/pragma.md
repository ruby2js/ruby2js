---
order: 19
title: Pragma
top_section: Filters
category: pragma
---

The **Pragma** filter provides line-level control over JavaScript output through
special comments. This allows fine-grained customization of the transpilation
on a per-line basis.

Pragmas are specified with a comment at the end of a line using the format:
`# Pragma: <name>`

## Available Pragmas

### `??` (nullish)

Forces the use of nullish coalescing (`??`) instead of logical or (`||`).

This is useful when you want to distinguish between `null`/`undefined` and
falsy values like `0`, `""`, or `false`.

```ruby
a ||= b # Pragma: ??
# => a ??= b

x = value || default # Pragma: ??
# => let x = value ?? default
```

**Requirements:** ES2020 for `??`, ES2021 for `??=`

**When to use:** jQuery/DOM APIs often return `null` or `undefined` but valid
values could be falsy (e.g., `0` for an index). Use this pragma when you need
nullish semantics.

### `noes2015` (or `function`)

Forces traditional `function` syntax instead of arrow functions.

Arrow functions lexically bind `this`, which is often desirable. However,
DOM event handlers and jQuery callbacks typically need dynamic `this` binding
to reference the element that triggered the event.

```ruby
element.on("click") { handle_click(this) } # Pragma: noes2015
# => element.on("click", function() {handle_click(this)})

items.each { |item| process(item) } # Pragma: function
# => items.each(function(item) {process(item)})
```

Without the pragma:
```ruby
items.each { |item| process(item) }
# => items.each(item => process(item))
```

**When to use:** jQuery event handlers, DOM callbacks, or any situation where
you need `this` to refer to the calling context rather than the lexical scope.

### `guard`

Ensures splat arrays return an empty array when the source is `null` or
`undefined`.

In Ruby, `[*nil]` returns `[]`. In JavaScript, spreading `null` throws an error.
This pragma guards against that by using nullish coalescing.

```ruby
[*items] # Pragma: guard
# => items ?? []

[1, *items, 2] # Pragma: guard
# => [1, ...items ?? [], 2]
```

**Requirements:** ES2020 (for `??`)

**When to use:** When working with data from external APIs or DOM methods that
might return `null`, and you want to safely spread the result into an array.

## Usage Notes

### Case Insensitivity

Pragma names are case-insensitive:

```ruby
x = a || b # PRAGMA: ??
x = a || b # pragma: ??
x = a || b # Pragma: ??
# All produce: let x = a ?? b
```

### Multiple Pragmas

You can use different pragmas on different lines:

```ruby
options ||= {} # Pragma: ??
element.on("click") { handle(this) } # Pragma: noes2015
```

### Filter Loading

The pragma filter is automatically loaded when you require it:

```ruby
require 'ruby2js/filter/pragma'
```

Or specify it in your configuration:

```ruby
Ruby2JS.convert(code, filters: [Ruby2JS::Filter::Pragma])
```

### Combining with Other Filters

The pragma filter works alongside other filters. It processes pragmas before
other transformations occur.

## Background

The pragma filter was inspired by the need to handle edge cases in real-world
JavaScript frameworks. When interfacing with existing JavaScript libraries,
particularly jQuery and DOM APIs, Ruby2JS's default output may not always
produce the desired semantics.

Rather than changing global behavior, pragmas provide targeted control exactly
where needed, keeping the rest of your code using standard Ruby2JS conventions.
