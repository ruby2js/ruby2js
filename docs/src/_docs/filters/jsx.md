---
order: 19
title: JSX
top_section: Filters
category: jsx
---

The **JSX** filter converts `React.createElement` calls into JSX syntax for human-readable output.

This filter is useful when you want human-readable JSX output, particularly for:
- Exporting Ruby2JS code for maintenance by JavaScript developers
- Generating JSX for use with build tools that expect JSX input
- Migrating from Phlex to idiomatic React/JSX
- Improving readability of React component output

It works in conjunction with the [React](react) filter and optionally the [Phlex](phlex) filter.

This is generally not necessary if the sources are being converted for
processing in the browser or by processing in Node.js for SSR purposes.
Instead, this filter is more likely to be useful when the code is being
processed as a part of a one-way export of the code, with the intention of the
result being maintained by developers.

## JSX Input with %x{}

You can write JSX directly in Ruby using the `%x{...}` syntax:

```ruby
%x{ <br/> }

%x{
  <div className="container">
    <h1>{title}</h1>
    <p>{description}</p>
  </div>
}
```

## React.createElement Conversion

The filter also converts `React.createElement` calls to JSX:

Example input:

```ruby
React.createElement("p", nil, "text",
  React.createElement("br", nil), data)
```

Example output:

```jsx
<p>text<br/>{data}</p>
```

## Supported JSX Features

- HTML elements: `<div>`, `<span>`, `<p>`, etc.
- React components: `<Card />`, `<MyComponent />`
- Custom elements: `<my-widget />`
- Fragments: `<>...</>`
- Expressions: `{variable}`, `{condition ? a : b}`
- Spread attributes: `{...props}`
- Children: `<div><Child /></div>`

## Phlex to JSX Migration

When used with the [Phlex](phlex) and [React](react) filters, the JSX filter enables one-way migration from Phlex to idiomatic JSX:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["phlex", "react", "jsx"]
}'></div>

```ruby
class TaskList < Phlex::HTML
  def initialize(title:, items:)
    @title = title
    @items = items
  end

  def view_template
    div(class: "task-list") do
      h1 { @title }
      ul do
        @items.each do |item|
          li { item }
        end
      end
    end
  end
end
```

This produces clean, maintainable JSX that JavaScript developers can work with directly.

## Limitations

There are cases where this conversion may be incomplete:

- Calls to `React.createElement` where the first argument is other than a literal string
- Complex control flow inside JSX expressions

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/jsx_spec.rb).
{% endrendercontent %}
