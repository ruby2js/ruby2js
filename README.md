Ruby2JS
=======

Minimal yet extensible Ruby to JavaScript conversion.  

[![Build Status](https://travis-ci.org/rubys/ruby2js.svg)](https://travis-ci.org/rubys/ruby2js)
[![Gem Version](https://badge.fury.io/rb/ruby2js.svg)](https://badge.fury.io/rb/ruby2js)
[![Gitter](https://badges.gitter.im/ruby2js/community.svg)](https://gitter.im/ruby2js/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)


Documentation
---

* Visit **[ruby2js.com](https://www.ruby2js.com)** for detailed setup instructions and API reference.

* [Try Ruby2JS online](https://ruby2js.com/demo)


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

Host variable substitution:

```ruby
 puts Ruby2JS.convert("@name", ivars: {:@name => "Joe"})
```

Enable ES2015 support:

```ruby
puts Ruby2JS.convert('"#{a}"', eslevel: 2015)
```


License
---

(The MIT License)

Copyright (c) 2009, 2020 Macario Ortega, Sam Ruby, Jared White

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
