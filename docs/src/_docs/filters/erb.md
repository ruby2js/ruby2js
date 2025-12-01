---
order: 15
title: ERB
top_section: Filters
category: erb
---

The **ERB** filter transforms compiled ERB or HERB template output into JavaScript render functions. It converts instance variable references to destructured parameters, making templates usable as standalone JavaScript functions.

{% rendercontent "docs/note", title: "ES Level Requirement" %}
This filter requires `eslevel: 2015` or newer for object destructuring in function parameters.
{% endrendercontent %}

## How It Works

When you compile an ERB or HERB template, Ruby generates code that builds a string buffer:

```ruby
# ERB compiled output
_erbout = +''; _erbout.<< "<h1>".freeze; _erbout.<<(( @title ).to_s); _erbout.<< "</h1>".freeze; _erbout

# HERB compiled output
_buf = ::String.new; _buf << '<h1>'.freeze; _buf << (@title).to_s; _buf << '</h1>'.freeze; _buf.to_s
```

The ERB filter detects this pattern and transforms it into a JavaScript render function:

```javascript
function render({ title }) {
  let _erbout = "";
  _erbout += "<h1>";
  _erbout += String(title);
  _erbout += "</h1>";
  return _erbout
}
```

## Examples

### Simple Template

```ruby
require "erb"
require "ruby2js/filter/erb"

template = "<h1><%= @title %></h1><p><%= @content %></p>"
erb_src = ERB.new(template).src

puts Ruby2JS.convert(erb_src, filters: [:erb], eslevel: 2015)
```

```javascript
// Output:
function render({ content, title }) {
  let _erbout = "";
  _erbout += "<h1>";
  _erbout += String(title);
  _erbout += "</h1><p>";
  _erbout += String(content);
  _erbout += "</p>";
  return _erbout
}
```

### Template with Loops

```ruby
require "erb"
require "ruby2js/filter/erb"
require "ruby2js/filter/functions"

template = <<~ERB
<ul>
<% @items.each do |item| %>
  <li><%= item.name %></li>
<% end %>
</ul>
ERB

erb_src = ERB.new(template).src
puts Ruby2JS.convert(erb_src, filters: [:erb, :functions], eslevel: 2015)
```

```javascript
// Output:
function render({ items }) {
  let _erbout = "";
  _erbout += "<ul>\n";

  for (let item of items) {
    _erbout += "\n  <li>";
    _erbout += String(item.name);
    _erbout += "</li>\n"
  };

  _erbout += "\n</ul>\n";
  return _erbout
}
```

### Using with HERB

The filter also works with [HERB](https://github.com/marcoroth/herb) (HTML + Embedded Ruby), which uses a similar buffer pattern:

```ruby
require "herb"
require "ruby2js/filter/erb"

template = "<h1><%= @title %></h1>"
herb_src = Herb::Engine.new(template).src

puts Ruby2JS.convert(herb_src, filters: [:erb], eslevel: 2015)
```

```javascript
// Output:
function render({ title }) {
  let _buf = "";
  _buf += "<h1>";
  _buf += String(title);
  _buf += "</h1>";
  return _buf.toString()
}
```

## Transformations

The filter performs these transformations:

| Ruby Pattern | JavaScript Output |
|-------------|-------------------|
| `_erbout = +''` | `let _erbout = ""` |
| `_buf = ::String.new` | `let _buf = ""` |
| `_erbout.<< "str".freeze` | `_erbout += "str"` |
| `_erbout.<<((@var).to_s)` | `_erbout += String(var)` |
| `@title` | `title` (from destructured parameter) |

## Limitations

{% rendercontent "docs/note", type: "warning", title: "Instance Variables Only" %}
This filter can only handle templates that depend solely on instance variables (`@var`). Templates that call Rails methods or helper functions directly will not work correctly in JavaScript.
{% endrendercontent %}

Common scenarios that require attention:

- **Helper methods** like `link_to`, `image_tag`, `form_for`, etc. won't be available in JavaScript. Either:
  - Move the URL/path computation to the controller and pass it as an instance variable
  - Implement the helper function in JavaScript
  - Transpile the helper using Ruby2JS

- **Rails methods** called directly in templates (though rare) won't work. Move the logic to the controller and pass results as instance variables.

For example, instead of:

```erb
<%= link_to @article.title, article_path(@article) %>
```

Pass the URL from the controller:

```ruby
# Controller
@article_url = article_path(@article)
```

```erb
<a href="<%= @article_url %>"><%= @article.title %></a>
```

## Usage Notes

- The filter automatically detects instance variables used in the template and creates a destructuring parameter pattern
- Instance variables are converted to local variables with the `@` prefix removed
- The function is always named `render` and returns the buffer string
- Combine with the **Functions** filter to convert Ruby iterators like `.each` to JavaScript `for...of` loops
- The `#coding:UTF-8` comment from ERB output becomes a harmless JavaScript comment (`//coding:UTF-8`)

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/erb_spec.rb).
{% endrendercontent %}
