---
order: 16
title: ESM
top_section: Filters
category: esm
---

The **ESM** filter provides conversion of import and export statements for use
with modern ES builders like Webpack and Snowpack.

## Examples

### import

```ruby
import "./index.scss"
# => import "./index.scss"

import Something from "./lib/something"
# => import Something from "./lib/something"

import Something, "./lib/something"
# => import Something from "./lib/something"

import [ LitElement, html, css ], from: "lit"
# => import { LitElement, html, css } from "lit"

import React, from: "react"
# => import React from "react"

import React, [ Component ], from: "react"
# => import React, { Component } from "react"

import "*", as: React, from: "react"
# => import * as React from "react"
```

### import.meta

The `import.meta` object is supported for accessing module metadata:

```ruby
import.meta.url
# => import.meta.url

URL.new("./data.json", import.meta.url)
# => new URL("./data.json", import.meta.url)
```

### \_\_FILE\_\_

Ruby's `__FILE__` constant is converted to `import.meta.url`, which provides the URL of the current module in ES modules:

```ruby
__FILE__
# => import.meta.url

puts __FILE__
# => puts(import.meta.url)
```

Note: `import.meta.url` returns a `file://` URL (e.g., `file:///path/to/file.js`). To get just the file path, you can use:

```ruby
URL.new(import.meta.url).pathname
# => new URL(import.meta.url).pathname
```

### export

```ruby
export hash = { ab: 123 }
# => export const hash = {ab: 123};

export func = ->(x) { x * 10 }
# => export const func = x => x * 10;

export def multiply(x, y)
  return x * y
end
# => export function multiply(x, y) {
#      return x * y
#    }

export default class MyClass
end
# => export default class MyClass {
#    };

# or final export statement:
export [ one, two, default: three ]
# => export { one, two, three as default }

# re-export all from another module:
export "*", from: "./utils.js"
# => export * from "./utils.js"
```

If the `autoexports` option is `true`, all top level modules, classes,
methods and constants will automatically be exported.

If the `autoexports` option is `:default`, and there is only one top level
module, class, method or constant it will automatically be exported as
`default`.  If there are multiple, each will be exported with none of them as
default.

## Require to Import Conversion

When the ESM filter is used **without** the [Require filter](require), it will convert `require` statements to `import` statements by analyzing the required files for exports.

```ruby
# Given a file lib/helper.rb containing:
# class Helper; end

require "lib/helper.rb"
# => import { Helper } from "./lib/helper.rb"
```

The ESM filter will:
1. Parse the required file
2. Detect exported classes, modules, constants, and methods
3. Generate an appropriate `import` statement

With the `autoexports` option enabled, top-level definitions in the required file are treated as exports:

```ruby
require "ruby2js/filter/esm"
puts Ruby2JS.convert('require "lib/myclass.rb"',
  file: __FILE__, autoexports: true)
# If lib/myclass.rb contains "class MyClass; end":
# => import { MyClass } from "./lib/myclass.rb"
```

With `autoexports: :default`, a single export becomes the default export:

```ruby
puts Ruby2JS.convert('require "lib/myclass.rb"',
  file: __FILE__, autoexports: :default)
# => import MyClass from "./lib/myclass.rb"
```

### Recursive Requires

The `require_recursive` option follows nested `require` and `require_relative` statements, generating import statements for all files in the dependency tree:

```ruby
puts Ruby2JS.convert('require "lib/main.rb"',
  file: __FILE__, autoexports: :default, require_recursive: true)
# If main.rb requires helper.rb which requires utils.rb:
# => import Main from "./lib/main.rb"; import Helper from "./lib/helper.rb"; import Utils from "./lib/utils.rb"
```

{% rendercontent "docs/note", title: "Using the Require Filter" %}
If the [Require filter](require) is included in the filter chain **before** the ESM filter, it will inline required files instead of converting them to imports. This is useful when you want to bundle all code into a single file rather than keeping separate modules.
{% endrendercontent %}

## Autoimports

The esm filter also provides a way to specify "autoimports" when you run the
conversion. It will add the relevant import statements automatically whenever
a particular class or function name is referenced. These can be either default
or named exports. Simply provide an `autoimports` hash with one or more keys
to the `Ruby2JS.convert` method. (NOTE: use camelCase names, not snake_case.) Examples:

```ruby
require "ruby2js/filter/esm"
puts Ruby2JS.convert('class MyElement < LitElement; end',
  eslevel: 2020, autoimports: {[:LitElement] => "lit"})
```

```js
// JavaScript output:
import { LitElement } from "lit"
class MyElement extends LitElement {}
```

```ruby
require "ruby2js/filter/esm"
puts Ruby2JS.convert('AWN.new({position: "top-right"}).success("Hello World")',
  eslevel: 2020, autoimports: {:AWN => "awesome-notifications"})
```

```js
// JavaScript output:
import AWN from "awesome-notifications"
new AWN({position: "top-right"}).success("Hello World")
```

The value of the `autoimports` option can be a `proc` or a `lambda` function,
in which case it will be invoked with each token eligible for importing.  If
this function returns `nil`, then no imports will be added.

The esm filter is able to recognize if you are defining a class or function
within the code itself and it won't add that import statement accordingly.
If for some reason you wish to disable autoimports entirely on a file-by-file
basis, you can add a magic comment to the top of the code:

```ruby
require "ruby2js/filter/esm"
puts Ruby2JS.convert(
  "# autoimports: false\n" +
  'AWN.new({position: "top-right"}).success("Hello World")',
  eslevel: 2020, autoimports: {:AWN => "awesome-notifications"}
)
```

```js
// autoimports: false
new AWN({position: "top-right"}).success("Hello World")
```

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/esm_spec.rb).
{% endrendercontent %}
