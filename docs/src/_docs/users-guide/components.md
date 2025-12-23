---
order: 9.6
title: Building UI Components
top_section: User's Guide
category: users-guide-components
---

# Building UI Components

Ruby2JS provides multiple approaches for building frontend UI components. This guide explains the options, their trade-offs, and when to use each.

## The Vision: Portable Components

Ruby2JS enables a **"write once, target both"** approach to component development. The same Ruby code can produce different JavaScript outputs depending on your needs:

```
                    ┌─────────────────────────────────────┐
                    │    Phlex Ruby (your component)      │
                    │  div { h1 { @title } }              │
                    └─────────────┬───────────────────────┘
                                  │
                    ┌─────────────┴───────────────────────┐
                    │                                     │
                    ↓                                     ↓
             [:phlex] filter                    [:phlex, :react] filters
                    │                                     │
                    ↓                                     ↓
            ┌──────────────┐                    ┌──────────────┐
            │  Phlex JS    │                    │  React JS    │
            │ (HTML strings│                    │ (virtual DOM)│
            │  + Stimulus) │                    │              │
            └──────────────┘                    └──────────────┘
```

**Why this matters:**

- **Migration flexibility** — Start with React, switch to lighter Phlex when reactivity isn't needed
- **Server/client parity** — Same Phlex component works on server (Ruby) and browser (transpiled JS)
- **Framework choice deferred** — Write components now, choose runtime later
- **Gradual adoption** — Mix approaches within the same application

## Approaches Compared

### 1. React with JSX Syntax

For full React applications with complex state management:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["react", "esm", "functions"]
}'></div>

```ruby
class Counter < React
  def initialize
    @count = 0
  end

  def render
    %x{
      <div>
        <p>Count: {count}</p>
        <button onClick={() => setCount(count + 1)}>+</button>
      </div>
    }
  end
end
```

**Best for:**
- Complex state management
- Applications already using React
- When you need React's ecosystem (hooks, context, libraries)

**Trade-offs:**
- Requires React runtime (~40KB min+gzip)
- JSX syntax differs from Ruby idioms
- Virtual DOM overhead for simple UIs

### 2. Phlex → Phlex JS (Lightweight)

For server-rendered HTML with lightweight client-side interactivity:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["phlex", "functions"]
}'></div>

```ruby
class Card < Phlex::HTML
  def initialize(title:)
    @title = title
  end

  def view_template
    div(class: "card") do
      h1 { @title }
      p { "Card content" }
    end
  end
end
```

**Best for:**
- Server-rendered applications (Rails, Sinatra)
- Static or mostly-static UIs
- When paired with Stimulus for interactivity
- Minimizing JavaScript bundle size

**Trade-offs:**
- No virtual DOM or automatic re-rendering
- Requires Stimulus or similar for interactivity
- String concatenation (less efficient for frequent updates)

### 3. Phlex → React JS (Portable)

Write Phlex, output React — the best of both worlds:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["phlex", "react", "functions"]
}'></div>

```ruby
class Card < Phlex::HTML
  def initialize(title:)
    @title = title
  end

  def view_template
    div(class: "card") do
      h1 { @title }
      p { "Card content" }
    end
  end
end
```

**Best for:**
- Teams familiar with Phlex who need React output
- Migrating from React to Phlex (or vice versa)
- Sharing components between server and client
- Keeping options open

**Trade-offs:**
- Phlex DSL doesn't expose all React features directly
- Two mental models to understand

## When to Use What

| Scenario | Recommended Approach |
|----------|---------------------|
| New React app | React with JSX |
| Rails app, minimal JS | Phlex + Stimulus |
| Rails app, complex UI sections | Phlex → React for those sections |
| Migrating away from React | Phlex → React now, Phlex later |
| Maximum portability | Phlex (can target either) |
| Need React hooks/context | React with JSX |
| Static marketing pages | Phlex + Stimulus |
| Interactive dashboards | React or Phlex → React |

## Phlex + Stimulus: A React Alternative

For many applications, the combination of Phlex (for HTML) and Stimulus (for behavior) provides a lighter alternative to React:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["phlex", "stimulus", "esm", "functions"]
}'></div>

```ruby
# Phlex component with Stimulus hooks
class Counter < Phlex::HTML
  def view_template
    div(data_controller: "counter") do
      span(data_counter_target: "display") { "0" }
      button(data_action: "click->counter#increment") { "+" }
    end
  end
end

# Stimulus controller
class CounterController < Stimulus::Controller
  def connect
    @count = 0
  end

  def increment
    @count += 1
    displayTarget.textContent = @count.to_s
  end
end
```

| Concern | React | Phlex + Stimulus |
|---------|-------|------------------|
| Initial HTML | Virtual DOM render | Server or Phlex JS |
| State | useState/useReducer | Controller instance |
| Updates | Re-render → diff → patch | Direct DOM manipulation |
| Bundle size | ~40KB+ | ~3KB (Stimulus) |
| Mental model | Declarative | Imperative |

**Choose Phlex + Stimulus when:**
- Updates are infrequent or localized
- You want HTML-first development
- Bundle size matters
- You're already using Rails/Hotwire

**Choose React when:**
- UI has complex, frequent state changes
- You need component composition with shared state
- You want the React ecosystem

## The Architecture: How It Works

Ruby2JS uses **pnodes** (Phlex nodes) as a unified intermediate representation:

```ruby
# Your Phlex code
div(class: "card") { h1 { @title } }

# Becomes a pnode (internal AST)
s(:pnode, :div, s(:hash, s(:pair, s(:sym, :class), s(:str, "card"))),
  s(:pnode, :h1, s(:hash),
    s(:pnode_text, s(:lvar, :title))))
```

This pnode can then be converted to:

- **Template literals** (Phlex JS): `` `<div class="card"><h1>${title}</h1></div>` ``
- **React.createElement** (React JS): `React.createElement("div", {className: "card"}, ...)`

The filter chain determines the output:

```ruby
# Phlex JS output
Ruby2JS.convert(code, filters: [:phlex])

# React JS output
Ruby2JS.convert(code, filters: [:phlex, :react])
```

## Examples

### Same Component, Different Outputs

**Source (Phlex Ruby):**

```ruby
class ProfileCard < Phlex::HTML
  def initialize(name:, avatar:)
    @name = name
    @avatar = avatar
  end

  def view_template
    div(class: "profile") do
      img(src: @avatar, alt: @name)
      h2 { @name }
    end
  end
end
```

**With `[:phlex]`:**

```javascript
class ProfileCard extends Phlex.HTML {
  render({avatar, name}) {
    let _phlex_out = "";
    _phlex_out += `<div class="profile">` +
      `<img src="${avatar}" alt="${name}">` +
      `<h2>${String(name)}</h2></div>`;
    return _phlex_out
  }
}
```

**With `[:phlex, :react]`:**

```javascript
class ProfileCard extends Phlex.HTML {
  render({avatar, name}) {
    return React.createElement("div", {className: "profile"},
      React.createElement("img", {src: avatar, alt: name}),
      React.createElement("h2", null, name)
    )
  }
}
```

### Component with Multiple Root Elements

When a component has multiple root elements, React mode automatically wraps them in a Fragment:

```ruby
class PageHeader < Phlex::HTML
  def view_template
    h1 { "Welcome" }
    nav { a(href: "/") { "Home" } }
  end
end
```

```javascript
// With [:phlex, :react]
class PageHeader extends Phlex.HTML {
  render() {
    return React.createElement(React.Fragment, null,
      React.createElement("h1", null, "Welcome"),
      React.createElement("nav", null,
        React.createElement("a", {href: "/"}, "Home")
      )
    )
  }
}
```

## Getting Started

1. **For React apps:** Use the [React filter](/docs/filters/react) with JSX syntax
2. **For Rails/server-rendered apps:** Use the [Phlex filter](/docs/filters/phlex) with [Stimulus filter](/docs/filters/stimulus)
3. **For maximum flexibility:** Write Phlex components and choose your output target

See the filter documentation for detailed API reference:
- [Phlex Filter](/docs/filters/phlex) — Phlex DSL and React integration
- [React Filter](/docs/filters/react) — React/Preact components and JSX
- [Stimulus Filter](/docs/filters/stimulus) — Stimulus controllers
- [JSX Filter](/docs/filters/jsx) — JSX output formatting
