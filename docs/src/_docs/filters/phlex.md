---
order: 23
title: Phlex
top_section: Filters
category: phlex
---

The **Phlex** filter transforms [Phlex](https://phlex.fun/) component classes into JavaScript render functions. It converts the Phlex HTML DSL into string concatenation, making components usable as standalone JavaScript functions.

{% rendercontent "docs/note", type: "warning", title: "Beta Status" %}
This filter is in beta. It supports ERB-replacement level functionality (generating HTML strings) but does not yet support component composition (`render OtherComponent.new`). See the Limitations section for details.
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

| Phlex Method | JavaScript Output |
|-------------|-------------------|
| `plain "text"` | `String("text")` |
| `unsafe_raw "<html>"` | `"<html>"` (no escaping) |
| `whitespace` | `" "` |
| `comment "text"` | `"<!-- text -->"` |
| `doctype` | `"<!DOCTYPE html>"` |

### Attributes

| Ruby | JavaScript |
|------|------------|
| `div(class: "foo")` | `<div class="foo">` |
| `div(data_controller: "x")` | `<div data-controller="x">` |
| `input(disabled: true)` | `<input disabled>` |
| `input(disabled: false)` | `<input>` (attribute omitted) |
| `div(class: @var)` | `` `<div class="${var}">` `` |

## Transformations

| Ruby Pattern | JavaScript Output |
|-------------|-------------------|
| `class X < Phlex::HTML` | `class X extends Phlex.HTML` |
| `def view_template` | `render({ ... })` |
| `def initialize(...)` | (removed, params become render args) |
| `@title` | `title` (from destructured parameter) |
| `div { ... }` | `_phlex_out += "<div>"; ...; _phlex_out += "</div>"` |
| `input` (void) | `_phlex_out += "<input>"` (no closing tag) |

## Limitations

{% rendercontent "docs/note", type: "warning", title: "Component Composition Not Yet Supported" %}
The filter does not yet support rendering other components:

```ruby
# NOT YET SUPPORTED
def view_template
  render HeaderComponent.new(title: @title)
  div { @content }
end
```

This feature is planned for a future release as part of the Vite plugin integration. See the [SFC Framework Integration Plan](https://github.com/ruby2js/ruby2js/blob/master/plans/SFC_FRAMEWORK_INTEGRATION.md) for details on the roadmap.
{% endrendercontent %}

Current limitations:

- **Component composition**: `render OtherComponent.new(...)` is not supported
- **Slots**: Phlex slot functionality is not supported
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

## Roadmap

The Phlex filter is part of a broader plan for single-file component (SFC) framework integration. Future work includes:

- **Vite plugin** for `.phlex.rb` files
- **Component composition** via ES module imports
- **Integration with Vue, Svelte, and Astro**

See the [SFC Framework Integration Plan](https://github.com/ruby2js/ruby2js/blob/master/plans/SFC_FRAMEWORK_INTEGRATION.md) for the full roadmap.
