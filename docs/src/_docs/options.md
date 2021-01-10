---
order: 2
title: Options
top_section: Introduction
category: options
---

## Auto Exports

The [ESM](esm) filter has an option to automatically export all top
level constants, methods, classes, and modules.

```ruby
require 'ruby2js/filter/esm'
puts Ruby2JS.convert("X = 1", autoexports: true)
```

## Auto Imports

The [ESM](esm) filter has an option to automatically import selected
modules if a given constant is encountered in the parsing of the source.
See [the ESM filter](filters/esm#autoimports) for details.

```ruby
require 'ruby2js/filter/esm'
puts Ruby2JS.convert('class MyElement < LitElement; end',
  eslevel: 2020, autoimports: {[:LitElement] => 'lit-element'})
```

## Binding

If the [binding](https://ruby-doc.org/core-3.0.0/Binding.html) option is
provided, expressions passed in back-tic <code>``</code> or `%x()` expressions
will be evaluated in the host context.  This is very unsafe if there is any
possibility of the script being provided by external sources; in such cases
[ivars](#ivars) are a much better alternative.

```ruby
require 'ruby2js'
puts Ruby2JS.convert('x = `Dir["*"]`', binding: binding)
```

## Comparison

While both Ruby and JavaScript provide double equal and triple equal
operators, they do different things.  By default (or by selecting
`:equality`), Ruby double equals is mapped to JavaScript double equals and
Ruby triple equals is mapped to JavaScript triple equals.  By selecting
`:identity`), both Ruby double equals and Ruby triple equals are mapped to
JavaScript triple equals.

```ruby
require 'ruby2js'
puts Ruby2JS.convert('a == b', comparison: :identity)
```

## ESLevel

Determine which ECMAScript level the resulting script will target.  See
[eslevels](eslevels) for details.

```ruby
require 'ruby2js'
puts Ruby2JS.convert("x ||= 1", eslevel: 2021)
```

## Exclude

Many filters include multiple conversions; and there may be cases where
a some of these conversions interfere with the intent of the code in
question.  The `exclude` option allows you to eliminate selected methods
from being eligible for conversion.
See also [Include](#include), [Include All](#include-all), and
[Include Only](#include-only).

```ruby
require 'ruby2js/filter/functions'
puts Ruby2JS.convert(
  "jQuery.each(x) do |i,v| text += v.textContent; end",
  exclude: [:each]
)
```

## Filters

By default, all filters that your code `require`s will be invoked in
every conversion.  The `filters` option allows you to control which
filters are actually applied to a specific conversion.  

```ruby
require 'ruby2js/filter/functions'
puts Ruby2JS.convert("list.empty?",
  filters: [Ruby2JS::Filter::Functions])
```

## Include

Some filters include conversions that may interfere with common usage and
therefore are only available via opt-in.  The `include` option allows you to
select additional methods to be eligible for conversion.  See also
[Exclude](#exclude), [Include All](#include-all), and 
[Include Only](#include-only).

```ruby
require 'ruby2js/filter/functions'
puts Ruby2JS.convert("object.class", include: [:class])
```

## Include All

Some filters include conversions that may interfere with common usage and
therefore are only available via opt-in.  The `include` option allows you to
opt into all available conversions.  See also [Exclude](#exclude),
[Include](include), and [Include Only](#include-only).

```ruby
require 'ruby2js/filter/functions'
puts Ruby2JS.convert("object.class", include_all: true)
```

## Include Only

Many filters include multiple conversions; and there may be cases where
a some of these conversions interfere with the intent of the code in
question.  The `include-olnly` option allows you to selected which methods
are eligible for conversion.
See also [Exclude](#exclude), [Include](#include), and 
[Include All](#include-all).

```ruby
require 'ruby2js/filter/functions'
puts Ruby2JS.convert("list.max()", include_only: [:max])
```

## Import From Skypack

Some filters, like [active_functions](filters/active_functions) will generate
import statements.  If the `import_from_skypack` option is set, these import
statements will make use of the [skypack](https://www.skypack.dev/) CDN.

```ruby
require 'ruby2js/filter/active_functions'
puts Ruby2JS.convert("x.present?",
  eslevel: 2015, import_from_skypack: true)
```

## IVars

Instance Variables (ivars) allow you to supply data to the script.  A common
use case is when the script is a view template.  See also [scope](#scope).


```ruby
require 'ruby2js'
puts Ruby2JS.convert("X = @x", ivars: {:@x => 1})
```

## Or

Introduced in ES2020, the [Nullish Coalescing] operator provides an alternative
implementation of the *or* operator.  Select which version of the operator you
want using the `or` option.  Permissible values are `:logical` and `:nullish`
with the default being logical.

```ruby
require 'ruby2js'
puts Ruby2JS.convert("a || b", or: :nullish, eslevel: 2020)
```

## Scope

Make all Instance Variables (ivars) in a given scope available to the
script.  See also [ivars](#ivars).

```ruby
require "ruby2js"
@x = 5
puts Ruby2JS.convert("X = @x", scope: self)
```

## Strict

Inserts `"use strict"` at the top of the output, causing the resulting script
to be run in 
[strict mode](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Strict_mode).
Typically this option is used in combination with setting [eslevel](eslevel)
to a value of `2015` or greater.

```ruby
require 'ruby2js'
puts Ruby2JS.convert("undefined = 5", strict: true)
```

## Template Literal Tags

The [Tagged Templates](filters/tagged-templates) filter will convert method
calls to a set of methods you provide to tagged template literal syntax.

```ruby
require 'ruby2js/filter/tagged_templates'
Ruby2JS.convert("color 'red'", template_literal_tags: [:color], eslevel: 2015)
```

## Underscored private

Private fields in JavaScript classes differ from instance variables in Ruby
classes in that subclasses can't access private fields in parent classes.  
The `underscored_private` option makes such variables public but prefixed with
an underscore instead.

```ruby
require 'ruby2js'
puts Ruby2JS.convert('class C; def initialize; @a=1; end; end', eslevel: 2020,
  underscored_private: true)
```

## Width

Ruby2JS tries, but does not guarantee, to produce output limited to 80 columns
in width.  You can change this value with the `width` option.

```ruby
require 'ruby2js/filter/functions'
puts Ruby2JS.convert("puts list.last unless list.empty?\n", width: 40)
```
