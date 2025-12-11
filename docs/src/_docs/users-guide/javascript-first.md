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

```ruby
# DOM manipulation
document.getElementById('app')
element.addEventListener('click') { |e| handle(e) }
element.classList.add('active')

# Console and debugging
console.log('Debug:', data)
console.error('Failed:', error)

# Modern JS APIs
data = await fetch('/api/users').then { |r| r.json() }
stored = localStorage.getItem('prefs')

# Node.js APIs
import "*", as: :fs, from: 'fs'
content = fs.readFileSync(path, 'utf-8')
```

### Constructor Calls

JavaScript's `new` keyword works naturally:

```ruby
# new ClassName(args) in JS
date = Date.new
map = Map.new
url = URL.new(path, import.meta.url)
view = DataView.new(buffer)
arr = Uint8Array.new(buffer, offset, length)
```

### Global Objects

Access `globalThis`, `window`, `document`, etc.:

```ruby
# Browser globals
window.location.href
document.body.style.background = 'red'

# Node.js globals
process.argv[2..-1]
process.env.DEBUG

# Universal global
globalThis.MyLib = my_module
```

## Module System

### ES Module Imports

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

```ruby
# Named exports
export class MyClass
  # ...
end

export def helper(x)
  x * 2
end

export DEFAULT_VALUE = 42

# Export list
export [MyClass, helper, DEFAULT_VALUE]

# Default export
export default MyComponent
```

## Async/Await

Ruby2JS supports async/await naturally:

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

```ruby
import [fileURLToPath], from: 'url'

# Module code here...

# Only run when executed directly (not imported)
if process.argv[1] == fileURLToPath(import.meta.url)
  main()
end
```

### Optional Chaining

Use Ruby's safe navigation operator:

```ruby
# Ruby: &.
user&.profile&.name

# Becomes JavaScript: ?.
# user?.profile?.name
```

### Nullish Coalescing

Use pragmas to control `||` vs `??`:

```ruby
# When 0 or "" are valid values, use ??
count ||= 0 # Pragma: ??

# When you need falsy-check (false, 0, ""), use ||
enabled ||= true # Pragma: logical
```

### Property Access vs Method Calls

Ruby2JS uses parentheses to distinguish:

```ruby
# No parens = property access
obj.length      # => obj.length
arr.first       # => arr[0] (with functions filter)

# Empty parens = method call
obj.process()   # => obj.process()
list.pop()      # => list.pop()

# Parens with args = always method call
obj.set(42)     # => obj.set(42)
```

### Skipping Ruby-Only Code

Use `# Pragma: skip` liberally:

```ruby
require 'json' # Pragma: skip

# Skip entire methods
def to_sexp # Pragma: skip
  # Ruby debugging only
end

# Skip conditional blocks
unless defined?(JS_RUNTIME) # Pragma: skip
  require 'parser/current'
  # Ruby-only setup...
end
```

### Type Disambiguation

When Ruby2JS can't infer types:

```ruby
# Array operations
items << item # Pragma: array
items.dup # Pragma: array

# Hash/Object operations
config.dup # Pragma: hash
options.each { |k, v| ... } # Pragma: entries

# First-class functions
handler.call(args) # Pragma: method
```

## Real Example: Self-Hosted Ruby2JS

The Ruby2JS project uses this approach for its browser bundle. Here's a simplified example:

```ruby
# lib/ruby2js/selfhost/runtime.rb
# This file is "Ruby-syntax JavaScript"

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

export async def initPrism
  @prismParse ||= await Prism.loadPrism()
  @prismParse
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

```ruby
# This becomes .toString()
obj.to_s

# Use bang to keep as .to_s()
obj.to_s!
```

### Arrow Functions and `this`

Blocks become arrow functions, which capture `this` lexically:

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

```ruby
class Token
  def text
    @text
  end
end

# Becomes a getter, accessed as: token.text (no parens)
```

To force method syntax:

```ruby
def text()  # Empty parens = method
  @text
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
