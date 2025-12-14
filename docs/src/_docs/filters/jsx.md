---
order: 19
title: JSX
top_section: Filters
category: jsx
---

The **JSX** filter converts Wunderbar-style element calls and `React.createElement` calls into JSX syntax.

This filter is useful when you want human-readable JSX output, particularly for:
- Exporting Ruby2JS code for maintenance by JavaScript developers
- Generating JSX for use with build tools that expect JSX input
- Improving readability of React component output

It works in conjunction with the [React](react) filter.

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
