# Phlex + Stimulus Demo

Interactive UI components built with Phlex (HTML) and Stimulus (behavior). Demonstrates that Phlex + Stimulus provides a lightweight alternative to React for many use cases.

## Components

| Component | Phlex Patterns                  | Stimulus Patterns             |
| --------- | ------------------------------- | ----------------------------- |
| Counter   | Basic elements, text            | Targets, actions, state       |
| Toggle    | Conditional classes             | classList manipulation        |
| Tabs      | Multiple children, active state | Multiple targets, data values |
| Modal     | Backdrop, nested content        | Show/hide, click-outside      |
| Dropdown  | Positioning, menu items         | Focus management, keyboard    |
| Accordion | Multiple expandable sections    | Multiple instances            |

## Quick Start

```bash
npm install
npm run dev
# Open http://localhost:3000
```

## How It Works

Phlex components define the HTML structure with Stimulus data attributes:

```ruby
# app/components/counter_view.rb
class CounterView < Phlex::HTML
  def view_template
    div(data_controller: "counter") do
      span(data_counter_target: "display") { "0" }
      button(data_action: "click->counter#increment") { "+" }
    end
  end
end
```

Stimulus controllers handle the behavior:

```ruby
# app/controllers/counter_controller.rb
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

Both are transpiled to JavaScript:

```
app/components/*.rb  → dist/components/*.js   (Phlex filter)
app/controllers/*.rb → dist/controllers/*.js  (Stimulus filter)
```

## Why Phlex + Stimulus?

| Concern      | React                    | Phlex + Stimulus        |
| ------------ | ------------------------ | ----------------------- |
| Initial HTML | Virtual DOM render       | Server or Phlex JS      |
| State        | useState/useReducer      | Controller instance     |
| Updates      | Re-render → diff → patch | Direct DOM manipulation |
| Bundle size  | ~40KB+                   | ~3KB (Stimulus)         |
| Mental model | Declarative              | Imperative              |

**Choose Phlex + Stimulus when:**
- Updates are infrequent or localized
- You want HTML-first development
- Bundle size matters
- You're already using Rails/Hotwire

## Project Structure

```
phlex-stimulus/
├── app/
│   ├── components/       # Phlex views (HTML structure)
│   │   ├── counter_view.rb
│   │   ├── toggle_view.rb
│   │   ├── tabs_view.rb
│   │   ├── modal_view.rb
│   │   ├── dropdown_view.rb
│   │   ├── accordion_view.rb
│   │   └── showcase_view.rb
│   └── controllers/      # Stimulus controllers (behavior)
│       ├── counter_controller.rb
│       ├── toggle_controller.rb
│       ├── tabs_controller.rb
│       ├── modal_controller.rb
│       ├── dropdown_controller.rb
│       └── accordion_controller.rb
├── config/
│   └── ruby2js.yml       # Transpilation options
├── dist/                 # Generated JavaScript
├── index.html            # Entry point
├── styles.css            # Component styles
└── package.json
```

## See Also

- [Phlex Filter](/docs/filters/phlex) - Phlex DSL reference
- [Stimulus Filter](/docs/filters/stimulus) - Stimulus controller patterns
- [Building UI Components](/docs/users-guide/components) - When to use what
