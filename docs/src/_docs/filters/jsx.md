---
order: 34
title: JSX
top_section: Deprecations
category: jsx
---

{% rendercontent "docs/note", type: "warning" %}
This filter has been deprecated and will be removed in Ruby2JS 6.0.
{% endrendercontent %}

The **jsx** filter will convert the types of scripts suitable for processing
by the [react](react) filter into JSX.

This is generally not necessarily if the sources are being converted for
processing in the browser or by processing in Node.js for SSR purposes.
Instead, this filter is more likely to be useful when the code is being
processed as a part of a one-way export of the code, with the intention of the
result being maintained by developers.

Example inputs:

```ruby
%x{ <br/> }

React.createElement("p", nil, "text", 
  React.createElement("br", nil), data)

_ul @@list do |item|
  _li item.text, key: item.id
end
```

Example outputs:

```jsx
<br/>

<p>text<br/>{data}</p>

<ul>{this.props.list.map(
  item => <li key={item.id}>{item.text}</li>
)}</ul>
```

There are cases where this conversion may be incomplete.  Examples:

 * calls to `React.createElement` where the first argument is other
   than a literal string.
 * wunderbar syntax involving blocks including complex control
   statements or even simple assignments.

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/jsx_spec.rb).
{% endrendercontent %}
