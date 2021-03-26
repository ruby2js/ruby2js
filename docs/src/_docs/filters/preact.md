---
order: 22
title: Preact
top_section: Filters
category: preact
---

Due to implementing a nearly identical API, there is no separate Preact
filter.  Instead, the **React** filter also enables you to build
[Preact](https://preactjs.com/) components.

When a class definition is encountered that derives from either `Preact` or
`Preact::Controller`, all of the transformations defined by the [React
filter](./react) will be applied with the following differences:

 * An `import` statement for Preact will be generated

 * `Preact.h` and more simply `h` calls can be used to create elements.  The
   JSX-like syntax as well as the [Wunderbar](https://github.com/rubys/wunderbar#readme) syntax.
   continue to be supported, and will generate `Preact.h` calls and references to
   `Preact.Fragment` as needed.

 * `onInput` instead of `onChange` functions are automatically generated for
   [controlled components](https://reactjs.org/docs/forms.html#controlled-components).
   For compatibility, `onChange` attributes on these elements will be replaced
   with `onInput`.

 * For compatibility,
     * `onDoubleClick` attributes will be mapped to `onDblClick` attributes.
     * `className` attributes will be mapped to `class` attributes.
     * `htmlFor` attributes will be mapped to `for` attributes.

For more information, see the [examples provided](../../examples/preact).

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the 
[specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/preact_spec.rb).
{% endrendercontent %}
