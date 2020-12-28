---
order: 9
title: matchAll
top_section: Filters
category: matchall
---

For ES level < 2020:

* maps `str.matchAll(pattern).forEach {}` to 
  `while (match = pattern.exec(str)) {}`

Note `pattern` must be a simple variable with a value of a regular
expression with the `g` flag set at runtime.

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/matchAll_spec.rb).
{% endrendercontent %}