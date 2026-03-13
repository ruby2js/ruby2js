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

| Directory                   | Purpose                                                    |
| --------------------------- | ---------------------------------------------------------- |
| `lib/ruby2js.rb`            | Entry point, `Ruby2JS.convert()` method                    |
| `lib/ruby2js/pipeline.rb`   | Transpilable orchestration (filter chain, converter setup) |
| `lib/ruby2js/converter.rb`  | Base converter class, AST → JavaScript                     |
| `lib/ruby2js/converter/`    | ~60 handlers for AST node types                            |
| `lib/ruby2js/filter.rb`     | Filter base class and registration                         |
| `lib/ruby2js/filter/`       | ~23 filters (functions, esm, react, etc.)                  |
| `lib/ruby2js/serializer.rb` | Output formatting                                          |
| `lib/ruby2js/namespace.rb`  | Scope/class tracking                                       |

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
```

### Demo Integration and System Tests

The `test/Rakefile` provides tasks for testing demo applications (blog, chat, notes, etc.):

```bash
# Integration tests (automated, uses vitest)
bundle exec rake -f test/Rakefile integration[blog]

# System tests (manual browser testing with Docker)
bundle exec rake -f test/Rakefile system[blog,sqlite,node]

# List available demos
bundle exec rake -f test/Rakefile list
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

Several CLI tools are available for debugging transpilation issues:

**Ruby CLI (`bin/ruby2js`)** - The main Ruby-based converter:
```bash
bin/ruby2js -e 'self.foo ||= 1'              # Basic conversion
bin/ruby2js --ast -e 'self.foo ||= 1'         # Show AST before filters
bin/ruby2js --filtered-ast -e 'self.foo ||= 1' # Show AST after filters
bin/ruby2js --filter functions -e 'puts "hello"' # Apply specific filters
```

**JavaScript CLI (`demo/selfhost/ruby2js-cli.js`)** - The self-hosted JS converter:
```bash
cd demo/selfhost
node ruby2js-cli.js -e 'self.foo ||= 1'       # Basic conversion
node ruby2js-cli.js --ast -e 'self.foo'        # Show AST (s-expression)
node ruby2js-cli.js --find=OrAssign -e 'x ||= 1' # Find Prism AST nodes
```

**Comparison Tool (`bin/compare`)** - Compare Ruby vs JS transpiler output:
```bash
bin/compare -e 'foo rescue nil'                # Side-by-side comparison
bin/compare --diff -e 'x ||= 1'               # Unified diff
```

## Documentation

The documentation source is in `docs/src/_docs/` and includes:

- **Reference docs** - Filter documentation, conversion details, options
- **[User's Guide](https://www.ruby2js.com/docs/users-guide/introduction)** - Patterns, pragmas, anti-patterns, dual-target and JS-only development

When trying to understand how a feature is intended to work, review the relevant documentation pages. Each page has live demos showing expected input/output.

## Specialized Reference Files

These files contain detailed guidance for specific subsystems. Read them when working in those areas:

- **[SELFHOST.md](./SELFHOST.md)** - Building, testing, and debugging the selfhost transpiler (`demo/selfhost/`)
- **[METADATA.md](./METADATA.md)** - Cross-file metadata pipeline: how Rails filters share type info between controllers, models, and views
- **[VISION.md](./VISION.md)** - Design principles: use existing infrastructure, fix bugs before pivoting, preserve deployment optionality
