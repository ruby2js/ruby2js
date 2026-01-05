---
order: 390
title: Require
top_section: Filters
category: require
---

The **Require** filter supports Ruby-style `require` and `require_relative` statements by inlining the referenced files.

When this filter is active, `require` and `require_relative` statements are processed by:
1. Reading the referenced Ruby file
2. Converting it to JavaScript
3. Inlining the result at the location of the require statement

This allows you to organize your Ruby source code across multiple files while producing a single bundled JavaScript output.

`require` function calls in expressions (e.g., `fs = require("fs")`) are left alone since they represent dynamic requires, not static file inclusions.

{% rendercontent "docs/note", title: "ESM Import Conversion" %}
If you want `require` statements to be converted to ES module `import` statements instead of being inlined, use the [ESM filter](esm) **without** the Require filter. See the [ESM filter documentation](esm#require-to-import-conversion) for details.
{% endrendercontent %}

## Skipping Specific Requires

You can prevent specific `require` or `require_relative` statements from being inlined by using the `skip` pragma:

```ruby
require 'json' # Pragma: skip
require_relative 'helper'
```

In this example, `require 'json'` will be removed from the output (since `json` is a Ruby-only library), while `require_relative 'helper'` will be processed normally and its contents inlined.

This allows the Require filter to be run before the Pragma filter in the filter chain while still respecting skip directives.

See the [Pragma filter documentation](pragma#skip) for more details on the `skip` pragma.

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/require_spec.rb).
{% endrendercontent %}
