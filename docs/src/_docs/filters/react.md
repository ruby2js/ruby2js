---
order: 21
title: React
top_section: Filters
category: react
---

The **React** filter enables you to build [React](https://reactjs.org/) components.

When a class definition is encountered that derives from `React::Controller`,
the following transformations are applied:

 * An `import` statement for React will be generated

 * `intialize` methods will construct `this.state`

 * Instance variables (`@var`) accesses will be mapped to `this.state`.
   Instance variable updates will be mapped to `this.setState`.

     * Except within `componentWillReceiveProps` methods, where accesses are
       mapped to the first argument passed.

 * Class variables (`@@var`) will be mapped to `this.props`.  Updates to class
   variables is not supported.

 * Three different HTML rendering syntaxes are supported:
     * `React.createElement` calls.
     * A JSX-like syntax, wrapped in `%x{...}`.  This differs from JSX
       primarily in that expressions are in Ruby syntax.
     * [Wunderbar](https://github.com/rubys/wunderbar#readme) syntax.

 * When using either JSX-like or Wunderbar syntaxes, sequences of elements
   will automatically be wrapped in 
   [React Fragments](https://reactjs.org/docs/fragments.html) when they occur
   in places where a single element is required.

 * `onChange` functions are automatically generated for
   [controlled components](https://reactjs.org/docs/forms.html#controlled-components).

 * ReactDOM calls are also supported, and generate a separate `import`
   statement.

For more information, see the [examples provided](../../examples/react).

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the
[specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/react_spec.rb).
{% endrendercontent %}
