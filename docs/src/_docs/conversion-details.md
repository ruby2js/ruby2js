---
order: 30
title: Conversion Details
top_section: Behind the Scenes
category: conversion-details
---

**Ruby2JS** makes writing JavaScript using Ruby idioms as straightforward as possible, but the devil is in the details. The following is a detailed explanation of what happens under the hood during the transpilation process and some of the thinking behind the various decisions made. 

{% toc %}

## Introduction

JavaScript is a language where `0` is considered `false`, strings are
immutable, and the behaviors for operators like `==` are, at best,
[convoluted](https://zero.milosz.ca/).

Any attempt to bridge the semantics of Ruby and JavaScript will involve
trade-offs.  Consider the following expression:

```ruby
a[-1]
```

Programmers who are familiar with Ruby will recognize that this returns the
last element (or character) of an array (or string).  However, the meaning is
quite different if `a` is a Hash.

One way to resolve this is to change the way indexing operators are evaluated,
and to provide a runtime library that adds properties to global JavaScript
objects to handle this.  This is the approach that [Opal](https://opalrb.com/)
takes.  It is a fine approach, with a number of benefits.  It also has some
notable drawbacks.  For example,
[readability](https://opalrb.com/try/#code:a%20%3D%20%22abc%22%3B%20puts%20a[-1])
and
[compatibility with other frameworks](https://github.com/opal/opal/issues/400).

Another approach is to simply accept JavaScript semantics for what they are.
This would mean that negative indexes would return `undefined` for arrays
and strings.  This is the base approach provided by Ruby2JS.

A third approach would be to do static transformations on the source in order
to address common usage patterns or idioms.  These transformations can even be
occasionally unsafe, as long as the transformations themselves are opt-in.
Ruby2JS provides a number of such filters, including one that handles negative
indexes when passed as a literal.  As indicated above, this is unsafe in that
it will do the wrong thing when it encounters a hash index which is expressed
as a literal constant negative one.  My experience is that such is rare enough
to be safely ignored, but YMMV.  More troublesome, this also won’t work when
the index is not a literal (e.g., `a[n]`) and the index happens to be
negative at runtime.

## Method Exclusions

This quickly gets into gray areas.  `each` in Ruby is a common method that
facilitates iteration over arrays.  `forEach` is the JavaScript equivalent.
Mapping this is fine until you start using a framework like jQuery which
provides a function named [each](https://api.jquery.com/jQuery.each/).

Fortunately, Ruby provides `?` and `!` as legal suffixes for method names,
Ruby2JS filters do an exact match, so if you select a filter that maps `each`
to `forEach`, `each!` will pass through the filter.  The final code that emits
JavaScript function calls and parameter accesses will strip off these
suffixes.

This approach works well if it is an occasional change, but if the usage is
pervasive, most filters support options to `exclude` a list of mappings,
for example:

```ruby
puts Ruby2JS.convert('jQuery("li").each {|index| ...}', exclude: :each)
```

Alternatively, you can change the default:

```ruby
Ruby2JS::Filter.exclude :each
```

Static transformations and runtime libraries aren't aren’t mutually exclusive.
With enough of each, one could reproduce any functionality desired.

## Syntax Mappings

  * a Ruby Hash literal becomes a JavaScript Object literal
  * Ruby symbols become JavaScript strings.
  * Ruby method calls become JavaScript function calls IF
    there are either one or more arguments passed OR
    parenthesis are used
  * otherwise Ruby method calls become JavaScript property accesses.
  * by default, methods and procs return `undefined`
  * splats mapped to spread syntax when ES2015 or later is selected, and
    to equivalents using `apply`, `concat`, `slice`, and `arguments` otherwise.
  * ruby string interpolation is expanded into string + operations
  * `and` and `or` become `&&` and `||`
  * `a ** b` becomes `Math.pow(a,b)`
  * `<< a` becomes `.push(a)`
  * `unless` becomes `if !`
  * `until` becomes `while !`
  * `case` and `when` becomes `switch` and `case`
  * ruby for loops become js for loops
  * `(1...4).step(2){` becomes `for (var i = 1; i < 4; i += 2) {`
  * `x.forEach { next }` becomes `x.forEach(function() {return})`
  * `lambda {}` and `proc {}` becomes `function() {}`
  * `class Person; end` becomes `function Person() {}`
  * `Class.new do; end` becomes `function () {}`
  * instance methods become prototype methods
  * instance variables become underscored, `@name` becomes `this._name`
  * self is assigned to this is if used
  * Any block becomes and explicit argument `new Promise do; y(); end` becomes `new Promise(function() {y()})`
  * regular expressions are mapped to js
  * `raise` becomes `throw`
  * `.is_a?` becomes `instanceof`
  * `.kind_of?` becomes `instanceof`
  * `.instance_of?` becomes `.constructor ==`

Ruby attribute accessors, methods defined with no parameters and no
parenthesis, as well as setter method definitions, are
mapped to
[Object.defineProperty](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/defineProperty?redirectlocale=en-US&redirectslug=JavaScript%2FReference%2FGlobal_Objects%2FObject%2FdefineProperty),
so avoid these if you wish to target users running IE8 or lower.

While both Ruby and JavaScript have open classes, Ruby unifies the syntax for
defining and extending an existing class, whereas JavaScript does not.  This
means that Ruby2JS needs to be told when a class is being extended, which is
done by prepending the `class` keyword with two plus signs, thus:
`++class C; ...; end`.

Filters may be provided to add Ruby-specific or framework specific
behavior.  Filters are essentially macro facilities that operate on
an AST representation of the code.

{% rendercontent "docs/note" %}
See
[notimplemented_spec](https://github.com/ruby2js/ruby2js/blob/master/spec/notimplemented_spec.rb)
for a list of Ruby features _known_ to be not implemented.
{% endrendercontent %}
