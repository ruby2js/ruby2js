# Ruby Feature Gaps Plan

## Status: Stages 0-2 Complete

This plan identifies Ruby language features not currently supported by Ruby2JS and evaluates which should be implemented.

## Current Coverage

Ruby2JS handles ~65 core AST node types covering:
- All basic literals (strings, numbers, symbols, arrays, hashes, regexps)
- Variables (local, instance, class, global, constants)
- Assignments (simple, multiple, operator, logical)
- Control flow (if/unless, case/when, while/until, for, break/next/return)
- Methods (def, class methods, arguments, yield, blocks)
- Classes and modules
- Exception handling (begin/rescue/ensure)
- Operators (arithmetic, logical, comparison)

## Unimplemented Node Types

### 1. Pattern Matching (Ruby 2.7+/3.0+)

**Node types:** `case_match`, `in_pattern`, `match_pattern`, `match_pattern_p`, `array_pattern`, `hash_pattern`, `find_pattern`, `match_var`, `match_as`, `match_rest`, `match_nil_pattern`, `pin`

**Example:**
```ruby
case data
in { name:, age: }
  puts "#{name} is #{age}"
in [first, *rest]
  puts first
end

# One-line pattern match
data => { name:, age: }
data in [a, b, *rest]
```

**JavaScript equivalent:** Destructuring with conditionals
```javascript
if (typeof data === 'object' && 'name' in data && 'age' in data) {
  let { name, age } = data;
  console.log(`${name} is ${age}`);
} else if (Array.isArray(data)) {
  let [first, ...rest] = data;
  console.log(first);
}
```

**Priority:** Medium - Pattern matching is increasingly common in modern Ruby
**Complexity:** High - Many sub-node types, complex conditional logic
**Recommendation:** Implement basic patterns (hash, array) first; skip advanced features (pin, find patterns)

### 2. Ranges as Values

**Node types:** `irange`, `erange`

**Current state:** Ranges work in specific contexts (for loops, array slicing, case/when) but not as standalone values.

**Example:**
```ruby
range = 1..10
range.each { |i| puts i }
range.include?(5)
```

**Issue:** JavaScript has no native Range object. Options:
1. Generate a custom Range class
2. Convert to Array immediately
3. Generate inline iterator

**Priority:** Low - Workarounds exist (use `.to_a`, explicit loops)
**Recommendation:** Document limitation; ranges in context already work

### 3. `alias` Statement (Top-level)

**Node type:** `alias`

**Current state:** `alias` works inside classes (converts to prototype assignment). Top-level `alias` is not handled.

**Example:**
```ruby
# Inside class - WORKS
class Foo
  alias new_name old_name
end

# Top-level - NOT IMPLEMENTED
alias new_name old_name
```

**Priority:** Low - Rare use case; `alias_method` in classes works

### 4. `retry` Statement

**Node type:** `retry`

**Example:**
```ruby
begin
  attempt_operation
rescue NetworkError
  retry  # Try again
end
```

**JavaScript equivalent:**
```javascript
while (true) {
  try {
    attemptOperation();
    break;
  } catch (e) {
    if (!(e instanceof NetworkError)) throw e;
    // continue loop (retry)
  }
}
```

**Priority:** Medium - Useful for network/IO operations
**Complexity:** Medium - Requires transforming begin/rescue into a loop
**Recommendation:** Implement; transforms rescue block into while loop

### 5. `BEGIN` and `END` Blocks

**Node types:** `preexe`, `postexe`

**Example:**
```ruby
BEGIN { puts "Starting" }
END { puts "Ending" }
```

**JavaScript equivalent:**
- `BEGIN` → Code at top of file/module
- `END` → No direct equivalent; could use `process.on('exit')` in Node

**Priority:** Very Low - Rarely used in modern Ruby
**Recommendation:** Skip; document as unsupported

### 6. Regex Back-references

**Node types:** `back_ref` (`$&`, `$'`, `` $` ``, `$+`)

**Current state:** Numbered captures (`$1`, `$2`) work via `nth_ref`. Special back-references don't.

**Example:**
```ruby
"hello world" =~ /world/
puts $&   # "world" - matched string
puts $`   # "hello " - before match
puts $'   # "" - after match
```

**JavaScript equivalent:** Use match result object
```javascript
let match = "hello world".match(/world/);
let matched = match[0];        // $&
let before = str.slice(0, match.index);  // $`
let after = str.slice(match.index + match[0].length);  // $'
```

**Priority:** Low - Numbered captures work; special refs are rare
**Complexity:** High - Requires tracking last match context
**Recommendation:** Skip; document as unsupported; suggest using match objects

### 7. Flip-flops

**Node type:** `iflipflop`, `eflipflop`

**Example:**
```ruby
DATA.each_line do |line|
  print line if /start/../end/  # Print lines between markers
end
```

**Priority:** Very Low - Obscure feature, rarely used
**Recommendation:** Skip; document as unsupported

### 8. `Rational` and `Complex` Literals

**Node types:** `rational`, `complex`

**Example:**
```ruby
r = 1/3r      # Rational(1, 3)
c = 2 + 3i    # Complex(2, 3)
```

**JavaScript equivalent:** None native; would need library

**Priority:** Very Low - Scientific computing use case
**Recommendation:** Skip; suggest using libraries if needed

### 9. Implicit Match (`if /regex/`)

**Node type:** Regular `if` with `match_current_line` or implicit `$_` match

**Example:**
```ruby
if /pattern/
  # Matches against $_
end
```

**Priority:** Very Low - Legacy Perl-ism, discouraged
**Recommendation:** Skip

### 10. Multiple Exception Types with Different Variables

**Current limitation:**
```ruby
# Works
begin
  risky
rescue StandardError => e
  handle(e)
end

# Does NOT work
begin
  risky
rescue NetworkError => ne
  handle_network(ne)
rescue IOError => ie
  handle_io(ie)
end
```

**Priority:** Medium - Common pattern
**Complexity:** Medium - Need to generate multiple catch blocks or type checking

**JavaScript equivalent:**
```javascript
try {
  risky();
} catch (e) {
  if (e instanceof NetworkError) {
    let ne = e;
    handleNetwork(ne);
  } else if (e instanceof IOError) {
    let ie = e;
    handleIo(ie);
  } else {
    throw e;
  }
}
```

**Recommendation:** Implement; useful for real error handling

### 11. `else` Clause in `begin/rescue`

**Example:**
```ruby
begin
  risky
rescue => e
  handle_error(e)
else
  # Runs if NO exception was raised
  success_action
end
```

**Priority:** Low - Less common pattern
**Recommendation:** Implement alongside multiple exception types

### 12. Endless Method Definition (Ruby 3.0+)

**Status:** ✅ IMPLEMENTED

**Example:**
```ruby
def square(x) = x * x
```

**Output:**
```javascript
function square(x) {return x * x}
```

### 13. Anonymous Block Forwarding (Ruby 3.1+)

**Example:**
```ruby
def foo(&)
  bar(&)
end
```

**Priority:** Low - New syntax, not widely adopted yet
**Recommendation:** Defer

### 14. Argument Forwarding (`...`) (Ruby 2.7+)

**Status:** ✅ IMPLEMENTED

**Example:**
```ruby
def wrapper(...)
  wrapped(...)
end
```

**Output:**
```javascript
function wrapper(...args) {
  wrapped(...args)
}
```

## Priority Summary

| Feature                     | Priority | Complexity | Status                                |
| --------------------------- | -------- | ---------- | ------------------------------------- |
| Endless method return       | **High** | Low        | ✅ Implemented                         |
| Argument forwarding (`...`) | Medium   | Low        | ✅ Implemented                         |
| `retry`                     | Medium   | Medium     | ✅ Already implemented                 |
| Multiple rescue types       | Medium   | Medium     | ✅ Already implemented                 |
| Pattern matching (basic)    | Medium   | High       | Deferred - explicitly not implemented |
| Ranges as values            | Low      | Medium     | Document limitation                   |
| `else` in rescue            | Low      | Low        | ✅ Implemented                         |
| Top-level `alias`           | Low      | Low        | Skip                                  |
| Regex back-refs             | Low      | High       | Skip                                  |
| Anonymous block forwarding  | Low      | Medium     | Defer                                 |
| BEGIN/END blocks            | Very Low | Medium     | Skip                                  |
| Rational/Complex            | Very Low | High       | Skip                                  |
| Flip-flops                  | Very Low | High       | Skip                                  |
| Implicit match              | Very Low | Medium     | Skip                                  |

## Implementation Stages

### Stage 0: Bug Fixes ✅ COMPLETE

1. **Endless method return statement** - Fixed missing `return` in `def foo(x) = expr`

### Stage 1: Modern Ruby Syntax ✅ COMPLETE

1. **Argument forwarding (`...`)** - Added `forward_args` and `forwarded_args` handlers

### Stage 2: Error Handling Improvements ✅ COMPLETE

These features were already implemented:
1. Multiple rescue clauses with different exception types
2. `retry` statement

Newly implemented:
- `else` clause in begin/rescue - uses a `$no_exception` flag to track success

### Stage 3: Pattern Matching (Basic)

1. Hash pattern matching (`in { key: value }`)
2. Array pattern matching (`in [a, b, *rest]`)
3. `=>` rightward assignment
4. `in` operator for pattern testing

**Rationale:** Pattern matching is a major Ruby 3.x feature. Basic support enables modern Ruby code.

**Note:** Pattern matching conversion has similar type-ambiguity issues as discussed in ECMASCRIPT_UPDATES.md. The generated JavaScript must handle type checking at runtime since Ruby's pattern matching includes implicit type guards.

### Stage 4: Pattern Matching (Advanced)

1. Guard clauses (`in pattern if condition`)
2. Alternative patterns (`in pattern1 | pattern2`)
3. Find patterns
4. Pin operator

**Rationale:** Complete pattern matching support; lower priority.

## Testing Strategy

Each feature should have:
1. Basic functionality tests
2. Edge case tests
3. Integration with existing features (e.g., pattern matching in methods)
4. ES level variations where applicable

## Not Implementing

The following are explicitly out of scope:

| Feature                   | Reason                                            |
| ------------------------- | ------------------------------------------------- |
| Flip-flops                | Obscure, rarely used                              |
| Rational/Complex literals | Requires numeric library                          |
| Regex special back-refs   | Would need match context tracking                 |
| BEGIN/END blocks          | Legacy feature, no JS equivalent                  |
| Implicit regex match      | Legacy Perl-ism                                   |
| Ranges as objects         | No JS equivalent; context-specific support exists |

## References

- [Parser AST Format](https://github.com/whitequark/parser/blob/master/doc/AST_FORMAT.md)
- [Ruby 3.0 Pattern Matching](https://docs.ruby-lang.org/en/3.0/syntax/pattern_matching_rdoc.html)
- [Ruby 3.1 Release Notes](https://www.ruby-lang.org/en/news/2021/12/25/ruby-3-1-0-released/)
- [Ruby 3.2 Release Notes](https://www.ruby-lang.org/en/news/2022/12/25/ruby-3-2-0-released/)
