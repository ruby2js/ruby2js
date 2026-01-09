# Ink CLI Target Plan

Transpile Ruby components to Ink (React for CLIs), enabling terminal applications with the same developer experience as web apps.

## Vision

Write Ruby components that render to terminal UIs:

```ruby
class QueryRepl < Ink::Component
  keys return: :execute,
       up: :history_back,
       ctrl_c: :quit

  def initialize
    @query = ""
    @results = []
    @history = []
  end

  def view_template
    Box(flexDirection: "column", padding: 1) do
      Text(bold: true, color: "green") { "ruby2js console" }

      Box(borderStyle: "round", paddingX: 1) do
        Text { "> " }
        TextInput(value: @query, onChange: ->(v) { @query = v })
      end

      if @results.any?
        Box(marginTop: 1) do
          ResultsTable(data: @results)
        end
      end
    end
  end
end
```

Transpiles to React/Ink JavaScript, runs in Node.js terminal.

## Strategic Goals

| Goal | Rationale |
|------|-----------|
| Direct Ink vocabulary | Developers learn Ink's actual API, not a translation layer |
| Ruby DSL first | Easier implementation, validates approach |
| JSX syntax later | Broader appeal to React/JS developers |
| Query REPL demo | Compelling use case that showcases real utility |
| Path to `juntos console` | Becomes a standard tool for Juntos projects |

## Architecture

### Filter Design

New `:ink` filter with base class detection, parallel to Phlex:

```
┌─────────────────────────────────────────────────────────────┐
│                     Ruby Source                             │
├─────────────────────────────────────────────────────────────┤
│  class MyView < Phlex::HTML    class MyPane < Ink::Component│
│    def view_template             def view_template          │
│      div { "hello" }               Box { Text { "hi" } }    │
│    end                           end                        │
│  end                           end                          │
└──────────────┬─────────────────────────────┬────────────────┘
               │                             │
        :phlex filter                  :ink filter
               │                             │
               ▼                             ▼
┌──────────────────────────┐   ┌──────────────────────────────┐
│  HTML strings or         │   │  React.createElement(Box,    │
│  React.createElement     │   │    null,                     │
│    ("div", ...)          │   │    React.createElement(Text, │
└──────────────────────────┘   │      null, "hi"))            │
                               └──────────────────────────────┘
```

### Why Not Reuse Phlex Filter

| Aspect | Phlex | Ink |
|--------|-------|-----|
| Elements | HTML (`div`, `span`, `h1`) | Ink (`Box`, `Text`, `Spacer`) |
| Output modes | Strings or React DOM | React Ink only |
| Attributes | HTML attrs (`class`, `data-*`) | React props (`flexDirection`, `borderStyle`) |
| Text handling | Implicit in elements | Must be wrapped in `<Text>` |

The vocabularies are different enough that a separate filter is cleaner than conditional logic.

### Component Model

```ruby
class MyComponent < Ink::Component
  # Declarative key bindings
  keys return: :submit,
       up: :previous,
       down: :next,
       "q" => :quit

  # Instance variables become props/state
  def initialize(title:)
    @title = title
    @selected = 0
  end

  # View template using Ink elements
  def view_template
    Box(flexDirection: "column") do
      Text(bold: true) { @title }
      yield if block_given?  # children
    end
  end

  # Key handlers
  def submit
    # Called when return pressed
  end

  def quit
    exit_app
  end
end
```

### Key Bindings

Declarative, component-scoped (not global routes):

```ruby
class ModelList < Ink::Component
  keys up: :select_previous,
       down: :select_next,
       return: :load_model

  # "up" means "select previous" when this component is focused
end

class QueryInput < Ink::Component
  keys up: :history_back,
       down: :history_forward,
       return: :execute

  # "up" means "history back" when this component is focused
end
```

This matches Ink's component focus model where `useInput` is scoped to focused components.

**Transpiled output:**

```javascript
import { useInput } from 'ink';

function ModelList({ models, onSelect }) {
  const [selected, setSelected] = useState(0);

  useInput((input, key) => {
    if (key.upArrow) selectPrevious();
    if (key.downArrow) selectNext();
    if (key.return) loadModel();
  });

  // ...
}
```

## Ink Elements

### Core Elements (Built into Ink)

| Element | Purpose | Key Props |
|---------|---------|-----------|
| `Box` | Flexbox container | `flexDirection`, `padding`, `margin`, `borderStyle` |
| `Text` | Text with styling | `color`, `bold`, `italic`, `underline`, `dimColor` |
| `Newline` | Line break | `count` |
| `Spacer` | Flexible space | (none) |
| `Static` | Non-rerendering content | `items` |
| `Transform` | Text transformation | `transform` (function) |

### Ecosystem Packages

| Package | Element | Purpose |
|---------|---------|---------|
| `ink-text-input` | `TextInput` | Editable text field |
| `ink-select-input` | `SelectInput` | Selection list |
| `ink-spinner` | `Spinner` | Loading indicator |
| `ink-table` | `Table` | Data tables |
| `ink-link` | `Link` | Clickable links (terminal support varies) |

### Hooks (Mapped to Ruby)

| Ink Hook | Ruby Equivalent |
|----------|-----------------|
| `useInput` | `keys` declaration + handler methods |
| `useApp` | `exit_app` method |
| `useFocus` | Automatic for components with `keys` |
| `useState` | Instance variables |

## Demo: Database Explorer (Query REPL)

### Phase 1: Minimal REPL

```
┌─────────────────────────────────────────────────┐
│ ruby2js console                                 │
├─────────────────────────────────────────────────┤
│ > Post.all                                      │
│                                                 │
│ ┌─────┬──────────────────┬─────────┐            │
│ │ id  │ title            │ author  │            │
│ ├─────┼──────────────────┼─────────┤            │
│ │ 1   │ Getting Started  │ alice   │            │
│ │ 2   │ Advanced Tips    │ bob     │            │
│ └─────┴──────────────────┴─────────┘            │
│                                                 │
│ > _                                             │
└─────────────────────────────────────────────────┘
```

**Components:**

```ruby
# app/components/app.rb
class App < Ink::Component
  def initialize
    @query = ""
    @results = nil
    @error = nil
  end

  def view_template
    Box(flexDirection: "column", padding: 1) do
      render Header.new
      render QueryInput.new(
        value: @query,
        on_change: ->(v) { @query = v },
        on_submit: ->{ execute_query }
      )

      if @error
        render ErrorDisplay.new(message: @error)
      elsif @results
        render ResultsTable.new(data: @results)
      end
    end
  end

  def execute_query
    @results = eval_query(@query)
    @error = nil
  rescue => e
    @error = e.message
    @results = nil
  end
end
```

```ruby
# app/components/query_input.rb
class QueryInput < Ink::Component
  keys return: :submit

  def initialize(value:, on_change:, on_submit:)
    @value = value
    @on_change = on_change
    @on_submit = on_submit
  end

  def view_template
    Box(borderStyle: "round", paddingX: 1) do
      Text(color: "green") { "> " }
      TextInput(value: @value, onChange: @on_change)
    end
  end

  def submit
    @on_submit.call
  end
end
```

```ruby
# app/components/results_table.rb
class ResultsTable < Ink::Component
  def initialize(data:)
    @data = data
  end

  def view_template
    return if @data.empty?

    Box(flexDirection: "column", marginTop: 1) do
      # Header row
      Box do
        columns.each do |col|
          Box(width: col[:width], paddingX: 1) do
            Text(bold: true) { col[:name] }
          end
        end
      end

      # Data rows
      @data.each do |row|
        Box do
          columns.each do |col|
            Box(width: col[:width], paddingX: 1) do
              Text { row[col[:key]].to_s }
            end
          end
        end
      end
    end
  end

  def columns
    return [] if @data.empty?
    @data.first.keys.map do |key|
      { name: key.to_s, key: key, width: 20 }
    end
  end
end
```

**Features:**
- Text input for queries
- Execute on Enter
- Table display for results
- Error display
- Quit with Ctrl+C

### Phase 2: Enhanced Navigation

```
┌─ Models ────────┬─ Query ─────────────────────────┐
│ ▸ Post (15)     │ > Post.where(published: true)   │
│   User (8)      ├─────────────────────────────────┤
│   Comment (47)  │ id │ title           │ published│
│                 │  1 │ Getting Started │ true     │
│                 │  3 │ Advanced Tips   │ true     │
└─────────────────┴─────────────────────────────────┘
```

**Adds:**
- Model sidebar (from schema)
- Tab between panes
- Arrow keys navigate model list
- Select model → auto-populates `Model.all`
- Command history (↑/↓ in query input)

```ruby
# app/components/app.rb (Phase 2)
class App < Ink::Component
  keys tab: :toggle_focus

  def initialize
    @focus = :query  # :models or :query
    @models = Schema.models
    @selected_model = 0
    @query = ""
    @history = []
    @history_index = -1
    @results = nil
  end

  def view_template
    Box(flexDirection: "row", padding: 1) do
      render ModelList.new(
        models: @models,
        selected: @selected_model,
        focused: @focus == :models,
        on_select: ->(m) { load_model(m) }
      )

      Box(flexDirection: "column", flexGrow: 1) do
        render QueryInput.new(
          value: @query,
          focused: @focus == :query,
          on_change: ->(v) { @query = v },
          on_submit: ->{ execute_query },
          on_history_back: ->{ history_back },
          on_history_forward: ->{ history_forward }
        )
        render ResultsPane.new(data: @results)
      end
    end
  end

  def toggle_focus
    @focus = @focus == :models ? :query : :models
  end

  def load_model(model)
    @query = "#{model.name}.all"
    @focus = :query
  end
end
```

**Features:**
- Two-pane layout
- Tab switches focus
- Model list with keyboard nav
- Query history

### Phase 3: Full Explorer

```
┌─ Models ────────┬─ Query ─────────────────────────┐
│ ▸ Post (15)     │ > Post.find(1)                  │
│   User (8)      ├─ Result ────────────────────────┤
│   Comment (47)  │ Post #1                         │
│                 │ ├─ title: "Getting Started"     │
│                 │ ├─ body: "Welcome to..."        │
│                 │ ├─ author: "alice"              │
│                 │ ├─ published: true              │
│                 │ └─ created_at: 2024-01-15       │
│                 ├─────────────────────────────────┤
│ [e]dit [d]elete │ [n]ew  [q]uit                   │
└─────────────────┴─────────────────────────────────┘
```

**Adds:**
- Detail view for single records
- CRUD operations
- Keyboard shortcuts shown in footer
- Confirmation prompts for destructive actions
- Record editing with form

## Syntax Phase 2: INKX (JSX-like)

After Ruby DSL is working, add ERB-like JSX syntax for broader appeal:

```erb
<%# app/components/query_input.inkx %>
<% keys return: :submit %>

<Box borderStyle="round" paddingX={1}>
  <Text color="green">&gt; </Text>
  <TextInput value={@value} onChange={@on_change} />
</Box>
```

### Parser Requirements

1. Parse JSX elements (`<Box>`, `<Text>`)
2. Handle ERB-style Ruby (`<% %>`, `<%= %>`)
3. Handle JSX expressions (`{@value}`, `{1 + 1}`)
4. Output same AST as Ruby DSL

### File Convention

```
app/components/
├── app.rb              # Ruby DSL
├── query_input.inkx    # INKX syntax
└── results_table.rb    # Ruby DSL

# Both compile to same output format
```

## Project Structure

### Demo Repository

```
ink-db-explorer/
├── app/
│   ├── components/
│   │   ├── app.rb
│   │   ├── header.rb
│   │   ├── model_list.rb
│   │   ├── query_input.rb
│   │   ├── results_table.rb
│   │   └── error_display.rb
│   └── models/
│       └── (loaded from target project)
├── lib/
│   ├── ink_runtime.mjs       # Base classes, hooks
│   ├── active_record.mjs     # Database adapter
│   └── query_evaluator.mjs   # Safe query parsing
├── config/
│   └── database.yml
├── dist/                     # Transpiled output
├── bin/
│   └── console               # Entry point
├── scripts/
│   └── build.rb              # Transpilation
└── package.json
```

### Entry Point

```javascript
#!/usr/bin/env node
// bin/console

import { render } from 'ink';
import React from 'react';
import { App } from '../dist/components/app.js';
import { initDatabase } from '../dist/lib/active_record.mjs';
import { loadModels } from '../dist/lib/model_loader.mjs';

async function main() {
  await initDatabase();
  await loadModels();

  render(React.createElement(App));
}

main().catch(console.error);
```

### Package Dependencies

```json
{
  "name": "ink-db-explorer",
  "type": "module",
  "bin": {
    "console": "./bin/console"
  },
  "dependencies": {
    "ink": "^4.0.0",
    "ink-text-input": "^5.0.0",
    "react": "^18.0.0",
    "better-sqlite3": "^9.0.0"
  },
  "devDependencies": {
    "ruby2js": "^5.x.x"
  }
}
```

## Filter Implementation

### lib/ruby2js/filter/ink.rb

```ruby
require 'ruby2js'

module Ruby2JS
  module Filter
    module Ink
      include SEXP

      INK_ELEMENTS = %i[
        Box Text Newline Spacer Static Transform
        TextInput SelectInput Spinner
      ]

      def initialize(*args)
        super
        @ink_class = false
        @ink_ivars = Set.new
        @ink_keys = nil
      end

      # Detect Ink::Component inheritance
      def on_class(node)
        name, parent, *body = node.children

        if ink_component?(parent)
          process_ink_class(node)
        else
          super
        end
      end

      # Handle `keys` declaration
      def on_send(node)
        target, method, *args = node.children

        if @ink_class && target.nil? && method == :keys
          @ink_keys = extract_key_bindings(args.first)
          return nil  # Remove from AST, handled separately
        end

        if @ink_class && ink_element?(method)
          process_ink_element(node)
        else
          super
        end
      end

      # Handle Ink element with block (children)
      def on_block(node)
        send_node = node.children.first
        return super unless send_node.type == :send

        target, method, *args = send_node.children

        if @ink_class && ink_element?(method)
          process_ink_element_with_children(node)
        else
          super
        end
      end

      private

      def ink_component?(parent)
        # Match Ink::Component
        parent == s(:const, s(:const, nil, :Ink), :Component)
      end

      def ink_element?(name)
        INK_ELEMENTS.include?(name)
      end

      def process_ink_class(node)
        @ink_class = true
        name, parent, *body = node.children

        # Collect instance variables
        collect_ivars(node)

        # Transform to functional component with hooks
        # ... implementation details
      end

      def process_ink_element(node)
        target, method, *args = node.children
        props = args.first || s(:hash)

        # React.createElement(Ink.Box, props)
        s(:send,
          s(:const, nil, :React),
          :createElement,
          s(:send, s(:const, nil, :Ink), method),
          process(props))
      end

      def process_ink_element_with_children(node)
        send_node, args, *body = node.children
        target, method, *call_args = send_node.children
        props = call_args.first || s(:hash)

        children = body.map { |child| process(child) }

        # React.createElement(Ink.Box, props, ...children)
        s(:send,
          s(:const, nil, :React),
          :createElement,
          s(:send, s(:const, nil, :Ink), method),
          process(props),
          *children)
      end

      def extract_key_bindings(hash_node)
        return {} unless hash_node&.type == :hash

        bindings = {}
        hash_node.children.each do |pair|
          key, value = pair.children
          key_name = key.children.first
          handler = value.children.first
          bindings[key_name] = handler
        end
        bindings
      end

      def generate_use_input(keys)
        return nil if keys.nil? || keys.empty?

        # Generate useInput hook call
        # useInput((input, key) => { ... })
        # ... implementation details
      end
    end

    DEFAULTS.push Ink
  end
end
```

### Key Binding Transpilation

```ruby
# Input
class MyComponent < Ink::Component
  keys return: :submit,
       up: :history_back,
       "q" => :quit
end

# Output
import { useInput } from 'ink';

function MyComponent(props) {
  useInput((input, key) => {
    if (key.return) submit();
    if (key.upArrow) historyBack();
    if (input === "q") quit();
  });

  // ...
}
```

## Implementation Phases

### Phase 0: Infrastructure

| Task | Description | Estimate |
|------|-------------|----------|
| Create demo repo | `ink-db-explorer/` structure | 1 hour |
| Set up build script | Ruby2JS transpilation | 2 hours |
| Ink runtime | Base classes, imports | 2 hours |
| Entry point | `bin/console` that boots app | 1 hour |

### Phase 1: Ink Filter (Core)

| Task | Description | Estimate |
|------|-------------|----------|
| Base class detection | Detect `Ink::Component` | 1 hour |
| Element handling | Box, Text → React.createElement | 2 hours |
| Props handling | Ruby hash → JS props | 1 hour |
| Children handling | Blocks → children | 2 hours |
| Instance variables | @vars → state/props | 2 hours |

### Phase 2: Key Bindings

| Task | Description | Estimate |
|------|-------------|----------|
| `keys` DSL parsing | Extract key → handler mapping | 2 hours |
| useInput generation | Transpile to useInput hook | 3 hours |
| Focus handling | useFocus integration | 2 hours |

### Phase 3: Demo Phase 1 (Minimal REPL)

| Task | Description | Estimate |
|------|-------------|----------|
| App component | Main container | 1 hour |
| QueryInput | Text input with submit | 2 hours |
| ResultsTable | Table display | 2 hours |
| Query evaluator | Safe Ruby-like query parsing | 3 hours |
| Integration | Wire up, test | 2 hours |

### Phase 4: Demo Phase 2 (Enhanced)

| Task | Description | Estimate |
|------|-------------|----------|
| Model list | Sidebar with schema models | 2 hours |
| Two-pane layout | Flexbox layout | 1 hour |
| Focus management | Tab between panes | 2 hours |
| Command history | Up/down in query input | 2 hours |

### Phase 5: Demo Phase 3 (Full)

| Task | Description | Estimate |
|------|-------------|----------|
| Detail view | Single record display | 2 hours |
| CRUD operations | Create, edit, delete | 4 hours |
| Keyboard shortcuts | Footer with shortcuts | 1 hour |
| Confirmation prompts | Delete confirmation | 2 hours |

### Phase 6: INKX Syntax (Future)

| Task | Description | Estimate |
|------|-------------|----------|
| INKX parser | JSX + ERB parsing | 8 hours |
| AST generation | Same output as Ruby DSL | 4 hours |
| File handling | .inkx extension support | 2 hours |
| Documentation | Syntax guide | 2 hours |

## Milestones

| Milestone | Deliverable | Phases | Total Estimate |
|-----------|-------------|--------|----------------|
| **M1** | Ink filter handles basic components | 0, 1 | 12 hours |
| **M2** | Key bindings work | 2 | 7 hours |
| **M3** | Minimal REPL demo | 3 | 10 hours |
| **M4** | Enhanced navigation | 4 | 7 hours |
| **M5** | Full explorer | 5 | 9 hours |
| **M6** | INKX syntax | 6 | 16 hours |

**M1-M3 (Proof of Concept): ~29 hours**
**M1-M5 (Complete Demo): ~45 hours**
**M1-M6 (With INKX): ~61 hours**

## Success Criteria

### M1: Ink Filter
- [ ] `Ink::Component` base class detected
- [ ] Box, Text elements transpile correctly
- [ ] Props pass through
- [ ] Children render

### M2: Key Bindings
- [ ] `keys` DSL parses
- [ ] Transpiles to `useInput` hook
- [ ] Handlers called correctly

### M3: Minimal REPL
- [ ] App renders in terminal
- [ ] Query input accepts text
- [ ] Enter executes query
- [ ] Results display in table
- [ ] Errors display

### M4: Enhanced Navigation
- [ ] Two-pane layout works
- [ ] Tab switches focus
- [ ] Model list navigable
- [ ] History works

### M5: Full Explorer
- [ ] Single record detail view
- [ ] Create new records
- [ ] Edit existing records
- [ ] Delete with confirmation

### M6: INKX Syntax
- [ ] .inkx files parse
- [ ] JSX elements handled
- [ ] ERB interpolation works
- [ ] Same output as Ruby DSL

## Future Possibilities

### juntos console Integration

```bash
# In any Juntos project
bin/juntos console

# Auto-discovers models from app/models/
# Connects to database from config/database.yml
# Opens interactive REPL
```

### Additional Commands

```bash
bin/juntos console              # Query REPL
bin/juntos db:migrate           # Run migrations (interactive)
bin/juntos generate model Post  # Scaffold generator (interactive)
bin/juntos server               # Dev server dashboard
```

### Other Ink Applications

The `:ink` filter enables any terminal UI, not just database explorer:

- **Test runner dashboard** - Real-time test results
- **Deployment CLI** - Interactive deploy with logs
- **Log viewer** - Tail and filter logs
- **Git dashboard** - Status, staging, commits

## Query Execution

Since Ruby2JS self-hosts in Node.js, query execution is straightforward:

```javascript
// lib/query_evaluator.mjs
import { convert } from 'ruby2js';
import * as Models from './models/index.mjs';

async function evaluateQuery(rubyQuery) {
  // Transpile Ruby to JavaScript
  const jsCode = convert(rubyQuery, {
    filters: ['functions'],
    autoreturn: true
  });

  // Execute with models in scope
  const fn = new Function(...Object.keys(Models), `return (async () => ${jsCode})()`);
  return await fn(...Object.values(Models));
}

// Usage:
// evaluateQuery("Post.where(published: true).limit(5)")
// → Transpiles to: await Post.where({published: true}).limit(5)
// → Executes against actual database
```

No special query parser needed - Ruby2JS handles the transpilation.

## Configuration

Follows existing Juntos CLI conventions:

```bash
# Default: reads config/database.yml[development]
bin/juntos console

# Use production environment from database.yml
bin/juntos console -e production

# Override adapter (e.g., use SQLite instead of configured adapter)
bin/juntos console -d sqlite

# Combined: production environment with specific adapter
bin/juntos console -e production -d pg
```

**Options:**

| Option | Description |
|--------|-------------|
| `-d, --database ADAPTER` | Database adapter (overrides database.yml) |
| `-e, --environment ENV` | Rails environment (default: development) |
| `-v, --verbose` | Show detailed output |
| `-h, --help` | Show help |

### Database Discovery

```yaml
# config/database.yml
development:
  adapter: sqlite
  database: db/development.sqlite3

production:
  adapter: pg
  database: myapp_production
```

Reads `DATABASE_URL` from `.env.local` for remote databases (Neon, Turso, etc.).

### Model Discovery

Models loaded from `app/models/` (transpiled to `dist/models/`):

```javascript
// lib/model_loader.mjs
import { readdirSync } from 'fs';
import { join } from 'path';

async function loadModels() {
  const modelsDir = join(process.cwd(), 'dist', 'models');
  const files = readdirSync(modelsDir).filter(f => f.endsWith('.js'));

  const models = {};
  for (const file of files) {
    const module = await import(join(modelsDir, file));
    const name = file.replace('.js', '');
    models[name] = module.default || module[Object.keys(module)[0]];
  }

  return models;
}
```

### Schema for Model List Sidebar

The sidebar shows models with record counts:

```javascript
// Get table names from database
const tables = await db.exec("SELECT name FROM sqlite_master WHERE type='table'");

// Or read from transpiled schema
import { Schema } from './config/schema.js';
const models = Schema.tables;  // ['posts', 'users', 'comments']
```

## Database Compatibility

Not all Juntos database adapters work with `juntos console` since it runs in Node.js:

| Adapter | Support | Notes |
|---------|---------|-------|
| **sqlite** | MVP | Direct file access via better-sqlite3 |
| **pg** | Complete | Standard PostgreSQL connection |
| **mysql2** | Complete | Standard MySQL connection |
| **neon** | Complete | PostgreSQL via connection string |
| **turso** | Complete | libsql client for Node.js |
| **planetscale** | Complete | MySQL or serverless driver |
| **d1** | Future | Requires Wrangler CLI or D1 HTTP API integration |
| **supabase** | Future | Verify direct pg connection or add REST adapter |
| **dexie** | Not possible | IndexedDB is browser-only |
| **sqljs** | Not applicable | In-memory WASM, no persistent data to query |
| **pglite** | Not applicable | Client-side WASM, no remote data |

**Implementation phases:**

- **MVP (M3):** SQLite via better-sqlite3 — simplest local development setup
- **Complete (M5):** Add pg and mysql2 — covers most production databases
- **Future:** D1 and Supabase — requires additional adapter work

The "Complete" adapters share a common pattern: standard database drivers with connection strings from `DATABASE_URL` or `config/database.yml`. No special infrastructure needed.

## Open Questions

1. **Ecosystem packages** - Bundle ink-text-input etc. or make optional?
   - Recommendation: Bundle essentials, document extras

2. **React version** - Ink 4.x requires React 18
   - Ensure compatibility with Ruby2JS React output

## References

- [Ink GitHub](https://github.com/vadimdemedes/ink)
- [Ink Components Documentation](https://github.com/vadimdemedes/ink#components)
- [ink-text-input](https://github.com/vadimdemedes/ink-text-input)
- [Building CLIs with Ink](https://vadimdemedes.com/posts/building-rich-command-line-interfaces-with-ink-and-react)
- [Phlex Filter](../lib/ruby2js/filter/phlex.rb) - Pattern reference
- [Phlex Demos Plan](./PHLEX_DEMOS.md) - Related work
