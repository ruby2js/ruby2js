---
order: 9.4
title: JavaScript-Only Development
top_section: User's Guide
category: users-guide-js-only
next_page_order: 10
---

# JavaScript-Only Development

This guide covers writing Ruby code that's designed exclusively to run as JavaScript. This is different from "dual-target" code—here, **JavaScript is the only target** and the code won't run in Ruby.

This approach is ideal for:
- Browser applications and SPAs
- Node.js tools and libraries
- Browser extensions
- CLI tools, runtimes, and scaffolding for self-hosted transpilers

{% toc %}

## Why JavaScript-Only?

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
    @element.addEventListener('click') { increment() }
  end

  def increment()
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

| Aspect          | Dual-Target        | JavaScript-Only   |
| --------------- | ------------------ | ----------------- |
| Primary runtime | Both Ruby and JS   | JavaScript only   |
| Ruby execution  | Production use     | None              |
| JS APIs         | Avoided or wrapped | Used directly     |
| Ruby-only code  | Minimized          | Skipped liberally |
| Pragmas         | Occasional         | Common            |

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

JavaScript's `new` keyword works naturally. Ruby2JS preserves whether you use parentheses—`new Date` vs `new Date()`. While functionally equivalent for no-argument constructors, parentheses affect operator precedence (e.g., `new Date().getTime()` works but `new Date.getTime()` tries to construct `Date.getTime`):

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
date = Date.new       # new Date
date = Date.new()     # new Date()
url = URL.new(path, base_url)
arr = Uint8Array.new(buffer, offset, length)
```

Note: Some JavaScript built-ins have special rules. Ruby2JS knows that `Symbol()` must not use `new`, while `Promise`, `Map`, and `Set` require it. Call `Symbol("name")` directly without `.new`.

### JavaScript Operators

The functions filter provides direct access to JavaScript operators:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
# typeof operator
type = typeof(value)

# debugger statement
debugger
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

## First-Class Functions

In JavaScript, functions are first-class citizens and can be called directly with parentheses. In Ruby, procs and lambdas require `.call()` or `.()`. For JavaScript-only code, you can skip the Ruby ceremony and call functions directly:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["functions"]
}'></div>

```ruby
# Lambda becomes arrow function
double = ->(x) { x * 2 }

# Ruby style (works but unnecessary)
result = double.call(5)
result = double.(5)

# JavaScript style (preferred for JS-only)
result = double(5)
```

All three Ruby syntaxes (`proc`, `lambda`, `->`) become JavaScript arrow functions. For JavaScript-only code, prefer calling them directly with parentheses.

## Patterns for JavaScript-Only Code

For common patterns (classes, methods, blocks, data structures), see [Patterns](/docs/users-guide/patterns). This section covers JavaScript-specific patterns.

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
  "filters": ["functions", "pragma"]
}'></div>

```ruby
# When 0 or "" are valid values, use ??
count ||= 0 # Pragma: ??

# When you need falsy-check (false, 0, ""), use ||
enabled ||= true # Pragma: logical
```

### Type Disambiguation

When Ruby2JS can't infer types:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["pragma", "functions"]
}'></div>

```ruby
# Array operations
items << item # Pragma: array

# Hash/Object operations
options.each { |k, v| process(k, v) } # Pragma: entries

# First-class functions
handler.call(args) # Pragma: method
```

## Real Example: Self-Hosted CLI

The Ruby2JS project uses this approach for its self-hosted CLI and runtime scaffolding. Here's a simplified example from the source buffer implementation:

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

Recommended filters for JavaScript-only development:

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

Blocks become arrow functions, which capture `this` lexically. For DOM event handlers where you need dynamic `this`, use `# Pragma: noes2015`. See [When You Need `this`](/docs/users-guide/patterns#when-you-need-this) in Patterns.

### Import Hoisting

Ruby2JS hoists imports to the top of the output. Be aware when inlining multiple files—duplicate imports may appear. This is a known area for improvement.

### Property Getters

Methods without parentheses become getters. See [Method Calls vs Property Access](/docs/users-guide/patterns#method-calls-vs-property-access) in Patterns.

## See Also

- [Patterns](/docs/users-guide/patterns) - Common patterns for all Ruby2JS code
- [ESM Filter](/docs/filters/esm) - ES module syntax
- [Require Filter](/docs/filters/require) - File bundling
- [Functions Filter](/docs/filters/functions) - Ruby→JS mappings
- [Pragmas](/docs/users-guide/pragmas) - Line-level control
