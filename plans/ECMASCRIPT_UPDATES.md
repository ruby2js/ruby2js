# ECMAScript Updates Plan

## Status: Implemented (Stage 2 Complete)

This plan documents ECMAScript features added since ES2022 (the last version Ruby2JS explicitly supports) and identifies which are relevant for Ruby2JS to implement.

## Current State

Ruby2JS currently supports ES2015 through ES2022:
- ES level detection via `eslevel` option
- Helper methods `es2015` through `es2022` for conditional code generation
- The `functions` filter maps Ruby methods to JavaScript equivalents

The last significant ES-level update was ES2022 which added:
- Private class fields (`#field`)
- `Array.prototype.at()`
- `replaceAll()` (ES2021)

## ECMAScript 2023 (ES14)

Released June 2023. All features supported in modern browsers since July 2023.

### Relevant Features

| Feature           | Ruby Equivalent          | Priority | Notes                                      |
| ----------------- | ------------------------ | -------- | ------------------------------------------ |
| `findLast()`      | `reverse.find` pattern   | Low      | Type ambiguity limits usefulness           |
| `findLastIndex()` | `rindex` with block      | Low      | String/Array ambiguity                     |
| `toReversed()`    | `reverse` (non-mutating) | Low      | Type ambiguity (Array vs String vs custom) |
| `toSorted()`      | `sort` (non-mutating)    | Low      | Type ambiguity                             |
| `toSpliced()`     | N/A                      | Low      | No direct Ruby equivalent                  |
| `with()`          | N/A                      | Low      | No direct Ruby equivalent                  |

### Implementation Plan

**`toReversed()` and `toSorted()`** (Priority: Low - See Note)

In theory, Ruby2JS could convert `array.reverse` to `toReversed()` for immutable semantics matching Ruby:

```ruby
# Ruby
result = array.reverse  # returns new array, original unchanged

# Current JS output
result = array.reverse()  // MUTATES array!

# ES2023+ output
result = array.toReversed()  // correct immutable semantics
```

**Important limitation:** Ruby2JS cannot determine from source code alone whether `a.reverse` is:
- Array reverse (should use `toReversed()`)
- String reverse (needs `split('').reverse().join('')`)
- Custom object with `reverse` method (should pass through)

Same ambiguity exists for `sort` → `toSorted()`.

Recommend: Keep current behavior. The mutation difference is a known JavaScript gotcha that users must be aware of. Changing this selectively based on guessed types would be inconsistent.

**`findLast()` and `findLastIndex()`** (Priority: Low - See Note)

Potential Ruby method mappings:
```ruby
# Ruby
array.reverse.find { |x| x > 5 }  # could optimize to findLast
array.rindex { |x| x > 5 }        # map to findLastIndex with block
```

**Limitations:**
- `reverse.find` optimization requires recognizing the pattern and knowing `reverse` is on an Array
- `rindex` with a block works on both String and Array with different semantics

Recommend: Only implement `findLast` for explicit `reverse.find` pattern where we can be reasonably confident it's an Array operation. Skip `rindex` due to String/Array ambiguity.

### Not Relevant

| Feature                 | Reason                                             |
| ----------------------- | -------------------------------------------------- |
| Symbols as WeakMap keys | Internal JS optimization, no Ruby equivalent       |
| Hashbang grammar        | Ruby2JS output is modules/scripts, not executables |

## ECMAScript 2024 (ES15)

Released June 2024. Supported in Chrome 117+, Firefox 119+, Safari 17+.

### Relevant Features

| Feature                             | Ruby Equivalent     | Priority     | Notes                    |
| ----------------------------------- | ------------------- | ------------ | ------------------------ |
| `Object.groupBy()`                  | `group_by`          | **Critical** | Direct 1:1 mapping       |
| `Map.groupBy()`                     | `group_by` (to Map) | Medium       | Variant returning Map    |
| `Promise.withResolvers()`           | N/A                 | Low          | Advanced Promise pattern |
| `isWellFormed()` / `toWellFormed()` | `valid_encoding?`   | Low          | Unicode validation       |

### Implementation Plan

**`Object.groupBy()`** (Priority: Critical)

This is the most important ES2024 feature for Ruby2JS. Ruby's `group_by` is extremely common:

```ruby
# Ruby
people.group_by { |p| p.age }
# => { 25 => [...], 30 => [...] }

# Current: requires underscore filter or manual implementation
_.groupBy(people, p => p.age)

# ES2024+ output
Object.groupBy(people, p => p.age)
```

Currently `group_by` is only supported via the deprecated `underscore` filter. ES2024 makes this native.

**Implementation approach:**
1. Add `es2024` helper method to `Converter` and `Filter::Processor`
2. In `functions` filter, map `group_by` block to `Object.groupBy()` when `es2024`
3. Similarly map `sort_by`, `max_by`, `min_by` using existing patterns

### Not Relevant

| Feature                | Reason                                          |
| ---------------------- | ----------------------------------------------- |
| Resizable ArrayBuffers | Low-level API, no Ruby equivalent               |
| ArrayBuffer.transfer() | Low-level API, no Ruby equivalent               |
| RegExp /v flag         | Complex regex feature, rare use case            |
| Atomics.waitAsync      | SharedArrayBuffer/threading, no Ruby equivalent |

## ECMAScript 2025 (ES16)

Released June 2025. Browser support varies by feature.

### Relevant Features

| Feature           | Ruby Equivalent                             | Priority | Notes                           |
| ----------------- | ------------------------------------------- | -------- | ------------------------------- |
| Iterator helpers  | `map`, `filter`, `take`, etc. on Enumerator | Medium   | Lazy iteration                  |
| Set methods       | Set operations                              | Medium   | Opt-in via `Set.new(x)` wrapper |
| `RegExp.escape()` | `Regexp.escape`                             | Medium   | Direct mapping                  |
| `Promise.try()`   | N/A                                         | Low      | Advanced Promise pattern        |

### Implementation Plan

**Set Methods** (Priority: Medium - Opt-in via explicit wrapper)

Ruby Set operations map directly to ES2025 Set methods:

```ruby
# Ruby
set1 & set2          # intersection
set1 | set2          # union
set1 - set2          # difference
set1 ^ set2          # symmetric difference
set1 <= set2         # subset?
set1 >= set2         # superset?
(set1 & set2).empty? # disjoint?

# ES2025
set1.intersection(set2)
set1.union(set2)
set1.difference(set2)
set1.symmetricDifference(set2)
set1.isSubsetOf(set2)
set1.isSupersetOf(set2)
set1.isDisjointFrom(set2)
```

**Type ambiguity solution:** Use explicit `Set.new()` wrapper as opt-in:

```ruby
# Ambiguous - not converted
a & b

# Explicit Set - safe to convert
Set.new(a) & Set.new(b)      # → new Set(a).intersection(new Set(b))
a.to_set & b.to_set          # → a.toSet().intersection(b.toSet())
Set.new(a).intersection(b)   # → new Set(a).intersection(b)
```

This follows the same pattern as `Array()` for Array methods - developers opt-in by being explicit about types.

**`RegExp.escape()`** (Priority: Medium)

```ruby
# Ruby
Regexp.escape("hello.world")  # => "hello\\.world"

# ES2025
RegExp.escape("hello.world")  // => "hello\\.world"
```

**Iterator Helpers** (Priority: Low)

ES2025 adds `.map()`, `.filter()`, `.take()`, `.drop()`, `.flatMap()`, `.reduce()`, `.toArray()`, `.forEach()`, `.some()`, `.every()`, `.find()` to Iterator.prototype.

This enables lazy evaluation similar to Ruby's Enumerator::Lazy. However, mapping is complex because:
1. Ruby iterators work on any Enumerable
2. JS iterator helpers require explicit iterator objects
3. Most Ruby code uses eager Array methods anyway

Recommend: Document but don't implement unless demand emerges.

### Not Relevant

| Feature                          | Reason                                       |
| -------------------------------- | -------------------------------------------- |
| Import Attributes / JSON Modules | ESM feature, handled by bundlers             |
| Float16Array                     | Specialized numeric type, no Ruby equivalent |
| Duplicate named capture groups   | Regex edge case                              |
| DurationFormat                   | Intl API, no direct Ruby equivalent          |

## Implementation Stages

### Stage 1: ES2023 Support

1. Add `es2023` helper method
2. Create `lib/ruby2js/es2023.rb`
3. Implement opt-in Array methods (when receiver is explicit Array wrapper):
   - `Array(x).reverse` → `Array(x).toReversed()`
   - `Array(x).sort` → `Array(x).toSorted()`
   - `Array(x).reverse.find { }` → `Array(x).findLast()`
4. Add tests for wrapper detection and conversion
5. Update documentation

### Stage 2: ES2024 Support

1. Add `es2024` helper method
2. Create `lib/ruby2js/es2024.rb`
3. Implement in `functions` filter:
   - `group_by` block → `Object.groupBy()` (always safe)
4. Add tests
5. Update documentation
6. Consider deprecating `underscore` filter's `group_by` support

### Stage 3: ES2025 Support

1. Add `es2025` helper method
2. Create `lib/ruby2js/es2025.rb`
3. Implement in `functions` filter:
   - `Regexp.escape` → `RegExp.escape()` (always safe)
   - Opt-in Set methods (when receiver is `Set.new(x)` or `x.to_set`):
     - `&` / `intersection` → `.intersection()`
     - `|` / `union` → `.union()`
     - `-` / `difference` → `.difference()`
     - `^` / `symmetric_difference` → `.symmetricDifference()`
     - `subset?` → `.isSubsetOf()`
     - `superset?` → `.isSupersetOf()`
     - `disjoint?` → `.isDisjointFrom()`
4. Add tests
5. Update documentation

## Priority Summary

| Feature                          | ES Version | Priority | Notes                                              |
| -------------------------------- | ---------- | -------- | -------------------------------------------------- |
| `Object.groupBy()`               | ES2024     | **Safe** | Unambiguous - only exists on Enumerable with block |
| `RegExp.escape()`                | ES2025     | **Safe** | Unambiguous - class method on Regexp               |
| `toReversed()` / `toSorted()`    | ES2023     | Opt-in   | Use `Array(x).reverse` for explicit type hint      |
| `findLast()` / `findLastIndex()` | ES2023     | Opt-in   | Use `Array(x).find` pattern                        |
| Set methods                      | ES2025     | Opt-in   | Use `Set.new(x)` for explicit type hint            |
| Iterator helpers                 | ES2025     | Complex  | Requires explicit iterator objects                 |

**Conclusion:**

Two features are always safe:
1. `Object.groupBy()` - Ruby's `group_by` is unambiguous
2. `RegExp.escape()` - Ruby's `Regexp.escape` is unambiguous

Additional features can be enabled via **explicit type wrappers** - when developers wrap values in `Array()`, `Set.new()`, etc., Ruby2JS can confidently apply type-specific transformations. This is opt-in on a case-by-case basis.

## Explicit Type Wrapper Pattern

Instead of guessing types, recognize explicit constructors/converters as type hints:

```ruby
# Ambiguous - Ruby2JS cannot know the type
data.reverse

# Explicit Array - safe to use toReversed()
Array(data).reverse

# Explicit Set - safe to use Set methods
Set.new(a) & Set.new(b)
Set.new(a).intersection(Set.new(b))

# Explicit - findLast optimization
Array(data).reverse.find { |x| x > 5 }
```

### Recognized Type Wrappers

| Ruby Expression | Inferred Type | Enables                                     |
| --------------- | ------------- | ------------------------------------------- |
| `Array(x)`      | Array         | `toReversed`, `toSorted`, `findLast`, etc.  |
| `[*x]`          | Array         | Same as above                               |
| `x.to_a`        | Array         | Same as above                               |
| `Set.new(x)`    | Set           | `intersection`, `union`, `difference`, etc. |
| `x.to_set`      | Set           | Same as above                               |

### Implementation Approach

When processing a method call, check if the receiver is a recognized type wrapper:

```ruby
# In functions filter
def on_send(node)
  target, method, *args = node.children

  # Check for explicit Array wrapper
  if array_wrapper?(target)
    case method
    when :reverse
      return es2023 ? s(:send, process(target), :toReversed) : super
    when :sort
      return es2023 ? s(:send, process(target), :toSorted) : super
    end
  end

  # Check for explicit Set wrapper
  if set_wrapper?(target)
    case method
    when :&, :intersection
      return es2025 ? s(:send, process(target), :intersection, *args) : super
    # ... etc
    end
  end

  super
end

def array_wrapper?(node)
  return false unless node
  # Array(x)
  (node.type == :send && node.children[0..1] == [nil, :Array]) ||
  # [*x]
  (node.type == :array && node.children.length == 1 && node.children[0].type == :splat) ||
  # x.to_a
  (node.type == :send && node.children[1] == :to_a)
end
```

## Testing Strategy

Each new ES level should have:
1. Unit tests for each transformation
2. Tests verifying fallback behavior for lower ES levels
3. Integration tests with the demo

Example test structure:
```ruby
describe "ES2023 support" do
  def to_js(string)
    Ruby2JS.convert(string, eslevel: 2023, filters: [:functions]).to_s
  end

  it "converts reverse to toReversed" do
    to_js('a.reverse').must_equal 'a.toReversed()'
  end

  it "converts sort to toSorted" do
    to_js('a.sort').must_equal 'a.toSorted()'
  end
end
```

## References

- [ECMAScript 2023 features](https://pawelgrzybek.com/whats-new-in-ecmascript-2023/)
- [ECMAScript 2024 features](https://pawelgrzybek.com/whats-new-in-ecmascript-2024/)
- [ECMAScript 2025 features](https://pawelgrzybek.com/whats-new-in-ecmascript-2025/)
- [TC39 Proposals](https://github.com/tc39/proposals)
- [ECMAScript 2024 Specification](https://tc39.es/ecma262/2024/)
- [ECMAScript 2025 Specification](https://tc39.es/ecma262/2025/)
