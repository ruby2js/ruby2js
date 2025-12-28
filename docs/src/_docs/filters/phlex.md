---
order: 23
title: Phlex
top_section: Filters
category: phlex
---

The **Phlex** filter transforms [Phlex](https://phlex.fun/) component classes into JavaScript render functions. It converts the Phlex HTML DSL into template literal strings, making components usable as standalone JavaScript functions.

{% rendercontent "docs/note" %}
**New to component development with Ruby2JS?** See the [Building UI Components](/docs/users-guide/components) guide for an overview of approaches, trade-offs, and when to use Phlex vs React.
{% endrendercontent %}

## How It Works

Phlex components use a Ruby DSL to build HTML:

```ruby
class CardComponent < Phlex::HTML
  def initialize(title:)
    @title = title
  end

  def view_template
    div(class: "card") do
      h1 { @title }
    end
  end
end
```

The Phlex filter transforms this into a JavaScript class with a render function:

```javascript
class CardComponent extends Phlex.HTML {
  render({ title }) {
    let _phlex_out = "";
    _phlex_out += `<div class="card">`;
    _phlex_out += "<h1>";
    _phlex_out += String(title);
    _phlex_out += "</h1>";
    _phlex_out += "</div>";
    return _phlex_out
  }
}
```

## Examples

### Basic Component

```ruby
require "ruby2js/filter/phlex"

code = <<~RUBY
  class Greeting < Phlex::HTML
    def view_template
      h1 { "Hello World" }
      p { "Welcome to Phlex!" }
    end
  end
RUBY

puts Ruby2JS.convert(code, filters: [:phlex], eslevel: 2020)
```

```javascript
// Output:
class Greeting extends Phlex.HTML {
  render() {
    let _phlex_out = "";
    _phlex_out += "<h1>";
    _phlex_out += "Hello World";
    _phlex_out += "</h1>";
    _phlex_out += "<p>";
    _phlex_out += "Welcome to Phlex!";
    _phlex_out += "</p>";
    return _phlex_out
  }
}
```

### Component with Parameters

Instance variables become destructured parameters on the render function:

```ruby
class ProfileCard < Phlex::HTML
  def initialize(name:, bio:, avatar_url:)
    @name = name
    @bio = bio
    @avatar_url = avatar_url
  end

  def view_template
    div(class: "profile") do
      img(src: @avatar_url, alt: @name)
      h2 { @name }
      p { @bio }
    end
  end
end
```

```javascript
// Output:
class ProfileCard extends Phlex.HTML {
  render({ avatar_url, bio, name }) {
    let _phlex_out = "";
    _phlex_out += `<div class="profile">`;
    _phlex_out += `<img src="${avatar_url}" alt="${name}">`;
    _phlex_out += "<h2>";
    _phlex_out += String(name);
    _phlex_out += "</h2>";
    _phlex_out += "<p>";
    _phlex_out += String(bio);
    _phlex_out += "</p>";
    _phlex_out += "</div>";
    return _phlex_out
  }
}
```

### Component Composition

Render other components using `render Component.new`:

```ruby
class Page < Phlex::HTML
  def view_template
    render Header.new(title: "Welcome")
    div(class: "content") do
      render Card.new(class: "featured") do
        h1 { "Featured Content" }
        p { "This is inside the card." }
      end
    end
    render Footer.new
  end
end
```

```javascript
// Output:
class Page extends Phlex.HTML {
  render() {
    let _phlex_out = "";
    _phlex_out += Header.render({ title: "Welcome" });
    _phlex_out += `<div class="content">`;
    _phlex_out += Card.render({ class: "featured" }, () => {
      _phlex_out += "<h1>Featured Content</h1>";
      _phlex_out += "<p>This is inside the card.</p>"
    });
    _phlex_out += "</div>";
    _phlex_out += Footer.render({});
    return _phlex_out
  }
}
```

### Custom Elements

Use `tag("element-name")` for custom HTML elements:

```ruby
class Widget < Phlex::HTML
  def view_template
    tag("my-widget", class: "custom") do
      span { "inner content" }
    end
    tag("custom-footer", data_year: "2024")
  end
end
```

```javascript
// Output:
class Widget extends Phlex.HTML {
  render() {
    let _phlex_out = "";
    _phlex_out += `<my-widget class="custom">`;
    _phlex_out += "<span>inner content</span>";
    _phlex_out += "</my-widget>";
    _phlex_out += `<custom-footer data-year="2024"></custom-footer>`;
    return _phlex_out
  }
}
```

### Fragments

Use `fragment` to group multiple elements without a wrapper:

```ruby
class MultiRoot < Phlex::HTML
  def view_template
    fragment do
      h1 { "Title" }
      p { "Paragraph" }
    end
  end
end
```

### Dynamic Attributes

Attributes with dynamic values use template literals:

```ruby
class ThemedButton < Phlex::HTML
  def view_template
    button(class: @theme, data_action: @action) { @label }
  end
end
```

```javascript
// Output:
class ThemedButton extends Phlex.HTML {
  render({ action, label, theme }) {
    let _phlex_out = "";
    _phlex_out += `<button class="${theme}" data-action="${action}">`;
    _phlex_out += String(label);
    _phlex_out += "</button>";
    return _phlex_out
  }
}
```

### Loops

Combine with the **Functions** filter to convert `.each` to `for...of`:

```ruby
require "ruby2js/filter/phlex"
require "ruby2js/filter/functions"

code = <<~RUBY
  class ItemList < Phlex::HTML
    def view_template
      ul do
        @items.each do |item|
          li { item.name }
        end
      end
    end
  end
RUBY

puts Ruby2JS.convert(code, filters: [:phlex, :functions], eslevel: 2020)
```

```javascript
// Output:
class ItemList extends Phlex.HTML {
  render({ items }) {
    let _phlex_out = "";
    _phlex_out += "<ul>";

    for (let item of items) {
      _phlex_out += "<li>";
      _phlex_out += String(item.name);
      _phlex_out += "</li>"
    };

    _phlex_out += "</ul>";
    return _phlex_out
  }
}
```

### Conditionals

```ruby
class ConditionalCard < Phlex::HTML
  def view_template
    div do
      h1 { @title } if @show_title
      p { @content } unless @hide_content
    end
  end
end
```

```javascript
// Output:
class ConditionalCard extends Phlex.HTML {
  render({ content, hide_content, show_title, title }) {
    let _phlex_out = "";
    _phlex_out += "<div>";

    if (show_title) {
      _phlex_out += "<h1>";
      _phlex_out += String(title);
      _phlex_out += "</h1>"
    };

    if (!hide_content) {
      _phlex_out += "<p>";
      _phlex_out += String(content);
      _phlex_out += "</p>"
    };

    _phlex_out += "</div>";
    return _phlex_out
  }
}
```

### Indirect Inheritance

For components that inherit from a base class (not directly from `Phlex::HTML`), use the pragma comment:

```ruby
# @ruby2js phlex
class Card < ApplicationComponent
  def view_template
    div(class: "card") { @title }
  end
end
```

## Supported Phlex Methods

### HTML Elements

All HTML5 elements are supported, including:

- **Standard elements**: `div`, `span`, `p`, `h1`-`h6`, `a`, `ul`, `li`, `table`, `tr`, `td`, `form`, `input`, `button`, `label`, `select`, `textarea`, etc.
- **Void elements** (self-closing): `input`, `br`, `hr`, `img`, `link`, `meta`, `area`, `base`, `col`, `embed`, `param`, `source`, `track`, `wbr`

### Special Methods

| Phlex Method           | JavaScript Output         |
| ---------------------- | ------------------------- |
| `plain "text"`         | `String("text")`          |
| `unsafe_raw "<html>"`  | `"<html>"` (no escaping)  |
| `whitespace`           | `" "`                     |
| `comment "text"`       | `"<!-- text -->"`         |
| `doctype`              | `"<!DOCTYPE html>"`       |
| `render Component.new` | `Component.render({...})` |
| `tag("name")`          | `<name>...</name>`        |
| `fragment { }`         | (no wrapper element)      |

### Attributes

| Ruby                        | JavaScript                    |
| --------------------------- | ----------------------------- |
| `div(class: "foo")`         | `<div class="foo">`           |
| `div(data_controller: "x")` | `<div data-controller="x">`   |
| `input(disabled: true)`     | `<input disabled>`            |
| `input(disabled: false)`    | `<input>` (attribute omitted) |
| `div(class: @var)`          | `` `<div class="${var}">` ``  |

## Transformations

| Ruby Pattern            | JavaScript Output                                    |
| ----------------------- | ---------------------------------------------------- |
| `class X < Phlex::HTML` | `class X extends Phlex.HTML`                         |
| `def view_template`     | `render({ ... })`                                    |
| `def initialize(...)`   | (removed, params become render args)                 |
| `@title`                | `title` (from destructured parameter)                |
| `div { ... }`           | `_phlex_out += "<div>"; ...; _phlex_out += "</div>"` |
| `input` (void)          | `_phlex_out += "<input>"` (no closing tag)           |
| `render X.new(...)`     | `X.render({...})`                                    |
| `tag("x")`              | `_phlex_out += "<x>...</x>"`                         |

## React Integration

The Phlex filter supports a **"write once, target both"** architecture. The same Phlex Ruby code can produce either Phlex JS or React JS depending on the filter chain:

```ruby
# Phlex JS output (template literals)
Ruby2JS.convert(code, filters: [:phlex])

# React JS output (React.createElement)
Ruby2JS.convert(code, filters: [:phlex, :react])
```

### Example

Given this Phlex component:

```ruby
class Card < Phlex::HTML
  def initialize(title:)
    @title = title
  end

  def view_template
    div(class: "card") do
      h1 { @title }
    end
  end
end
```

**With `[:phlex]`** (Phlex JS):

```javascript
class Card extends Phlex.HTML {
  render({ title }) {
    let _phlex_out = "";
    _phlex_out += `<div class="card"><h1>${String(title)}</h1></div>`;
    return _phlex_out
  }
}
```

**With `[:phlex, :react]`** (React JS):

```javascript
class Card extends Phlex.HTML {
  render({ title }) {
    return React.createElement(
      "div",
      {className: "card"},
      React.createElement("h1", null, title)
    )
  }
}
```

### Multiple Elements

When a component has multiple root elements, React mode automatically wraps them in a `React.Fragment`:

```ruby
class Page < Phlex::HTML
  def view_template
    h1 { "Title" }
    p { "Content" }
  end
end
```

```javascript
// With [:phlex, :react]
class Page extends Phlex.HTML {
  render() {
    return React.createElement(
      React.Fragment,
      null,
      React.createElement("h1", null, "Title"),
      React.createElement("p", null, "Content")
    )
  }
}
```

## Limitations

Current limitations:

- **Slots**: Phlex slot functionality is not yet supported
- **Helpers**: Custom helper methods defined in the component are not transformed

## Usage Notes

- Instance variables are automatically collected and become destructured parameters
- The `initialize` method is removed (its parameters become render function parameters)
- Combine with the **Functions** filter for proper loop conversion (`.each` to `for...of`)
- Data attributes use underscore-to-dash conversion: `data_foo` becomes `data-foo`
- Boolean `true` attributes render as valueless (`checked`), `false` attributes are omitted

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/phlex_spec.rb).
{% endrendercontent %}
