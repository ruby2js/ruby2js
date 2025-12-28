# Phase 3: Selfhost Filter Audit

## Filter Overview

The selfhost filter suite consists of 4 files:

| File           | Lines | Purpose                                       |
| -------------- | ----- | --------------------------------------------- |
| `core.rb`      | 18    | Entry point only, loads other modules         |
| `walker.rb`    | 187   | Prism API mapping (Ruby ↔ JS)                 |
| `converter.rb` | 323   | Handle pattern, respond_to?, array comparison |
| `spec.rb`      | 74    | Test spec transformations                     |

## Analysis by Filter

### 1. selfhost/core.rb (Entry Point)

**Status**: No transformations, just module loading.

No changes needed.

### 2. selfhost/walker.rb (Prism API Mapping)

**Purpose**: Maps Ruby Prism API to JavaScript @ruby/prism package conventions.

**Transformations**:
- `visit_program_node` → `visitProgramNode` (method name camelCase)
- `node.opening_loc` → `node.openingLoc` (property camelCase)
- `node.safe_navigation?` → `node.isSafeNavigation()` (predicate methods)
- `node.arguments` → `node.arguments_` (reserved word suffixing)
- `node.unescaped` → `node.unescaped.value` (JS returns object)
- `node.end_offset` → `node.startOffset + node.length` (API difference)
- Remove `private`/`protected`/`public` (no-op in JS)

**Assessment**: Highly specific to Prism API differences. Not generalizable.

**Recommendation**: Keep as-is. This is the canonical example of a "library adapter filter" - it bridges API differences between Ruby and JS versions of the same library.

### 3. selfhost/converter.rb (Converter Transformations)

**Purpose**: Transforms Ruby2JS converter source code patterns.

#### 3.1 `handle :type do...end` Pattern (lines 275-315)

Transforms Ruby2JS's handler registration DSL:
```ruby
handle :nil do put 'null' end
```
becomes:
```javascript
on_nil() { this.put('null') }
Converter._handlers.push('nil')
```

**Assessment**: Completely specific to Ruby2JS internals.

**Recommendation**: Keep as-is. This is a great example of a filter that handles domain-specific DSL patterns.

#### 3.2 `respond_to?` Transformation (lines 118-133, 222-273)

Transforms:
```ruby
obj.respond_to?(:prop)
```
to:
```javascript
typeof obj === 'object' && obj !== null && 'prop' in obj
```

**Analysis**: The functions filter already has a basic `respond_to?` handler:
```ruby
elsif method == :respond_to? and args.length == 1
  process S(:in?, args.first, target)
```
But it produces only `'prop' in obj`, which throws on primitives/null.

The selfhost filter adds safety guards because converter code calls `respond_to?` on values that might be:
- Primitives (strings, symbols, numbers from AST)
- Null/undefined (optional children)

**Can this be generalized?**
- **Option A**: Upgrade functions filter to always include guards → Breaking change, more verbose output
- **Option B**: Add an ES option for "safe respond_to?" → Complexity
- **Option C**: Keep in selfhost filter → Current approach

**Recommendation**: Keep in selfhost filter. The current functions filter behavior is correct for most use cases (checking properties on known objects). The guarded version is only needed when you might call respond_to? on primitives.

#### 3.3 Array Slice Comparison (lines 138-167)

Transforms:
```ruby
x.children[0..1] == [nil, :async]
```
to:
```javascript
x.children[0] === null && x.children[1] === 'async'
```

**Assessment**: This handles a very specific pattern used in converter code. JavaScript array comparison fails because `[] === []` compares references, not values.

**Could this be generalized?** Theoretically, but the pattern is rare outside of AST manipulation code. Adding it to functions filter would add overhead for a rare case.

**Recommendation**: Keep in selfhost filter.

#### 3.4 ALWAYS_METHODS / GETTER_METHODS (lines 41-46, 81-94)

Forces certain method calls to emit parentheses or not:
- `pop`, `shift`, `is_method?`, etc. → Always method calls
- `first`, `last` → Getters (prevents functions filter's `[0]` transform)

**Assessment**: These compensate for Ruby2JS's method/property ambiguity. They're specific to the selfhost codebase's internal classes (Line, Token).

**Recommendation**: Keep as-is. Document as example of how to handle method/property disambiguation when you know your object types.

#### 3.5 CONVERTER_INSTANCE_METHODS (lines 51-54, 69-73)

Transforms unqualified calls to instance methods to use `self.`:
```ruby
parse_condition(x)  →  self.parseCondition(x)
```

**Assessment**: Ruby allows calling instance methods without `self.`, JS requires `this.`. This list is specific to the converter codebase.

**Recommendation**: Keep as-is.

#### 3.6 `puts` Protection (lines 64-66)

Transforms `puts` to `self.puts` to prevent functions filter from converting to `console.log`.

**Assessment**: Selfhost-specific. The Serializer class has a `puts` method that adds tokens.

**Recommendation**: Keep as-is.

#### 3.7 `defined?(RUBY2JS_SELFHOST)` Guard (lines 21-34)

Removes code blocks guarded by `unless defined?(RUBY2JS_SELFHOST)`.

**Assessment**: This is a compile-time conditional compilation mechanism. Very useful pattern.

**Could this be generalized?** Yes! This could become a general-purpose `defined?` filter that removes code based on constants. Example use cases:
- `defined?(DEBUG)` - Remove debug code
- `defined?(PRODUCTION)` - Remove dev-only code

**Recommendation**: Consider extracting to a general `conditional_compile` filter in a future phase.

#### 3.8 `Ruby2JS::Node.new` Global Reference (lines 99-116)

Transforms:
```ruby
Ruby2JS::Node.new(...)
```
to:
```javascript
new globalThis.Ruby2JS.Node(...)
```

**Assessment**: Specific to the converter module which defines its own `Ruby2JS` local that shadows the global.

**Recommendation**: Keep as-is.

#### 3.9 `.join` Empty Separator (lines 76-79)

Transforms `.join` → `.join("")` because Ruby defaults to "" but JS defaults to ",".

**Assessment**: The functions filter does NOT handle `.join`. This transformation is necessary.

**Could this be generalized?** Yes! This is a common Ruby/JS semantic difference that affects all users. The functions filter should handle this.

**Recommendation**: Consider adding `.join` handling to the functions filter:
```ruby
elsif method == :join and args.length == 0
  process node.updated(nil, [target, :join, s(:str, '')])
```

### 4. selfhost/spec.rb (Test Spec Transformations)

**Purpose**: Transforms test spec patterns for browser execution.

**Transformations**:
- `_(value)` → `value` (removes minitest expectation wrapper)
- `@var` → `globalThis._var` (outside classes, for arrow function contexts)

**Assessment**: Highly specific to the minitest-to-browser test harness.

**Recommendation**: Keep as-is.

## Summary

### Generalizable Patterns

| Pattern                 | Current Location     | Generalization Potential                       |
| ----------------------- | -------------------- | ---------------------------------------------- |
| `.join` empty separator | converter.rb:76-79   | **High** - common Ruby/JS difference           |
| `defined?(CONST)` guard | converter.rb:21-34   | High - useful for conditional compilation      |
| Safe `respond_to?`      | converter.rb:118-133 | Medium - useful when target might be primitive |

### Recommended Actions

1. **Immediate**: Add `.join` empty separator handling to functions filter (benefits all users)
2. **Keep other filters as-is** - They serve their purpose well
3. **Document patterns** - Use these as examples in User's Guide of how to write domain-specific filters
4. **Future consideration**: Extract `defined?(CONST)` pattern to a general conditional compilation filter

### Notable Design Patterns

The selfhost filters demonstrate several valuable patterns:

1. **Library Adapter Filter** (walker.rb)
   - Bridges API differences between Ruby and JS versions of a library
   - Uses lookup tables for name mapping
   - Handles semantic differences (`.unescaped` returning object vs string)

2. **DSL Transformation Filter** (converter.rb - handle pattern)
   - Transforms Ruby DSL syntax into JS equivalent
   - Generates both method definition and registration code

3. **Method Disambiguation** (converter.rb - ALWAYS_METHODS/GETTER_METHODS)
   - When you know your object types, you can force method vs property access
   - Prevents unwanted filter transformations

4. **Conditional Compilation** (converter.rb - defined? guard)
   - Remove code paths at compile time based on constants
   - Useful for platform-specific code

## Verdict

The selfhost filters are appropriately scoped. They handle patterns that are genuinely specific to:
- The Prism library API differences (walker.rb)
- The Ruby2JS internal DSL (converter.rb - handle pattern)
- The specific codebase structure (converter.rb - instance methods, etc.)
- The test harness requirements (spec.rb)

No code should be removed. The one generalizable pattern (conditional compilation) is a candidate for future extraction but is working well in its current location.
