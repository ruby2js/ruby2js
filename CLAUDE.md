# CLAUDE.md

This file provides guidance to Claude Code when working with the Ruby2JS codebase.

## Project Overview

Ruby2JS is a Ruby to JavaScript transpiler. It parses Ruby source code and generates equivalent JavaScript, with configurable output for different ES levels (ES5 through ES2022) and optional filters for framework-specific transformations.

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
- **Prism** (Ruby 3.3+) - Auto-detected when available, uses `Prism::Translation::Parser` for AST compatibility
- **whitequark/parser gem** - Fallback for older Ruby versions

Override with environment variable: `RUBY2JS_PARSER=prism` or `RUBY2JS_PARSER=parser`

### Key Components

| Directory | Purpose |
|-----------|---------|
| `lib/ruby2js.rb` | Entry point, `Ruby2JS.convert()` method |
| `lib/ruby2js/converter.rb` | Base converter class, orchestration |
| `lib/ruby2js/converter/` | ~60 handlers for AST node types |
| `lib/ruby2js/filter.rb` | Filter base class and registration |
| `lib/ruby2js/filter/` | ~23 filters (functions, esm, react, etc.) |
| `lib/ruby2js/serializer.rb` | Output formatting |
| `lib/ruby2js/namespace.rb` | Scope/class tracking |

### Converter Handlers

Each Ruby AST node type has a handler in `lib/ruby2js/converter/`:

- `send.rb` - Method calls, operators
- `class.rb`, `class2.rb` - Class definitions (ES5 and ES2015+)
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

### Adding to a Filter

1. Edit the filter in `lib/ruby2js/filter/`
2. Add handling in `on_send` or `on_block` methods
3. Add tests

### Debugging AST

```ruby
require 'ruby2js'
ast, _ = Ruby2JS.parse('your_ruby_code')
puts ast.to_sexp
```

## Online Demo

The ruby2js.com demo runs in the browser using Opal (Ruby compiled to JavaScript). The demo code is in `docs/src/demo/`.

## Plans

See `plans/` directory for future work:
- `PRISM_MIGRATION.md` - Prism parser integration (complete)
- `ECMASCRIPT_UPDATES.md` - ES2023/2024/2025 feature support
- `RUBY_FEATURE_GAPS.md` - Missing Ruby language features
- `SELF_HOSTING.md` - Transpiling Ruby2JS to JavaScript for browser use
