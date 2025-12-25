---
layout: post
title:  React filter documentation has landed!
subtitle: |
  This filter does so much more than transpiling Ruby syntax into JavaScript.
  It also integrates other syntaxes and reduces the need to code repetitive
  boilerplate/administrativia.
categories: updates
author: rubys
---

While filters can do one-for-one transformations, they can also do much more.
The [react](/docs/filters/react) filter will, for example, do the following:

 * Support multiple syntaxes for HTML, including
   [JSX](https://react.dev/learn/writing-markup-with-jsx) and direct calls to
   [React.createElement](https://react.dev/reference/react/createElement).

 * Unifying all of the mechanisms to initialize, reference, and update state
   with assignments and references to instance variables.

 * Automatically
   [bind](https://developer.mozilla.org/en-us/docs/web/javascript/reference/global_objects/function/bind)
   all event handlers.

 * Eliminate the need to create event handlers for
   [controlled components](https://react.dev/reference/react-dom/components#form-components).

See the [documentation](/docs/filters/react) for more details and live examples.
