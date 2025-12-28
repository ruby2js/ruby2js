---
order: 26
title: React
top_section: Filters
category: react
---

The **React** filter enables you to build [React](https://react.dev/) and [Preact](https://preactjs.com/) components using Ruby syntax.

{% rendercontent "docs/note" %}
**Choosing between React and Phlex?** See the [Building UI Components](/docs/users-guide/components) guide for an overview of approaches, trade-offs, and the "write once, target both" architecture.
{% endrendercontent %}

## Function Components (Recommended)

The modern approach uses function components with hooks. Simply inherit from `React` or `Preact`:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "react", "functions"]
}'></div>

```ruby
class Counter < React
  def initialize
    @count = 0
  end

  def render
    %x{
      <div>
        <p>Count: {count}</p>
        <button onClick={-> { setCount(count + 1) }}>Increment</button>
      </div>
    }
  end
end
```

This generates a function component with `useState` hooks:

- `@count = 0` becomes `const [count, setCount] = React.useState(0)`
- `@@prop` accesses `props.prop`

## Class Components

For components that need lifecycle methods, inherit from `React::Component`:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "react", "functions"]
}'></div>

```ruby
class Timer < React::Component
  def initialize
    @seconds = 0
  end

  def componentDidMount
    @interval = setInterval(1000) { @seconds += 1 }
  end

  def componentWillUnmount
    clearInterval(@interval)
  end

  def render
    %x{ <p>Seconds: {this.state.seconds}</p> }
  end
end
```

## JSX Syntax

Elements are created using JSX syntax with `%x{...}`:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["react", "functions"]
}'></div>

```ruby
class Example < React
  def render
    %x{
      <div className="container">
        <h1>Hello</h1>
        <p>Welcome to React</p>
        <ul>
          <li>Item 1</li>
          <li>Item 2</li>
        </ul>
      </div>
    }
  end
end
```

### JSX Features

- Standard HTML elements: `<div>`, `<p>`, `<span>`, etc.
- React components (capitalized): `<MyComponent />`
- Custom elements: `<my-widget />`
- Fragments: `<>...</>`
- Expressions: `{expression}`
- Spread attributes: `{...props}`

### Attribute Names

JSX uses camelCase attribute names:

| JSX         | HTML       |
| ----------- | ---------- |
| `className` | `class`    |
| `htmlFor`   | `for`      |
| `onClick`   | `onclick`  |
| `tabIndex`  | `tabindex` |

## Variable Mappings

| Ruby      | JavaScript                        | Notes                           |
| --------- | --------------------------------- | ------------------------------- |
| `@x`      | `useState` hook or `this.state.x` | Instance variables become state |
| `@@x`     | `props.x`                         | Class variables become props    |
| `$x`      | `this.refs.x`                     | Global variables become refs    |
| `~x`      | `this.refs.x`                     | Tilde also accesses refs        |
| `~(expr)` | `document.querySelector(expr)`    | DOM queries                     |

## Preact Support

The same filter supports [Preact](https://preactjs.com/). Use `Preact` instead of `React`:

```ruby
class Counter < Preact
  # Same syntax as React
end
```

Differences from React:
- Uses `Preact.h` instead of `React.createElement`
- Uses `onInput` instead of `onChange` for form inputs
- Uses `class` instead of `className`

## Phlex Integration

The React filter can be combined with the [Phlex](phlex) filter for a **"write once, target both"** approach. Write components using Phlex's Ruby DSL and output either Phlex JS or React JS:

```ruby
# Same Phlex code, different outputs
Ruby2JS.convert(code, filters: [:phlex])          # → Phlex JS (template literals)
Ruby2JS.convert(code, filters: [:phlex, :react])  # → React JS (createElement)
```

See the [Building UI Components](/docs/users-guide/components) guide for the full picture, or [Phlex filter documentation](phlex#react-integration) for API details.

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the
[specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/react_spec.rb).
{% endrendercontent %}
