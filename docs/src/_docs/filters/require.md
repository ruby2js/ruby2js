---
order: 22
title: Require
top_section: Filters
category: require
---

The **Require** filter supports Ruby-style `require` and `require_relative` statements.  `require` function calls in expressions are left alone.

If the [esm](esm) filter is used and the code being required contains
[`export`](esm#export) statements (either explicitly or via the `autoexports`
option), then the require statement will be replaced with an `import`
statement referencing the top level classes, modules, constants, and methods
defined in that source.

If no exports are found, the required file is converted to JavaScript and expanded inline. 

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/require_spec.rb).
{% endrendercontent %}
