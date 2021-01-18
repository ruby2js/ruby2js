---
order: 14
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
* `.chr` {{ caret }} `fromCharCode`
* `.clear` {{ caret }} `.length = 0`
* `.define_method` {{ caret }} `klass.prototype.meth = function ...`
* `.delete` {{ caret }} `delete target[arg]`
* `.downcase` {{ caret }} `.toLowerCase`
* `.each` {{ caret }} `.forEach`
* `.each_key` {{ caret }} `for (i in ...) {}`
* `.each_pair` {{ caret }} `for (var key in item) {var value = item[key]; ...}`
* `.each_value` {{ caret }} `.forEach`
* `.each_with_index` {{ caret }} `.forEach`
* `.end_with?` {{ caret }} `.slice(-arg.length) == arg`
* `.empty?` {{ caret }} `.length == 0`
* `.find_index` {{ caret }} `findIndex`
* `.first` {{ caret }} `[0]`
* `.first(n)` {{ caret }} `.slice(0, n)`
* `.floor` {{ caret }} `Math.floor()`
* `.gsub` {{ caret }} `replace(//g)`
* `.include?` {{ caret }} `.indexOf() != -1`
* `.inspect` {{ caret }} `JSON.stringify()`
* `.keys()` {{ caret }} `Object.keys()`
* `.last` {{ caret }} `[*.length-1]`
* `.last(n)` {{ caret }} `.slice(*.length-1, *.length)`
* `.lstrip` {{ caret }} `.replace(/^\s+/, "")`
* `.max` {{ caret }} `Math.max.apply(Math)`
* `.merge` {{ caret }} `Object.assign({}, ...)`
* `.merge!` {{ caret }} `Object.assign()`
* `.method_defined?` {{ caret }} `obj.hasOwnProperty(meth)` or `meth in obj`
* `.min` {{ caret }} `Math.min.apply(Math)`
* `.nil?` {{ caret }} `== null`
* `.ord` {{ caret }} `charCodeAt(0)`
* `puts` {{ caret }} `console.log`
* `.replace` {{ caret }} `.length = 0; ...push.apply(*)`
* `.respond_to?` {{ caret }} `right in left`
* `.rstrip` {{ caret }} `.replace(/s+$/, "")`
* `.scan` {{ caret }} `.match(//g)`
* `.sum` {{ caret }} `.reduce(function(a, b) {a + b}, 0)`
* `.start_with?` {{ caret }} `.substring(0, arg.length) == arg` or `.startsWith(arg)` for ES2015+
* `.upto(lim)` {{ caret }} `for (var i=num; i<=lim; i+=1)`
* `.downto(lim)` {{ caret }} `for (var i=num; i>=lim; i-=1)`
* `.step(lim, n).each` {{ caret }} `for (var i=num; i<=lim; i+=n)`
* `.step(lim, -n).each` {{ caret }} `for (var i=num; i>=lim; i-=n)`
* `(0..a).to_a` {{ caret }} `Array.apply(null, {length: a}).map(Function.call, Number)`
* `(b..a).to_a` {{ caret }} `Array.apply(null, {length: (a-b+1)}).map(Function.call, Number).map(function (idx) { return idx+b })`
* `(b...a).to_a` {{ caret }} `Array.apply(null, {length: (a-b)}).map(Function.call, Number).map(function (idx) { return idx+b })`
* `.strip` {{ caret }} `.trim`
* `.sub` {{ caret }} `.replace`
* `.tap {|n| n}` {{ caret }} `(function(n) {n; return n})(...)`
* `.to_f` {{ caret }} `parseFloat`
* `.to_i` {{ caret }} `parseInt`
* `.to_s` {{ caret }} `.to_String`
* `.upcase` {{ caret }} `.toUpperCase`
* `.yield_self {|n| n}` {{ caret }} `(function(n) {return n})(...)`
* `[-n]` {{ caret }} `[*.length-n]` for literal values of `n`
* `[n...m]` {{ caret }} `.slice(n,m)`
* `[n..m]` {{ caret }} `.slice(n,m+1)`
* `[/r/, n]` {{ caret }} `.match(/r/)[n]`
* `[/r/, n]=` {{ caret }} `.replace(/r/, ...)`
* `(1..2).each {|i| ...}` {{ caret }} `for (var i=1 i<=2; i+=1)`
* `"string" * length` {{ caret }} `new Array(length + 1).join("string")`
* `@foo.call(args)` {{ caret }} `this._foo(args)`
* `@@foo.call(args)` {{ caret }} `this.constructor._foo(args)`
* `Array(x)` {{ caret }} `Array.prototype.slice.call(x)`
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
* `raise Exception.new(...)` will be replaced with `throw new Error(...)`
* `block_given?` will check for the presence of optional argument `_implicitBlockYield` which is a function made accessible through the use of `yield` in a method body.
* `alias_method` works both inside of a class definition as well as called directly on a class name (e.g. `MyClass.alias_method`)

Additionally, there is one mapping that will only be done if explicitly
included (pass `include: :class` as a `convert` option to enable):

{:.functions-list}
* `.class` {{ caret }} `.constructor`

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/functions_spec.rb).
{% endrendercontent %}