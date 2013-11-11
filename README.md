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

Filters may be provided to add Ruby-specific or Framework specific
behavior.  Filters are essentially macro facilities that operate on
an AST representation of the code.

Synopsis
---

```ruby
require 'ruby2js/filter/functions'
puts Ruby2JS.convert('"2A".to_i(16)', filters: [Ruby2JS::Filter::Functions])
```

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
