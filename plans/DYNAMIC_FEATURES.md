# Dynamic Ruby Features Implementation Plan

## Goal

Support Ruby's class-based object-oriented patterns that map naturally to JavaScript's prototype system. This gives users a clear mental model: **Ruby's OO patterns work; runtime metaprogramming doesn't.**

## Phase 1: Module Mixins (`include` / `extend`)

### Current State
- `include` inside class bodies partially works but has bugs
- `include` in `Class.new { include Mod }` generates invalid JS (`$0 = prototype` without receiver)
- `extend` is not supported

### Implementation

**1.1 Fix `include` in class bodies (converter/class.rb)**

Currently generates:
```javascript
// Buggy output for: class Foo; include Bar; end
(() => {
  let $0 = prototype;  // BUG: should be Foo.prototype
  return Object.defineProperties($0, Object.getOwnPropertyDescriptors(Bar))
})();
```

Fix to generate:
```javascript
Object.defineProperties(Foo.prototype, Object.getOwnPropertyDescriptors(Bar));
```

**1.2 Fix `include` in `Class.new` blocks (converter/class.rb)**

Currently broken for:
```ruby
filter = Class.new(Parent) { include Mod }
```

Should generate:
```javascript
let _class = class extends Parent {};
Object.defineProperties(_class.prototype, Object.getOwnPropertyDescriptors(Mod));
filter = _class;
```

**1.3 Add `extend` support**

```ruby
class Foo
  extend Bar  # Add Bar's methods as class methods
end
```

Generates:
```javascript
class Foo {}
Object.defineProperties(Foo, Object.getOwnPropertyDescriptors(Bar));
```

### Tests
- `include` single module in class
- `include` multiple modules
- `include` in `Class.new` block
- `include` in loop (`filters.each { |m| Class.new { include m } }`)
- `extend` single module
- `extend` multiple modules
- Module with instance methods, class methods, and constants

### Documentation
- Update anti-patterns.md: Change `include`/`extend` from "❌ Avoid" to "✅ Safe"
- Add examples to patterns.md
- Update functions.md filter docs

---

## Phase 2: Type Introspection

### Current State
- `is_a?`, `kind_of?`, `instance_of?` documented as "Pragma skip" in anti-patterns
- No automatic conversion

### Implementation (functions filter)

**2.1 `is_a?` / `kind_of?`**

```ruby
obj.is_a?(Foo)      # => obj instanceof Foo
obj.kind_of?(Foo)   # => obj instanceof Foo
```

Handle special cases:
```ruby
obj.is_a?(Array)    # => Array.isArray(obj)
obj.is_a?(String)   # => typeof obj === "string"
obj.is_a?(Integer)  # => typeof obj === "number" && Number.isInteger(obj)
obj.is_a?(Float)    # => typeof obj === "number"
obj.is_a?(Hash)     # => typeof obj === "object" && obj !== null && !Array.isArray(obj)
```

**2.2 `instance_of?`**

```ruby
obj.instance_of?(Foo)  # => obj.constructor === Foo
```

Special cases same as `is_a?`.

**2.3 `respond_to?`**

```ruby
obj.respond_to?(:foo)        # => "foo" in obj
obj.respond_to?("foo")       # => "foo" in obj
obj.respond_to?(method_var)  # => method_var in obj
```

Or optionally check for function:
```ruby
obj.respond_to?(:foo, true)  # => typeof obj.foo === "function"
```

### Tests
- `is_a?` with user classes
- `is_a?` with built-in types (Array, String, Integer, Float, Hash)
- `kind_of?` (alias behavior)
- `instance_of?` exact match
- `respond_to?` with symbol and string
- `respond_to?` with variable

### Documentation
- Update anti-patterns.md: Change from "⚠️ Pragma skip" to "✅ Safe"
- Add type checking examples to patterns.md

---

## Phase 3: Class Introspection

### Current State
- `.class` requires `# Pragma: proto` to become `.constructor`
- `superclass` not supported

### Implementation (functions filter)

**3.1 `.class` method**

```ruby
obj.class            # => obj.constructor
obj.class.name       # => obj.constructor.name
obj.class == Foo     # => obj.constructor === Foo
```

Note: Currently requires `include: [:class]`. Consider making this default or documenting better.

**3.2 `superclass`**

```ruby
Foo.superclass       # => Object.getPrototypeOf(Foo.prototype).constructor
```

For class without explicit parent:
```ruby
class Foo; end
Foo.superclass       # => Object
```

### Tests
- `.class` returns constructor
- `.class.name` returns class name
- `superclass` with inheritance
- `superclass` chain

### Documentation
- Update anti-patterns.md
- Add introspection examples

---

## Phase 4: Documentation Overhaul

### Changes to anti-patterns.md

Update the Summary table:

| Feature             | Status  | Notes                   |
| ------------------- | ------- | ----------------------- |
| `define_method`     | ✅ Safe  | In class bodies         |
| `send`              | ✅ Safe  | Static or dynamic names |
| `include`/`extend`  | ✅ Safe  | Module mixins           |
| `is_a?`, `kind_of?` | ✅ Safe  | Maps to `instanceof`    |
| `instance_of?`      | ✅ Safe  | Exact type check        |
| `respond_to?`       | ✅ Safe  | Property existence      |
| `.class`            | ✅ Safe  | Returns constructor     |
| `superclass`        | ✅ Safe  | Parent class            |
| `method_missing`    | ❌ Avoid | Requires runtime proxy  |
| `eval`              | ❌ Avoid | Runtime code gen        |
| `prepend`           | ❌ Avoid | MRO incompatible        |

### New Section: "Ruby's Object Model in JavaScript"

Explain the mapping:
- Ruby classes → JavaScript classes (ES6)
- Ruby modules → JavaScript objects with methods
- `include` → prototype property copying
- `extend` → class property copying
- Inheritance → `extends` keyword
- `super` → `super` keyword

---

## Phase 5: Selfhost Benefits

Once implemented, the selfhost can:

1. Use `include` for filter composition instead of hand-written adapters
2. Use `is_a?` / `respond_to?` for type checks instead of manual patterns
3. Remove FilterProcessor wrapper class
4. Transpile the filter chain pattern directly

---

## Implementation Order

1. **Phase 1.1**: Fix `include` in class bodies (unblocks most use cases)
2. **Phase 2.1-2.3**: Type introspection (`is_a?`, `respond_to?`)
3. **Phase 1.2**: Fix `include` in `Class.new` blocks
4. **Phase 1.3**: Add `extend` support
5. **Phase 3**: Class introspection (`.class`, `superclass`)
6. **Phase 4**: Documentation updates

Each phase includes tests and documentation before moving to next.

---

## Success Criteria

- All new features have spec tests
- Documentation is updated
- Anti-patterns.md reflects new capabilities
- Selfhost can use `include` for filter composition
- No regressions in existing tests
