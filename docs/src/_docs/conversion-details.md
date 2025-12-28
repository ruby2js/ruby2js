---
order: 30
title: Design Philosophy
top_section: Behind the Scenes
category: conversion-details
---

This page explains the design decisions behind Ruby2JS and how it compares to other approaches for running Ruby in the browser.

{% toc %}

## Three Approaches to Ruby in the Browser

There are three main ways to run Ruby code in a web browser:

### 1. Opal (Runtime Compilation)

[Opal](https://opalrb.com/) compiles Ruby to JavaScript with a comprehensive runtime library. It modifies JavaScript's built-in objects to match Ruby semantics—for example, making `a[-1]` return the last element of an array.

**Pros:**
- High Ruby compatibility
- Ruby semantics preserved (negative indexing, truthiness, etc.)

**Cons:**
- Large runtime required
- Output is [harder to read](https://opalrb.com/try/#code:a%20%3D%20%22abc%22%3B%20puts%20a[-1])
- [Compatibility issues](https://github.com/opal/opal/issues/400) with some JavaScript frameworks

### 2. WebAssembly Ruby (ruby.wasm)

[ruby.wasm](https://github.com/ruby/ruby.wasm) runs a full Ruby interpreter compiled to WebAssembly. This is actual Ruby running in the browser, not transpiled code.

**Pros:**
- Full Ruby compatibility (it *is* Ruby)
- Access to Ruby standard library
- Can run existing Ruby code unmodified

**Cons:**
- Large download (~20-40MB depending on configuration)
- Slower startup (must initialize Ruby VM)
- JavaScript interop requires explicit bridging
- Not suitable for generating JavaScript libraries

### 3. Ruby2JS (Static Transpilation)

Ruby2JS takes a different approach: it performs **static transformations** at build time to produce idiomatic JavaScript. There's no runtime—just the generated code.

**Pros:**
- Small output (~460KB for the transpiled converter, walker, and runtime)
- Readable, debuggable JavaScript output
- Works seamlessly with JavaScript frameworks
- Generated code runs at native JavaScript speed

**Cons:**
- Not all Ruby features translate (see [Anti-Patterns](/docs/users-guide/anti-patterns))
- Some semantic differences (truthiness, negative indexing)
- Requires understanding of what translates and what doesn't

## Ruby2JS Design Decisions

### Choose Your Level of Ruby Compatibility

{% rendercontent "docs/note", title: "Start with the Preset" %}
If you're not sure which options to choose, start with `preset: true` (or the `# ruby2js: preset` magic comment). The preset provides sensible defaults including the most commonly used filters, ES2022 support, and identity comparison. You can always fine-tune individual settings later. See [Preset Configuration](/docs/options#preset-configuration) for details.
{% endrendercontent %}

By default, Ruby2JS accepts JavaScript semantics rather than fighting them:

```ruby
a[-1]  # Returns undefined in JS, not last element
0 || 1 # Returns 0 in Ruby, 1 in JS (0 is falsy in JS)
```

But you can opt into more Ruby-like behavior at multiple levels:

**Filters** transform Ruby methods to JavaScript equivalents at transpile time:
```ruby
# With functions filter:
arr.first        # => arr[0]
arr.empty?       # => arr.length === 0
str.gsub(/a/, 'b')  # => str.replace(/a/g, 'b')
```

**Polyfills** add Ruby methods to JavaScript prototypes at runtime:
```ruby
# With polyfill filter:
arr.first        # => arr.first (property, via Object.defineProperty)
arr.compact      # => arr.compact (property, returns new array)
```

**Pragmas** give line-level control for edge cases:
```ruby
x ||= default # Pragma: ??     # Use nullish coalescing
hash.each { |k,v| } # Pragma: entries  # Use Object.entries()
```

**Options** like `or: :nullish` and `truthy: :ruby` can change behavior globally.

This layered approach lets you choose the trade-offs appropriate for your project—from minimal transformation to comprehensive Ruby compatibility.

### Static Over Dynamic

The real limitations come from Ruby2JS using **static AST transformations** rather than runtime modifications:

- **Predictable output** - The same Ruby always produces the same JavaScript
- **No runtime overhead** - Generated code runs at native speed
- **Framework compatible** - No conflicts with React, Vue, etc.

The cost is that Ruby's dynamic features simply can't be supported. There's no way to statically transpile `method_missing`, `define_method`, or `eval`—these require a runtime that can intercept and handle arbitrary method calls. See [Anti-Patterns](/docs/users-guide/anti-patterns) for the full list.

## Edge Cases

### Extending Existing Classes

Both Ruby and JavaScript have open classes, but Ruby unifies syntax for defining and extending classes while JavaScript does not. To extend an existing class, use the `extend` pragma:

```ruby
class String # Pragma: extend
  def blank?
    strip.empty?
  end
end
```

This tells Ruby2JS you're extending an existing class rather than defining a new one. The pragma approach works in both Ruby (where the comment is ignored) and Ruby2JS, making it ideal for dual-target code.

### Suffix Stripping

Ruby allows `?` and `!` in method names; JavaScript doesn't. Ruby2JS strips these suffixes:

```ruby
array.empty?   # => array.empty
string.chomp!  # => string.chomp
```

This can be useful for avoiding filter conflicts—if a filter maps `each` to `forEach`, you can use `each!` to bypass it.

## Further Reading

- **[User's Guide](/docs/users-guide/introduction)** - How to write dual-target Ruby/JavaScript code
- **[Options](/docs/options)** - Configuration including `exclude` for filter control
- **[notimplemented_spec](https://github.com/ruby2js/ruby2js/blob/master/spec/notimplemented_spec.rb)** - Ruby features known to be unsupported
