---
order: 617
title: Cross-File Metadata
top_section: Juntos
category: juntos
---

# Cross-File Metadata

Juntos analyzes controllers, models, and concerns during transpilation and shares metadata across files. This enables type-aware JavaScript output in views and correct async/sync decisions in tests — without manual annotations.

{% toc %}

## Overview

When `juntos build` or `juntos transform` processes your application, each filter captures metadata about the file it transpiles. Downstream filters use this metadata to make better decisions:

```
Models          → associations, scopes, enums
Concerns        → method names
Controllers     → instance variable types, file paths
                     ↓
Views (ERB)     ← uses controller types for Map/Array/Hash disambiguation
Tests           ← uses model metadata for async/sync, fixtures, imports
```

## Controller → View Type Inference

The most visible metadata feature. When a controller action assigns instance variables, Juntos infers their types and passes that information to the corresponding view.

```
Controller                   Metadata                  View
───────────                  ────────                  ────
@items = people.to_a    →  items: "array"    →  items.push(x)
@groups = data.group_by  →  groups: "map"    →  groups.get(key)
@count = items.count     →  count: "number"  →  count + 1
```

This means `@groups[key]` in a view transpiles to `groups.get(key)` (Map access) rather than `groups[key]` (object property access), without any pragma annotations.

### Inferred Types

The controller filter recognizes these patterns on the right-hand side of instance variable assignments:

**Literals:**

```ruby
@config = {}           # hash
@items = []            # array
@message = "hello"     # string
@count = 0             # number
```

**Method return types:**

| Type | Methods |
|------|---------|
| **array** | `to_a`, `pluck`, `ids`, `keys`, `values`, `split`, `chars`, `sort`, `reverse`, `uniq`, `compact`, `flatten`, `shuffle` |
| **hash** | `to_h` |
| **number** | `count`, `sum`, `average`, `minimum`, `maximum`, `length`, `size` |
| **string** | `to_s`, `name`, `title` |
| **map** | `group_by` (block or block_pass form) |

**Block methods:**

```ruby
@results = items.select { |x| x.active? }    # array
@groups = items.group_by(&:category)          # map
@mapped = items.map { |x| x.name }           # array
```

**Local variable propagation** — types flow through local variable assignments:

```ruby
def summary
  people = Person.all.to_a          # people is array
  by_type = people.group_by(&:type) # by_type is map
  @people_by_type = by_type         # @people_by_type inherits map type
end
```

### What This Enables

#### Map Operations from group_by

Without type inference, `@people_by_type[key]` would transpile to bracket access. With it, the transpiler generates correct Map operations:

```ruby
# Controller
def summary
  @people_by_type = people.group_by(&:type)
end
```

```erb
<%# View — no pragmas needed %>
<% @people_by_type.keys.sort.each do |type| %>
  <% members = @people_by_type[type] %>
  <li><%= type %>: <%= members.length %></li>
<% end %>
```

Transpiles to:

```javascript
for (let type of Array.from(people_by_type.keys()).sort()) {
  let members = people_by_type.get(type);
  // ...
}
```

The key transformations from Map type inference:
- `.keys` → `Array.from(map.keys())` (returns Array, not iterator)
- `.values` → `Array.from(map.values())` (returns Array, not iterator)
- `map[key]` → `map.get(key)`
- `map[key] = val` → `map.set(key, val)`
- `.each { |k,v| }` → `for (let [k, v] of map)`
- `.key?(k)` / `.include?(k)` → `map.has(k)`

#### Chained group_by in Views

Inline `group_by` calls also get Map type inference via the pragma filter's own type tracking — no controller metadata needed:

```erb
<% roles = members.group_by(&:role) %>
<% roles.keys.sort.each do |role| %>
  <li><%= role %>: <%= roles[role].length %></li>
<% end %>
```

#### Array Operations

```ruby
# Controller
@items = Article.where(status: "published").to_a
```

```erb
<%# View %>
<% @items << new_item %>
```

Transpiles to `items.push(new_item)` instead of the ambiguous `items << new_item`.

## Model Metadata

The model filter captures structural information used by the test filter and other downstream consumers.

### Associations

`has_many`, `has_one`, and `belongs_to` declarations are recorded. The test filter uses this to determine which method calls return promises (association access is async) versus synchronous values.

```ruby
class Article < ApplicationRecord
  has_many :comments, dependent: :destroy
  belongs_to :author
end
```

In transpiled tests, `article.comments` is awaited because the metadata identifies it as an association.

### Enums

Enum declarations generate predicate and bang methods that are synchronous (they operate on in-memory state, not the database):

```ruby
class Article < ApplicationRecord
  enum :status, %w[draft published archived]
end
```

The test filter knows `article.draft?` and `article.published!` don't need `await`, even though most model operations do.

### Scopes

Named scopes are recorded so the test filter can generate correct query chains.

## Concern Metadata

Concerns record which methods they define:

```ruby
module Trackable
  extend ActiveSupport::Concern

  def track_event(name)
    # ...
  end
end
```

This allows downstream filters to recognize `track_event` as a known method when it appears in models that include `Trackable`.

## When Inference Fails

Type inference has limitations. You may need explicit [pragmas](/docs/users-guide/pragmas) when:

### Unknown Method Return Types

Custom methods don't have known return types:

```erb
<% data = compute_results() %>
<% data << item %>  <%# Is data an Array, String, or Set? %>
```

**Fix:** Add a pragma: `<% data << item # Pragma: array %>`

### Parameters and Partials

Method parameters and partial locals have no type information:

```erb
<%= render partial: "item", locals: { items: @items } %>
```

Inside the partial, `items` has no type metadata. However, if the partial accesses `@items` directly (as an instance variable), the type is available.

### Reassignment to Different Type

If a variable is reassigned to a different type, the last assignment wins:

```ruby
@data = []           # array
@data = compute()    # unknown — type cleared
```

## Debugging Metadata

### View Controller Metadata

Controller metadata is stored as a comment at the top of the transpiled controller file:

```bash
npx juntos transform app/controllers/events_controller.rb
```

Look for the metadata comment near the top of the output:

```javascript
/* @metadata {"view_types":{"events/summary":{"people_by_type":"map","count":"number"}}} */
```

### Check What the View Receives

```bash
npx juntos transform app/views/events/summary.html.erb
```

Look for Map operations (`.get()`, `.keys()`, `for...of`) vs object operations (bracket access, `Object.keys()`) to verify type inference is working.

### Override with Pragmas

When inference produces the wrong result, pragmas always take precedence:

```erb
<%# Force hash treatment even if controller inferred map %>
<% @data.each { |k, v| process(k, v) } # Pragma: hash %>
```

## See Also

- [Pragma Filter](/docs/filters/pragma) — Complete pragma and type inference reference
- [Pragmas in Practice](/docs/users-guide/pragmas) — Common patterns and best practices
- [Architecture](/docs/juntos/architecture) — How the build process works
- [Testing](/docs/juntos/testing) — How model metadata affects test transpilation
