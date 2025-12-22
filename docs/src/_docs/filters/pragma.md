---
order: 25
title: Pragma
top_section: Filters
category: pragma
next_page_order: 25.5
---

The **Pragma** filter provides line-level control over JavaScript output through
special comments. This allows fine-grained customization of the transpilation
on a per-line basis.

Pragmas are specified with a comment at the end of a line using the format:
`# Pragma: <name>`

## Available Pragmas

### `??` (or `nullish`)

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

### `||` (or `logical`)

Forces the use of logical or (`||`) instead of nullish coalescing (`??`).

This is the inverse of the `??` pragma. It's useful when you're using the
`or: :nullish` or `or: :auto` options globally but need logical `||` behavior
for a specific line where the value could legitimately be `false`.

```ruby
enabled ||= true # Pragma: logical
# => enabled ||= true  (not ??=)

x = flag || default # Pragma: ||
# => let x = flag || default  (not ??)
```

**When to use:** When a variable can hold `false` as a valid value and you
want the fallback to execute for `false`, not just `null`/`undefined`. For
example, boolean flags where `false` should trigger the default assignment.

### `function` (or `noes2015`)

Forces traditional `function` syntax instead of arrow functions.

Arrow functions lexically bind `this`, which is often desirable. However,
DOM event handlers and jQuery callbacks typically need dynamic `this` binding
to reference the element that triggered the event.

```ruby
element.on("click") { handle_click(this) } # Pragma: function
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

**Alternative:** You can also use `Function.new { }` (with the [Functions
filter](/docs/filters/functions)) to get the same result without a pragma:

```ruby
fn = Function.new { |x| x * 2 }
# => let fn = function(x) {x * 2}
```

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

### `skip`

Removes statements from the JavaScript output entirely. Works with:

- `require` and `require_relative` statements
- Method definitions (`def`)
- Class method definitions (`def self.method`)
- Alias declarations (`alias`)
- Block structures: `if`/`unless`, `begin`, `while`/`until`, `case`

This is useful when a Ruby file contains code that shouldn't be included in
the JavaScript output (e.g., Ruby-specific methods, native Ruby gems, runtime
dependencies that will be provided separately).

```ruby
require 'prism' # Pragma: skip
# => (no output)

require_relative 'helper' # Pragma: skip
# => (no output)

def respond_to?(method) # Pragma: skip
  # Ruby-only method, not needed in JS
  true
end
# => (no output)

def self.===(other) # Pragma: skip
  # Ruby-only class method
  other.is_a?(Node)
end
# => (no output)

alias loc location # Pragma: skip
# => (no output)

unless defined?(RUBY2JS_SELFHOST) # Pragma: skip
  require 'parser/current'
  # Ruby-only code block
end
# => (no output - entire block removed)

require 'my_module'  # No pragma, will be processed normally
# => import ... (if ESM filter is active)
```

**When to use:**
- When transpiling Ruby code that requires external dependencies provided
  separately in the JavaScript environment
- When using the `require` filter and you need to exclude specific requires
  from bundling
- When Ruby source files contain methods that are Ruby-specific and have no
  JavaScript equivalent (e.g., `respond_to?`, `is_a?`, `to_sexp`)
- When removing Ruby metaprogramming methods that don't translate to JavaScript

## Type Disambiguation Pragmas

Some Ruby methods have different JavaScript equivalents depending on the
receiver type. These pragmas let you specify the intended type.

### `array`

Specifies that the receiver is an Array.

```ruby
arr.dup # Pragma: array
# => arr.slice()

arr << item # Pragma: array
# => arr.push(item)
```

**When to use:** When Ruby2JS can't infer the type and you need array-specific
behavior.

### `hash`

Specifies that the receiver is a Hash (JavaScript object).

```ruby
obj.dup # Pragma: hash
# => {...obj}

obj.include?(key) # Pragma: hash
# => key in obj
```

**When to use:** When you need hash-specific operations like the `in` operator
for key checking.

### `set`

Specifies that the receiver is a Set (or Map).

```ruby
s << item # Pragma: set
# => s.add(item)

s.include?(item) # Pragma: set
# => s.has(item)

s.delete(item) # Pragma: set
# => s.delete(item)

s.clear() # Pragma: set
# => s.clear()
```

**When to use:** When working with JavaScript `Set` or `Map` objects. By default:
- `<<` becomes `.push()` (array behavior)
- `.include?` becomes `.includes()` (array/string behavior)
- `.delete()` becomes `delete obj[key]` (hash/object behavior)
- `.clear()` becomes `.length = 0` (array behavior)

Use this pragma to get the correct Set methods: `.add()`, `.has()`,
`.delete()`, and `.clear()`.

### `map`

Specifies that the receiver is a JavaScript `Map` object.

```ruby
m[key] # Pragma: map
# => m.get(key)

m[key] = value # Pragma: map
# => m.set(key, value)

m.key?(key) # Pragma: map
# => m.has(key)

m.delete(key) # Pragma: map
# => m.delete(key)

m.clear # Pragma: map
# => m.clear()
```

**When to use:** When working with JavaScript `Map` objects. By default:
- `hash[key]` becomes bracket access `hash[key]` (object behavior)
- `hash[key] = value` becomes `hash[key] = value` (object behavior)
- `.key?()` becomes `key in obj` (object behavior)
- `.delete()` becomes `delete obj[key]` (object behavior)
- `.clear()` becomes `.length = 0` (array behavior)

Use this pragma to get the correct Map methods: `.get()`, `.set()`, `.has()`,
`.delete()`, and `.clear()`.

### `string`

Specifies that the receiver is a String.

```ruby
str.dup # Pragma: string
# => str
```

**Note:** Strings in JavaScript are immutable, so `.dup` is a no-op.

## Behavior Pragmas

These pragmas modify how specific Ruby patterns translate to JavaScript.

### `method`

Converts `.call()` to direct invocation for function objects.

```ruby
fn.call(x, y) # Pragma: method
# => fn(x, y)
```

**When to use:** When working with first-class functions stored in variables
that need to be invoked directly rather than using `.call()`.

### `proto`

Converts `.class` to `.constructor` for JavaScript prototype access.

```ruby
obj.class # Pragma: proto
# => obj.constructor
```

**When to use:** When you need to access the JavaScript constructor function
rather than a literal `.class` property.

### `entries`

Converts hash iteration to use `Object.entries()`.

```ruby
hash.each { |k, v| process(k, v) } # Pragma: entries
# => Object.entries(hash).forEach(([k, v]) => process(k, v))
```

**When to use:** When iterating over JavaScript objects where you need both
keys and values, and the standard `.each` translation doesn't apply.

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

You can use multiple pragmas on the same line, and they will all be applied:

```ruby
# Both logical and method pragmas apply
x ||= fn.call(y) # Pragma: logical # Pragma: method
# => x ||= fn(y)

# Nullish and method together
x ||= fn.call(y) # Pragma: ?? # Pragma: method
# => x ??= fn(y)
```

You can also use different pragmas on different lines:

```ruby
options ||= {} # Pragma: ??
element.on("click") { handle(this) } # Pragma: function
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

The pragma filter works alongside other filters. It automatically reorders
itself to run before the Functions and ESM filters, ensuring pragmas like
`skip`, `entries`, and `method` are processed correctly regardless of the
order filters are specified.

## Background

The pragma filter was inspired by the need to handle edge cases in real-world
JavaScript frameworks. When interfacing with existing JavaScript libraries,
particularly jQuery and DOM APIs, Ruby2JS's default output may not always
produce the desired semantics.

Rather than changing global behavior, pragmas provide targeted control exactly
where needed, keeping the rest of your code using standard Ruby2JS conventions.
