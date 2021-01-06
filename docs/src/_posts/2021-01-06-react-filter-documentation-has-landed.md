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

 * Support three different syntaxes for HTML, one based on
   [JSX](https://reactjs.org/docs/introducing-jsx.html), one involving
   direct calls to
   [React.createElement](https://reactjs.org/docs/react-api.html#createelement),
   and finally one based on
   [Wunderbar](https://github.com/rubys/wunderbar#readme)

 * Unifying all of the mechanisms to initialize, reference, and update state
   with assignments and references to instance variables.

 * Automatically
   [bind](https://developer.mozilla.org/en-us/docs/web/javascript/reference/global_objects/function/bind)
   all event handlers.

 * Eliminate the need to create event handlers for 
   [controlled components](https://reactjs.org/docs/forms.html#controlled-components).


In addition to the [documentation](/docs/filters/react), a 
[downloadable](https://github.com/ruby2js/ruby2js/tree/master/demo/reactjs.org#readme)
version of the demos is provided, enabling you to be up and running in
seconds!
