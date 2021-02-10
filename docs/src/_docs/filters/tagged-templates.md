---
order: 25
title: Tagged Templates
top_section: Filters
category: tagged-templates
---

The **Tagged Templates** filter allows you to turn certain method calls with a string argument into tagged template literals. By default it supports `html` and `css`, so you can write `html "<div>#{1+2}</div>"` which converts to `` html`<div>${1+2}</div>` ``.

Works nicely with squiggly heredocs for multiline templates as well. If you
need to configure the tag names yourself, pass a `template_literal_tags`
option to `convert` with an array of tag name symbols.

_Note: these conversions are only done if eslevel >= 2015_

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/tagged_templates_spec.rb).
{% endrendercontent %}
