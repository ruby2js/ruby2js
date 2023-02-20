---
order: 35
title: matchAll
top_section: Deprecations
category: matchall
---

{% rendercontent "docs/note", type: "warning" %}
This filter has been deprecated and will be removed in Ruby2JS 6.0.
{% endrendercontent %}

For ES level < 2020:

* maps `str.matchAll(pattern).forEach {}` to 
  `while (match = pattern.exec(str)) {}`

Note `pattern` must be a simple variable with a value of a regular
expression with the `g` flag set at runtime.

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/matchAll_spec.rb).
{% endrendercontent %}
