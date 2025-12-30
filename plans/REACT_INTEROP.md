# React Interoperability Plan

Enable Ruby2JS applications to both produce React components and consume components from the React ecosystem.

## Related Plans

- [VERCEL_TARGET.md](./VERCEL_TARGET.md) — Vercel deployment (benefits from React interop)
- [UNIVERSAL_DATABASES.md](./UNIVERSAL_DATABASES.md) — Database adapters

## Context

Ruby2JS already has React/Preact filters that generate React components. However:

1. The primary syntax (Wunderbar) uses underscore prefixes (`_div`, `_Button`) that are unfamiliar to most developers
2. Consuming external React components works but isn't well-documented
3. Phlex-style syntax support exists but is incomplete
4. No clear guidance on integrating with React ecosystems (Next.js, component libraries)

## Goals

1. **Produce**: Ruby classes → React components usable in any React app
2. **Consume**: Use npm React components (MUI, Chakra, Radix, etc.) in Ruby2JS apps
3. **Syntax**: Support familiar syntaxes (Phlex, JSX) alongside Wunderbar
4. **Ecosystem**: Enable integration with Next.js and React component libraries

## Current State

### Producing React Components (Works)

```ruby
class Counter < React
  def initialize
    @count = 0
  end

  def render
    _button(onClick: -> { @count += 1 }) { @count }
  end
end
```

Generates:
```javascript
function Counter() {
  let [count, setCount] = React.useState(0);
  return <button onClick={() => setCount(count + 1)}>{count}</button>
}
```

### Consuming React Components (Works, Undocumented)

```ruby
import DatePicker, from: "react-datepicker"
import Button, from: "@mui/material"

class MyForm < React
  def initialize
    @date = nil
  end

  def render
    _div do
      _DatePicker value: @date, onChange: ->(d) { @date = d }
      _Button variant: "contained" do
        "Submit"
      end
    end
  end
end
```

Generates:
```jsx
import DatePicker from "react-datepicker";
import Button from "@mui/material";

function MyForm() {
  let [date, setDate] = React.useState(null);
  return <div>
    <DatePicker value={date} onChange={d => setDate(d)}/>
    <Button variant="contained">Submit</Button>
  </div>
}
```

## Syntax Options

### Current: Wunderbar Style

```ruby
_div class: "container" do
  _DatePicker value: @date
  _Button(onClick: handler) { "Submit" }
end
```

**Pros**: Concise, established in Ruby2JS
**Cons**: Unfamiliar underscore prefix, not used elsewhere in Ruby ecosystem

### Proposed: Phlex Style

```ruby
div class: "container" do
  render DatePicker.new(value: @date)
  render Button.new(onClick: handler) { "Submit" }
end
```

**Pros**: Familiar to Phlex users, Ruby-idiomatic, no special prefix
**Cons**: More verbose for simple elements

### Proposed: JSX Literals

```ruby
def render
  %x{
    <div className="container">
      <DatePicker value={@date} />
      <Button onClick={handler}>Submit</Button>
    </div>
  }
end
```

**Pros**: Familiar to React developers, copy-paste from React examples
**Cons**: String-based, less Ruby-like

### All Three Together

A component could mix syntaxes based on preference:

```ruby
class MyForm < React
  def initialize
    @date = nil
  end

  def render
    # Phlex-style for structure
    div class: "form" do
      # Wunderbar for simple elements
      _label "Select date:"

      # Phlex-style for external components
      render DatePicker.new(value: @date, onChange: date_handler)

      # JSX for complex snippets copied from docs
      %x{<Button variant="contained" onClick={submit}>Save</Button>}
    end
  end

  def date_handler
    ->(d) { @date = d }
  end

  def submit
    -> { save_form() }
  end
end
```

## Implementation

### Phase 1: Complete Phlex-Style Support in React Filter

Currently, Phlex-style patterns are gated behind `@jsx_content` flag. Expand to work in all React contexts:

```ruby
# lib/ruby2js/filter/react.rb

# Remove @jsx_content guard from these patterns:
# - render Component.new(props)
# - div/span/etc element methods
# - fragment { }
# - plain "text"

# These should work anywhere inside a React class, not just in %x{} blocks
```

**Files to modify:**
- `lib/ruby2js/filter/react.rb` — Remove `@jsx_content` guards
- `spec/react_spec.rb` — Add tests for Phlex-style in React classes

### Phase 2: Improve JSX Literal Parsing

Current JSX literals have limitations with complex expressions:

```ruby
# This fails:
%x{<DatePicker onChange={(d) => @date = d} />}

# Need to handle arrow functions with instance variable assignment
```

**Files to modify:**
- `lib/ruby2js/jsx.rb` — Improve expression parsing
- `lib/ruby2js.rb` — JSX-to-Ruby conversion

### Phase 3: Documentation

Document the three syntax options and when to use each:

| Use Case | Recommended Syntax |
|----------|-------------------|
| Simple HTML elements | Wunderbar (`_div`, `_p`) |
| External React components | Phlex (`render Component.new`) |
| Complex JSX from docs | JSX literal (`%x{...}`) |
| Phlex users | Phlex style throughout |
| React developers | JSX literals |

### Phase 4: Next.js Integration

Enable Ruby2JS components to be used in Next.js projects:

**Approach 1: Build Step**
```
ruby/
  components/
    counter.rb
    form.rb
↓ ruby2js build
components/
  counter.jsx
  form.jsx
↓ next.js imports
app/
  page.tsx (imports from components/)
```

**Approach 2: Webpack/Turbopack Loader**
```javascript
// next.config.js
module.exports = {
  webpack: (config) => {
    config.module.rules.push({
      test: /\.rb$/,
      use: 'ruby2js-loader',
    });
    return config;
  },
};
```

**Approach 3: Component Library**
Publish Ruby2JS components as an npm package:
```bash
# Build
ruby2js build --output dist/

# Publish
npm publish
```

Then consume in any React project:
```jsx
import { Counter, Form } from 'my-ruby-components';
```

### Phase 5: Server Components vs Client Components

For Next.js App Router, distinguish between:

**Client Components** (with state, effects):
```ruby
# Pragma or convention to add 'use client'
# use client
class Counter < React
  def initialize
    @count = 0  # useState
  end
end
```

Generates:
```javascript
'use client';
import React from "react";
// ...
```

**Server Components** (no state, async):
```ruby
# Default or explicit pragma
class ArticleList < React
  def render
    articles = Article.all  # Could be async fetch
    _ul do
      articles.each { |a| _li { a.title } }
    end
  end
end
```

## Use Cases

### Use Case 1: Ruby Developer Using React Component Library

A Rails developer wants to use Material UI without learning JSX:

```ruby
import [Button, TextField, Card], from: "@mui/material"

class LoginForm < React
  def initialize
    @email = ""
    @password = ""
  end

  def render
    render Card.new do
      render TextField.new(
        label: "Email",
        value: @email,
        onChange: ->(e) { @email = e.target.value }
      )
      render TextField.new(
        label: "Password",
        type: "password",
        value: @password,
        onChange: ->(e) { @password = e.target.value }
      )
      render Button.new(variant: "contained", onClick: submit) do
        "Login"
      end
    end
  end

  def submit
    -> { Auth.login(@email, @password) }
  end
end
```

### Use Case 2: React Project Adding Ruby Components

A Next.js project wants some components written in Ruby:

```
my-nextjs-app/
├── app/
│   ├── page.tsx
│   └── layout.tsx
├── components/
│   ├── Header.tsx       # TypeScript
│   └── Footer.tsx       # TypeScript
├── ruby/
│   └── components/
│       ├── pricing_table.rb  # Ruby
│       └── feature_grid.rb   # Ruby
└── package.json
```

```tsx
// app/page.tsx
import Header from '../components/Header';
import PricingTable from '../components/pricing_table';  // Generated from Ruby
import Footer from '../components/Footer';

export default function Home() {
  return (
    <>
      <Header />
      <PricingTable plans={plans} />
      <Footer />
    </>
  );
}
```

### Use Case 3: Full Ruby2JS App with React UI

A Ruby2JS on Rails app using React components for UI:

```ruby
# app/views/articles/index.rb
import [Card, CardContent, Typography, Button], from: "@mui/material"

class ArticlesIndex < ApplicationView
  def render
    _div class: "articles" do
      @articles.each do |article|
        render Card.new(key: article.id) do
          render CardContent.new do
            render Typography.new(variant: "h5") { article.title }
            render Typography.new(variant: "body2") { article.excerpt }
          end
          render Button.new(onClick: -> { navigate("/articles/#{article.id}") }) do
            "Read More"
          end
        end
      end
    end
  end
end
```

## Comparison: Ruby2JS + React vs Pure Next.js

| Aspect | Ruby2JS + React | Pure Next.js |
|--------|-----------------|--------------|
| **Language** | Ruby syntax | TypeScript/JSX |
| **Component libraries** | Full access | Full access |
| **State management** | `@var` → `useState` | `useState` directly |
| **Props** | `@@var` → `props.var` | Explicit props |
| **Learning curve** | Ruby developers: Low | React developers: Low |
| **Tooling** | Build step needed | Native |
| **Type safety** | Limited | Full TypeScript |

Ruby2JS + React isn't "better" than Next.js — it's an alternative syntax for developers who prefer Ruby.

## Success Criteria

1. Phlex-style `render Component.new()` works in all React contexts
2. External npm components can be imported and used
3. Generated code works in Next.js without modification
4. Documentation covers all three syntax options
5. Examples show integration with popular component libraries (MUI, Chakra)
6. Build tooling supports Next.js workflow

## Open Questions

### ISR (Incremental Static Regeneration)

Next.js ISR allows static pages to be regenerated on-demand. Questions:

1. Could Ruby2JS generate ISR-compatible pages?
2. What would the Ruby syntax look like for `revalidate`?
3. How would this interact with Ruby2JS on Rails' current rendering model?

```ruby
# Possible syntax?
class ArticlePage < React
  revalidate 60  # seconds

  def self.getStaticProps(params)
    { article: Article.find(params[:id]) }
  end

  def render
    _article do
      _h1 { @@article.title }
      _div { @@article.body }
    end
  end
end
```

### Hooks Beyond useState

Current support focuses on `useState`. What about:

- `useEffect` → lifecycle methods?
- `useContext` → class variables?
- `useMemo`/`useCallback` → automatic optimization?
- Custom hooks → Ruby modules?

### TypeScript Generation (Deferred)

Type systems are not a strength of Ruby. While Ruby2JS could potentially generate TypeScript:

```ruby
class Button < React
  prop :label, String
  prop :onClick, Proc
  prop :disabled, Boolean, default: false
end
```

→

```typescript
interface ButtonProps {
  label: string;
  onClick: () => void;
  disabled?: boolean;
}

function Button({ label, onClick, disabled = false }: ButtonProps) {
  // ...
}
```

This is deferred to a future release. The focus is on JavaScript output that works in TypeScript projects (via `.js` files or `allowJs`).

## Implementation Phases Summary

| Phase | Description | Effort |
|-------|-------------|--------|
| 1 | Complete Phlex-style in React filter | Small |
| 2 | Improve JSX literal parsing | Medium |
| 3 | Documentation | Small |
| 4 | Next.js integration tooling | Medium |
| 5 | Server/Client component distinction | Small |

Total estimated effort: Medium — mostly documentation and polish rather than new architecture.
