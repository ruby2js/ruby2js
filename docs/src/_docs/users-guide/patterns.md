---
order: 9.1
title: Patterns
top_section: User's Guide
category: users-guide-patterns
next_page_order: 9.2
---

# Dual-Target Patterns

This guide covers patterns that work well when writing Ruby code that will run both natively and as transpiled JavaScript.

{% toc %}

## Classes and Methods

### Basic Classes

Classes translate naturally:

```ruby
class Greeter
  def initialize(name)
    @name = name
  end

  def greet
    "Hello, #{@name}!"
  end
end
```

```javascript
class Greeter {
  constructor(name) {
    this._name = name
  }

  get greet() {
    return `Hello, ${this._name}!`
  }
}
```

Note: Instance variables become underscore-prefixed properties by default (configurable via `underscored_private` option).

### Private Methods

Mark private methods and they'll be prefixed with underscore in JavaScript:

```ruby
class Calculator
  def calculate(x)
    validate(x)
    process(x)
  end

  private

  def validate(x)
    raise "Invalid" unless x.is_a?(Numeric)
  end

  def process(x)
    x * 2
  end
end
```

### Method Calls vs Property Access

Ruby2JS distinguishes between method calls and property access based on parentheses:

```ruby
# No parens, no args - becomes property access in JS
obj.value     # => obj.value
obj.length    # => obj.length
arr.first     # => arr.first (with polyfill) or arr[0]

# No parens, with args - becomes method call in JS
obj.set 42    # => obj.set(42)
puts "hello"  # => console.log("hello")

# Empty parens - becomes method call in JS
obj.process() # => obj.process()

# Parens with args - becomes method call in JS
obj.set(42)   # => obj.set(42)
```

## Data Structures

### Arrays

Most array operations translate directly:

```ruby
arr = [1, 2, 3]
arr.push(4)           # => arr.push(4)
arr.length            # => arr.length
arr.map { |x| x * 2 } # => arr.map(x => x * 2)
arr.select { |x| x > 1 }  # => arr.filter(x => x > 1)
arr.find { |x| x > 1 }    # => arr.find(x => x > 1)
```

**Watch out:** The `<<` operator needs disambiguation:

```ruby
# Could be Array#<< or String#<<
items << item  # Ruby2JS may not know the type

# Solution 1: Use push explicitly
items.push(item)

# Solution 2: Use pragma for one-off cases
items << item # Pragma: array
```

### Hashes/Objects

Ruby hashes become JavaScript objects:

```ruby
options = { name: "test", count: 42 }
options[:name]        # => options.name or options["name"]
options.keys          # => Object.keys(options)
options.values        # => Object.values(options)
```

**Type disambiguation for methods that exist on both Hash and Array:**

```ruby
# .dup behavior differs
arr.dup   # => [...arr] (spread) or arr.slice()
hash.dup  # => {...hash} (spread)

# Use pragma when type is ambiguous
data.dup # Pragma: hash
```

### Rich Object Literals

JavaScript objects can have getters, setters, and methods—richer than Ruby hashes. Ruby2JS supports this via anonymous classes:

```ruby
# Ruby: anonymous class instance
obj = Class.new do
  def initialize
    @count = 0
  end

  def increment
    @count += 1
  end

  def count
    @count
  end
end.new
```

```javascript
// JavaScript: object literal with methods
let obj = {
  _count: 0,

  increment() {
    return this._count++
  },

  get count() {
    return this._count
  }
}
```

This pattern is useful when you need a one-off object with behavior, not just data.

### Hash Iteration

Ruby's `.each` on hashes needs special handling:

```ruby
# Ruby: iterates key-value pairs
hash.each { |k, v| process(k, v) }

# JavaScript equivalent needs Object.entries()
# Use the entries pragma:
hash.each { |k, v| process(k, v) } # Pragma: entries
```

This generates:
```javascript
Object.entries(hash).forEach(([k, v]) => process(k, v))
```

## Control Flow

### Conditionals

Standard conditionals work as expected:

```ruby
if condition
  do_something
elsif other
  do_other
else
  do_default
end
```

### Ternary Expressions

```ruby
result = condition ? value_a : value_b
```

### Unless

```ruby
unless done?
  continue_work
end
# => if (!done()) { continueWork() }
```

## Blocks and Lambdas

### Blocks

Blocks become arrow functions by default:

```ruby
items.each { |item| process(item) }
# => items.forEach(item => process(item))

items.map { |x| x * 2 }
# => items.map(x => x * 2)
```

### When You Need `this`

Arrow functions capture `this` lexically. For DOM event handlers where you need dynamic `this`:

```ruby
element.on("click") { handle_click(this) } # Pragma: noes2015
# => element.on("click", function() { handleClick(this) })
```

### Lambdas

Lambdas with stabby syntax work well:

```ruby
double = ->(x) { x * 2 }
double.call(21)  # => double(21)
```

## Variable Declarations

### Local Variables

Ruby2JS tracks variable declarations and emits `let` appropriately:

```ruby
x = 1       # First use: let x = 1
x = 2       # Reassignment: x = 2
y = x + 1   # let y = x + 1
```

### Constants

```ruby
MAX_SIZE = 100  # => const MAX_SIZE = 100
```

## Working with First-Class Functions

When you have functions stored in variables:

```ruby
# Ruby: handlers is a hash of procs
handler = handlers[event_type]
handler.call(data)

# For JS, use the method pragma to invoke directly:
handler.call(data) # Pragma: method
# => handler(data)
```

## String Operations

### Interpolation

String interpolation translates to template literals:

```ruby
"Hello, #{name}!"
# => `Hello, ${name}!`
```

### Common Methods

```ruby
str.length        # => str.length
str.upcase        # => str.toUpperCase()
str.downcase      # => str.toLowerCase()
str.include?("x") # => str.includes("x")
str.start_with?("x")  # => str.startsWith("x")
str.end_with?("x")    # => str.endsWith("x")
str.gsub(/a/, "b")    # => str.replace(/a/g, "b")

# join handles the Ruby/JS difference automatically:
arr.join          # => arr.join("") (Ruby default is "", JS default is ",")
arr.join(",")     # => arr.join(",")
```

## Type Checking

### Avoiding `is_a?` and `respond_to?`

These methods are Ruby-specific. Instead:

```ruby
# Instead of:
if obj.is_a?(Array)

# Use duck typing or explicit checks:
if Array.isArray(obj)  # when targeting JS

# Or structure code to avoid type checks
```

### The `respond_to?` Pattern

If you must check for method existence:

```ruby
# Ruby-only method, skip in JS:
def respond_to?(method) # Pragma: skip
  # Ruby implementation
end
```

## Module Organization

### Exports

Using the ESM filter:

```ruby
export class MyClass
  # ...
end

export def helper_method
  # ...
end

export DEFAULT_VALUE = 42
```

### Imports

```ruby
import React, { useState, useEffect } from 'react'
import MyModule from './my_module'
```

## Ruby-Only Code

### Skipping Code

Use `# Pragma: skip` to exclude Ruby-only code from JS output:

```ruby
require 'some_gem' # Pragma: skip

def ruby_only_helper # Pragma: skip
  # This entire method won't appear in JS
end

# For class methods:
def self.from_file(path) # Pragma: skip
  # File I/O - Ruby only
end
```

### Conditional Blocks

For larger blocks of Ruby-only code:

```ruby
unless defined?(RUBY2JS_SELFHOST) # Pragma: skip
  # This entire block is Ruby-only
  require 'some_ruby_lib'

  def complex_ruby_method
    # ...
  end
end
```

## Recommended Filter Combination

For dual-target code, we recommend:

```ruby
# ruby2js: preset

# Or explicitly:
# ruby2js: filters: functions, esm, pragma, return
```

The `preset` mode enables:
- **functions** - Ruby method → JS method mappings
- **esm** - ES module imports/exports
- **pragma** - Line-level control via comments (e.g., `# Pragma: ??` for nullish coalescing)
- **return** - Implicit returns in methods
- ES2022 features
- Identity comparison (`==` → `===`)

## Summary

| Pattern | Works Well | Needs Care |
|---------|------------|------------|
| Classes | ✓ Directly translates | |
| Methods | ✓ Normal methods | Private with underscore |
| Arrays | ✓ Most operations | `<<` needs pragma |
| Hashes | ✓ Symbol keys | `.each` needs pragma |
| Blocks | ✓ Arrow functions | Use noes2015 for `this` |
| Strings | ✓ Interpolation | |
| Control flow | ✓ if/unless/case | |
| Type checks | | Avoid `is_a?` |

See [Anti-Patterns](/docs/users-guide/anti-patterns) for patterns to avoid, and [Pragmas](/docs/users-guide/pragmas) for fine-grained control.
