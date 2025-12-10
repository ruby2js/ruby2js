---
order: 15
title: Functions
top_section: Filters
category: functions
---

The **Functions** filter provides a large number of convenience methods Rubyists are familar with. Statements such as `"252.3".to_i` transform into `parseInt("252.3")`, or `[1,3,5].yield_self { |arr| arr[1] }` into `(arr => arr[1])([1, 3, 5])`. Generally you will want to include this filter in your configuration unless you have specific reason not to.

{% rendercontent "docs/note", title: "ES Level Enhancements" %}
If you set the `eslevel` option to `2015` or newer, the Functions filter enables additional functionality, [documented on the ES Levels page](/docs/eslevels).
{% endrendercontent %}

## List of Transformations

{% capture caret %}<sl-icon name="caret-right-fill"></sl-icon>{% endcapture %}

{:.functions-list}
* `.abs` {{ caret }} `Math.abs()`
* `.all?` {{ caret }} `.every`
* `.any?` {{ caret }} `.some`
* `.ceil` {{ caret }} `Math.ceil()`
* `.chars` {{ caret }} `Array.from()`
* `.chr` {{ caret }} `fromCharCode`
* `.clear` {{ caret }} `.length = 0`
* `debugger` {{ caret }} `debugger` (JS debugger statement)
* `.define_method` {{ caret }} `klass.prototype.meth = function ...`
* `.delete` {{ caret }} `delete target[arg]`
* `.downcase` {{ caret }} `.toLowerCase`
* `.each` {{ caret }} `.forEach`
* `.each_key` {{ caret }} `for (i in ...) {}`
* `.each_pair` {{ caret }} `for (let key in item) {let value = item[key]; ...}`
* `.each_value` {{ caret }} `.forEach`
* `.each_with_index` {{ caret }} `.forEach`
* `.end_with?` {{ caret }} `.slice(-arg.length) == arg`
* `.empty?` {{ caret }} `.length == 0`
* `.find_index` {{ caret }} `findIndex`
* `.first` {{ caret }} `[0]`
* `.first(n)` {{ caret }} `.slice(0, n)`
* `.flat_map {}` {{ caret }} `.flatMap()`
* `.floor` {{ caret }} `Math.floor()`
* `.freeze` {{ caret }} `Object.freeze()`
* `.group_by {}` {{ caret }} `Object.groupBy()` (ES2024+) or `.reduce()` fallback
* `.group_by {|k,v| ...}` {{ caret }} destructuring support `([k, v]) => ...`
* `.gsub` {{ caret }} `replace(//g)`
* `.has_key?` {{ caret }} `key in hash`
* `.include?` {{ caret }} `.indexOf() != -1`
* `.index` {{ caret }} `indexOf` (when using arg) or `findIndex` (when using block)
* `.inspect` {{ caret }} `JSON.stringify()`
* `.join` {{ caret }} `.join('')` (Ruby defaults to `""`, JS to `","`)
* `.key?` {{ caret }} `key in hash`
* `.keys()` {{ caret }} `Object.keys()`
* `.last` {{ caret }} `[*.length-1]`
* `.last(n)` {{ caret }} `.slice(*.length-1, *.length)`
* `.lstrip` {{ caret }} `.replace(/^\s+/, "")`
* `.max` {{ caret }} `Math.max.apply(Math)`
* `.max_by {}` {{ caret }} `.reduce()`
* `.member?` {{ caret }} `key in hash`
* `.merge` {{ caret }} `Object.assign({}, ...)`
* `.merge!` {{ caret }} `Object.assign()`
* `.method_defined?` {{ caret }} `klass.prototype.hasOwnProperty(meth)` or `meth in klass.prototype`
* `.min` {{ caret }} `Math.min.apply(Math)`
* `.min_by {}` {{ caret }} `.reduce()`
* `[-n] = x` {{ caret }} `[*.length-n] = x` for literal negative index assignment
* `.new(size,default)` {{ caret }} `== .new(size).fill(default)`
* `.nil?` {{ caret }} `== null`
* `.ord` {{ caret }} `charCodeAt(0)`
* `puts` {{ caret }} `console.log`
* `rand` {{ caret }} `Math.random`
* `.reject {}` {{ caret }} `.filter(x => !(...))` (negated condition)
* `.reject(&:method)` {{ caret }} `.filter(item => !item.method())` (symbol-to-proc)
* `.replace` {{ caret }} `.length = 0; ...push.apply(*)`
* `.respond_to?` {{ caret }} `right in left`
* `.rindex` {{ caret }} `.lastIndexOf`
* `.round` {{ caret }} `Math.round()`
* `.rstrip` {{ caret }} `.replace(/s+$/, "")`
* `.scan` {{ caret }} `.match(//g)`
* `.sort_by {}` {{ caret }} `.toSorted()` (ES2023+) or `.slice().sort()` fallback
* `.sum` {{ caret }} `.reduce((a, b) => a + b, 0)`
* `.reduce(:+)` {{ caret }} `.reduce((a, b) => a + b)` (symbol-to-proc for operators)
* `.reduce(:merge)` {{ caret }} `.reduce((a, b) => ({...a, ...b}))` (hash merge)
* `.times` {{ caret }} `for (let i = 0; i < n; i++)`
* `.start_with?` {{ caret }} `.startsWith(arg)`
* `.upto(lim)` {{ caret }} `for (let i=num; i<=lim; i+=1)`
* `.downto(lim)` {{ caret }} `for (let i=num; i>=lim; i-=1)`
* `.step(lim, n).each` {{ caret }} `for (let i=num; i<=lim; i+=n)`
* `.step(lim, -n).each` {{ caret }} `for (let i=num; i>=lim; i-=n)`
* `(0..a).to_a` {{ caret }} `[...Array(a+1).keys()]`
* `(b..a).to_a` {{ caret }} `Array.from({length: (a-b+1)}, (_, idx) => idx+b)`
* `(b...a).to_a` {{ caret }} `Array.from({length: (a-b)}, (_, idx) => idx+b)`
* `.strip` {{ caret }} `.trim`
* `.sub` {{ caret }} `.replace`
* `.tap {|n| n}` {{ caret }} `(n => {n; return n})(...)`
* `.to_f` {{ caret }} `parseFloat`
* `.to_i` {{ caret }} `parseInt`
* `.to_s` {{ caret }} `.toString`
* `.to_sym` {{ caret }} (removed - symbols are strings in JS)
* `.to_json` {{ caret }} `JSON.stringify(obj)`
* `typeof(x)` {{ caret }} `typeof x` (JS type checking operator)
* `.upcase` {{ caret }} `.toUpperCase`
* `.yield_self {|n| n}` {{ caret }} `(n => n)(...)`
* `[-n]` {{ caret }} `[*.length-n]` for literal values of `n`
* `[n...m]` {{ caret }} `.slice(n,m)`
* `[n..m]` {{ caret }} `.slice(n,m+1)`
* `[start, length]` {{ caret }} `.slice(start, start+length)` (Ruby 2-arg slice)
* `[n..m] = v` {{ caret }} `.splice(n, m-n+1, ...v)` (ES2015+ for spread syntax)
* `.slice!(n..m)` {{ caret }} `.splice(n, m-n+1)`
* `[/r/, n]` {{ caret }} `.match(/r/)[n]`
* `[/r/, n]=` {{ caret }} `.replace(/r/, ...)`
* `(1..2).each {|i| ...}` {{ caret }} `for (let i=1; i<=2; i+=1)`
* `"string" * length` {{ caret }} `"string".repeat(length)`
* `@foo.call(args)` {{ caret }} `this._foo(args)`
* `@@foo.call(args)` {{ caret }} `this.constructor._foo(args)`
* `Array(x)` {{ caret }} `Array.from(x)`
* `delete x` {{ caret }} `delete x` (note lack of parenthesis)

## Additional Features

* `.sub!` and `.gsub!` become equivalent `x = x.replace` statements
* `.map!`, `.reverse!`, and `.select!` become equivalent
  `.splice(0, .length, *.method())` statements
* `setInterval` and `setTimeout` allow block to be treated as the
    first parameter on the call
* for the following methods, if the block consists entirely of a simple
  expression (or ends with one), a `return` is added prior to the
  expression: `sub`, `gsub`, `any?`, `all?`, `map`, `find`, `find_index`.
* New classes subclassed off of `Exception` will become subclassed off
  of `Error` instead; and default constructors will be provided
* `loop do...end` will be replaced with `while (true) {...}`
* `n.times do...end` and `n.times { |i| ... }` will be replaced with `for` loops
* `raise Exception.new(...)` will be replaced with `throw new Error(...)`
* `block_given?` will check for the presence of optional argument `_implicitBlockYield` which is a function made accessible through the use of `yield` in a method body.
* `alias_method` works both inside of a class definition as well as called directly on a class name (e.g. `MyClass.alias_method`)
* Block parameter destructuring is supported: `.map {|k, v| ...}` becomes `.map(([k, v]) => ...)`

## Methods Requiring Parentheses

Some Ruby method names like `keys`, `values`, `index`, `max`, etc. could also be
property accesses in JavaScript (e.g., on DOM nodes). To avoid incorrect
transformations, these methods are only converted when called with parentheses:

```ruby
a.keys     # => a.keys (no conversion - could be property access)
a.keys()   # => Object.keys(a) (converted - clearly a method call)
```

The following methods require parentheses for automatic conversion:
`keys`, `values`, `entries`, `index`, `rindex`, `clear`, `reverse!`, `max`, `min`

To force conversion even without parentheses, explicitly include the method:

```ruby
Ruby2JS.convert('a.keys', include: [:keys])  # => Object.keys(a)
```

Or use `include_all: true` to enable conversion for all such methods:

```ruby
Ruby2JS.convert('a.keys', include_all: true)  # => Object.keys(a)
```

## Methods Requiring Explicit Inclusion

The following mappings will only be done if explicitly included
(pass `include: [:class, :call]` as a `convert` option to enable):

{:.functions-list}
* `.class` {{ caret }} `.constructor`
* `a.call` {{ caret }} `a()`

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/functions_spec.rb).
{% endrendercontent %}
