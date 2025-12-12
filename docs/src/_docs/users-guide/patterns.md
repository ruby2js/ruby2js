---
order: 9.1
title: Patterns
top_section: User's Guide
category: users-guide-patterns
next_page_order: 9.2
---

# Patterns

This guide covers patterns that work well when writing Ruby code for JavaScript. These patterns apply whether you're writing dual-target code (runs in both Ruby and JavaScript) or JavaScript-only code.

{% toc %}

## Classes and Methods

### Basic Classes

Classes translate naturally:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

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

Note: With ES2022, instance variables become private fields (`#name`). With older ES levels or `underscored_private: true`, they use underscore prefix (`_name`).

### Private Methods

Mark private methods and they'll be prefixed appropriately in JavaScript. With ES2022, private methods use the `#` prefix (true JavaScript private methods). With older ES levels or `underscored_private: true`, they use `_` prefix:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
class Calculator
  def calculate(x)
    validate(x)
    process(x)
  end

  private

  def validate(x)
    raise "Invalid" unless x > 0
  end

  def process(x)
    x * 2
  end
end
```

Calls to private methods (with or without explicit `self`) are automatically prefixed to match the method definition.

### Method Calls vs Property Access

Ruby2JS uses parentheses to distinguish between property access and method calls. **This is one of the most important concepts.**

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
# No parens = property access (getter)
len = obj.length
first = arr.first

# Empty parens = method call
item = list.pop()
result = obj.process()

# Parens with args = always method call
obj.set(42)
```

**This applies to your own methods too.** When defining methods:
- `def foo` — becomes a getter, accessed as `obj.foo`
- `def foo()` — becomes a method, called as `obj.foo()`

When calling methods (especially in callbacks):

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
class Widget
  def setup()
    # WRONG: increment without parens just returns the getter
    # @button.addEventListener('click') { increment }

    # RIGHT: use parens to actually call the method
    @button.addEventListener('click') { increment() }
  end

  def increment()
    @count += 1
  end
end
```

## Data Structures

### Arrays

Most array operations translate directly:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
arr = [1, 2, 3]
arr.push(4)
arr.length
doubled = arr.map { |x| x * 2 }
big = arr.select { |x| x > 1 }
found = arr.find { |x| x > 1 }
```

**Watch out:** The `<<` operator needs disambiguation:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions", "pragma"]
}'></div>

```ruby
items = [1, 2, 3]

# Solution 1: Use push explicitly
items.push(4)

# Solution 2: Use pragma for one-off cases
items << 5 # Pragma: array
```

### Hashes/Objects

Ruby hashes become JavaScript objects:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
options = { name: "test", count: 42 }
name = options[:name]
keys = options.keys()
values = options.values()
```

### Rich Object Literals

JavaScript objects can have getters, setters, and methods—richer than Ruby hashes. Ruby2JS supports this via anonymous classes:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
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

This pattern is useful when you need a one-off object with behavior, not just data.

### Hash Iteration

Ruby's `.each` on hashes needs special handling:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
hash = { a: 1, b: 2, c: 3 }

# Use the entries pragma for key-value iteration
hash.each { |k, v| console.log(k, v) } # Pragma: entries
```

## Control Flow

### Conditionals

Standard conditionals work as expected:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
def classify(x)
  if x > 10
    "large"
  elsif x > 5
    "medium"
  else
    "small"
  end
end
```

### Unless

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
def process(item)
  return if item.nil?

  unless item.empty?
    handle(item)
  end
end
```

## Blocks and Lambdas

### Blocks

Blocks become arrow functions by default. Try editing the code below:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
items = [1, 2, 3, 4, 5]

doubled = items.map { |x| x * 2 }
evens = items.select { |x| x % 2 == 0 }
sum = items.reduce(0) { |acc, x| acc + x }
```

### When You Need `this`

Arrow functions capture `this` lexically. For DOM event handlers where you need dynamic `this`:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions", "pragma"]
}'></div>

```ruby
# Arrow function - this is lexical (outer scope)
element.on("click") { handle(this) }

# Traditional function - this is the element
element.on("click") { handle(this) } # Pragma: noes2015
```

### Lambdas

Lambdas with stabby syntax work well:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
double = ->(x) { x * 2 }
result = double.call(21)

add = ->(a, b) { a + b }
sum = add.call(1, 2)
```

## Variable Declarations

### Local Variables

Ruby2JS tracks variable declarations and emits `let` appropriately:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
x = 1       # First use: let x = 1
x = 2       # Reassignment: x = 2
y = x + 1   # let y = x + 1
```

### Constants

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
MAX_SIZE = 100
PI = 3.14159
```

## Working with First-Class Functions

When you have functions stored in variables:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions", "pragma"]
}'></div>

```ruby
handlers = {
  click: ->(e) { console.log("clicked", e) },
  hover: ->(e) { console.log("hovered", e) }
}

handler = handlers[:click]
handler.call(event) # Pragma: method
```

## String Operations

### Interpolation

String interpolation translates to template literals:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
name = "World"
greeting = "Hello, #{name}!"
multi = "Count: #{1 + 2 + 3}"
```

### Common Methods

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
str = "Hello World"

len = str.length
upper = str.upcase
lower = str.downcase
has_o = str.include?("o")
starts = str.start_with?("Hello")
ends = str.end_with?("World")
replaced = str.gsub(/o/, "0")
```

## Modules

Ruby's `module` keyword works for namespacing in both Ruby and JavaScript:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
module Utils
  def self.format(str)
    str.upcase
  end
end
```

Modules with constants use an IIFE pattern:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
module Config
  VERSION = "1.0"

  def self.load
    # ...
  end
end
```

Nested modules work too:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
module App
  module Models
    class User
    end
  end
end
```

## Organizing Files

For dual-target code, the **require** filter bundles multiple files:

```ruby
# main.rb
require_relative 'utils'
require_relative 'config'

# Works in Ruby, inlined for JavaScript
```

This pattern works in Ruby natively and produces a single bundled JavaScript file. See [Require Filter](/docs/filters/require) for details.

For JavaScript-only code, use ESM imports instead. See [JavaScript-Only](/docs/users-guide/javascript-only).

## Ruby-Only Code

### Skipping Code

Use `# Pragma: skip` to exclude Ruby-only code from JS output:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
require 'json' # Pragma: skip

def ruby_only_helper # Pragma: skip
  # This method won't appear in JS
end

def works_in_both
  "Hello from Ruby or JS!"
end
```

## Recommended Filters

The most commonly used filters:

- **functions** - Ruby method → JS method mappings (`.select` → `.filter`, etc.)
- **pragma** - Line-level control via comments
- **return** - Implicit returns in methods
- **require** - Bundle multiple files (for dual-target code)

For JavaScript-only code, add:
- **esm** - ES module imports/exports

The `preset` option enables sensible defaults:

```ruby
# ruby2js: preset
```

See [Options](/docs/options) for configuration details.

## Summary

| Pattern | Works Well | Needs Care |
|---------|------------|------------|
| Classes | ✓ Directly translates | |
| Methods | ✓ Normal methods | Parens matter |
| Modules | ✓ Namespacing | |
| Private methods | ✓ `#` prefix (ES2022) or `_` prefix | |
| Arrays | ✓ Most operations | `<<` needs pragma |
| Hashes | ✓ Symbol keys | `.each` needs pragma |
| Blocks | ✓ Arrow functions | Use noes2015 for `this` |
| Strings | ✓ Interpolation | |
| Control flow | ✓ if/unless/case | |
| Type checks | | Avoid `is_a?` |

See [Anti-Patterns](/docs/users-guide/anti-patterns) for patterns to avoid, [Pragmas](/docs/users-guide/pragmas) for fine-grained control, and [JavaScript-Only](/docs/users-guide/javascript-only) for ESM, async/await, and JavaScript APIs.
