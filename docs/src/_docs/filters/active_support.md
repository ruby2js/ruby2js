---
order: 10
title: ActiveSupport
top_section: Filters
category: active_support
---

The **ActiveSupport** filter provides JavaScript equivalents for common [Rails ActiveSupport core extensions](https://guides.rubyonrails.org/active_support_core_extensions.html). These methods are frequently used in Rails templates and views.

{% rendercontent "docs/note", title: "Not Loaded by Default" %}
This filter is **not** included in the default filter set. You must explicitly request it:

```ruby
Ruby2JS.convert(source, filters: [:active_support])
```
{% endrendercontent %}

## Supported Methods

### Object Methods

#### blank?

Returns `true` if the object is `null`, empty, or a blank string. Uses optional chaining for concise output.

```ruby
name.blank?
```

```javascript
!name?.length
```

#### present?

The opposite of `blank?` - returns `true` if the object has meaningful content.

```ruby
user.email.present?
```

```javascript
user.email?.length > 0
```

#### presence

Returns the object if it's `present?`, otherwise returns `null`.

```ruby
name.presence || "Anonymous"
```

```javascript
(name?.length > 0 ? name : null) || "Anonymous"
```

#### try

Calls a method on the receiver, returning `null` if the receiver is `null` or `undefined`. Uses JavaScript optional chaining (`?.`).

```ruby
user.try(:name)
user.try(:fetch, :key)
```

```javascript
user?.name()
user?.fetch("key")
```

{% rendercontent "docs/note", title: "ES Level Requirement" %}
The `try` method requires `eslevel: 2020` or newer for optional chaining support. On older ES levels, it falls back to a guard expression.
{% endrendercontent %}

#### in?

Checks if the object is included in a collection. The inverse of `include?`.

```ruby
status.in?(["active", "pending"])
```

```javascript
["active", "pending"].includes(status)
```

### String Methods

#### squish

Removes leading/trailing whitespace and collapses internal whitespace to single spaces.

```ruby
"  hello   world  ".squish
```

```javascript
"  hello   world  ".trim().replace(/\s+/g, " ")
```

#### truncate

Truncates a string to a specified length, adding an omission marker (default: `"..."`).

```ruby
title.truncate(50)
description.truncate(100, omission: "…")
```

```javascript
title.length > 50 ? title.slice(0, 47) + "..." : title
description.length > 100 ? description.slice(0, 99) + "…" : description
```

### Array Methods

#### to_sentence

Converts an array to a comma-separated sentence with "and" before the last element.

```ruby
["Alice", "Bob", "Carol"].to_sentence
```

```javascript
// Returns: "Alice, Bob and Carol"
arr.length === 0 ? "" :
  arr.length === 1 ? arr[0] :
  arr.slice(0, -1).join(", ") + " and " + arr[arr.length - 1]
```

## Usage with ERB Filter

The ActiveSupport filter pairs well with the [ERB filter](/docs/filters/erb) for converting Rails templates to JavaScript:

```ruby
require "ruby2js"
require "ruby2js/filter/active_support"
require "ruby2js/filter/erb"
require "ruby2js/erubi"

template = <<~ERB
<% if @user.name.present? %>
  <h1><%= @user.name.truncate(30) %></h1>
<% end %>
ERB

src = Ruby2JS::Erubi.new(template).src
puts Ruby2JS.convert(src, filters: [:erb, :active_support], eslevel: 2020)
```

## Limitations

These methods provide simplified JavaScript equivalents. Some edge cases may behave differently from Rails:

- `blank?` uses `!obj?.length` which checks for `null`/`undefined` or zero length. It doesn't handle `false` or whitespace-only strings as blank.
- `to_sentence` uses hardcoded "and" connector (no internationalization support)
- `truncate` doesn't support `:separator` option for word boundaries

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/active_support_spec.rb).
{% endrendercontent %}
