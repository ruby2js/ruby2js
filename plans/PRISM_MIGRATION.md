# Prism Migration Plan

## Overview

Add Prism support to Ruby2JS while maintaining full backwards compatibility with older Ruby versions. Uses `Prism::Translation::Parser` as a compatibility layer, with automatic fallback to the whitequark `parser` gem when Prism is unavailable.

## Parser Selection

Ruby2JS auto-detects the best available parser:
- **Ruby 3.3+**: Uses Prism via `Prism::Translation::Parser`
- **Older Ruby**: Falls back to whitequark `parser` gem

Override with the `RUBY2JS_PARSER` environment variable:
- `RUBY2JS_PARSER=prism` - force Prism (requires Ruby 3.3+)
- `RUBY2JS_PARSER=parser` - force whitequark parser gem

## Approach: Translation Layer

When using Prism, `Prism::Translation::Parser` translates Prism's AST into the whitequark parser gem's AST format. This provides:

1. **Full compatibility** - Existing filters and converters work unchanged
2. **Backwards compatible** - Older Ruby versions continue to work
3. **Maintained by Ruby team** - Battle-tested translation logic
4. **Proper location info** - Source maps work correctly

```
Ruby Source
    ↓
Prism::Translation::Parser (Ruby 3.3+)
  or Parser::CurrentRuby (older Ruby)
    ↓
Parser::AST::Node
    ↓
Filters (unchanged)
    ↓
Converter (unchanged)
    ↓
JavaScript Output
```

## Implementation

### Core Changes

**lib/ruby2js.rb**
- Auto-detect parser based on Prism availability, with env var override
- Add `parse_with_prism()` and `parse_with_parser()` methods
- Add comment re-association after filtering (filters create new AST nodes, breaking identity-based comment lookup)
- Rewrite `Filter::Processor` to not inherit from `Parser::AST::Processor` (simpler, self-contained implementation)

**lib/ruby2js/converter.rb**
- Add `is_method?` extension to `Parser::AST::Node` (Prism sets this; needed to distinguish method calls from property access)
- Add `find_comment_entry()` helper with fallback lookup strategies for synthetic nodes
- Add `find_first_location()` to locate source positions in synthetic AST trees

### Edge Case Fixes

**lib/ruby2js/filter/node.rb**
- Add `on_str` handler: Prism converts `__FILE__` to `s(:str, filename)` instead of `s(:__FILE__)`

**lib/ruby2js/filter/jquery.rb**
- Add `:attr` node handling in `on_send` and `rewrite_tilda` for consecutive tildes (`~~value`)

**lib/ruby2js/converter/class.rb**
- Clear source comments after copying to constructor node (prevents duplicate output)

**lib/ruby2js/filter/vue.rb**
- Copy class-level comments to generated Vue definition

**lib/ruby2js/filter/require.rb**
- Fix comment hash merging for required files

## Test Results

Both parsers pass all tests:

- **1302 tests, 2486 assertions**
- **0 failures, 0 errors**

Tested with:
- `bundle exec rake test` (Prism, auto-detected)
- `RUBY2JS_PARSER=parser bundle exec rake test` (whitequark parser)

## Future Work

### Option A: Native Prism AST

Use Prism's AST directly without the translation layer.

**Challenges:**
- Prism AST has different node types and structure than whitequark parser
- All 60+ converter handlers would need updates
- All 23 filters would need updates
- The `s(:type, *children)` pattern used throughout would change
- Location API differs between the two ASTs
- Significant testing burden to ensure feature parity

**When to consider:**
- If Prism::Translation::Parser is deprecated
- If performance becomes critical (eliminates translation overhead)

### Option B: Fork Translation Layer

Copy `Prism::Translation::Parser` into Ruby2JS, simplify it, and remove the whitequark parser gem dependency.

**Benefits:**
- Full control over the code
- Can fix comment association at the source
- Can remove unused features (lexer tokens, diagnostics, version-specific parsers)
- Eliminates parser gem dependency (smaller footprint, Opal compatibility)

**What would be needed:**
- Vendor `compiler.rb` (~2000 lines) and `builder.rb` (~60 lines)
- Create minimal stubs for `Parser::AST::Node`, `Parser::Source::Buffer`, `Parser::Source::Comment`, `Parser::Source::Range`
- Potentially simplify the compiler to only emit node types Ruby2JS actually uses

**Why defer:**
- Translation layer is actively maintained by Ruby team
- Bug fixes and Ruby version updates come for free
- ~2500 lines of code to own and maintain
- Current solution works perfectly (0 test failures)
- Prism itself is still evolving

**When to consider:**
- When Ruby team announces deprecation of translation layer
- If maintenance clearly stalls
- If Opal/browser support becomes a priority

### Option C: Opal / Online Demo

The online demo at ruby2js.com runs in the browser using Opal (Ruby compiled to JavaScript). The current approach requires the parser gem for `Parser::Source::Buffer` and related classes.

**Options for browser support:**

1. **Self-hosting** - Transpile Ruby2JS itself to JavaScript, use `@prism-ruby/prism` npm module directly for parsing in the browser.

2. **ruby.wasm** - Replace Opal with ruby.wasm, which runs CRuby + Prism in WebAssembly.

3. **Defer** - Current Opal-based demo continues to work with the parser gem; no immediate action needed.

## Files Modified

- `lib/ruby2js.rb` - Prism integration, filter processor rewrite
- `lib/ruby2js/converter.rb` - Comment lookup helpers, `is_method?` extension
- `lib/ruby2js/converter/class.rb` - Fix comment duplication
- `lib/ruby2js/filter/node.rb` - Handle `__FILE__` from Prism
- `lib/ruby2js/filter/jquery.rb` - Fix `:attr` node handling
- `lib/ruby2js/filter/vue.rb` - Copy class-level comments
- `lib/ruby2js/filter/require.rb` - Fix comment merging
