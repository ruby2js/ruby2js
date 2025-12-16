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

## Recommended Code Style for Dual-Target Ruby/JS

1. **Always use explicit `self.`** for accessing instance methods/getters within methods
2. **Add `()` to method calls** that should remain method calls in JS
3. **Use `Object.keys()` for hash iteration**
4. **Use `.push()` instead of `<<`** for array operations
5. **Avoid predicate methods with `?`** suffix - use `is_` prefix instead
6. **Avoid `class << self`** - use `def self.` pattern
7. **Be explicit about parentheses** to control getter vs method transpilation

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
