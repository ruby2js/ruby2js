---
order: 26
title: React
top_section: Filters
category: react
---

The **React** filter enables you to build [React](https://react.dev/) and [Preact](https://preactjs.com/) components using Ruby syntax.

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
    _div do
      _p "Count: #{@count}"
      _button "Increment", onClick: -> { @count += 1 }
    end
  end
end
```

This generates a function component with `useState` hooks:

- `@count = 0` becomes `const [count, setCount] = React.useState(0)`
- `@count += 1` becomes `setCount(count + 1)`
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
    _p "Seconds: #{@seconds}"
  end
end
```

## Wunderbar Element Syntax

Elements are created using underscore-prefixed method calls:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["react", "functions"]
}'></div>

```ruby
class Example < React
  def render
    _div class: "container" do
      _h1 "Hello"
      _p "Welcome to React"
      _ul do
        _li "Item 1"
        _li "Item 2"
      end
    end
  end
end
```

### Element Syntax Features

- `_div`, `_p`, `_span` → HTML elements
- `_MyComponent` → React components (capitalized)
- `class:` → becomes `className`
- `for:` → becomes `htmlFor`
- Markaby-style: `_div.container.active` → `<div className="container active">`
- IDs: `_div.main!` → `<div id="main">`

## JSX-like Syntax

You can also use JSX-like syntax with `%x{...}`:

```ruby
def render
  %x{
    <div className="app">
      <h1>Hello, {@@name}!</h1>
    </div>
  }
end
```

## Variable Mappings

| Ruby | JavaScript | Notes |
|------|------------|-------|
| `@x` | `useState` hook or `this.state.x` | Instance variables become state |
| `@@x` | `props.x` | Class variables become props |
| `$x` | `this.refs.x` | Global variables become refs |
| `~x` | `this.refs.x` | Tilde also accesses refs |
| `~(expr)` | `document.querySelector(expr)` | DOM queries |

## Controlled Components

For form inputs with `value:` bound to state, `onChange` handlers are automatically generated:

```ruby
_input value: @name  # Auto-generates onChange to update @name
_input checked: @active  # Auto-generates onChange to toggle @active
```

## Preact Support

The same filter supports [Preact](https://preactjs.com/). Use `Preact` instead of `React`:

```ruby
class Counter < Preact
  # Same syntax as React
end
```

Differences from React:
- Uses `Preact.h` instead of `React.createElement`
- Uses `onInput` instead of `onChange` for controlled components
- Uses `class` instead of `className`

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the
[specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/react_spec.rb).
{% endrendercontent %}
