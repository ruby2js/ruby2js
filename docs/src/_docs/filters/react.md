---
order: 38
title: React
top_section: Deprecations
category: react
---

{% rendercontent "docs/note", type: "warning" %}
This filter has been deprecated and will be removed in Ruby2JS 6.0.
{% endrendercontent %}

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

## Hooks

[React hooks](https://reactjs.org/docs/hooks-intro.html) are an alternate
mechanism for expressing React components.  Components expressed as hooks tend
to be smaller than the equivalent code expressed as JavaScript classes.
Perhaps the most important difference is that at this time,
[React refresh](https://www.npmjs.com/package/react-refresh) will only update
hooks in a running application without losing state.  The most notable
limitation of hooks is that you [can't use the `ref` attribute on
hooks](https://reactjs.org/docs/refs-and-the-dom.html#refs-and-function-components).

To enable hooks, change your component from inheriting from `React::Component`
to `React`.  If this is done, a React hook will be generated if all of the
following conditions are met:

  * No class/static methods (`def self.`)
  * No use of 
    [React lifecycle methods](https://reactjs.org/docs/react-component.html#the-component-lifecycle)
    other than `render`.
  * No attribute accessors (getters/setters)

If any of these conditions are not met, a class inheriting from
`React.component` will be emitted instead.  This means that you can code both
classes and hooks using the same syntax.

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works with hooks are in the
[specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/hook_spec.rb).
{% endrendercontent %}

