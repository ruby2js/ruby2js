---
order: 4
title: ES Levels
top_section: Introduction
category: eslevels
---

By default, Ruby2JS will output JavaScript with the widest compatibility possible, but that also means many new features in recent ECMAScript versions are compromised or impossible to achieve.

By passing an `eslevel` option to the `convert` method, you can indicate which new language features you wish to enable. Every newer level enables older levels, so for example `2021` will enable ES2015, ES2016, etc.

{% capture caret %}<sl-icon name="caret-right-fill"></sl-icon>{% endcapture %}

## ES2015 support

When option `eslevel: 2015` is provided, the following additional
conversions are made:

{:.functions-list}
* `"#{a}"` {{ caret }} <code>\`${a}\`</code>
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
* `(0...a).to_a` {{ caret }} `[...Array(a).keys()]`
* `(0..a).to_a` {{ caret }} `[...Array(a+1).keys()]`
* `(b..a).to_a` {{ caret }} `Array.from({length: (a-b+1)}, (_, idx) => idx+b)`

ES2015 class support includes constructors, super, methods, class methods,
instance methods, instance variables, class variables, getters, setters,
attr_accessor, attr_reader, attr_writer, etc.

Additionally, the `functions` filter will provide the following conversion:

{:.functions-list}
* `Array(x)` {{ caret }} `Array.from(x)`
* `.inject(n) {}` {{ caret }} `.reduce(() => {}, n)`

Keyword arguments and optional keyword arguments will be mapped to
parameter destructuring.

Classes defined with a `method_missing` method will emit a `Proxy` object
for each instance that will forward calls.  Note that in order to forward
arguments, this proxy will return a function that will need to be called,
making it impossible to proxy attributes/getters.  As a special accommodation,
if the `method_missing` method is defined to only accept a single parameter
it will be called with only the method name, and it is free to return
either values or functions.

## ES2016 support

When option `eslevel: 2016` is provided, the following additional
conversion is made:

{:.functions-list}
* `a ** b` {{ caret }} `a ** b`

Additionally the following conversions is added to the `functions` filter:

{:.functions-list}
* `.include?` {{ caret }} `.includes`

## ES2017 support

When option `eslevel: 2017` is provided, the following additional
conversions are made by the `functions` filter:

{:.functions-list}
* `.values()` {{ caret }} `Object.values()`
* `.entries()` {{ caret }} `Object.entries()`
* `.each_pair {}` {{ caret }} `for (let [key, value] of Object.entries()) {}`

async support:

{:.functions-list}
* `async def` {{ caret }} `async function`
* `async lambda` {{ caret }} `async =>`
* `async proc` {{ caret }} `async =>`
* `async ->` {{ caret }} `async =>`
* `foo bar, async do...end` {{ caret }} `foo(bar, async () => {})`

## ES2018 support

When option `eslevel: 2018` is provided, the following additional
conversion is made by the `functions` filter:

{:.functions-list}
* `.merge` {{ caret }} `{...a, ...b}`

Additionally, rest arguments can now be used with keyword arguments and
optional keyword arguments.

## ES2019 support

When option `eslevel: 2019` is provided, the following additional
conversion is made by the `functions` filter:

{:.functions-list}
* `.flatten` {{ caret }} `.flat(Infinity)`
* `.lstrip` {{ caret }} `.trimEnd`
* `.rstrip` {{ caret }} `.trimStart`
* `a.to_h` {{ caret }} `Object.fromEntries(a)`
* `Hash[a]` {{ caret }} `Object.fromEntries(a)`

Additionally, `rescue` without a variable will map to `catch` without a
variable.

## ES2020 support

When option `eslevel: 2020` is provided, the following additional
conversions are made:

{:.functions-list}
* `@x` {{ caret }} `this.#x` (unless the `underscored_private` option is set to `true`)
* `@@x` {{ caret }} `ClassName.#x`
* `a&.b` {{ caret }} `a?.b`
* `.scan` {{ caret }} `Array.from(str.matchAll(/.../g), s => s.slice(1))`

## ES2021 support

When option `eslevel: 2021` is provided, the following additional
conversions are made:

{:.functions-list}
* `x ||= 1` {{ caret }} `x ||= 1`
* `x &&= 1` {{ caret }} `x &&= 1`
* `1000000.000001` {{ caret }} `1_000_000.000_001`