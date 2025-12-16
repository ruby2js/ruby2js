# Ruby2JS Transpilation Notes

This document records patterns and issues discovered while building the Rails-in-JS demo, which transpiles Ruby ActiveRecord-like models to JavaScript.

## Working Patterns

### ES Module Imports/Exports

```ruby
# Named imports (use array syntax)
import [ApplicationRecord], './application_record.js'
import [Article, Comment], './models.js'

# Default imports
import ApplicationRecord, './application_record.js'

# Named exports
export class Article < ApplicationRecord
end
```

### Class Inheritance

```ruby
export class Article < ApplicationRecord
  def self.table_name
    'articles'
  end
end
```

Transpiles to:
```javascript
export class Article extends ApplicationRecord {
  static get table_name() {
    return "articles"
  }
}
```

### Method Call Patterns

Zero-argument methods become getters:
```ruby
def save
  # ...
end
```

```javascript
get save() {
  // ...
}
```

Call without parentheses: `record.save` (not `record.save()`)

Methods with arguments remain methods:
```ruby
def find(id)
  # ...
end
```

```javascript
static find(id) {
  // ...
}
```

### Hash/Object Iteration

Use `Object.keys()` for JS compatibility:
```ruby
Object.keys(attrs).each do |key|
  value = attrs[key]
  # ...
end
```

Transpiles to:
```javascript
for (let key of Object.keys(attrs)) {
  let value = attrs[key];
  // ...
}
```

### Explicit Method Calls

For methods that should be method calls (not getters), add explicit `()`:
```ruby
stmt.step()      # Method call
stmt.getAsObject()
Time.now()
```

Without parentheses, zero-arg methods become property accesses.

## Issues and Workarounds

### 1. Private Field Shadowing in Subclasses

**Issue**: When a subclass references `@attribute`, the transpiler creates a new private field `#attribute` that shadows the parent's field.

**Workaround**: In subclasses, use `self.attribute` to access inherited getters instead of `@attribute`:

```ruby
# Instead of:
def title
  @attributes['title']  # Creates new #attributes in subclass
end

# Use:
def title
  self.attributes['title']  # Uses parent's attributes getter
end
```

### 2. `class << self` Not Supported

**Issue**: Singleton class syntax is not supported by the converter.

**Workaround**: Use explicit `def self.method_name` for class methods:

```ruby
# Instead of:
class << self
  attr_accessor :table_name
end

# Use:
def self.table_name
  @table_name
end

def self.table_name=(value)
  @table_name = value
end
```

### 3. Predicate Methods (`?` suffix)

**Issue**: Methods like `valid?` get transpiled with `.bind(this)` appended, causing incorrect behavior.

**Workaround**: Rename predicate methods to avoid the `?` suffix:

```ruby
# Instead of:
def valid?
  # ...
end

# Use:
def is_valid
  # ...
end
```

### 4. Hash Iteration with `each`

**Issue**: `hash.each do |key, value|` transpiles to `for (let [key, value] of hash)` which doesn't work on JS objects.

**Workaround**: Use `Object.keys()` pattern as shown above.

### 5. Array Append Operator (`<<`)

**Issue**: The `<<` operator is passed through as-is, which doesn't work in JS.

**Workaround**: Use `.push()` instead:

```ruby
# Instead of:
@errors << "error message"

# Use:
@errors.push("error message")
```

### 6. String `empty?` Method

**Issue**: May not transpile correctly in all contexts.

**Workaround**: Use explicit length check:

```ruby
# Instead of:
value.to_s.strip.empty?

# Use:
value.to_s.strip.length == 0
```

### 7. Module Instance Variables

**Issue**: Instance variables (`@var`) in modules transpile to `this.#var` which doesn't work correctly in an IIFE context.

**Workaround**: Use local variables within the module or avoid module-level state:

```ruby
# Instead of:
export module Routes
  @routes = []
  def self.add(route)
    @routes.push(route)
  end
end

# Use closures or pass state explicitly:
export module Routes
  def self.create_router
    routes = []
    {
      add: ->(route) { routes.push(route) },
      routes: -> { routes }
    }
  end
end
```

### 8. `chomp` Method

**Issue**: Ruby's `String#chomp` doesn't have a direct JS equivalent.

**Workaround**: Use `replace` with a regex:

```ruby
# Instead of:
name.chomp('s')

# Use:
name.gsub(/s$/, '')
```

## Recommended Code Style for Dual-Target Ruby/JS

1. **Always use explicit `self.`** for accessing instance methods/getters within methods
2. **Add `()` to method calls** that should remain method calls in JS
3. **Use `Object.keys()` for hash iteration**
4. **Use `.push()` instead of `<<`** for array operations
5. **Avoid predicate methods with `?`** suffix - use `is_` prefix instead
6. **Avoid `class << self`** - use `def self.` pattern
7. **Be explicit about parentheses** to control getter vs method transpilation

## View Transpilation

Views are written in Ruby as module functions that return HTML strings:

```ruby
export module ArticleViews
  def self.escape_html(str)
    return '' if str.nil?
    String(str).gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def self.list(locals)
    articles = locals[:articles]
    html = '<h1>Articles</h1>'
    articles.each do |article|
      html += %{<div class="article">#{escape_html(article.title)}</div>}
    end
    html
  end
end
```

Transpiles to:
```javascript
export const ArticleViews = (() => {
  function escape_html(str) {
    if (str == null) return "";
    return String(str).replaceAll("&", "&amp;")...
  };

  function list(locals) {
    let articles = locals.articles;
    let html = "<h1>Articles</h1>";
    for (let article of articles) {
      html += `<div class="article">${escape_html(article.title)}</div>`
    };
    return html
  };

  return {escape_html, list}
})()
```

Key patterns:
- Use `module` instead of `class` for view collections
- Use `self.` for all module methods
- Hash access `locals[:articles]` becomes property access `locals.articles`
- String interpolation `#{}` becomes template literals `${}`
- Ruby's `%{}` strings work well for HTML (avoid escaping quotes)
- **Avoid naming methods `index`** - the Functions filter converts `index` to `indexOf` (Ruby's String#index maps to JS indexOf). Use `list` instead.

## Controller Transpilation

Controllers use the same module pattern as views:

```ruby
import [Article], '../models/article.js'
import [ArticleViews], '../views/articles.js'

export module ArticlesController
  def self.list
    articles = Article.all
    ArticleViews.list({ articles: articles })
  end

  def self.show(id)
    article = Article.find(id)
    ArticleViews.show({ article: article })
  end

  def self.create(title, body)
    article = Article.create({ title: title, body: body })
    if article.id
      { success: true, id: article.id }
    else
      { success: false, html: ArticleViews.new_article({ article: article }) }
    end
  end
end
```

Key patterns:
- Controllers import models and views, then compose them
- Return HTML strings for read operations (list, show, edit forms)
- Return result objects for write operations (create, update, destroy)
- Use `list` instead of `index` to avoid Functions filter collision

## ERB Template Transpilation

The demo supports two view approaches:

### 1. Ruby Module Views (Original)
Views are written as Ruby modules with methods that return HTML strings:

```ruby
export module ArticleViews
  def self.list(locals)
    articles = locals[:articles]
    html = '<h1>Articles</h1>'
    articles.each { |a| html += "<div>#{a.title}</div>" }
    html
  end
end
```

### 2. ERB Template Views (New)
Standard ERB templates can be transpiled to JavaScript render functions:

```erb
<!-- app/views/articles/list.html.erb -->
<h1>Articles</h1>
<% @articles.each do |article| %>
  <div><%= article.title %></div>
<% end %>
```

Transpiles to:

```javascript
export function render({ articles }) {
  let _buf = "";
  _buf += "<h1>Articles</h1>\n";
  for (let article of articles) {
    _buf += `  <div>${String(article.title)}</div>\n`;
  }
  return _buf;
}
```

### ERB Filter Details

The ERB filter (`Ruby2JS::Filter::Erb`) transforms ERB buffer patterns:
- Detects `_erbout = +''` or `_buf = ::String.new` initialization
- Converts instance variables (`@articles`) to destructured parameters
- Transforms buffer concatenation (`<<`) to string concatenation (`+=`)
- Wraps output in a `render` function with proper parameters

### Build Script ERB Support

The build script uses `Ruby2JS::Erubi` to compile ERB templates:

```ruby
require 'ruby2js/filter/erb'
require 'ruby2js/erubi'

template = File.read('list.html.erb')
ruby_src = Ruby2JS::Erubi.new(template).src
js = Ruby2JS.convert(ruby_src, filters: [Ruby2JS::Filter::Erb, ...])
```

### Switching Between View Types

The demo includes a toggle to switch between Ruby module views and ERB views at runtime, demonstrating both approaches work equivalently.

## Filters Used

This demo uses the following Ruby2JS filters:

- `functions` - Ruby method to JS method mapping
- `esm` - ES module import/export support
- `return` - Implicit return handling

```ruby
OPTIONS = {
  eslevel: 2022,
  include: [:class, :call],
  filters: [
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::ESM,
    Ruby2JS::Filter::Return
  ]
}
```

## Helper Modules

Rails-like helpers are implemented as transpiled Ruby modules:

### Path Helpers

```ruby
export module PathHelpers
  def self.articles_path
    '/articles'
  end

  def self.article_path(article)
    id = extract_id(article)
    "/articles/#{id}"
  end

  def self.extract_id(obj)
    # Works with both objects {id: 5} and primitives (5)
    (obj && obj.id) || obj
  end
end
```

Usage: `PathHelpers.article_path(article)` or `PathHelpers.article_path(5)`

### View Helpers

```ruby
export module ViewHelpers
  def self.link_to(text, path, options = {})
    onclick = options[:onclick] || "navigate('#{path}')"
    style = options[:style] ? " style=\"#{options[:style]}\"" : ''
    "<a onclick=\"#{onclick}\"#{style}>#{text}</a>"
  end
end
```

Usage: `ViewHelpers.link_to('Articles', '/articles', style: 'color: blue;')`
