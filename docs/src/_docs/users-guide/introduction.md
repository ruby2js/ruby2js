---
order: 9
title: Introduction
top_section: User's Guide
category: users-guide-intro
next_page_order: 9.1
---

# Writing Ruby for JavaScript

Ruby2JS transpiles Ruby code to JavaScript. There are two main approaches, and understanding when to use each will help you get the most out of Ruby2JS.

**Try it now** — edit the Ruby code below and see the JavaScript output:

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

{% toc %}

## Two Approaches

### Dual-Target Development

Write Ruby code that runs **both** natively in Ruby and as transpiled JavaScript. The same source file works in both environments.

**Best for:**
- Shared validation logic (server and client)
- Isomorphic rendering
- Libraries that work in Ruby and JavaScript
- Gradual migration from Ruby to JavaScript

**Key constraint:** Code must avoid Ruby-specific features that don't translate (metaprogramming, `eval`, etc.)

### JavaScript-Only Development

Write Ruby code designed **exclusively** to become JavaScript. The Ruby code won't run in Ruby—it's just a nicer syntax for writing JavaScript.

**Best for:**
- Browser applications and SPAs
- Node.js tools and CLI utilities
- Using JavaScript APIs directly (DOM, fetch, etc.)
- Portions of the Ruby2JS self-hosted transpiler

**Key advantage:** Full access to JavaScript APIs and idioms without dual-target constraints.

## Choosing Your Approach

| Factor              | Dual-Target        | JavaScript-Only  |
| ------------------- | ------------------ | ---------------- |
| Ruby execution      | Production use     | None             |
| JavaScript APIs     | Wrapped or avoided | Used directly    |
| ESM imports/exports | No (use require)   | Yes              |
| Pragmas needed      | Occasional         | Common           |
| Code complexity     | Simpler patterns   | Full flexibility |

**Not sure?** Start with dual-target patterns. They work for JavaScript-only too, and you can add JavaScript-specific features as needed.

## How Ruby2JS Works

```
┌─────────────────────────────────────────────────────────────────┐
│                         Ruby Source                              │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
    ┌─────────────────┐             ┌─────────────────┐
    │  Ruby Runtime   │             │    Ruby2JS      │
    │  (dual-target)  │             │   Transpiler    │
    └─────────────────┘             └─────────────────┘
              │                               │
              ▼                               ▼
    ┌─────────────────┐             ┌─────────────────┐
    │  Ruby Behavior  │             │  JavaScript     │
    └─────────────────┘             └─────────────────┘
```

For dual-target code, pragmas (special comments) let you handle edge cases without affecting Ruby execution—Ruby sees them as comments.

## The Ruby2JS Approach

Unlike Opal (which compiles Ruby to JavaScript with a runtime), Ruby2JS produces **idiomatic JavaScript** that reads like hand-written code:

- **Small output** - No runtime library required
- **Readable** - The JavaScript looks like JavaScript
- **Framework-friendly** - Works with React, Vue, Stimulus, etc.
- **Fast** - Generated code runs at native JavaScript speed

The trade-off: Ruby's dynamic features (`method_missing`, `define_method`, `eval`) can't be supported. See [Anti-Patterns](/docs/users-guide/anti-patterns) for what to avoid.

## What You'll Learn

This guide covers:

1. **[Patterns](/docs/users-guide/patterns)** - Common patterns that work well
2. **[Pragmas](/docs/users-guide/pragmas)** - Fine-grained control over specific lines
3. **[Anti-Patterns](/docs/users-guide/anti-patterns)** - What to avoid
4. **[JavaScript-Only](/docs/users-guide/javascript-only)** - ESM, async/await, and JavaScript APIs

## Prerequisites

This guide assumes familiarity with:
- Ruby syntax and idioms
- Basic JavaScript
- Ruby2JS [Getting Started](/docs/) and [Options](/docs/options)

For filter-specific documentation, see the [Filters](/docs/filters/functions) section.
