---
order: 15
title: ERB
top_section: Filters
category: erb
---

The **ERB** filter transforms compiled ERB or HERB template output into JavaScript render functions. It converts instance variable references to destructured parameters, making templates usable as standalone JavaScript functions.


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

puts Ruby2JS.convert(erb_src, filters: [:erb], eslevel: 2020)
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
puts Ruby2JS.convert(erb_src, filters: [:erb, :functions], eslevel: 2020)
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

puts Ruby2JS.convert(herb_src, filters: [:erb], eslevel: 2020)
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
| `raw(html)` | `html` (pass-through) |
| `str.html_safe` | `str` (pass-through) |

## Using Ruby2JS::Erubi for Block Helpers

Ruby's standard ERB generates invalid syntax when block-based helpers like `form_for` are used with `<%= %>` tags. Ruby2JS provides a custom Erubi engine that handles these cases correctly:

```ruby
require "ruby2js"
require "ruby2js/erubi"
require "ruby2js/filter/erb"

template = <<~ERB
<%= form_for @user do |f| %>
  <%= f.label :name %>
  <%= f.text_field :name %>
  <%= f.label :email %>
  <%= f.email_field :email %>
  <%= f.submit "Save" %>
<% end %>
ERB

src = Ruby2JS::Erubi.new(template).src
puts Ruby2JS.convert(src, filters: [:erb], eslevel: 2020)
```

```javascript
// Output:
function render({ user }) {
  let _buf = "";
  _buf += "<form data-model=\"user\">";
  _buf += "<label for=\"user_name\">Name</label>";
  _buf += "<input type=\"text\" name=\"user[name]\" id=\"user_name\">";
  _buf += "<label for=\"user_email\">Email</label>";
  _buf += "<input type=\"email\" name=\"user[email]\" id=\"user_email\">";
  _buf += "<input type=\"submit\" value=\"Save\">";
  _buf += "</form>";
  return _buf
}
```

The ERB filter with `Ruby2JS::Erubi`:
- Detects block expressions (ending with `do |...|` or `{`)
- Converts `form_for` to HTML `<form>` tags with `data-model` attribute
- Converts form builder methods to HTML input elements

### Supported Form Builder Methods

| Ruby Method | HTML Output |
|-------------|-------------|
| `f.text_field :name` | `<input type="text" name="model[name]" id="model_name">` |
| `f.email_field :email` | `<input type="email" name="model[email]" ...>` |
| `f.password_field :pass` | `<input type="password" name="model[pass]" ...>` |
| `f.hidden_field :id` | `<input type="hidden" name="model[id]" ...>` |
| `f.text_area :body` | `<textarea name="model[body]" id="model_body"></textarea>` |
| `f.check_box :active` | `<input type="checkbox" name="model[active]" value="1">` |
| `f.radio_button :role, :admin` | `<input type="radio" name="model[role]" value="admin">` |
| `f.label :name` | `<label for="model_name">Name</label>` |
| `f.select :category` | `<select name="model[category]" id="model_category"></select>` |
| `f.submit "Save"` | `<input type="submit" value="Save">` |
| `f.button "Click"` | `<button type="submit">Click</button>` |

Additional input types: `number_field`, `tel_field`, `url_field`, `search_field`, `date_field`, `time_field`, `datetime_local_field`, `month_field`, `week_field`, `color_field`, `range_field`.

## Limitations

{% rendercontent "docs/note", type: "warning", title: "Instance Variables Only" %}
This filter can only handle templates that depend solely on instance variables (`@var`). Templates that call Rails methods or helper functions directly will not work correctly in JavaScript without corresponding JavaScript implementations.
{% endrendercontent %}

Common scenarios that require attention:

- **Helper methods** like `link_to`, `image_tag`, etc. won't be available in JavaScript. Either:
  - Move the URL/path computation to the controller and pass it as an instance variable
  - Implement the helper function in JavaScript
  - Transpile the helper using Ruby2JS

- **Block helpers** like `form_for` require:
  - Using `Ruby2JS::Erubi` instead of standard ERB
  - Providing JavaScript implementations of the helper functions

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
