---
order: 375
title: Pragma
top_section: Filters
category: pragma
---

The **Pragma** filter provides line-level control over JavaScript output through
special comments. This allows fine-grained customization of the transpilation
on a per-line basis.

Pragmas are specified with a comment at the end of a line using the format:
`# Pragma: <name>`

## Available Pragmas

### `??` (or `nullish`)

Forces the use of nullish coalescing (`??`) instead of logical or (`||`).

This is useful when you want to distinguish between `null`/`undefined` and
falsy values like `0`, `""`, or `false`.

```ruby
a ||= b # Pragma: ??
# => a ??= b

x = value || default # Pragma: ??
# => let x = value ?? default
```

**Requirements:** ES2020 for `??`, ES2021 for `??=`

**When to use:** jQuery/DOM APIs often return `null` or `undefined` but valid
values could be falsy (e.g., `0` for an index). Use this pragma when you need
nullish semantics.

### `||` (or `logical`)

Forces the use of logical or (`||`) instead of nullish coalescing (`??`).

This is the inverse of the `??` pragma. It's useful when you're using the
`or: :nullish` or `or: :auto` options globally but need logical `||` behavior
for a specific line where the value could legitimately be `false`.

```ruby
enabled ||= true # Pragma: logical
# => enabled ||= true  (not ??=)

x = flag || default # Pragma: ||
# => let x = flag || default  (not ??)
```

**When to use:** When a variable can hold `false` as a valid value and you
want the fallback to execute for `false`, not just `null`/`undefined`. For
example, boolean flags where `false` should trigger the default assignment.

### `function` (or `noes2015`)

Forces traditional `function` syntax instead of arrow functions.

Arrow functions lexically bind `this`, which is often desirable. However,
DOM event handlers and jQuery callbacks typically need dynamic `this` binding
to reference the element that triggered the event.

```ruby
element.on("click") { handle_click(this) } # Pragma: function
# => element.on("click", function() {handle_click(this)})

items.each { |item| process(item) } # Pragma: function
# => items.each(function(item) {process(item)})
```

Without the pragma:
```ruby
items.each { |item| process(item) }
# => items.each(item => process(item))
```

**When to use:** jQuery event handlers, DOM callbacks, or any situation where
you need `this` to refer to the calling context rather than the lexical scope.

**Alternative:** You can also use `Function.new { }` (with the [Functions
filter](/docs/filters/functions)) to get the same result without a pragma:

```ruby
fn = Function.new { |x| x * 2 }
# => let fn = function(x) {x * 2}
```

### `guard`

Ensures splat arrays return an empty array when the source is `null` or
`undefined`.

In Ruby, `[*nil]` returns `[]`. In JavaScript, spreading `null` throws an error.
This pragma guards against that by using nullish coalescing.

```ruby
[*items] # Pragma: guard
# => items ?? []

[1, *items, 2] # Pragma: guard
# => [1, ...items ?? [], 2]
```

**Requirements:** ES2020 (for `??`)

**When to use:** When working with data from external APIs or DOM methods that
might return `null`, and you want to safely spread the result into an array.

### `skip`

Removes statements from the JavaScript output entirely. Works with:

- `require` and `require_relative` statements
- Method definitions (`def`)
- Class method definitions (`def self.method`)
- Alias declarations (`alias`)
- Block structures: `if`/`unless`, `begin`, `while`/`until`, `case`

This is useful when a Ruby file contains code that shouldn't be included in
the JavaScript output (e.g., Ruby-specific methods, native Ruby gems, runtime
dependencies that will be provided separately).

```ruby
require 'prism' # Pragma: skip
# => (no output)

require_relative 'helper' # Pragma: skip
# => (no output)

def respond_to?(method) # Pragma: skip
  # Ruby-only method, not needed in JS
  true
end
# => (no output)

def self.===(other) # Pragma: skip
  # Ruby-only class method
  other.is_a?(Node)
end
# => (no output)

alias loc location # Pragma: skip
# => (no output)

unless defined?(RUBY2JS_SELFHOST) # Pragma: skip
  require 'parser/current'
  # Ruby-only code block
end
# => (no output - entire block removed)

require 'my_module'  # No pragma, will be processed normally
# => import ... (if ESM filter is active)
```

**When to use:**
- When transpiling Ruby code that requires external dependencies provided
  separately in the JavaScript environment
- When using the `require` filter and you need to exclude specific requires
  from bundling
- When Ruby source files contain methods that are Ruby-specific and have no
  JavaScript equivalent (e.g., `respond_to?`, `is_a?`, `to_sexp`)
- When removing Ruby metaprogramming methods that don't translate to JavaScript

## Type Disambiguation Pragmas

Some Ruby methods have different JavaScript equivalents depending on the
receiver type. These pragmas let you specify the intended type.

**Note:** Ruby2JS also supports [automatic type inference](#type-inference)
from literals and constructor calls. Use these pragmas when the type cannot
be inferred or when you need to override the inferred type.

### `array`

Specifies that the receiver is an Array.

```ruby
arr.dup # Pragma: array
# => arr.slice()

arr << item # Pragma: array
# => arr.push(item)

arr += [1, 2] # Pragma: array
# => arr.push(...[1, 2])

# Binary operators (Ruby array operations → JS equivalents)
x = a + b # Pragma: array
# => let x = [...a, ...b]  (concatenation)

x = a - b # Pragma: array
# => let x = a.filter(x => !b.includes(x))  (difference)

x = a & b # Pragma: array
# => let x = a.filter(x => b.includes(x))  (intersection)

x = a | b # Pragma: array
# => let x = [...new Set([...a, ...b])]  (union)
```

**Note:** All array operators work with type inference:

```ruby
arr = []
arr += [1, 2]  # No pragma needed - type inferred from []
# => let arr = []; arr.push(...[1, 2])

a = [1, 2, 3]
x = a - [2]    # Type inferred from [1, 2, 3]
# => let a = [1, 2, 3]; let x = a.filter(x => ![2].includes(x))
```

**When to use:** When Ruby2JS can't infer the type and you need array-specific
behavior.

### `hash`

Specifies that the receiver is a Hash (JavaScript object).

```ruby
obj.dup # Pragma: hash
# => {...obj}

obj.include?(key) # Pragma: hash
# => key in obj
```

**When to use:** When you need hash-specific operations like the `in` operator
for key checking.

### `set`

Specifies that the receiver is a Set (or Map).

```ruby
s << item # Pragma: set
# => s.add(item)

s.include?(item) # Pragma: set
# => s.has(item)

s.merge(items) # Pragma: set
# => for (let _item of items) {s.add(_item)}

s.delete(item) # Pragma: set
# => s.delete(item)

s.clear() # Pragma: set
# => s.clear()
```

**When to use:** When working with JavaScript `Set` or `Map` objects. By default:
- `<<` becomes `.push()` (array behavior)
- `.include?` becomes `.includes()` (array/string behavior)
- `.merge()` becomes `{...a, ...b}` (hash/object behavior)
- `.delete()` becomes `delete obj[key]` (hash/object behavior)
- `.clear()` becomes `.length = 0` (array behavior)

Use this pragma to get the correct Set methods: `.add()`, `.has()`,
`.merge()`, `.delete()`, and `.clear()`.

### `map`

Specifies that the receiver is a JavaScript `Map` object.

```ruby
m[key] # Pragma: map
# => m.get(key)

m[key] = value # Pragma: map
# => m.set(key, value)

m.key?(key) # Pragma: map
# => m.has(key)

m.delete(key) # Pragma: map
# => m.delete(key)

m.clear # Pragma: map
# => m.clear()
```

**When to use:** When working with JavaScript `Map` objects. By default:
- `hash[key]` becomes bracket access `hash[key]` (object behavior)
- `hash[key] = value` becomes `hash[key] = value` (object behavior)
- `.key?()` becomes `key in obj` (object behavior)
- `.delete()` becomes `delete obj[key]` (object behavior)
- `.clear()` becomes `.length = 0` (array behavior)

Use this pragma to get the correct Map methods: `.get()`, `.set()`, `.has()`,
`.delete()`, and `.clear()`.

### `string`

Specifies that the receiver is a String.

```ruby
str.dup # Pragma: string
# => str
```

**Note:** Strings in JavaScript are immutable, so `.dup` is a no-op.

## Type Inference

Ruby2JS can automatically infer variable types from literals and constructor
calls, reducing the need for explicit pragma annotations. When a variable is
assigned a value with a recognizable type, subsequent operations on that
variable will use the appropriate JavaScript equivalent.

### Inferred Types

Types are inferred from:

**Literals:**
- `[]` → array
- `{}` → hash
- `""` or `''` → string
- Integer/float literals → number
- Regular expressions → regexp

**Constructor calls:**
- `Set.new` → set
- `Map.new` → map
- `Array.new` → array
- `Hash.new` → hash
- `String.new` → string

**Callable types:**
- `proc { }` → proc (callable with `[]`)
- `lambda { }` → proc (callable with `[]`)

**Sorbet T.let annotations:**
- `T.let(value, Array)` → array
- `T.let(value, Hash)` → hash
- `T.let(value, Set)` → set
- `T.let(value, Map)` → map
- `T.let(value, String)` → string
- `T.let(value, T::Array[X])` → array
- `T.let(value, T::Hash[K, V])` → hash
- `T.let(value, T::Set[X])` → set

### Examples

```ruby
# Type inferred from literal - no pragma needed
items = []
items << "hello"
# => let items = []; items.push("hello")

# Type inferred from constructor
cache = Map.new
cache[:key] = value
# => let cache = new Map(); cache.set("key", value)

# Hash operations work automatically
config = {}
config.empty?
# => let config = {}; Object.keys(config).length === 0

# Proc/lambda calls are converted
fn = proc { |x| x * 2 }
fn[5]
# => let fn = x => x * 2; fn(5)
```

### Sorbet T.let

Ruby2JS recognizes [Sorbet](https://sorbet.org/)'s `T.let` type annotations.
The `T.let` wrapper is stripped from the output, and the type is used for
disambiguation:

```ruby
# Sorbet annotation - T.let is stripped, type is used
items = T.let([], Array)
items << "hello"
# => let items = []; items.push("hello")

# Works with generic types too
cache = T.let({}, T::Hash[Symbol, String])
cache.empty?
# => let cache = {}; Object.keys(cache).length === 0

# Set types work correctly
visited = T.let(Set.new, T::Set[String])
visited << "page1"
# => let visited = new Set; visited.add("page1")
```

This allows you to write Ruby code that is both type-checked by Sorbet and
correctly transpiled by Ruby2JS. The type annotations are used at compile
time for disambiguation and removed from the JavaScript output.

**Note:** `require 'sorbet-runtime'` is automatically stripped from the output
since Sorbet is Ruby-only. This enables writing dual-target code that works
in both Ruby and JavaScript environments.

### Instance Variables

Type inference works with instance variables, and types set in `initialize` are
tracked across all methods in the class:

```ruby
class Counter
  def initialize
    @items = []
    @visited = Set.new
  end

  def add(item)
    @items << item     # Uses push() - type known from initialize
    @visited << item   # Uses add() - type known from initialize
  end

  def unvisited
    # Set.select auto-converts to [...set].filter()
    @items.select { |x| !@visited.include?(x) }
  end
end
```

Output:
```javascript
class Counter {
  constructor() {
    this._items = [];
    this._visited = new Set
  }

  add(item) {
    this._items.push(item);
    this._visited.add(item)
  }

  get unvisited() {
    return this._items.filter(x => !this._visited.has(x))
  }
}
```

**Note:** Instance variable types are only tracked when assigned in `initialize`.
Types assigned in other methods are not propagated class-wide.

### Pragma Override

Explicit pragmas always take precedence over inferred types. This allows you
to override the inference when needed:

```ruby
items = []           # Inferred as array
items << x           # Uses push()

items << y # Pragma: set  # Pragma overrides - uses add()
```

### Scope Boundaries

**Local variables** are scoped to their method. Types inferred in one method
do not affect other methods:

```ruby
def method_a
  items = []        # Array in this scope
  items << "a"      # push()
end

def method_b
  items = Set.new   # Set in this scope
  items << "b"      # add()
end
```

**Instance variables** assigned in `initialize` are tracked class-wide (see
[Instance Variables](#instance-variables) above). Instance variables assigned
in other methods are only tracked within that method.

### When to Use Pragmas

You still need pragmas when:

1. **No assignment visible:** The variable comes from a parameter or external source
2. **Type changes:** A variable is reassigned to a different type
3. **Override needed:** You want different behavior than the inferred type

```ruby
def process(data)   # data type unknown
  data << item # Pragma: array  # Pragma needed
end

items = get_items() # Return type unknown
items << x # Pragma: set        # Pragma needed
```

## Behavior Pragmas

These pragmas modify how specific Ruby patterns translate to JavaScript.

### `method`

Converts `.call()` to direct invocation for function objects.

```ruby
fn.call(x, y) # Pragma: method
# => fn(x, y)
```

**When to use:** When working with first-class functions stored in variables
that need to be invoked directly rather than using `.call()`.

### `proto`

Converts `.class` to `.constructor` for JavaScript prototype access.

```ruby
obj.class # Pragma: proto
# => obj.constructor
```

**When to use:** When you need to access the JavaScript constructor function
rather than a literal `.class` property.

### `entries`

Converts hash iteration to use `Object.entries()`.

```ruby
hash.each { |k, v| process(k, v) } # Pragma: entries
# => Object.entries(hash).forEach(([k, v]) => process(k, v))
```

**When to use:** When iterating over JavaScript objects where you need both
keys and values, and the standard `.each` translation doesn't apply.

### `extend`

Extends an existing JavaScript class (monkey patching) instead of defining a
new class.

```ruby
class String # Pragma: extend
  def blank?
    self.strip.empty?
  end
end
# => String.prototype.blank = function() {return this.trim().length === 0}

class Array # Pragma: extend
  def second
    self[1]
  end
end
# => Object.defineProperty(Array.prototype, "second", {
#      enumerable: true, configurable: true,
#      get() {return this[1]}
#    })
```

**When to use:** When you need to add methods to built-in JavaScript classes
like `String`, `Array`, or `Number`, or extend classes defined elsewhere.

Since the pragma is a Ruby comment, it's ignored when code runs in Ruby,
making it ideal for dual-target development.

### Automatic Class Reopening Detection

Ruby2JS automatically detects when a class is reopened after being defined via
`Struct.new` or `Class.new`. This pattern is common in Ruby:

```ruby
# Define a Struct
Color = Struct.new(:name, :value)

# Reopen to add methods
class Color
  class << self
    def for_value(v)
      COLORS.find { |c| c.value == v }
    end
  end

  def to_s
    value
  end
end
```

Ruby2JS recognizes that the `class Color` block is reopening the existing
`Color` constant (not defining a new class) and treats it as a class extension:

```javascript
const Color = new Struct("name", "value");
Color.for_value = v => COLORS.find(c => c.value == v);

Object.defineProperty(
  Color.prototype,
  "to_s",
  {enumerable: true, configurable: true, get() {return value}}
)
```

This automatic detection works for:
- `Name = Struct.new(...)` followed by `class Name`
- `Name = Class.new(...)` followed by `class Name`

Without this detection, reopening a class would create a duplicate `class Name`
declaration, causing a JavaScript syntax error.

**Note:** This detection only applies when the `Struct.new` or `Class.new`
assignment and the class reopening are in the same file and processed together.

## Target-Specific Pragmas

Target pragmas allow you to conditionally include or exclude import statements
based on the deployment target. When building for a specific target, imports
marked for a different target are removed from the output.

### Available Targets

| Pragma | Description |
|--------|-------------|
| `browser` | Browser/web applications |
| `capacitor` | Capacitor mobile apps |
| `electron` | Electron desktop apps |
| `tauri` | Tauri desktop apps |
| `node` | Node.js runtime |
| `bun` | Bun runtime |
| `deno` | Deno runtime |
| `cloudflare` | Cloudflare Workers |
| `vercel` | Vercel Edge Functions |
| `fly` | Fly.io |
| `server` | Any server target (node, bun, deno, cloudflare, vercel, fly) |

### Basic Usage

```ruby
import 'reactflow/dist/style.css' # Pragma: browser
import '@capacitor/camera' # Pragma: capacitor
import '@vercel/og' # Pragma: vercel
import 'common-utils'  # No pragma - included for all targets
```

When building with `target: 'browser'`:
- `reactflow/dist/style.css` is included
- `@capacitor/camera` is excluded
- `@vercel/og` is excluded
- `common-utils` is included

When building with `target: 'capacitor'`:
- `reactflow/dist/style.css` is excluded
- `@capacitor/camera` is included
- `@vercel/og` is excluded
- `common-utils` is included

### Using with `defined?` for Runtime Branching

Combine target pragmas with `defined?` to write code that adapts to the
available imports:

```ruby
import Camera from '@capacitor/camera' # Pragma: capacitor

def take_photo
  if defined?(Camera)
    # Capacitor path - uses native camera
    result = await Camera.getPhoto(quality: 80)
    result.base64String
  else
    # Browser fallback - uses getUserMedia
    stream = await navigator.mediaDevices.getUserMedia(video: true)
    capture_from_stream(stream)
  end
end
```

When building for `capacitor`, the Camera import is included and `defined?(Camera)`
is true. When building for `browser`, the import is excluded and the else branch
is used.

### The `server` Meta-Target

The `server` pragma matches any server-side runtime:

```ruby
import 'pg' # Pragma: server
```

This import is included when the target is `node`, `bun`, `deno`, `cloudflare`,
`vercel`, or `fly`, but excluded for `browser`, `capacitor`, `electron`, or `tauri`.

### Specifying the Target

The target is specified when calling `Ruby2JS.convert`:

```ruby
Ruby2JS.convert(code, target: 'browser', filters: [Ruby2JS::Filter::Pragma])
```

With Juntos, use the `-t` flag:

```bash
bin/juntos build -t browser
bin/juntos build -t capacitor
bin/juntos deploy -t cloudflare
```

### No Target = Include All

When no target is specified, all imports are included regardless of their
target pragma. This is useful during development when you want to see the
complete output.

## Usage Notes

### Case Insensitivity

Pragma names are case-insensitive:

```ruby
x = a || b # PRAGMA: ??
x = a || b # pragma: ??
x = a || b # Pragma: ??
# All produce: let x = a ?? b
```

### Multiple Pragmas

You can use multiple pragmas on the same line, and they will all be applied:

```ruby
# Both logical and method pragmas apply
x ||= fn.call(y) # Pragma: logical # Pragma: method
# => x ||= fn(y)

# Nullish and method together
x ||= fn.call(y) # Pragma: ?? # Pragma: method
# => x ??= fn(y)
```

You can also use different pragmas on different lines:

```ruby
options ||= {} # Pragma: ??
element.on("click") { handle(this) } # Pragma: function
```

### Filter Loading

The pragma filter is automatically loaded when you require it:

```ruby
require 'ruby2js/filter/pragma'
```

Or specify it in your configuration:

```ruby
Ruby2JS.convert(code, filters: [Ruby2JS::Filter::Pragma])
```

### Combining with Other Filters

The pragma filter works alongside other filters. It automatically reorders
itself to run before the Functions and ESM filters, ensuring pragmas like
`skip`, `entries`, and `method` are processed correctly regardless of the
order filters are specified.

## Background

The pragma filter was inspired by the need to handle edge cases in real-world
JavaScript frameworks. When interfacing with existing JavaScript libraries,
particularly jQuery and DOM APIs, Ruby2JS's default output may not always
produce the desired semantics.

Rather than changing global behavior, pragmas provide targeted control exactly
where needed, keeping the rest of your code using standard Ruby2JS conventions.
