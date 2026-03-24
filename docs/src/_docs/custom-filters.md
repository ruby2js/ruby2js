---
order: 320
title: Custom Filters
top_section: Filters
category: custom-filters
---

Filters are the heart of Ruby2JS's extensibility. They transform the Abstract Syntax Tree (AST) before it's converted to JavaScript, allowing you to customize how Ruby constructs are translated. This guide explains how to write your own filters.

{% toc %}

## Filter Basics

A filter is a Ruby module that:

1. Lives in the `Ruby2JS::Filter` namespace
2. Includes the `SEXP` helper module
3. Defines `on_*` methods to transform specific AST node types
4. Optionally registers itself in `DEFAULTS` to be included automatically

Here's the minimal structure:

```ruby
require 'ruby2js'

module Ruby2JS
  module Filter
    module MyFilter
      include SEXP

      def on_send(node)
        # Transform :send nodes (method calls)
        # Always call super first to let other filters process the node
        node = super

        # Your transformation logic here
        node
      end
    end

    # Optional: auto-include this filter
    # DEFAULTS.push MyFilter
  end
end
```

## Understanding the AST

Ruby2JS uses the [Parser](https://github.com/whitequark/parser) gem to parse Ruby code into an AST. Each node has a **type** (a symbol) and **children** (an array of values or other nodes). For a comprehensive reference of all AST node types, see the [AST Format documentation](https://github.com/whitequark/parser/blob/master/doc/AST_FORMAT.md).

You can inspect the AST for any Ruby code:

```ruby
require 'parser/current'
ast = Parser::CurrentRuby.parse('puts "hello"')
puts ast.inspect
# => s(:send, nil, :puts, s(:str, "hello"))
```

Common node types:

| Node Type | Example Ruby        | AST Structure                          |
| --------- | ------------------- | -------------------------------------- |
| `:send`   | `foo.bar(x)`        | `s(:send, receiver, :method, args...)` |
| `:lvar`   | `x`                 | `s(:lvar, :x)`                         |
| `:lvasgn` | `x = 1`             | `s(:lvasgn, :x, value)`                |
| `:def`    | `def foo; end`      | `s(:def, :foo, args, body)`            |
| `:defs`   | `def self.foo; end` | `s(:defs, target, :foo, args, body)`   |
| `:class`  | `class Foo; end`    | `s(:class, name, parent, body)`        |
| `:if`     | `if x; y; end`      | `s(:if, cond, then, else)`             |
| `:block`  | `x { \|a\| b }`     | `s(:block, call, args, body)`          |
| `:int`    | `42`                | `s(:int, 42)`                          |
| `:str`    | `"hello"`           | `s(:str, "hello")`                     |
| `:sym`    | `:foo`              | `s(:sym, :foo)`                        |
| `:array`  | `[1, 2]`            | `s(:array, elements...)`               |
| `:hash`   | `{a: 1}`            | `s(:hash, pairs...)`                   |
| `:ivar`   | `@foo`              | `s(:ivar, :@foo)`                      |
| `:const`  | `Foo`               | `s(:const, nil, :Foo)`                 |

## Helper Methods

The `SEXP` module provides two essential helpers:

### `s(type, *children)` - Create a new node

Creates a brand new AST node:

```ruby
s(:str, "hello")           # => s(:str, "hello")
s(:send, nil, :puts, arg)  # => s(:send, nil, :puts, arg)
```

### `S(type, *children)` - Update the current node

Creates a node that preserves source location info from `@ast`:

```ruby
S(:send, nil, :console_log, arg)
```

Use `S()` when replacing the current node to maintain source maps.

### `node.updated(type, children)` - Update a specific node

Updates an existing node with new type and/or children:

```ruby
node.updated(nil, [receiver, :new_method, *args])  # change children only
node.updated(:csend, node.children)                 # change type only
```

### `process(node)` - Recursively process a node

Runs a node through all filters:

```ruby
def on_send(node)
  node = super
  # Create a new node and process it
  new_node = s(:send, nil, :something)
  process(new_node)
end
```

## Writing Filter Methods

### The `on_*` Pattern

For each AST node type you want to transform, define an `on_<type>` method:

```ruby
def on_send(node)    # called for :send nodes (method calls)
def on_def(node)     # called for :def nodes (method definitions)
def on_block(node)   # called for :block nodes (blocks)
def on_class(node)   # called for :class nodes (class definitions)
def on_lvar(node)    # called for :lvar nodes (local variables)
```

### Always Call `super` First

This ensures other filters get a chance to process the node:

```ruby
def on_send(node)
  node = super  # Let other filters process first
  # Your logic here
  node
end
```

### Extracting Node Children

Use destructuring to extract children:

```ruby
def on_send(node)
  node = super
  receiver, method, *args = node.children

  # receiver: the object (nil for bare method calls)
  # method: the method name (a Symbol)
  # args: array of argument nodes

  node
end
```

### Returning Nodes

Always return a node from your `on_*` method:

- Return the original `node` if no transformation is needed
- Return a new node created with `s()`, `S()`, or `node.updated()`

## Example: Simple Method Renaming

This filter renames `log` calls to `console.log`:

```ruby
module Ruby2JS
  module Filter
    module MyLogger
      include SEXP

      def on_send(node)
        node = super
        return node unless node.type == :send

        receiver, method, *args = node.children

        # Transform: log("msg") => console.log("msg")
        if receiver.nil? && method == :log
          S(:send, s(:lvar, :console), :log, *args)
        else
          node
        end
      end
    end
  end
end
```

## Example: Transforming Blocks

This filter transforms `3.times { ... }` to a `for` loop:

```ruby
module Ruby2JS
  module Filter
    module TimesLoop
      include SEXP

      def on_block(node)
        node = super
        return node unless node.type == :block

        call, args, body = node.children
        return node unless call.type == :send

        receiver, method = call.children

        if method == :times && receiver&.type == :int
          count = receiver.children.first
          var = args.children.first&.children&.first || :i

          # Create: for (let i = 0; i < count; i++) { body }
          s(:for,
            s(:lvasgn, var),
            s(:erange, s(:int, 0), s(:int, count)),
            body
          )
        else
          node
        end
      end
    end
  end
end
```

## Using Your Filter

### Pass to `convert` directly

```ruby
require 'ruby2js'
require_relative 'my_filter'

js = Ruby2JS.convert('log "hello"', filters: [Ruby2JS::Filter::MyLogger])
```

### Add to DEFAULTS

```ruby
module Ruby2JS
  module Filter
    module MyLogger
      include SEXP
      # ... filter code ...
    end

    DEFAULTS.push MyLogger
  end
end
```

### Combine with other filters

```ruby
Ruby2JS.convert(code, filters: [
  Ruby2JS::Filter::Functions,
  Ruby2JS::Filter::MyLogger
])
```

## Controlling Method Processing

Filters can opt-in or opt-out of processing specific methods:

### Check if a method is excluded

```ruby
def on_send(node)
  node = super
  receiver, method, *args = node.children

  # Skip if this method was excluded by user configuration
  return node if excluded?(method)

  # Your transformation
end
```

### Skip certain methods in your filter

```ruby
SKIP_METHODS = [:initialize, :constructor]

def on_def(node)
  node = super
  return node if SKIP_METHODS.include?(node.children.first)
  # Transform other methods
end
```

## Debugging Tips

### Inspect the AST

```ruby
require 'parser/current'
code = 'your_ruby_code_here'
ast = Parser::CurrentRuby.parse(code)
puts ast.inspect
```

### Add logging to your filter

```ruby
def on_send(node)
  node = super
  puts "Processing: #{node.inspect}"
  # ... rest of filter
end
```

### Test incrementally

```ruby
# Test your filter in isolation
require 'ruby2js'
require_relative 'my_filter'

test_cases = [
  'log "hello"',
  'x.log "test"',
  'other_method'
]

test_cases.each do |code|
  puts "Input:  #{code}"
  puts "Output: #{Ruby2JS.convert(code, filters: [Ruby2JS::Filter::MyLogger])}"
  puts
end
```

## Filter DSL

For app-specific filters, Ruby2JS provides a declarative DSL that is simpler than writing raw `on_*` methods with `s()` calls. Filters written with the DSL can be transpiled to JavaScript for use with the selfhost runtime.

The DSL supports multiple layers, from most declarative to most flexible. You can mix layers freely within a single filter.

### Layer 1: Declarative Rewrites

The simplest approach — match a Ruby expression pattern and replace it:

```ruby
require 'ruby2js/filter_dsl'

Ruby2JS.filter(:MyApp) do
  # Rename method calls
  rewrite 'puts(_1)', to: 'console.log(_1)'
  rewrite 'p(_1)', to: 'console.log(_1)'

  # Stub a gem with a static value
  rewrite 'RQRCode::QRCode.new(_1).as_svg(_2)',
    to: '"<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"'

  # Replace a constant
  rewrite 'Rails::Html::WhiteListSanitizer.allowed_tags',
    to: '%w[a b em strong p br]'
end
```

Placeholders `_1`, `_2`, etc. match any subtree and can be referenced in the replacement. The pattern and replacement strings are parsed as Ruby expressions at definition time.

### Layer 2: Pattern Matching

When you need conditional logic, use Ruby's `case/in` pattern matching on AST nodes. This is valid Ruby syntax that transpiles to JavaScript automatically:

```ruby
Ruby2JS.filter(:MyApp) do
  on_send do |node|
    case node
    in type: :send, children: [nil, :log, {type: :str} => msg]
      s(:send, s(:lvar, :console), :log, msg)
    else
      nil  # return nil to skip (falls through to super)
    end
  end
end
```

### Layer 3: Builders

For generating complex AST structures, builder classes provide a readable API:

```ruby
require 'ruby2js/builder'

# Call builder — chainable method calls
call = Ruby2JS::Builder::Call.self(:save).await
# => s(:send, nil, :await, s(:send, s(:self), :save))

call = Ruby2JS::Builder::Call.on(receiver, :find, id).chain(:first).await
# => await receiver.find(id).first()

# Property access (no parentheses)
call = Ruby2JS::Builder::Call.self_attr(:name)
# => this.name

# Member builder — class members
Ruby2JS::Builder::Member.getter(:name, body)
# => get name() { body }

Ruby2JS::Builder::Member.cached_getter(:comments, constructor)
# => get comments() { if (this._comments) return this._comments; return this._comments = constructor; }

Ruby2JS::Builder::Member.accessor(:items, constructor)
# => getter + setter pair

Ruby2JS::Builder::Member.async(:create, args, body)
# => async create(args) { body }

# Html builder — HTML template literals
Ruby2JS::Builder::Html.tag(:a, {class: "btn", href: path_expr}, text_expr)
# Static attrs collapse into strings; dynamic attrs use template interpolation

Ruby2JS::Builder::Html.void(:input, {type: "hidden", name: "token", value: val})
# => <input type="hidden" name="token" value="${val}" />
```

### Layer 4: Raw s() Calls

You can always drop down to raw AST construction when no higher-level abstraction fits:

```ruby
Ruby2JS.filter(:MyApp) do
  on_send do |node|
    receiver, method, *args = node.children
    if some_unusual_condition?(receiver, method)
      s(:send, nil, :custom_thing, *args)
    end
  end
end
```

### Combining Layers

All layers coexist in a single filter:

```ruby
Ruby2JS.filter(:MyApp) do
  # Layer 1: simple rewrites
  rewrite 'puts(_1)', to: 'console.log(_1)'

  # Layer 2+3+4: custom handler with pattern matching and builders
  on_send do |node|
    case node
    in type: :send, children: [nil, :positioned_within, {type: :sym, children: [parent]}, *]
      Ruby2JS::Builder::Member.method(:positioning_parent, s(:args),
        Ruby2JS::Builder::Call.self(parent).node)
    else
      nil
    end
  end
end
```

### App-Specific Filters (Juntos)

For Juntos applications, place your filter at `config/ruby2js_filter.rb`. It will be automatically transpiled to JavaScript and loaded before the built-in filters.

```ruby
# config/ruby2js_filter.rb
filter :Writebook do
  # Stub QR code gem (not needed in browser)
  rewrite 'RQRCode::QRCode.new(_1).as_svg(_2)',
    to: '"<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"'

  # Replace sanitizer constant
  rewrite 'Rails::Html::WhiteListSanitizer.allowed_tags',
    to: '%w[a abbr b blockquote br code em h1 h2 h3 h4 h5 h6 hr i li ol p pre s span strong u ul]'
end
```

## Real-World Examples

For more complex examples, explore the built-in filters in the Ruby2JS source:

- [functions.rb](https://github.com/ruby2js/ruby2js/blob/master/lib/ruby2js/filter/functions.rb) - Comprehensive method transformations
- [camelCase.rb](https://github.com/ruby2js/ruby2js/blob/master/lib/ruby2js/filter/camelCase.rb) - Identifier renaming
- [return.rb](https://github.com/ruby2js/ruby2js/blob/master/lib/ruby2js/filter/return.rb) - Simple AST wrapping
- [esm.rb](https://github.com/ruby2js/ruby2js/blob/master/lib/ruby2js/filter/esm.rb) - Module system transformations
