---
order: 27
next_page_order: 30
title: Vue
top_section: Filters
category: vue
---

The **Vue** filter enables you to build [Vue.js](https://vuejs.org/) components.

{% rendercontent "docs/note", type: "warning" %}
At the current time, this filter is **not** recommended for use.  Pull requests
are welcome!  😏
{% endrendercontent %}

The basic idea is that you can take code that is working with the
[React](react) filter and get it working with vue.js with the following changes:

 * Change the classes to inherit from `Vue` instead of `React`
 * Convert the [React lifecycle methods](https://reactjs.org/docs/react-component.html)
   to [Vue lifecyle methods](https://v3.vuejs.org/api/options-lifecycle-hooks.html).
 * Update the attribute names for event handlers, in particular `onChange` and
   `onInput`.

The problem with this approach is that all of this was inplemented using Vue.js version
2, and pretty much all of the APIs that the generated code depend on were significantly
changed with Vue.js version 3.  More background and details can be found in
[whimsy issue#110](https://github.com/apache/whimsy/issues/110).


{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/vue_spec.rb).
{% endrendercontent %}
