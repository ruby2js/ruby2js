---
order: 39
title: Require
top_section: Deprecations
category: require
---

{% rendercontent "docs/note", type: "warning" %}
This filter has been deprecated and will be removed in Ruby2JS 6.0.
{% endrendercontent %}

The **Require** filter supports Ruby-style `require` and `require_relative` statements.  `require` function calls in expressions are left alone.

If the [esm](esm) filter is used and the code being required contains
[`export`](esm#export) statements (either explicitly or via the `autoexports`
option), then the require statement will be replaced with an `import`
statement referencing the top level classes, modules, constants, and methods
defined in that source.

If the `require_recursive` option is specified, then all symbols defined by all
sources referenced by the transitive closure of all requires defined by that
source.

If no exports are found, the required file is converted to JavaScript and expanded inline. 

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/require_spec.rb).
{% endrendercontent %}
