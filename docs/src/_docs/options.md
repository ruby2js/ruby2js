---
order: 2
title: Options
top_section: Introduction
category: options
---

Ruby2JS provides quite a few options to help you configure your transpilation process.

{% toc %}

## Preset Configuration

Starting with Ruby2JS 5.1, we've created a single "preset" configuration option which provides you with a sane set of modern conversion defaults. This includes:

* The [Functions](/docs/filters/functions), [ESM](/docs/filters/esm), and [Return](/docs/filters/return) filters
* ES2021 support
* Underscored fields for ivars (`@ivar` becomes `this._ivar`)
* Identity comparison (`==` becomes `===`)

You can pass `preset: true` as an option to the Ruby2JS API or `--preset` via the CLI. In addition, you can set it in your configuration file should you choose to have one.

Finally, for maximum portability (great for code sharing!) you can use a **magic comment** at the top of a file to set the preset mode:

```
# ruby2js: preset
```

You can also configure additional filters plus eslevel, and disable preset filters individually too:

```
# ruby2js: preset, filters: camelCase

# ruby2js: preset, eslevel: 2025

# ruby2js: preset, disable_filters: return
```

## Create Your Own Configuration

There are a number of configuration options available for both the converter itself as well as any filters you choose to add.

If you find yourself needing a centralized location to specify these options for your project, create an `config/ruby2js.rb` file in your project root. Example:

```ruby
preset

filter :camelCase

eslevel 2022

include_method :class
```

If you need to specify a custom location for your config file, you can use the `config_file` argument in the Ruby DSL, or the `-C` or `--config` options in the CLI.

Otherwise, Ruby2JS will automatically file the `config/ruby2js.rb` file in the current working directory.

```ruby
# some_other_script.rb

ruby_code = <<~RUBY
  export toggle_menu_icon = ->(button) do
    button.query_selector_all(".icon").each do |item|
      item.class_list.toggle "not-shown"
    end
    button.query_selector(".icon:not(.not-shown)").class_list.add("shown")
  end
RUBY

js_code = Ruby2JS.convert(ruby_code) # picks up config automatically
```

Keep reading for all the options you can add to the configuration file.

## Auto Exports

The ESM filter has an option to automatically export all top
level constants, methods, classes, and modules.

```ruby
# Configuration

autoexports true # or :default
```

```ruby
puts Ruby2JS.convert("X = 1", filters: [:esm], autoexports: true)
```

If the `autoexports` option is `:default`, and there is only one top level
module, class, method or constant it will automatically be exported as
`default`.  If there are multiple, each will be exported with none of them as
default.

## Auto Imports

The ESM filter has an option to automatically import selected
modules if a given constant is encountered in the parsing of the source.
See [the ESM filter](filters/esm#autoimports) for details.

```ruby
# Configuration

autoimport [:LitElement], 'lit'
```

```ruby
puts Ruby2JS.convert('class MyElement < LitElement; end',
  preset: true, autoimports: {[:LitElement] => 'lit'})
```

## Binding

If the [binding](https://ruby-doc.org/core-3.0.0/Binding.html) option is
provided, expressions passed in back-tic <code>``</code> or `%x()` expressions
will be evaluated in the host context.  This is very unsafe if there is any
possibility of the script being provided by external sources; in such cases
[ivars](#ivars) are a much better alternative.

```ruby
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
# Configuration

identity_comparison
```

```ruby
puts Ruby2JS.convert('a == b', comparison: :identity)
```

## Defs

List of methods and properties for classes and modules imported via
[autoimports](#auto-imports).  Prepend an `@` for properties.

```ruby
# Configuration

defs({A: [:x,:@y]})
```

```ruby
puts Ruby2JS.convert('class C < A; def f; x; end; end',
  defs: {A: [:x,:@y]}, filters: [:esm], eslevel: 2020, autoimports: {A: 'a.js'})
```

## ESLevel

Determine which ECMAScript level the resulting script will target.  See
[eslevels](eslevels) for details.

```ruby
# Configuration

eslevel 2021
```

```ruby
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
puts Ruby2JS.convert(
  "jQuery.each(x) do |i,v| text += v.textContent; end",
  preset: true, exclude: [:each]
)
```

## Filters

The `filters` option (`filter` in the configuration file) allows you to control which available filters are applied to a specific conversion.  

```ruby
# Configuration

filter :functions
filter :camelCase
```

```ruby
puts Ruby2JS.convert("my_list.empty?", filters: [:functions, :camelCase])
```

You can also remove filters if you're using the preset configuration and you want to take one out:

```ruby
# Configuration

preset

remove_filter :esm
```

See our documentation for various filters over on the sidebar.

## Include

Some filters include conversions that may interfere with common usage and therefore are only available via opt-in.  The `include` option (`include_method` in the configuration file) allows you to select additional methods to be eligible for conversion.

```ruby
# Configuration

include_method :class
```

```ruby
puts Ruby2JS.convert("object.class", preset: true, include: [:class])
```

See also
[Exclude](#exclude), [Include All](#include-all), and 
[Include Only](#include-only).

## Include All

Some filters include conversions that may interfere with common usage and
therefore are only available via opt-in.  The `include_all` option allows you to
opt into all available conversions.  See also [Exclude](#exclude),
[Include](include), and [Include Only](#include-only).

```ruby
puts Ruby2JS.convert("object.class", preset: true, include_all: true)
```

## Include Only

Many filters include multiple conversions; and there may be cases where
a some of these conversions interfere with the intent of the code in
question.  The `include-only` option allows you to selected which methods
are eligible for conversion.
See also [Exclude](#exclude), [Include](#include), and 
[Include All](#include-all).

```ruby
puts Ruby2JS.convert("list.max()", preset: true, include_only: [:max])
```

## Import From Skypack

Some filters like [ActiveFunctions](filters/active_functions) will generate
import statements.  If the `import_from_skypack` option is set, these import
statements will make use of the [skypack](https://www.skypack.dev/) CDN.

```ruby
puts Ruby2JS.convert("x.present?",
  preset: true, filters: [:active_functions], import_from_skypack: true)
```

## IVars

Instance Variables (ivars) allow you to supply data to the script.  A common
use case is when the script is a view template.  See also [scope](#scope).


```ruby
puts Ruby2JS.convert("X = @x", ivars: {:@x => 1})
```

## Nullish To S

Ruby's `nil.to_s` returns an empty string, but JavaScript's `null.toString()` throws an error,
and `String(null)` returns `"null"`. Similarly, string interpolation in Ruby like `"#{nil}"` produces `""`,
but JavaScript's `` `${null}` `` produces `"null"`.

The `nullish_to_s` option wraps these operations with the nullish coalescing operator (`??`) to match
Ruby's behavior. This requires ES2020 or later.

```ruby
# Configuration

nullish_to_s
```

```ruby
# to_s becomes nil-safe
puts Ruby2JS.convert("x.to_s", nullish_to_s: true, eslevel: 2020)
# => (x ?? "").toString()

# String() becomes nil-safe
puts Ruby2JS.convert("String(x)", nullish_to_s: true, eslevel: 2020, filters: [:functions])
# => String(x ?? "")

# Interpolation becomes nil-safe
puts Ruby2JS.convert('"hello #{x}"', nullish_to_s: true, eslevel: 2020)
# => `hello ${x ?? ""}`
```

## Or

Ruby's `||` operator treats only `nil` and `false` as falsy. JavaScript's `||` operator treats `null`, `undefined`, `false`, `0`, `""`, and `NaN` as falsy. This difference can cause subtle bugs when transpiling Ruby code.

**The default is `:nullish`**, which maps Ruby's `||` to JavaScript's `??` (nullish coalescing). This is closer to Ruby semantics because `??` only treats `null` and `undefined` as falsy, preserving values like `0` and `""`.

| Ruby Expression | `or: :nullish` (default) | `or: :logical` |
|-----------------|--------------------------|----------------|
| `count \|\| 0` | `count ?? 0` | `count \|\| 0` |
| `0 \|\| 42` | `0` (0 is kept) | `42` (0 is falsy in JS) |
| `"" \|\| "default"` | `""` (empty string kept) | `"default"` |
| `false \|\| true` | `false` (⚠️ differs from Ruby) | `true` |

{% rendercontent "docs/note", type: "warning" %}
**Note about `false`:** Ruby's `||` treats `false` as falsy, but JavaScript's `??` does not. If your code relies on `false || x` returning `x`, use `or: :logical` or consider the `truthy: :ruby` option for exact Ruby semantics.
{% endrendercontent %}

In boolean contexts (comparisons, predicates ending in `?`, etc.), Ruby2JS automatically uses `||` even when `:nullish` is set, since the nullish distinction doesn't matter for boolean results:

```ruby
# These always use || regardless of :or setting
a > 5 || b < 3      # => a > 5 || b < 3
a.empty? || b.nil?  # => a.empty || b.nil
```

### Configuration

```ruby
# Configuration file - use nullish (default)
nullish_or

# Configuration file - use logical
logical_or
```

```ruby
# API usage
puts Ruby2JS.convert("a || b")                    # => a ?? b (default)
puts Ruby2JS.convert("a || b", or: :logical)      # => a || b
puts Ruby2JS.convert("a || b", or: :nullish)      # => a ?? b
```

## Truthy

Ruby and JavaScript have different definitions of truthiness. In Ruby, only `false` and `nil` are falsy - all other values (including `0`, `""`, and `NaN`) are truthy. In JavaScript, `false`, `null`, `undefined`, `0`, `""`, and `NaN` are all falsy.

The `truthy` option controls how the `||`, `&&`, `||=`, and `&&=` operators handle truthiness:

- `truthy: :ruby` - Use Ruby-style truthiness (only `false` and `nil` are falsy)
- `truthy: :js` - Use standard JavaScript truthiness (explicit, same as default)

```ruby
# Configuration

truthy :ruby
```

```ruby
puts Ruby2JS.convert("a || b", truthy: :ruby)
```

This outputs:

```javascript
const $T=v=>v!==false&&v!=null; const $ror=(a,b)=>$T(a)?a:b(); $ror(a, () => b)
```

With `truthy: :ruby` enabled:

| Ruby Expression | `truthy: :js` (default) | `truthy: :ruby` |
|-----------------|-------------------------|-----------------|
| `0 \|\| 42` | `42` (JS: 0 is falsy) | `0` (Ruby: 0 is truthy) |
| `"" \|\| "fallback"` | `"fallback"` (JS: "" is falsy) | `""` (Ruby: "" is truthy) |
| `0 && 42` | `0` (JS: 0 is falsy) | `42` (Ruby: 0 is truthy) |

{% rendercontent "docs/note", type: "warning", title: "Performance Consideration" %}
The `truthy: :ruby` option adds small helper functions and wraps expressions in function calls to preserve short-circuit evaluation. This has minimal performance impact but does increase code size slightly.
{% endrendercontent %}

## Module

Controls the module format for import/export statements. The default is `:esm` (ES Modules).

```ruby
# Configuration - use ES Modules (default)
esm_modules

# Configuration - use CommonJS
cjs_modules
```

```ruby
# API usage
puts Ruby2JS.convert("export x = 1", module: :esm)   # => export let x = 1
puts Ruby2JS.convert("export x = 1", module: :cjs)   # => exports.x = 1
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

Adds `"use strict";` at the beginning of the generated JavaScript output.

```ruby
puts Ruby2JS.convert("x = 1", strict: true)
# => "use strict"; let x = 1
```

## Template Literal Tags

The [Tagged Templates](filters/tagged-templates) filter will convert method
calls to a set of methods you provide to tagged template literal syntax.

```ruby
# Configuration

template_literal_tags [:color]
```

```ruby
Ruby2JS.convert("color 'red'",
  preset: true, filters: [:tagged_templates], template_literal_tags: [:color])
```

## Underscored private

Private fields in JavaScript classes differ from instance variables in Ruby classes in that subclasses can't access private fields in parent classes.  The `underscored_private` (`underscored_ivars` in the configuration file) option makes such variables public but prefixed with an underscore instead.

```ruby
# Configuration

underscored_ivars
```

```ruby
puts Ruby2JS.convert('class C; def initialize; @a=1; end; end', eslevel: 2020,
  underscored_private: true)
```

## Width

Ruby2JS tries, but does not guarantee, to produce output limited to 80 columns
in width.  You can change this value with the `width` option.

```ruby
puts Ruby2JS.convert("puts list.last unless list.empty?\n", preset: true, width: 50)
```

## Configuring JavaScript Packages

When configuring the Node version of Ruby2JS, note that the options are expressed in JSON format instead of
as a Ruby Hash.  The following rules will help explain the conversions
necessary:

  * use strings for symbols
  * for `functions`, specify string names not module names
  * for `autoimports`, specify keys as strings, even if key is an array
  * not supported: `binding`, `ivars`, `scope`

Currently the new configuration file format (`config/ruby2js.rb`) isn't supported by the Node version of Ruby2JS either.

An example of all of the supported options:

```json
{
  "autoexports": true,
  "autoimports": {"[:LitElement]": "lit"},
  "comparison": "identity",
  "defs": {"A": ["x", "@y"]},
  "eslevel": 2021,
  "exclude": ["each"],
  "filters": ["functions"],
  "include": ["class"],
  "include_all": true,
  "include_only": ["max"],
  "import_from_skypack": true,
  "module": "esm",
  "nullish_to_s": true,
  "or": "nullish",
  "preset": true,
  "require_recursive": true,
  "strict": true,
  "template_literal_tags": ["color"],
  "truthy": "ruby",
  "underscored_private": true,
  "width": 40
}
```
