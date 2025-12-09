---
order: 9
title: Introduction
top_section: User's Guide
category: users-guide-intro
next_page_order: 9.1
---

# Dual-Target Ruby Development

Ruby2JS enables a powerful development pattern: write Ruby code that runs natively in Ruby **and** transpiles to JavaScript. This "dual-target" approach lets you maintain a single codebase that works in both environments.

{% toc %}

## Why Dual-Target?

### Use Cases

**Shared Business Logic**
: Validation rules, calculations, and data transformations can run on the server (Ruby) and client (JavaScript) from the same source.

**Isomorphic Applications**
: The same rendering or processing code works server-side and browser-side.

**Universal Libraries**
: Date handling, formatting, parsing utilities that work everywhere.

**Cross-Platform Tools**
: A CLI tool (Ruby) and browser interface (JavaScript) sharing core logic.

**Gradual Migration**
: Move functionality from Ruby to JavaScript incrementally.

### The Ruby2JS Approach

Unlike Opal (which compiles Ruby to JavaScript with a runtime), Ruby2JS produces **idiomatic JavaScript** that reads like hand-written code. This means:

- **Small output size** (~2.5MB vs ~24MB with Opal for equivalent functionality)
- **Debuggable output** - the JavaScript looks like JavaScript
- **Framework-friendly** - works with React, Vue, Stimulus, etc.
- **No runtime required** - just the transpiled code

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                    Single Ruby Source                           │
│    (with optional pragma annotations for edge cases)            │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
    ┌─────────────────┐             ┌─────────────────┐
    │  Ruby Runtime   │             │  Ruby2JS with   │
    │  (pragmas are   │             │  filters        │
    │   just comments)│             │                 │
    └─────────────────┘             └─────────────────┘
              │                               │
              ▼                               ▼
    ┌─────────────────┐             ┌─────────────────┐
    │  Ruby Behavior  │             │  JS Behavior    │
    │  (server-side)  │             │  (browser/node) │
    └─────────────────┘             └─────────────────┘
```

The key insight is that **Ruby2JS pragmas are just comments** - they have no effect when code runs in Ruby. This means the same source file works in both environments without conditional compilation.

## Example: A Dual-Target Class

```ruby
class Calculator
  def initialize(precision = 2)
    @precision = precision
  end

  def add(a, b)
    round(a + b)
  end

  def multiply(a, b)
    round(a * b)
  end

  private

  def round(value)
    value.round(@precision)
  end
end
```

This class works identically in Ruby and when transpiled to JavaScript:

```javascript
class Calculator {
  constructor(precision = 2) {
    this._precision = precision
  }

  add(a, b) {
    return this._round(a + b)
  }

  multiply(a, b) {
    return this._round(a * b)
  }

  _round(value) {
    return Math.round(value * 10 ** this._precision) / 10 ** this._precision
  }
}
```

## When Dual-Target Works Best

Dual-target development works best when your code:

- Uses **data structures** that exist in both languages (arrays, hashes/objects, strings, numbers)
- Relies on **pure functions** without side effects
- Follows **patterns** that translate cleanly (classes, methods, blocks)
- Avoids **Ruby-specific features** like `method_missing`, `define_method`, or `eval`

## What You'll Learn

This guide covers:

1. **[Patterns](/docs/users-guide/patterns)** - How to write Ruby that transpiles cleanly
2. **[Pragmas](/docs/users-guide/pragmas)** - Fine-grained control over specific lines
3. **[Anti-Patterns](/docs/users-guide/anti-patterns)** - What to avoid
4. **[Build Setup](/docs/users-guide/build-setup)** - Integrating Ruby2JS into your workflow

## Prerequisites

This guide assumes familiarity with:
- Ruby syntax and idioms
- Basic JavaScript
- Ruby2JS [Getting Started](/docs/) and [Options](/docs/options)

For filter-specific documentation, see the [Filters](/docs/filters/functions) section.
