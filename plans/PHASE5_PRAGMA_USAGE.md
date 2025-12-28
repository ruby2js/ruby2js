# Phase 5: Pragma Usage Review

## Summary

| Pragma Type | Count | Purpose                                                 |
| ----------- | ----- | ------------------------------------------------------- |
| `array`     | 22    | Force `arr.push(x)` instead of `arr << x` → `arr + [x]` |
| `skip`      | 19    | Exclude line/method from transpilation                  |
| `method`    | 18    | Force `walk.call(x)` instead of `walk(x)`               |
| `hash`      | 16    | Force `prop in obj` instead of `obj[prop]`              |
| `logical`   | 6     | Force `                                                 |
| `entries`   | 4     | Use `Object.entries()` for hash iteration               |

**Total**: 85 pragmas across selfhost-transpiled files

## Pragma Analysis by Category

### 1. `# Pragma: skip` (19 uses)

**Purpose**: Exclude Ruby-specific code that shouldn't be transpiled.

**Locations**:
- `prism_walker.rb`: `require 'prism'`, `respond_to?` methods, `visit` method override
- `node.rb`: Ruby introspection methods (`==`, `hash`, `to_sexp`, `inspect`, `is_a?`)
- `serializer.rb`: Array index operators (`[]`, `[]=`, `<<`)
- `converter.rb`: `unless defined?(RUBY2JS_SELFHOST)` blocks

**Assessment**: All appropriate. These are Ruby-specific implementations that either:
- Are replaced by JavaScript equivalents (require, respond_to?)
- Provide Ruby debugging support not needed in JS (to_sexp, inspect)
- Are handled differently in JS (array operators)

### 2. `# Pragma: array` (22 uses)

**Purpose**: Force `arr.push(x)` output instead of concatenation.

**Pattern**: `arr << item # Pragma: array`

**Why needed**: Without pragma, `<<` becomes `arr + [item]` (creates new array).
With pragma: `arr.push(item)` (mutates in place, correct behavior).

**Locations**: All in `serializer.rb` for building output lines/tokens.

**Assessment**: Necessary for correct semantics. This is a common pattern when building arrays incrementally.

**Could this be improved?**:
- The polyfill filter could potentially detect `<<` used in loops and auto-convert
- But explicit pragmas are clearer about intent

### 3. `# Pragma: method` (18 uses)

**Purpose**: Force method call syntax (`fn.call(x)`) instead of property access.

**Pattern**: `walk.call(node) # Pragma: method`

**Why needed**: Local block variables like `walk = proc { |n| ... }` are callable in Ruby but need explicit `.call()` in JavaScript.

**Locations**:
- `converter.rb`, `class2.rb`, `def.rb`, `hash.rb`, `kwbegin.rb`, `masgn.rb`
- All involve local proc/lambda variables used for recursive tree walking

**Assessment**: Necessary. These are all cases where a local variable holds a callable.

**Could this be improved?**:
- A filter could detect `walk = proc { ... }` and auto-add `.call()` to invocations
- But this would require complex dataflow analysis
- Pragmas are simpler and more explicit

### 4. `# Pragma: hash` (16 uses)

**Purpose**: Force `prop in obj` syntax instead of `obj[prop]`.

**Pattern**: `@vars.include?(name) # Pragma: hash`

**Why needed**: Ruby's `hash.include?(key)` checks for key existence.
- Without pragma: becomes `hash[key]` (gets value, truthy check)
- With pragma: becomes `key in hash` (proper existence check)

**Locations**: All in variable declaration tracking (`@vars` hash).

**Assessment**: Necessary for correct semantics. The converter tracks variable declarations in `@vars` hash, and needs true existence checks.

**Could this be improved?**:
- The functions filter could handle `include?` on Hash objects differently
- But Ruby2JS doesn't track types, so can't distinguish Hash from Array

### 5. `# Pragma: logical` (6 uses)

**Purpose**: Force `||` instead of `??` for nullish coalescing.

**Pattern**: `a || b # Pragma: logical`

**Why needed**: Modern Ruby2JS converts `||` to `??` (nullish coalescing) which only handles `null`/`undefined`. Some code needs traditional `||` which also handles falsy values like `false` or `0`.

**Locations**:
- `send.rb`: Default receiver lookups
- `kwbegin.rb`: Result accumulation where `false` is valid

**Assessment**: Necessary for semantic correctness.

### 6. `# Pragma: entries` (4 uses)

**Purpose**: Force `Object.entries()` for hash iteration.

**Pattern**: `hash.map { |k, v| ... } # Pragma: entries`

**Why needed**: Ruby hash iteration yields `[key, value]` pairs. JavaScript object iteration needs `Object.entries()` to get the same behavior.

**Locations**: All in `converter.rb` for iterating `@vars` hash.

**Assessment**: Necessary. This is a fundamental Ruby/JS difference for hash iteration.

## Reduction Opportunities

### Already Addressed

1. ✅ **`.join` empty separator** - Added to functions filter (Phase 3)

### Could Be Addressed

| Pattern             | Current Pragma | Potential Solution                      |
| ------------------- | -------------- | --------------------------------------- |
| `arr << x` in loops | `array`        | Detect loop context, auto-use `.push()` |
| `hash.include?(k)`  | `hash`         | Type inference (complex)                |
| `proc.call(x)`      | `method`       | Track proc variables (complex)          |

### Not Worth Addressing

1. **`# Pragma: skip`** - Inherently needs explicit marking
2. **`# Pragma: logical`** - Semantic choice, must be explicit
3. **`# Pragma: entries`** - Only 4 uses, explicit is clearer

## Assessment

The current pragma count (85 total) is reasonable for a codebase of this complexity:
- **~600 lines** in converter.rb
- **~600 lines** in serializer.rb
- **~250 lines** in prism_walker.rb
- **~50 converter handlers** (average ~30 lines each)

**Pragma density**: ~85 pragmas / ~3000 lines = **~2.8%** of lines have pragmas

This is acceptable for a dual-target codebase. Each pragma serves a legitimate purpose for semantic correctness.

## Recommendations

1. **No immediate changes needed** - Pragma usage is appropriate
2. **Document patterns** in User's Guide (Phase 6) as examples
3. **Consider future filter improvements**:
   - `<<` in loop context → auto `.push()`
   - Would reduce ~10-15 pragmas but adds complexity

## Conclusion

The pragma usage follows the principle of "explicit is better than implicit." Each pragma addresses a genuine Ruby/JavaScript semantic difference that cannot be safely auto-detected without risking incorrect behavior in other contexts.

The current approach prioritizes correctness over minimizing pragmas, which is the right trade-off for production code.
