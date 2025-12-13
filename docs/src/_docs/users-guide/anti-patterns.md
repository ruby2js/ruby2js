---
order: 9.3
title: Anti-Patterns
top_section: User's Guide
category: users-guide-anti-patterns
next_page_order: 9.4
---

# Anti-Patterns to Avoid

Some Ruby features don't translate to JavaScript, or translate in ways that may surprise you. This guide helps you avoid common pitfalls when writing dual-target code.

{% toc %}

## Metaprogramming

### `method_missing`

Ruby's dynamic method dispatch doesn't exist in JavaScript:

```ruby
# Won't work
class Proxy
  def method_missing(name, *args)
    @target.send(name, *args)
  end
end
```

**Alternative:** Define methods explicitly or use JavaScript's `Proxy` object directly.

### `define_method`

`define_method` is supported inside class bodies, including inside loops:

```ruby
# This works
class Color
  %w[red green blue].each do |color|
    define_method("#{color}?") { @color == color }
  end
end
```

Becomes:

```javascript
class Color {};
for (let color of ["red", "green", "blue"]) {
  Color.prototype[`${color}?`] = function() { return this._color == color }
}
```

However, `define_method` at the top level (outside a class) or with complex metaprogramming may not translate correctly.

### `eval` and `instance_eval`

Code evaluation at runtime doesn't translate:

```ruby
# Won't work
eval("x + y")
instance_eval(&block)
```

**Alternative:** Restructure to avoid dynamic evaluation.

### `send` and `public_send`

Basic `send` is supported:

```ruby
# Static method name - works
obj.send(:foo, x, y)      # => obj.foo(x, y)

# Dynamic method name - works
obj.send(method_name, x)  # => obj[method_name](x)
```

However, `public_send` is not specifically handled (treated the same as `send`), and complex dispatch patterns may not translate correctly.

## Type Introspection

### `is_a?`, `kind_of?`, `instance_of?`

These methods are fully supported with the functions filter:

```ruby
obj.is_a?(MyClass)    # => obj instanceof MyClass
obj.kind_of?(MyClass) # => obj instanceof MyClass
obj.instance_of?(MyClass) # => obj.constructor === MyClass
```

Built-in types are handled specially:

```ruby
obj.is_a?(Array)   # => Array.isArray(obj)
obj.is_a?(String)  # => typeof obj === "string"
obj.is_a?(Integer) # => typeof obj === "number" && Number.isInteger(obj)
obj.is_a?(Float)   # => typeof obj === "number"
obj.is_a?(Hash)    # => typeof obj === "object" && obj !== null && !Array.isArray(obj)
```

### `respond_to?`

Method/property existence checks work:

```ruby
obj.respond_to?(:save)  # => "save" in obj
obj.respond_to?("save") # => "save" in obj
```

### `class` and `superclass`

These are supported with the functions filter:

```ruby
obj.class        # => obj.constructor
obj.class.name   # => obj.constructor.name
obj.class == Foo # => obj.constructor === Foo

Foo.superclass   # => Object.getPrototypeOf(Foo.prototype).constructor
```

## Ruby-Specific Features

### Symbols vs Strings

Ruby symbols don't exist in JavaScript:

```ruby
# These become identical in JS
:foo     # => "foo"
"foo"    # => "foo"

# Hash keys work, but type distinction is lost
{ foo: 1 }        # => { foo: 1 }
{ "foo" => 1 }    # => { "foo": 1 }
```

### Ranges as Objects

Ruby ranges are objects with methods:

```ruby
# Works (converted to loops or conditions)
(1..10).each { |i| puts i }
(1...5).to_a

# Problematic - ranges as first-class objects
range = (1..10)
range.include?(5)  # May not work as expected
```

**Alternative:** Use explicit loops or arrays.

### Multiple Return Values

Ruby's implicit array unpacking differs from JS:

```ruby
# Ruby
def pair; [1, 2]; end
a, b = pair  # Works

# JavaScript
# let [a, b] = pair()  # Works too, but be explicit
```

This generally works, but be aware of edge cases with nested destructuring.

### Default Mutable Arguments

A classic Ruby gotcha that's different in JS:

```ruby
# Ruby gotcha - shared mutable default
def add(item, list = [])
  list << item
end

# JavaScript doesn't share defaults, but still avoid:
def add(item, list = [])
  list.push(item)  # Creates new array each call in JS
end
```

## Control Flow Differences

### `retry`

Ruby's `retry` in exception handling doesn't exist in JS:

```ruby
# Won't work
begin
  attempt_operation
rescue
  retry if should_retry?
end
```

**Alternative:** Use explicit loops:

```ruby
loop do
  begin
    attempt_operation
    break
  rescue
    next if should_retry?
    raise
  end
end
```

### `redo`

Loop `redo` doesn't translate:

```ruby
# Won't work
items.each do |item|
  redo if needs_retry?(item)
end
```

**Alternative:** Restructure with explicit control flow.

### `catch` / `throw`

Ruby's catch/throw (not exceptions) doesn't exist in JS:

```ruby
# Won't work
catch(:done) do
  items.each do |item|
    throw :done if found?(item)
  end
end
```

**Alternative:** Use `break`, `return`, or exceptions.

## Object Model Differences

### Singleton Methods

Instance-level method definition doesn't work:

```ruby
# Won't work
obj = Object.new
def obj.custom_method
  "custom"
end
```

### Module Mixins

`include` and `extend` are supported:

```ruby
module Loggable
  def log(msg)
    puts msg
  end
end

class MyClass
  include Loggable  # Add instance methods
end

class MyClass
  extend Loggable   # Add class methods
end
```

Generates:

```javascript
const Loggable = {log(msg) {console.log(msg)}};

class MyClass {}
Object.defineProperties(MyClass.prototype, Object.getOwnPropertyDescriptors(Loggable));

class MyClass {}
Object.defineProperties(MyClass, Object.getOwnPropertyDescriptors(Loggable));
```

This also works with anonymous classes:

```ruby
filter = Class.new { include Loggable }
```

### `prepend`

Method prepending doesn't exist in JS:

```ruby
# Won't work
module Wrapper
  def process
    pre_process
    super
    post_process
  end
end

class MyClass
  prepend Wrapper
end
```

## Numeric Precision

### BigDecimal

Ruby's arbitrary precision decimals don't exist natively in JS:

```ruby
# Ruby-only
require 'bigdecimal'
price = BigDecimal("19.99")
```

**Alternative:** Use JavaScript libraries or work with cents:

```ruby
price_cents = 1999  # Store as integer cents
```

### Integer Division

Ruby and JavaScript handle division differently:

```ruby
# Ruby
5 / 2    # => 2 (integer division)
5.0 / 2  # => 2.5

# JavaScript
5 / 2    // => 2.5 (always float)
```

Use `Math.floor()` for integer division in JS contexts.

## String Differences

### Encoding

Ruby's encoding system doesn't translate:

```ruby
# Ruby-only
str.encoding
str.force_encoding("UTF-8")
```

### Character Iteration

```ruby
# Ruby - iterates codepoints properly
"emoji: 😀".each_char { |c| puts c }

# JavaScript - may split surrogate pairs
# Use Array.from() for proper iteration
```

## Summary: Safe vs Unsafe

| Feature | Status | Notes |
|---------|--------|-------|
| Classes, methods | ✅ Safe | |
| Blocks as lambdas | ✅ Safe | |
| Arrays, hashes | ✅ Safe | Mind `<<`, `.dup` |
| String interpolation | ✅ Safe | |
| Control flow | ✅ Safe | Except `retry`, `redo` |
| `define_method` | ✅ Safe | In class bodies |
| `send` | ✅ Safe | Static or dynamic names |
| `include`/`extend` | ✅ Safe | Module mixins |
| `is_a?`, `kind_of?` | ✅ Safe | Maps to `instanceof` |
| `instance_of?` | ✅ Safe | Exact type check |
| `respond_to?` | ✅ Safe | Property existence |
| `.class` | ✅ Safe | Returns constructor |
| `superclass` | ✅ Safe | Parent class |
| Symbols | ⚠️ Caution | Work as strings |
| `method_missing` | ❌ Avoid | Explicit methods |
| `eval` | ❌ Avoid | Restructure |
| `prepend` | ❌ Avoid | MRO incompatible |
| `retry`/`redo` | ❌ Avoid | Explicit loops |
| `catch`/`throw` | ❌ Avoid | Break/return |

## See Also

- [Patterns](/docs/users-guide/patterns) - Recommended patterns that work well
- [Pragmas](/docs/users-guide/pragmas) - Fine-grained control for edge cases
- [Conversion Details](/docs/conversion-details) - How Ruby constructs translate
