---
order: 21
title: Require
top_section: Filters
category: require
---

The **Require** filter supports Ruby-style `require` and `require_relative` statements.  Contents of files that are required are converted to JavaScript and expanded inline. `require` function calls in expressions are left alone.

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/require_spec.rb).
{% endrendercontent %}
