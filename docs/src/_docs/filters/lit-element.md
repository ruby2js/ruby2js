---
order: 17
title: Lit-Element
top_section: Filters
category: litelement
---

The **Lit-Element** filter makes it easier to build
[LitElement](https://lit-element.polymer-project.org/) controllers.

When a class definition is encountered that derives from
`LitElement`, the following transformations are applied:

 * an `import` statement for LitElement will be generated if the [esm](./esm)
   filter is also applied.

 * instance variables (e.g., `@x`) are **not** mapped to properties prefixed
   with either an underscore (`_`) or a hash (`#`).  

 * References to instance variables will cause entries to be added to the
   `static get properties` function if not already present, and simple type
   inferencing will be used to determine the type.

 * `self.style` methods that return a string will have that string mapped to a
   `css` literal string.

 * `render` methods that return a string will have that string mapped to a
   `html` literal string if that string starts with a less than sign.  This
   also applies, recursively, to all interpolated values within that string.

 * Methods referenced within HTML literals are not automatically bound, but
   will be automatically prefixed with `this.`.

 * If `super` is not called by the `initialize` function, a call to `super`
   will be added.

For more information, see the [Rails example](../../examples/rails/lit-element).

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the
[specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/litelement_spec.rb).
{% endrendercontent %}

