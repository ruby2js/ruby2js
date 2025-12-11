---
order: 9.4
title: JavaScript-First Development
top_section: User's Guide
category: users-guide-js-first
next_page_order: 10
---

# JavaScript-First Development

This guide covers writing Ruby code that's designed primarily to run as JavaScript, with optional Ruby execution for testing. This is different from "dual-target" code—here, **JavaScript is the primary target**.

This approach is ideal for:
- Browser applications and SPAs
- Node.js tools and libraries
- Browser extensions
- Self-hosting transpilers (like Ruby2JS itself)

{% toc %}

## Why JavaScript-First?

**Try it** — this example uses JavaScript APIs directly:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "functions"]
}'></div>

```ruby
export class Counter
  def initialize(element)
    @element = element
    @count = 0
    @element.addEventListener('click') { increment }
  end

  def increment
    @count += 1
    @element.textContent = "Count: #{@count}"
  end
end
```

Ruby2JS produces idiomatic JavaScript without a runtime. Combined with Ruby's cleaner syntax, you get:

- **Better syntax** - blocks, unless, guard clauses, implicit returns
- **Familiar patterns** - Ruby's object model maps well to JavaScript
- **Full JS access** - call any JavaScript API directly
- **No runtime overhead** - output is plain JavaScript
- **Better tooling** - use Ruby editors, formatters, and linters

## Key Differences from Dual-Target

| Aspect | Dual-Target | JavaScript-First |
|--------|-------------|------------------|
| Primary runtime | Both Ruby and JS | JavaScript only |
| Ruby execution | Production use | Testing only |
| JS APIs | Avoided or wrapped | Used directly |
| Ruby-only code | Minimized | Skipped liberally |
| Pragmas | Occasional | Common |

## Calling JavaScript APIs

### Direct API Access

Call JavaScript APIs as if they were Ruby methods:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "functions"]
}'></div>

```ruby
# DOM manipulation
element = document.getElementById('app')
element.addEventListener('click') { |e| handle(e) }
element.classList.add('active')

# Console and debugging
console.log('Debug:', data)

# Modern JS APIs
data = await fetch('/api/users').then { |r| r.json() }
```

### Constructor Calls

JavaScript's `new` keyword works naturally:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
date = Date.new
map = Map.new
url = URL.new(path, base_url)
view = DataView.new(buffer)
arr = Uint8Array.new(buffer, offset, length)
```

### Global Objects

Access `globalThis`, `window`, `document`, etc.:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
# Browser globals
location = window.location.href
document.body.style.background = 'red'

# Node.js globals
args = process.argv[2..-1]
debug = process.env.DEBUG

# Universal global
globalThis.MyLib = my_module
```

## Module System

### ES Module Imports

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "functions"]
}'></div>

```ruby
# Default import
import React, from: 'react'

# Named imports
import [useState, useEffect], from: 'react'

# Namespace import
import "*", as: Prism, from: '@ruby/prism'

# Side-effect import
import 'styles.css'

# Dynamic import
mod = await import('./module.js')
```

### ES Module Exports

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "functions"]
}'></div>

```ruby
export class MyClass
  def process(x)
    x * 2
  end
end

export def helper(x)
  x * 2
end

export DEFAULT_VALUE = 42
```

## Async/Await

Ruby2JS supports async/await naturally:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "functions"]
}'></div>

```ruby
async def fetch_user(id)
  response = await fetch("/api/users/#{id}")
  await response.json()
end

async def load_data
  # Parallel fetches
  users, posts = await Promise.all([
    fetch_user(1),
    fetch_posts()
  ])
  { users: users, posts: posts }
end
```

## Patterns for JavaScript-First Code

### Entry Point Guard

For modules that can be both imported and run directly:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "functions"]
}'></div>

```ruby
import [fileURLToPath], from: 'url'

def main
  console.log("Running as CLI")
end

# Only run when executed directly (not imported)
if process.argv[1] == fileURLToPath(import.meta.url)
  main()
end
```

### Optional Chaining

Use Ruby's safe navigation operator:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
# Ruby's &. becomes JavaScript's ?.
name = user&.profile&.name
count = data&.items&.length
```

### Nullish Coalescing

Use pragmas to control `||` vs `??`:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
# When 0 or "" are valid values, use ??
count ||= 0 # Pragma: ??

# When you need falsy-check (false, 0, ""), use ||
enabled ||= true # Pragma: logical
```

### Property Access vs Method Calls

Ruby2JS uses parentheses to distinguish:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
# No parens = property access
len = obj.length
first = arr.first

# Empty parens = method call
item = list.pop()
result = obj.process()

# Parens with args = always method call
obj.set(42)
```

### Skipping Ruby-Only Code

Use `# Pragma: skip` liberally:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "functions", "pragma"]
}'></div>

```ruby
require 'json' # Pragma: skip

def to_sexp # Pragma: skip
  # Ruby debugging only
end

def process(data)
  data.map { |x| x * 2 }
end
```

### Type Disambiguation

When Ruby2JS can't infer types:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions", "pragma"]
}'></div>

```ruby
# Array operations
items << item # Pragma: array

# Hash/Object operations
options.each { |k, v| process(k, v) } # Pragma: entries

# First-class functions
handler.call(args) # Pragma: method
```

## Real Example: Self-Hosted Ruby2JS

The Ruby2JS project uses this approach for its browser bundle. Here's a simplified example:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "functions"]
}'></div>

```ruby
import "*", as: Prism, from: '@ruby/prism'

export class SourceBuffer
  def initialize(source, file)
    @source = source
    @name = file || '(eval)'
    @lineOffsets = [0]
    i = 0
    while i < source.length
      @lineOffsets.push(i + 1) if source[i] == "\n"
      i += 1
    end
  end

  attr_reader :source, :name

  def lineForPosition(pos)
    idx = @lineOffsets.findIndex { |offset| offset > pos }
    idx == -1 ? @lineOffsets.length : idx
  end
end
```

Notice:
- Direct use of JavaScript APIs (`findIndex`, `push`)
- ES module syntax (`import`, `export`)
- Ruby control flow (`while`, `if` modifier)
- Instance variables as properties

## Bundling with Require Filter

For larger projects, split code across files and use the Require filter:

```ruby
# bundle.rb - entry point
require_relative 'runtime'
require_relative 'parser'
require_relative 'converter'

export [Parser, Converter]
```

The Require filter inlines these files, producing a single bundled JavaScript module.

### Skip External Dependencies

```ruby
require 'json' # Pragma: skip
require_relative 'helper'  # This gets inlined
```

## Filter Configuration

Recommended filters for JavaScript-first development:

```ruby
Ruby2JS.convert(source,
  eslevel: 2022,
  comparison: :identity,      # == becomes ===
  underscored_private: true,  # @foo becomes this._foo
  filters: [
    Ruby2JS::Filter::Pragma,    # Line-level control
    Ruby2JS::Filter::Require,   # File inlining
    Ruby2JS::Filter::Functions, # Ruby→JS method mapping
    Ruby2JS::Filter::Return,    # Implicit returns
    Ruby2JS::Filter::ESM        # ES modules
  ]
)
```

## Common Gotchas

### `.to_s` vs `.toString()`

The functions filter converts `.to_s` to `.toString()`. When you need the literal `.to_s` method:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
# This becomes .toString()
str = obj.to_s

# Use bang to keep as .to_s()
str = obj.to_s!
```

### Arrow Functions and `this`

Blocks become arrow functions, which capture `this` lexically:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions", "pragma"]
}'></div>

```ruby
# Arrow function - this is outer scope
element.on("click") { handle(this) }

# Traditional function - this is the element
element.on("click") { handle(this) } # Pragma: noes2015
```

### Import Hoisting

Ruby2JS hoists imports to the top of the output. Be aware when inlining multiple files—duplicate imports may appear. This is a known area for improvement.

### Property Getters

Methods without parentheses become getters:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
class Token
  def initialize(text)
    @text = text
  end

  # Becomes a getter, accessed as: token.text
  def text
    @text
  end

  # Empty parens = method call: token.getText()
  def getText()
    @text
  end
end
```

## Testing JavaScript-First Code

You can still run tests in Ruby:

```ruby
# test_helper.rb
require 'minitest/autorun'

# Mock JS APIs for Ruby testing
module GlobalMocks
  def console
    @console ||= OpenStruct.new(log: ->(*args) { puts args.join(' ') })
  end
end

# Your test file
class MyClassTest < Minitest::Test
  include GlobalMocks

  def test_something
    obj = MyClass.new
    assert_equal "expected", obj.compute
  end
end
```

## See Also

- [ESM Filter](/docs/filters/esm) - ES module syntax
- [Require Filter](/docs/filters/require) - File bundling
- [Functions Filter](/docs/filters/functions) - Ruby→JS mappings
- [Pragmas](/docs/users-guide/pragmas) - Line-level control
