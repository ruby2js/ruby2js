---
order: 9.2
title: Pragmas in Practice
top_section: User's Guide
category: users-guide-pragmas
next_page_order: 9.3
---

# Pragmas in Practice

Pragmas provide line-level control over transpilation. They're implemented as Ruby comments, so they have **no effect when code runs in Ruby**—making them perfect for dual-target development.

{% toc %}

## How Pragmas Work

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
# Without pragma: ||= becomes ??= in value contexts
x ||= default

# With pragma: force nullish coalescing
y ||= default # Pragma: ??

# With pragma: force logical OR
z ||= default # Pragma: logical
```

- In **Ruby**: The comment is ignored, `||=` runs normally
- In **Ruby2JS**: The pragma triggers the specified output

This is the key insight: pragmas let you fine-tune JavaScript output without affecting Ruby behavior.

## Quick Reference

| Pragma | Purpose | Example |
|--------|---------|---------|
| `skip` | Remove from JS output | `require 'gem' # Pragma: skip` |
| `array` | Treat as Array | `items << x # Pragma: array` |
| `hash` | Treat as Hash | `data.dup # Pragma: hash` |
| `entries` | Use Object.entries() | `h.each {...} # Pragma: entries` |
| `method` | Direct invocation | `fn.call(x) # Pragma: method` |
| `logical` or `\|\|` | Force `\|\|` | `x \|\|= y # Pragma: logical` |
| `??` or `nullish` | Force `??` | `x \|\|= y # Pragma: ??` |
| `noes2015` or `function` | Traditional function | `{ this } # Pragma: noes2015` |

For complete documentation, see the [Pragma Filter](/docs/filters/pragma) reference.

## Common Use Cases

### Excluding Ruby-Only Code

The most common pragma—skip code that only makes sense in Ruby:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
# Skip requires that are Ruby-specific
require 'prism' # Pragma: skip

# Skip methods that don't translate
def respond_to?(method) # Pragma: skip
  super || @handlers.key?(method)
end

def to_sexp # Pragma: skip
  # Ruby debugging method
end

# Code that runs in both
def process(x)
  x * 2
end
```

### Type Disambiguation

When Ruby2JS can't infer whether something is an Array or Hash:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
items = []
config = {}

# The << operator exists on both Array and String
items << "new_item" # Pragma: array

# .dup behaves differently for Array vs Hash
backup = config.dup # Pragma: hash
```

### Hash Iteration

Ruby's hash iteration doesn't map directly to JavaScript:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
options = { a: 1, b: 2, c: 3 }

# Ruby: each yields [key, value] pairs
# JavaScript needs Object.entries()
options.each { |k, v| console.log(k, v) } # Pragma: entries

# Same for select/reject on hashes
big = options.select { |k, v| v > 1 } # Pragma: entries
```

### First-Class Functions

When storing functions in variables:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
# handlers is a hash of callable procs/lambdas
handlers = {
  add: ->(a, b) { a + b },
  multiply: ->(a, b) { a * b }
}

handler = handlers[:add]
result = handler.call(2, 3) # Pragma: method
```

### OR Semantics

Ruby's `||` treats only `nil` and `false` as falsy. JavaScript's `||` also treats `0`, `""`, and `NaN` as falsy.

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
# When 0 or "" are valid values, use nullish coalescing
count ||= 0 # Pragma: ??

# When you need standard JS || behavior (e.g., for false)
enabled ||= true # Pragma: logical
```

### Dynamic `this` in Callbacks

Arrow functions capture `this` lexically. DOM handlers often need dynamic `this`:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
# Arrow function - this is lexical (often wrong for DOM)
element.on("click") { clicked(this) }

# Traditional function - this is the element
element.on("click") { clicked(this) } # Pragma: noes2015
```

## Real-World Examples

These examples come from Ruby2JS's own self-hosting codebase.

### Converter Initialization

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
# @vars is a hash, needs explicit .dup treatment
vars = {}
@ast, @comments, @vars = ast, comments, vars.dup # Pragma: hash
```

### Variable Tracking

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
@vars = { a: :pending, b: true, c: :pending }

# Hash operations need entries pragma for iteration
vars = @vars.select { |key, value| value == :pending }.keys() # Pragma: entries
```

### Handler Invocation

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
# handler is a proc, call it directly as a function
handler = ->(x, y) { x + y }
result = handler.call(1, 2) # Pragma: method
```

### Skipping Code Blocks

The skip pragma works on both individual statements and entire block structures:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
# Skip individual statements
require 'parser/current' # Pragma: skip
require 'json' # Pragma: skip

# Skip entire conditional blocks
unless defined?(RUBY2JS_SELFHOST) # Pragma: skip
  require 'prism'
  def ruby_only_method; end
end

# Skip method definitions
def respond_to?(method) # Pragma: skip
  true
end

def shared_method
  "Works in both!"
end
```

### Multiple Pragmas

One line can have multiple pragmas, and they will all be applied:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
# logical + method work together
x ||= fn.call(y) # Pragma: logical # Pragma: method

# entries + hash work together for hash operations
result = options.select { |k, v| v > 0 }.keys() # Pragma: entries # Pragma: hash
```

## Best Practices

### Minimize Pragma Usage

Pragmas are powerful but create maintenance burden. Prefer:

1. **Alternative syntax** that works without pragmas
2. **Consistent patterns** across your codebase
3. **Pragmas only when necessary**

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
items = [1, 2, 3]

# Instead of: items << x # Pragma: array
# Consider: works without pragma
items.push(4)
```

### Document Complex Cases

When pragmas aren't self-explanatory, add context:

```ruby
# Use ?? because cache[key] could legitimately be 0 or ""
cached = cache[key] ||= compute(key) # Pragma: ??
```

### Group Related Pragmas

```ruby
# Ruby-only introspection methods
def is_a?(klass) # Pragma: skip
  # ...
end

def respond_to?(method) # Pragma: skip
  # ...
end

alias :kind_of? :is_a? # Pragma: skip
```

## Pragma Categories

| Category | Pragmas | When to Use |
|----------|---------|-------------|
| **Exclusion** | `skip` | Ruby-only code |
| **Type hints** | `array`, `hash`, `string` | Ambiguous operations |
| **Iteration** | `entries` | Hash `.each`, `.select`, `.map` |
| **Functions** | `method`, `noes2015` | Callables, DOM handlers |
| **Operators** | `??`, `logical`, `guard` | OR semantics, splat safety |

## See Also

- [Pragma Filter Reference](/docs/filters/pragma) - Complete pragma documentation
- [Polyfill Filter](/docs/filters/polyfill) - Runtime polyfills for Ruby methods
- [Functions Filter](/docs/filters/functions) - Inline method transformations
