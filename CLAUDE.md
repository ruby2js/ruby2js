# CLAUDE.md

This file provides guidance to Claude Code when working with the Ruby2JS codebase.

## Project Overview

Ruby2JS is a Ruby to JavaScript transpiler. It parses Ruby source code and generates equivalent JavaScript, with configurable output for different ES levels (ES2020 through ES2025) and optional filters for framework-specific transformations.

**Website:** https://www.ruby2js.com/
**Documentation:** https://www.ruby2js.com/docs/

## Architecture

```
Ruby Source
    ↓
Parser (Prism or whitequark/parser gem)
    ↓
Ruby AST (Parser::AST::Node format)
    ↓
Filters (optional AST transformations)
    ↓
Converter (AST → JavaScript)
    ↓
Serializer (formatting, indentation)
    ↓
JavaScript Output
```

### Parser Selection

Ruby2JS supports two parsers:
- **Prism** (Ruby 3.4+) - Auto-detected when available
- **Translation** (Ruby 3.3), uses `Prism::Translation::Parser` for AST compatibility
- **whitequark/parser gem** - Fallback for older Ruby versions and Opal

Override with environment variable: `RUBY2JS_PARSER=prism` or `RUBY2JS_PARSER=parser` or `RUBY2JS_PARSER=translation`

### Key Components

| Directory | Purpose |
|-----------|---------|
| `lib/ruby2js.rb` | Entry point, `Ruby2JS.convert()` method |
| `lib/ruby2js/pipeline.rb` | Transpilable orchestration (filter chain, converter setup) |
| `lib/ruby2js/converter.rb` | Base converter class, AST → JavaScript |
| `lib/ruby2js/converter/` | ~60 handlers for AST node types |
| `lib/ruby2js/filter.rb` | Filter base class and registration |
| `lib/ruby2js/filter/` | ~23 filters (functions, esm, react, etc.) |
| `lib/ruby2js/serializer.rb` | Output formatting |
| `lib/ruby2js/namespace.rb` | Scope/class tracking |

### Converter Handlers

Each Ruby AST node type has a handler in `lib/ruby2js/converter/`:

- `send.rb` - Method calls, operators
- `class.rb`, `class2.rb` - Class definitions
- `def.rb` - Method definitions
- `if.rb`, `case.rb`, `while.rb` - Control flow
- `hash.rb`, `array.rb` - Data structures
- `arg.rb` - Arguments and parameters
- etc.

Handlers are defined with `handle :node_type do |*args| ... end`.

### Filters

Filters transform the AST before conversion. Key filters:

- `functions` - Maps Ruby methods to JS equivalents (`.select` → `.filter`, etc.)
- `esm` - ES6 module imports/exports
- `camelCase` - Convert snake_case to camelCase
- `react` - React/JSX support
- `stimulus` - Stimulus controller patterns

## Running Tests

```bash
# Run full test suite
bundle exec rake test

# Run specific spec file
bundle exec rake spec SPEC=spec/converter_spec.rb

# Run with specific Ruby version
RUBY_VERSION=3.3 bundle exec rake test
```

## Common Development Tasks

### Adding a New Handler

1. Create or edit file in `lib/ruby2js/converter/`
2. Use `handle :node_type do |*args| ... end`
3. Add tests in `spec/`
4. Update docs in `docs/src/_docs/` if the change affects user-facing behavior

### Adding to a Filter

1. Edit the filter in `lib/ruby2js/filter/`
2. Add handling in `on_send` or `on_block` methods
3. Add tests
4. Update the filter's documentation page in `docs/src/_docs/filters/`

### Fixing Bugs

When fixing significant bugs in `lib/ruby2js/converter/` or `lib/ruby2js/filter/`:

1. Add a test case that reproduces the bug
2. Fix the bug
3. Verify the test passes
4. Update documentation if the fix changes expected behavior

### Debugging AST

```ruby
require 'ruby2js'
ast, _ = Ruby2JS.parse('your_ruby_code')
puts ast.to_sexp
```

### Debugging Tools

Two CLI tools are available for debugging transpilation issues:

**Ruby CLI (`bin/ruby2js`)** - The main Ruby-based converter:
```bash
# Basic conversion
bin/ruby2js -e 'self.foo ||= 1'

# Show AST before filters
bin/ruby2js --ast -e 'self.foo ||= 1'

# Show AST after filters (what converter sees)
bin/ruby2js --filtered-ast -e 'self.foo ||= 1'

# Apply specific filters
bin/ruby2js --filter functions --filter esm -e 'puts "hello"'
```

**JavaScript CLI (`demo/selfhost/ruby2js.mjs`)** - The self-hosted JS converter:
```bash
cd demo/selfhost

# Basic conversion (inline code or stdin)
node ruby2js.mjs -e 'self.foo ||= 1'
echo 'self.foo ||= 1' | node ruby2js.mjs

# Show AST (s-expression format, like Ruby CLI)
node ruby2js.mjs --ast -e 'self.foo'

# Show raw Prism AST (JavaScript objects)
node ruby2js.mjs --prism-ast -e 'self.foo'

# Find nodes matching a pattern in Prism AST
node ruby2js.mjs --find=OrAssign -e 'self.foo ||= 1'

# Inspect specific property paths
node ruby2js.mjs --inspect=root.statements.body[0] -e 'self.foo ||= 1'

# ES level and comparison options (aligned with Ruby CLI)
node ruby2js.mjs --es2022 --identity -e 'x == y'
```

These tools help debug differences between Ruby and JS converters, especially for self-hosting work.

## Documentation

The documentation source is in `docs/src/_docs/` and includes:

- **Reference docs** - Filter documentation, conversion details, options
- **[User's Guide](https://www.ruby2js.com/docs/users-guide/introduction)** - Patterns, pragmas, anti-patterns, dual-target and JS-only development

When trying to understand how a feature is intended to work, review the relevant documentation pages. Each page has live demos showing expected input/output.

## Online Demo

Two demos are available at ruby2js.com:

- **[Opal-based demo](https://www.ruby2js.com/demo/)** - Full filter support, uses Opal (Ruby compiled to JavaScript), ~5MB
- **[Self-hosted demo](https://www.ruby2js.com/demo/selfhost/)** - Basic transliteration, uses transpiled Ruby2JS, ~200KB + Prism WASM

The demo code is in `docs/src/demo/`. The self-hosted version uses the unified `ruby2js.mjs` bundle from `demo/selfhost/`.

## Selfhost Testing

The selfhost project (`demo/selfhost/`) transpiles Ruby2JS itself to JavaScript, enabling the converter to run in browsers. Ruby specs are also transpiled and run against the JS converter.

### Spec Manifest Categories

The `demo/selfhost/spec_manifest.json` tracks which specs work with the selfhost converter:

- **ready**: Specs that must pass (CI fails if they don't)
- **partial**: Specs being worked on (failures are informational)
- **blocked**: Specs waiting on dependencies (e.g., filters not yet transpiled)

### Running Selfhost Tests

```bash
cd demo/selfhost

# Run all specs
node run_all_specs.mjs

# Run with failure details for partial specs
node run_all_specs.mjs --verbose

# Run only ready specs (for CI)
node run_all_specs.mjs --ready-only

# Run only partial specs (for development)
node run_all_specs.mjs --partial-only

# Skip transpilation (use pre-built files)
node run_all_specs.mjs --skip-transpile
```

### Debugging a Specific Spec

To debug a failing spec with full details:

```bash
cd demo/selfhost

# Rebuild everything
npm run build

# Transpile just one spec
bundle exec ruby scripts/transpile_spec.rb ../../spec/serializer_spec.rb > dist/serializer_spec.mjs

# Run it directly to see all failures
node -e "
import('./test_harness.mjs').then(async h => {
  await h.initPrism();
  await import('./dist/serializer_spec.mjs');
  h.runTests();
});
"
```

### Common Failure Patterns

1. **Transpilation bug**: The Ruby-to-JS conversion produces incorrect code
   - Check `lib/ruby2js/filter/` for filter issues
   - Check `lib/ruby2js/converter/` for conversion issues
   - Use `bin/ruby2js --ast` vs `--filtered-ast` to see where transformation happens

2. **Missing polyfill**: A Ruby method has no JS equivalent in the test harness
   - Add to `demo/selfhost/test_harness.mjs`

3. **Runtime incompatibility**: Code works in Ruby but not in JS
   - Fix in source Ruby file (`lib/ruby2js/*.rb`) with dual-compatible code
   - Example: `arg.is_a?(Range)` won't work in JS; use `arg.respond_to?(:begin)` instead

### Promoting Specs

When a partial spec passes all tests:
1. Move it from `partial` to `ready` in `spec_manifest.json`
2. Commit and push - CI will now enforce it passes

### Debugging Selfhost Transpilation Failures

When a selfhost test fails, follow this methodology to diagnose and fix:

**Important: Never edit generated files.** In the selfhost directory, files ending in `.js` are typically generated outputs (e.g., `ruby2js.js`, `filters/phlex.js`). If a `.js` file needs fixing, make the change to the original source instead:
- Ruby source files in `lib/ruby2js/` (for dual-compatible code changes)
- Converter handlers in `lib/ruby2js/converter/` (for AST-to-JS conversion fixes)
- Filters in `lib/ruby2js/filter/` (for AST transformation fixes)

If a pattern is common, fixing the transpiler is preferred over changing individual source files.

#### 1. Identify the Problem in Transpiled Output

Look at the failing test and find the transpiled JavaScript that behaves differently from Ruby:

```bash
# Rebuild and run tests to see failures
cd demo/selfhost
npm run build
node run_all_specs.mjs --verbose
```

#### 2. Isolate to a Single Source File

Create a minimal reproduction by transpiling just the problematic code:

```bash
# Transpile a minimal example through the selfhost filter
bin/ruby2js --filter selfhost -e '
class Processor
  def on_send(node)
    return on_block(node)  # Bug: produces on_block() not this.on_block()
  end
end
'
```

#### 3. Examine the AST

Use `--filtered-ast` to see what the converter receives:

```bash
bin/ruby2js --filter selfhost --filtered-ast -e 'return on_block(node)'
```

Look for the root cause. Example: `s(:send, nil, :on_block, ...)` - the `nil` receiver means no `this.` prefix in JavaScript.

#### 4. Identify Potential Solutions

There are typically multiple ways to fix a transpilation issue:

| Approach | When to Use |
|----------|-------------|
| **Change Ruby source** | Problem is isolated (few occurrences), fix is simple (e.g., add explicit `self.`) |
| **Change selfhost filter** | Problem is pervasive, pattern is predictable, worth automating |
| **Change core Ruby2JS filter** | Problem affects all users, not just selfhost |

#### 5. Assess Pervasiveness

Before choosing an approach, check how widespread the problem is:

```bash
# Find all occurrences of the pattern
grep -rn "return on_" lib/ruby2js/filter/*.rb | grep -v "self\."
```

If only a few occurrences exist, prefer changing the Ruby source. If dozens exist with a consistent pattern, consider a filter-based solution.

#### 6. Example: Implicit Self Method Calls

**Problem:** Ruby allows `on_block(...)` to implicitly call `self.on_block(...)`, but JavaScript requires explicit `this.`.

**Diagnosis:**
```bash
# Shows: on_block(...) instead of this.on_block(...)
bin/ruby2js --filter selfhost -e 'def foo; on_block(x); end'

# AST shows nil receiver
bin/ruby2js --filter selfhost --filtered-ast -e 'def foo; on_block(x); end'
# => s(:send, nil, :on_block, ...)  # nil = no receiver
```

**Solution options:**
1. **Change Ruby source** - Add explicit `self.on_block(...)` (chosen: only 9 occurrences)
2. **Change selfhost filter** - Detect `on_*` calls inside filter classes and add `s(:self)` receiver (not chosen: overkill for 9 cases)

**Assessment:** Grep found only 9 implicit `on_*` calls across all filter files. The simpler fix of adding `self.` to those 9 lines was preferred over building filter logic to handle this automatically.

#### 7. Verify the Fix

After making changes, verify with the same minimal reproduction:

```bash
# Should now show this.on_block(...)
bin/ruby2js --filter selfhost -e '
class Processor
  def on_send(node)
    return self.on_block(node)
  end
end
'
```

Then rebuild and run the full test suite to confirm the fix resolves the original failure.
