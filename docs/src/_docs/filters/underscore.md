---
order: 27
title: Underscore
top_section: Filters
category: underscore
---

The **Underscore** filter maps relevant Ruby methods to their [Underscore.js](https://underscorejs.org) library equivalents.

## List of Transformations

{% capture caret %}<sl-icon name="caret-right-fill"></sl-icon>{% endcapture %}

{:.functions-list}
* `.clone()` {{ caret }} `_.clone()`
* `.compact()` {{ caret }} `_.compact()`
* `.count_by {}` {{ caret }} `_.countBy {}`
* `.find {}` {{ caret }} `_.find {}`
* `.find_by()` {{ caret }} `_.findWhere()`
* `.flatten()` {{ caret }} `_.flatten()`
* `.group_by {}` {{ caret }} `_.groupBy {}`
* `.has_key?()` {{ caret }} `_.has()`
* `.index_by {}` {{ caret }} `_.indexBy {}`
* `.invert()` {{ caret }} `_.invert()`
* `.invoke(&:n)` {{ caret }} `_.invoke(, :n)`
* `.map(&:n)` {{ caret }} `_.pluck(, :n)`
* `.merge!()` {{ caret }} `_.extend()`
* `.merge()` {{ caret }} `_.extend({}, )`
* `.reduce {}` {{ caret }} `_.reduce {}`
* `.reduce()` {{ caret }} `_.reduce()`
* `.reject {}` {{ caret }} `_.reject {}`
* `.sample()` {{ caret }} `_.sample()`
* `.select {}` {{ caret }} `_.select {}`
* `.shuffle()` {{ caret }} `_.shuffle()`
* `.size()` {{ caret }} `_.size()`
* `.sort()` {{ caret }} `_.sort_by(, _.identity)`
* `.sort_by {}` {{ caret }} `_.sortBy {}`
* `.times {}` {{ caret }} `_.times {}`
* `.values()` {{ caret }} `_.values()`
* `.where()` {{ caret }} `_.where()`
* `.zip()` {{ caret }} `_.zip()`
* `(n...m)` {{ caret }} `_.range(n, m)`
* `(n..m)` {{ caret }} `_.range(n, m+1)`

## Additional Features

* `.compact!`, `.flatten!`, `shuffle!`, `reject!`, `sort_by!`, and
  `.uniq` become equivalent `.splice(0, .length, *.method())` statements
* for the following methods, if the block consists entirely of a simple
  expression (or ends with one), a `return` is added prior to the
  expression: `reduce`, `sort_by`, `group_by`, `index_by`, `count_by`,
  `find`, `select`, `reject`.
* `is_a?` and `kind_of?` map to `Object.prototype.toString.call() ===
  "[object #{type}]" for the following types: `Arguments`, `Boolean`,
  `Date`, `Error`, `Function`, `Number`, `Object`, `RegExp`, `String`; and
  maps Ruby names to JavaScript equivalents for `Exception`, `Float`,
  `Hash`, `Proc`, and `Regexp`.  Additionally, `is_a?` and `kind_of?` map
  to `Array.isArray()` for `Array`.

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/underscore_spec.rb).
{% endrendercontent %}
