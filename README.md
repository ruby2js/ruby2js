ruby2js
=======

Minimal yet extensible Ruby to JavaScript conversion.  

Description
---

The base package maps Ruby syntax to JavaScript semantics.  For example,
a Ruby Hash literal becomes a JavaScript Object literal.  Ruby symbols
become JavaScript strings.  Ruby method calls become JavaScript function
calls IF there are either one or more arguments passed OR parenthesis are
used, otherwise Ruby method calls become JavaScript property accesses.
By default, methods, lambdas, and procs return `undefined`.

Filters may be provided to add Ruby-specific or framework specific
behavior.  Filters are essentially macro facilities that operate on
an AST representation of the code.

See
[notimplemented_spec](https://github.com/rubys/ruby2js/blob/master/spec/notimplemented_spec.rb)
for a list of Ruby features _known_ to be not implemented.

Synopsis
---

Basic:

```ruby
require 'ruby2js'
puts Ruby2JS.convert("a={age:3}\na.age+=1")
```

With filter:

```ruby
require 'ruby2js/filter/functions'
puts Ruby2JS.convert('"2A".to_i(16)')
```

Conversions can be explored interactively using the
[demo](https://github.com/rubys/ruby2js/blob/master/demo/ruby2js.rb) provided.

Introduction
---

JavaScript is a language where `0` is considered `false`, strings are
immutable, and the [behaviors](http://zero.milosz.ca/) for operators like `==` 
are, at best, convoluted.

Any attempt to bridge the semantics of Ruby and JavaScript will involve
trade-offs.  Consider the following expression:

```ruby
a[-1]
```

Programmers who are familiar with Ruby will recognize that this returns the
last element (or character) of an array (or string).  However, the meaning is
quite different if a is a Hash.

One way to resolve this is to change the way indexing operators are evaluated,
and to provide a runtime library that adds properties to global JavaScript
objects to handle this.  It’s the approach that [Opal](http://opalrb.org/)
takes.  It is a fine approach, with a number of benefits.  It also has some
notable drawbacks.  For example,
[Readability](http://opalrb.org/try/#code:a%20%3D%20%22abc%22%3B%20puts%20a[-1])
and 
[compatibility with other frameworks](https://github.com/opal/opal/issues/400).

Another approach is to simply accept JavaScript semantics for what they are.
This would mean that negative indexes would return `undefined` for arrays
and strings.  This is the base approach provided by ruby2js.

A third approach would be to do static transformations on the source in order
to address common usage patterns or idioms.  These transformations can even be
occasionally unsafe, as long as the transformations themselves are opt-in.
ruby2js provides a number of such filters, including one that handles negative
indexes when passes as a literal.  As indicated above, this is unsafe in that
it will do the wrong thing when it encounters a hash index which is expressed
as a literal constant negative one.  My experience is that such is rare enough
to be safely ignored, but YMMV.  More troublesome, this also won’t work when
the index is not a literal (e.g., `a[n]`) where the index happens to be
negative at runtime.

This quickly gets into gray areas.  `each` in Ruby is a common method that
facilitates iteration over arrays.  `forEach` is the JavaScript equivalent.
Mapping this is fine until you start using a framework like jQuery which
provides a function named [each](http://api.jquery.com/jQuery.each/).

These approaches aren’t mutually exclusive. With enough static transformations
and runtime libraries, one could reproduce any functionality desired.  Just be
forewarned, that implementing a function like `method_missing` would require a
_lot_ of work.

Picking a Ruby to JS mapping tool
---

If you simply want to get a job done, and would like a mature and tested
framework, and only use one of the many integrations that
[opal](http://opalrb.org/) provides, then Opal is the way to go right now.

ruby2js is for those that want to produce JavaScript that looks like it
wasn’t machine generated, and with the absolute bare minimum in terms of
limitations as to what JavaScript can be produced.

[Try](http://intertwingly.net/projects/ruby2js/all) for yourself.
[compare](http://opalrb.org/try/#code:).

License
---

(The MIT License)

Copyright (c) 2009,2013 Macario Ortega, Sam Ruby

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
