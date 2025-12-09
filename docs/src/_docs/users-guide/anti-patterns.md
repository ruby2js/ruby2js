---
order: 9.3
title: Anti-Patterns
top_section: User's Guide
category: users-guide-anti-patterns
next_page_order: 10
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

Runtime method definition isn't supported:

```ruby
# Won't work
%w[red green blue].each do |color|
  define_method("#{color}?") { @color == color }
end
```

**Alternative:** Define methods explicitly:

```ruby
def red?; @color == "red"; end
def green?; @color == "green"; end
def blue?; @color == "blue"; end
```

### `eval` and `instance_eval`

Code evaluation at runtime doesn't translate:

```ruby
# Won't work
eval("x + y")
instance_eval(&block)
```

**Alternative:** Restructure to avoid dynamic evaluation.

### `send` and `public_send`

Dynamic method dispatch is problematic:

```ruby
# Won't work reliably
obj.send(method_name, *args)
```

**Alternative:** Use explicit conditionals or a dispatch table:

```ruby
case method_name
when :add then obj.add(*args)
when :remove then obj.remove(*args)
end
```

## Type Introspection

### `is_a?`, `kind_of?`, `instance_of?`

Ruby's type checking doesn't translate directly:

```ruby
# Problematic
if obj.is_a?(Array)
  # ...
end
```

**Alternatives:**

```ruby
# Use JavaScript's Array.isArray
if Array.isArray(obj)
  # ...
end

# Or duck typing
if obj.respond_to?(:each)
  # ...
end
```

If you need these methods in Ruby but not JS:

```ruby
def is_a?(klass) # Pragma: skip
  # Ruby-only implementation
end
```

### `respond_to?`

Method existence checks are Ruby-specific:

```ruby
# Problematic
if obj.respond_to?(:save)
  obj.save
end
```

**Alternatives:**

```ruby
# Check for property existence (for known patterns)
if 'save' in obj  # JavaScript: key in object
  obj.save
end

# Or skip the method definition entirely
def respond_to?(method) # Pragma: skip
  # ...
end
```

### `class` and `superclass`

These have different meanings in JS:

```ruby
# Ruby
obj.class        # => SomeClass
obj.class.name   # => "SomeClass"

# JavaScript equivalent
obj.constructor       # => function
obj.constructor.name  # => "SomeClass"
```

Use `# Pragma: proto` if you need constructor access:

```ruby
obj.class # Pragma: proto
# => obj.constructor
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

`include` and `extend` don't translate directly:

```ruby
# Problematic
module Loggable
  def log(msg)
    puts msg
  end
end

class MyClass
  include Loggable
end
```

**Alternative:** Use composition or explicit delegation:

```ruby
class MyClass
  def initialize
    @logger = Logger.new
  end

  def log(msg)
    @logger.log(msg)
  end
end
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

| Feature | Status | Alternative |
|---------|--------|-------------|
| Classes, methods | ✅ Safe | |
| Blocks as lambdas | ✅ Safe | |
| Arrays, hashes | ✅ Safe | Mind `<<`, `.dup` |
| String interpolation | ✅ Safe | |
| Control flow | ✅ Safe | Except `retry`, `redo` |
| `method_missing` | ❌ Avoid | Explicit methods |
| `define_method` | ❌ Avoid | Explicit methods |
| `eval` | ❌ Avoid | Restructure |
| `is_a?`, `kind_of?` | ⚠️ Pragma skip | Duck typing |
| `respond_to?` | ⚠️ Pragma skip | Property checks |
| Symbols | ⚠️ Work as strings | |
| `include`/`extend` | ❌ Avoid | Composition |
| `retry`/`redo` | ❌ Avoid | Explicit loops |
| `catch`/`throw` | ❌ Avoid | Break/return |

## See Also

- [Patterns](/docs/users-guide/patterns) - Recommended patterns that work well
- [Pragmas](/docs/users-guide/pragmas) - Fine-grained control for edge cases
- [Conversion Details](/docs/conversion-details) - How Ruby constructs translate
