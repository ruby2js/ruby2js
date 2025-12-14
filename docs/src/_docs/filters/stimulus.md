---
order: 29
title: Stimulus
top_section: Filters
category: stimulus
---

The **Stimulus** filter makes it easier to build [Stimulus](https://stimulus.hotwire.dev/) controllers.

When a class definition is encountered that derives from
`Stimulus::Controller`, the following transformations are applied:

 * an `import` statement for Stimulus will be generated if the [esm](./esm)
   filter is also applied.

 * `initialize` methods are **not** mapped to constructors.

 * Unqualified references to `application` and `element` are prefixed with 
   `this.`.  As will each of the identifiers mentioned in the next three
   bullets.

 * If any of the following are found, "x" will be addded to the list of
   static targets if not already present: `xTarget`, `xTargets`, `hasXTarget`.

 * If any of the following are found, "x" will be addded to the list of
   static values with a type of `String` if not already present: `xValue`,
   `xValue=`, `hasXValue`.

 * If any of the following are found, "x" will be addded to the list of
   static classes if not already present: `xClass`, `hasXClass`.

For more information, see the [examples provided](../../examples/stimulus).

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/stimulus_spec.rb).
{% endrendercontent %}

