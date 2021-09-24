---
order: 17
title: Lit
top_section: Filters
category: litelement
---

The **Lit** filter makes it easier to build
[LitElement](https://lit.dev/) web components.

When a class definition is encountered that derives from
`LitElement`, the following transformations are applied:

 * an `import` statement for LitElement will be generated if the [esm](./esm)
   filter is also applied.

 * instance variables (e.g., `@x`) are **not** mapped to properties prefixed
   with either an underscore (`_`) or a hash (`#`).  

 * References to instance variables will cause entries to be added to the
   `static properties` property if not already present, and simple type
   inferencing will be used to determine the type.

 * `@styles` assignments, `self.styles` assignments and `self.styles` methods
   that return a string will have that string mapped to a
   `css` literal string.  These are three alternate syntaxes to specifying
   [static styles](https://lit.dev/docs/components/styles/).

 * `render` methods that return a string will have that string mapped to a
   `html` literal string if that string starts with a less than sign.  This
   also applies, recursively, to all interpolated values within that string.

 * Methods referenced within HTML literals are not automatically bound, but
   will be automatically prefixed with `this.`.

 * LitElement inheritance will also automatically prefix inherited properties
   and methods with `this.`, and will autobind inherited methods when
   referenced without any parameters or parenthesis.
     * methods: `performUpdate`,`requestUpdate`
     * properties: `hasUpdated`, `renderRoot`, `shadowRoot`, `updateComplete`

 * `customElement` calls are converted to `customElements.define` calls.

 * `query`, `queryAll`, and `queryAsync` calls are converted to corresponding
   `this.renderRoot.querySelector` calls.

 * If `super` is not called by the `initialize` function, a call to `super`
   will be added.

For more information, see the [Rails example](../../examples/rails/lit).

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the
[specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/lit_spec.rb).
{% endrendercontent %}

