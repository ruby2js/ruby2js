---
order: 130
title: ES Levels
top_section: Introduction
category: eslevels
---

By default, Ruby2JS targets **ES2020**, which is the minimum supported version. ES2020 includes `let`/`const`, arrow functions, template literals, classes, spread syntax, optional chaining (`?.`), and nullish coalescing (`??`).

By passing an `eslevel` option to the `convert` method, you can target a newer ECMAScript version. Every newer level enables older levels, so for example `2021` will enable ES2020 features plus ES2021-specific features.

{% capture caret %}<sl-icon name="caret-right-fill"></sl-icon>{% endcapture %}

## Baseline Features (ES2015-ES2019)

The following features are always available since ES2020 is the minimum supported version:

{:.functions-list}
* `"#{a}"` {{ caret }} <code>`${a}`</code>
* `a = 1` {{ caret }} `let a = 1`
* `A = 1` {{ caret }} `const A = 1`
* `a, b = b, a` {{ caret }} `[a, b] = [b, a]`
* `a, (foo, *bar) = x` {{ caret }} `let [a, [foo, ...bar]] = x`
* `def f(a, (foo, *bar))` {{ caret }} `function f(a, [foo, ...bar])`
* `def a(b=1)` {{ caret }} `function a(b=1)`
* `def a(*b)` {{ caret }} `function a(...b)`
* `.each_value` {{ caret }} `for (i of ...) {}`
* `a(*b)` {{ caret }} `a(...b)`
* `"#{a}"` {{ caret }} <code>\`${a}\`</code>
* `lambda {|x| x}` {{ caret }} `(x) => {return x}`
* `proc {|x| x}` {{ caret }} `(x) => {x}`
* `a {|x|}` {{ caret }} `a((x) => {})`
* `class Person; end` {{ caret }} `class Person {}`
* `Class.new do; end` {{ caret }} `class {}`
* `(0...a).to_a` {{ caret }} `[...Array(a).keys()]`
* `(0..a).to_a` {{ caret }} `[...Array(a+1).keys()]`
* `(b..a).to_a` {{ caret }} `Array.from({length: (a-b+1)}, (_, idx) => idx+b)`
* `hash => {a:, b:}` {{ caret }} `let { a, b } = hash`

Class support includes constructors, super, methods, class methods,
instance methods, instance variables, class variables, getters, setters,
attr_accessor, attr_reader, attr_writer, etc.

Additionally, the `functions` filter provides the following conversions:

{:.functions-list}
* `Array(x)` {{ caret }} `Array.from(x)`
* `.inject(n) {}` {{ caret }} `.reduce(() => {}, n)`
* `a[0..2] = v` {{ caret }} `a.splice(0, 3, ...v)`
* `a ** b` {{ caret }} `a ** b`
* `.include?` {{ caret }} `.includes`
* `.values()` {{ caret }} `Object.values()`
* `.entries()` {{ caret }} `Object.entries()`
* `.each_pair {}` {{ caret }} `for (let [key, value] of Object.entries()) {}`
* `include M` {{ caret }} `Object.defineProperties(..., Object.getOwnPropertyDescriptors(M))`
* `.merge` {{ caret }} `{...a, ...b}`
* `.flatten` {{ caret }} `.flat(Infinity)`
* `.lstrip` {{ caret }} `.trimEnd`
* `.rstrip` {{ caret }} `.trimStart`
* `a.to_h` {{ caret }} `Object.fromEntries(a)`
* `a.to_h { |x| [k, v] }` {{ caret }} `Object.fromEntries(a.map(x => [k, v]))`
* `Hash[a]` {{ caret }} `Object.fromEntries(a)`
* `a&.b` {{ caret }} `a?.b`
* `.scan` {{ caret }} `Array.from(str.matchAll(/.../g), s => s.slice(1))`
* `a.nil? ? b : a` {{ caret }} `a ?? b`

Async support:

{:.functions-list}
* `async def` {{ caret }} `async function`
* `async lambda` {{ caret }} `async =>`
* `async proc` {{ caret }} `async =>`
* `async ->` {{ caret }} `async =>`
* `foo bar, async do...end` {{ caret }} `foo(bar, async () => {})`

Keyword arguments and optional keyword arguments are mapped to parameter destructuring.
Rest arguments can be used with keyword arguments and optional keyword arguments.
`rescue` without a variable maps to `catch` without a variable.

Classes defined with a `method_missing` method will emit a `Proxy` object
for each instance that will forward calls. Note that in order to forward
arguments, this proxy will return a function that will need to be called,
making it impossible to proxy attributes/getters. As a special accommodation,
if the `method_missing` method is defined to only accept a single parameter
it will be called with only the method name, and it is free to return
either values or functions.

## ES2021 support

When option `eslevel: 2021` is provided, the following additional
conversions are made:

{:.functions-list}
* `x ||= 1` {{ caret }} `x ||= 1`
* `x &&= 1` {{ caret }} `x &&= 1`
* `x = y if x.nil?` {{ caret }} `x ??= y`
* `1000000.000001` {{ caret }} `1_000_000.000_001`
* `.gsub` {{ caret }} `.replaceAll`

The `x = y if x.nil?` pattern provides an idiomatic Ruby way to express
nullish assignment. This is useful when you want nullish semantics (only
assign if `nil`) rather than the falsy semantics of `||=` (which also
triggers on `false`).

## ES2022 support

{:.functions-list}
* `@x` {{ caret }} `this.#x` (unless the `underscored_private` option is set to `true`)
* `@@x` {{ caret }} `ClassName.#x`
* `self.a = []` {{ caret }} `static a = []` (within a class)
* `private` {{ caret }} methods after `private` use `#` prefix (e.g., `#helper()`)

Private method support allows you to use Ruby's `private` keyword to mark methods as private:

```ruby
class Calculator
  def calculate(x)
    helper(x)      # Calls this.#helper(x)
  end

  private

  def helper(x)    # Becomes #helper(x)
    x * 2
  end
end
```

Both implicit and explicit `self` calls to private methods are correctly prefixed:

```ruby
helper(x)       # => this.#helper(x)
self.helper(x)  # => this.#helper(x)
```

When `underscored_private: true` is set, private methods use `_` prefix instead of `#`.

When the `functions` filter is enabled, the following additional conversions are
made:

{:.functions-list}
* `x[-2]` {{ caret }} `x.at(-2)`
* `x.last` {{ caret }} `x.at(-1)`

## ES2023 support

When option `eslevel: 2023` is provided, the following additional
conversion is made by the `functions` filter:

{:.functions-list}
* `.sort_by {}` {{ caret }} `.toSorted()`

Ruby's `sort_by` method uses ES2023's non-mutating `toSorted()`:

```ruby
# Ruby
people.sort_by { |p| p.age }

# JavaScript (ES2023)
people.toSorted((p_a, p_b) => p_a.age < p_b.age ? -1 : p_a.age > p_b.age ? 1 : 0)
```

For older ES levels, `sort_by` uses `slice().sort()` to avoid mutating the original array.

## ES2024 support

When option `eslevel: 2024` is provided, the following additional
conversion is made by the `functions` filter:

{:.functions-list}
* `.group_by {}` {{ caret }} `Object.groupBy()`

Ruby's `group_by` method maps directly to ES2024's `Object.groupBy()`:

```ruby
# Ruby
people.group_by { |p| p.age }

# JavaScript (ES2024)
Object.groupBy(people, p => p.age)
```

For older ES levels, `group_by` uses a `reduce()` fallback to build the grouped object.

## ES2025 support

When option `eslevel: 2025` is provided, the following additional
conversion is made by the `functions` filter:

{:.functions-list}
* `Regexp.escape()` {{ caret }} `RegExp.escape()`

Ruby's `Regexp.escape` method maps directly to ES2025's `RegExp.escape()`:

```ruby
# Ruby
Regexp.escape("hello.world")

# JavaScript (ES2025)
RegExp.escape("hello.world")
```
