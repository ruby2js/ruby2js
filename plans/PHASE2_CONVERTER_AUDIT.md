# Phase 2: Converter Audit

This document audits all converter changes made since commit e15b9777 for the self-hosting effort. For each change, we assess whether it:
1. Could be simplified now that we have pragmas and polyfills
2. Should be moved to a filter
3. Is properly generalized to benefit all users
4. Is well documented

## Change Categories

The converter changes fall into several categories:

### Category A: JS Compatibility Fixes (Keep as-is)
Changes that fix fundamental Ruby/JS differences that affect everyone.

### Category B: Pragma-Driven (Keep as-is)
Changes that add pragma support - these are by design.

### Category C: Selfhost-Specific Workarounds (Review)
Changes specifically for transpiling Ruby2JS itself - may need filters.

### Category D: Array Comparison Fixes (Keep as-is)
Changes from `== s(:const, nil, :X)` to element-by-element comparison.

---

## Detailed Audit

### converter.rb (165 lines changed)

| Change | Category | Assessment |
|--------|----------|------------|
| `JS_RESERVED` from Set to Array | C | **Could simplify:** This was done because JS `Set.has()` vs Ruby `Set.include?`. The selfhost filter could map `.include?` → `.has()` for Sets instead. However, Array works fine and is simpler. **Keep.** |
| `vars.dup # Pragma: hash` | B | Pragma needed - Hash.dup differs from Array.dup. **Keep.** |
| `@need_truthy_helpers` from Set to Array | C | Same as JS_RESERVED. Array works fine. **Keep.** |
| `Hash[...] # Pragma: entries` | B | Pragma needed for hash iteration. **Keep.** |
| `.keys()` with explicit parens | C | Needed because `.keys` without parens becomes property access. **Keep.** |
| `.pop()` with explicit parens | C | Same reason. **Keep.** |
| `s()` method conditional on RUBY2JS_SELFHOST | C | Returns Ruby2JS::Node in selfhost mode. **Keep** - necessary for JS runtime. |
| `comments()` nil checks | A | Better null safety. **Keep.** |
| `@comments.include?(key) # Pragma: hash` | B | Pragma needed - Hash.include? vs Array.include?. **Keep.** |
| `find_comment_entry` SELFHOST skip block | C | Complex location-based lookup skipped in selfhost. **Keep** - reasonable optimization. |
| `ast_node?()` helper method | A | **Good generalization.** Safe way to check if something is an AST node. Benefits everyone. **Keep.** |
| `handler.call(*ast.children) # Pragma: method` | B | Pragma needed - proc.call() in JS needs direct invocation. **Keep.** |
| `last_arg = args[-1] # Pragma: method` | B | Pragma needed. **Keep.** |
| `SELFHOST skip` for Parser::AST::Node extension | C | Parser gem specific code. **Keep.** |

**Summary:** converter.rb changes are well-justified. Most are pragmas (Category B) or necessary selfhost accommodations (Category C).

---

### logical.rb (64 lines changed)

| Change | Category | Assessment |
|--------|----------|------------|
| `Converter::LOGICAL` instead of `LOGICAL` | C | Explicit module reference for JS. **Keep.** |
| `Converter::INVERT_OP` instead of `INVERT_OP` | C | Same. **Keep.** |
| Chained `||` handling (left.type != :or) | A | **Bug fix for issue #264.** Prevents mixing `??` and `||` in chained expressions. Benefits everyone. **Keep.** |
| Handle nil left in `:nullish` handler | A | **Bug fix.** Handles `nil.to_s` with `nullish_to_s` option. **Keep.** |
| `Converter::OPERATORS` reference | C | Explicit module reference. **Keep.** |
| `:in?` node check in rewrite | A | **Bug fix.** Skip `:in?` nodes in optional chaining rewrite. **Keep.** |

**Summary:** Mostly bug fixes that benefit everyone, plus JS-compatible constant references.

---

### logical_or.rb (58 lines - NEW FILE)

| Change | Category | Assessment |
|--------|----------|------------|
| New `:logical_or` handler | B | Created for `# Pragma: logical` and `# Pragma: ||`. **Keep.** |
| New `:logical_asgn` handler | B | Created for `||=` with logical pragma. **Keep.** |

**Summary:** New file implementing pragma support. Necessary and well-designed.

---

### kwbegin.rb (43 lines changed)

| Change | Category | Assessment |
|--------|----------|------------|
| `exception_vars` from `.map.compact.uniq` to explicit loop | C | JS Array methods differ. **Keep.** |
| Lambda to proc with `# Pragma: method` | B | Pragmas for `.call()` invocation. **Keep.** |
| `self.ast_node?()` instead of `respond_to?` checks | A | Uses new helper. **Keep.** |
| `.any?` to `.length > 0` | C | `.any?` without block doesn't exist in JS. **Keep.** |
| `exception == s(:const, nil, :String)` to element comparison | D | Array comparison fix. **Keep.** |
| Add `nil` initialization for procs before assignment | C | JS hoisting requirement. **Keep.** |

**Summary:** Mix of pragmas and JS compatibility. All justified.

---

### send.rb (50 lines changed)

| Change | Category | Assessment |
|--------|----------|------------|
| Remove local `ast` variable, use `@ast` | C | Avoids variable shadowing issues. **Keep.** |
| `receiver.children == [nil, :Class]` to element comparison | D | Array comparison fix. **Keep.** |
| `receiver.children == [nil, :Proc]` to element comparison | D | Same. **Keep.** |
| `|| nil # Pragma: logical` | B | Pragma for explicit nil fallback. **Keep.** |
| `GROUP_OPERATORS.include? # Pragma: logical` | B | Pragma. **Keep.** |
| `receiver == s(:const, nil, :Regexp)` to element comparison | D | Array comparison fix. **Keep.** |
| `.each_char` to `.split('')` | C | JS string iteration. **Could be filter.** But simple enough to keep. |
| `@vars.include?(:idx) # Pragma: hash` | B | Pragma for hash key check. **Keep.** |
| `self._compact` instead of `compact` | C | Method name collision with Array#compact. **Should be addressed** - see below. |

**Notable:** The `self._compact` change is a workaround for method name collision. The converter has a `compact` method that conflicts with Array#compact when the functions filter is active. This could be:
1. Renamed to `compact_output` in the converter (breaking change)
2. Handled by selfhost filter (current approach)
3. Excluded in selfhost filter config

**Recommendation:** Keep current approach but document the collision.

---

### class.rb (42 lines changed)

| Change | Category | Assessment |
|--------|----------|------------|
| `body.first.children.dup # Pragma: array` | B | Pragma for array dup. **Keep.** |
| Hash iteration with `# Pragma: entries` | B | Multiple pragmas. **Keep.** |

---

### class2.rb (16 lines changed)

| Change | Category | Assessment |
|--------|----------|------------|
| `walk.call(child) # Pragma: method` | B | Pragma for proc call. **Keep.** |
| `constructor.first.children.dup # Pragma: array` | B | Pragma. **Keep.** |
| `respond_to?(:type) && respond_to?(:children) # Pragma: method` | B | **Could use `ast_node?`** - see recommendation below. |

---

### def.rb (12 lines changed)

| Change | Category | Assessment |
|--------|----------|------------|
| `self.ast_node?(child)` | A | Uses new helper. **Keep.** |
| `walk.call # Pragma: method` | B | Pragma. **Keep.** |
| `args.children.dup # Pragma: array` | B | Pragma. **Keep.** |

---

### masgn.rb (16 lines changed)

| Change | Category | Assessment |
|--------|----------|------------|
| `@vars.include?(var_name) # Pragma: hash` | B | Multiple pragmas for hash key checks. **Keep.** |
| `walk.call # Pragma: method` | B | Pragmas for proc calls. **Keep.** |

---

### return.rb (8 lines changed)

| Change | Category | Assessment |
|--------|----------|------------|
| `statements.dup # Pragma: array` | B | Pragmas for array dup. **Keep.** |
| `block.first.children.dup # Pragma: array` | B | **Keep.** |
| `node.children.dup # Pragma: array` | B | **Keep.** |
| `children[i].children.dup # Pragma: array` | B | **Keep.** |

---

### vasgn.rb (8 lines changed)

| Change | Category | Assessment |
|--------|----------|------------|
| `@vars.include? name # Pragma: hash` | B | Multiple pragmas for hash key checks. **Keep.** |

---

### Other Files (Minor Changes)

| File | Lines | Changes |
|------|-------|---------|
| args.rb | 8 | Whitespace, minor fixes |
| array.rb | 2 | Minor |
| block.rb | 18 | `vars.dup # Pragma: hash`, proc initialization |
| dstr.rb | 4 | Empty interpolation handling |
| for.rb | 2 | Minor |
| hash.rb | 11 | Spacing, hash handling |
| if.rb | 2 | Minor |
| import.rb | 2 | Minor |
| ivar.rb | 10 | Spacing |
| module.rb | 8 | Minor |
| opasgn.rb | 5 | Minor |
| regexp.rb | 10 | Rest position handling |

---

## Recommendations

### 1. `ast_node?` and `respond_to?` Handling
The `ast_node?` helper in converter.rb uses `respond_to?` internally. The selfhost filter handles this in two ways:
1. **General transformation:** Any `respond_to?(:prop)` call becomes `typeof obj === 'object' && obj !== null && 'prop' in obj`
2. **Method-specific:** Methods like `ast_node?` and `hoist?` have their `respond_to?` calls transformed

This means inline `respond_to?` checks in converter code are also handled by the selfhost filter—no need to convert them all to use `ast_node?`.

**Action:** No change needed. The selfhost filter handles both patterns.

### 2. Document Method Name Collision
The `compact` → `_compact` rename is a known issue. Document it in:
- CLAUDE.md or a selfhost-specific doc
- User's Guide anti-patterns (if using `compact` as a method name)

**Action:** Add to documentation.

### 3. Consider Filter for Set Operations
`JS_RESERVED` and `@need_truthy_helpers` were changed from Set to Array. A filter could map Set.include? → Set.has() instead. However:
- Array works fine for these small collections
- The change is already done and tested
- No performance concern

**Action:** No change needed. Document as acceptable pattern.

### 4. Array Comparison Pattern
Multiple places changed from `x == s(:const, nil, :Foo)` to element-by-element comparison. This is correct because JavaScript `==` on arrays compares references, not contents.

**Action:** Document this pattern in User's Guide anti-patterns.

---

## Summary

| Category | Count | Action |
|----------|-------|--------|
| A: JS Compatibility (benefits all) | ~10 | Keep |
| B: Pragma-driven | ~45 | Keep |
| C: Selfhost-specific | ~15 | Keep (some could be filter) |
| D: Array comparison | ~6 | Keep |

**Overall Assessment:** The converter changes are well-justified and properly implemented. Most changes are either:
1. Bug fixes that benefit everyone
2. Pragma support (by design)
3. Necessary JS compatibility fixes

**No major refactoring needed.** The main opportunities are:
1. Consistent use of `ast_node?` helper (low priority)
2. Documentation updates (medium priority)
