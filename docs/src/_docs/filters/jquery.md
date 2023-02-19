---
order: 33
title: jQuery
top_section: Deprecations
category: jquery
---

{% rendercontent "docs/note", type: "warning" %}
This filter has been deprecated and will be removed in Ruby2JS 6.0.
{% endrendercontent %}

The **jQuery** filter enhances the interaction between Ruby syntax and common jQuery functionality:

* maps Ruby unary operator `~` to jQuery `$` function
* also maps `$$` to jQuery `$` function
* maps Ruby attribute syntax to jQuery attribute syntax
* `.to_a` becomes `toArray`
* defaults the fourth parameter of $$.post to `"json"`, allowing Ruby block
  syntax to be used for the success function.

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/jquery_spec.rb).
{% endrendercontent %}