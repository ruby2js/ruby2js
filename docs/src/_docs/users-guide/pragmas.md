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

```ruby
x ||= default # Pragma: ??
```

- In **Ruby**: The comment is ignored, `||=` runs normally
- In **Ruby2JS**: The pragma triggers nullish coalescing output (`??=`)

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

```ruby
# Skip requires that are Ruby-specific
require 'prism' # Pragma: skip
require_relative 'helper' # Pragma: skip

# Skip methods that don't translate
def respond_to?(method) # Pragma: skip
  super || @handlers.key?(method)
end

def to_sexp # Pragma: skip
  # Ruby debugging method
end

# Skip class methods for Ruby-specific operations
def self.from_yaml(path) # Pragma: skip
  YAML.load_file(path)
end
```

### Type Disambiguation

When Ruby2JS can't infer whether something is an Array or Hash:

```ruby
# The << operator exists on both Array and String
items << new_item # Pragma: array

# .dup behaves differently for Array vs Hash
config.dup # Pragma: hash

# .include? is different for Array vs Hash
seen.include?(key) # Pragma: hash
```

### Hash Iteration

Ruby's hash iteration doesn't map directly to JavaScript:

```ruby
# Ruby: each yields [key, value] pairs
options.each { |k, v| process(k, v) }

# JavaScript needs Object.entries()
options.each { |k, v| process(k, v) } # Pragma: entries

# Same for select/reject on hashes
options.select { |k, v| v > 0 } # Pragma: entries
```

### First-Class Functions

When storing functions in variables:

```ruby
# handlers is a hash of callable procs/lambdas
handler = handlers[event]
handler.call(args) # Pragma: method
# => handler(args)  instead of handler.call(args)
```

### OR Semantics

Ruby's `||` treats only `nil` and `false` as falsy. JavaScript's `||` also treats `0`, `""`, and `NaN` as falsy.

```ruby
# When 0 or "" are valid values, use nullish coalescing
count ||= 0 # Pragma: ??
# => count ??= 0  (preserves count if it's 0)

# When you need standard JS || behavior (e.g., for false)
enabled ||= true # Pragma: logical
# => enabled ||= true  (not ??=)
```

### Dynamic `this` in Callbacks

Arrow functions capture `this` lexically. DOM handlers often need dynamic `this`:

```ruby
# Arrow function - this is lexical (often wrong for DOM)
element.on("click") { clicked(this) }
# => element.on("click", () => clicked(this))

# Traditional function - this is the element
element.on("click") { clicked(this) } # Pragma: noes2015
# => element.on("click", function() { clicked(this) })
```

## Real-World Examples

These examples come from Ruby2JS's own self-hosting codebase.

### Converter Initialization

```ruby
# @vars is a hash, needs explicit .dup treatment
@ast, @comments, @vars = ast, comments, vars.dup # Pragma: hash
```

### Variable Tracking

```ruby
# Hash operations on @vars need entries pragma for iteration
@vars = Hash[@vars.map {|key, value| [key, true]}] # Pragma: entries
vars = @vars.select {|key, value| value == :pending}.keys() # Pragma: entries
```

### Handler Invocation

```ruby
# handler is a proc, call it directly as a function
handler.call(*ast.children) # Pragma: method
```

### Conditional Blocks

```ruby
# Entire block excluded from JS output
unless defined?(RUBY2JS_SELFHOST) # Pragma: skip
  require 'parser/current'

  def parse_with_comments(source)
    Parser::CurrentRuby.parse_with_comments(source)
  end
end
```

### Multiple Pragmas

One line can have multiple pragmas:

```ruby
result ||= walk.call(child) # Pragma: method # Pragma: logical
```

## Best Practices

### Minimize Pragma Usage

Pragmas are powerful but create maintenance burden. Prefer:

1. **Alternative syntax** that works without pragmas
2. **Consistent patterns** across your codebase
3. **Pragmas only when necessary**

```ruby
# Instead of:
items << x # Pragma: array

# Consider:
items.push(x)  # Works without pragma
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
