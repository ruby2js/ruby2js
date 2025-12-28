# Phlex Components Demo

A shadcn-inspired component library built with Phlex. Demonstrates variant patterns, compound components, and design system primitives.

## Components

| Component | Patterns Demonstrated                                                      |
| --------- | -------------------------------------------------------------------------- |
| Button    | Variants (primary, secondary, destructive, outline, ghost), sizes          |
| Card      | Compound components (Card, CardHeader, CardTitle, CardContent, CardFooter) |
| Input     | Form integration, disabled state, placeholder                              |
| Badge     | Simple variants                                                            |
| Alert     | Variants, icon slot, dismissible                                           |
| Dialog    | Modal behavior, Stimulus integration                                       |
| Tabs      | Compound component, Stimulus integration                                   |

## Quick Start

```bash
npm install
npm run dev
# Open http://localhost:3000
```

## Portability: Phlex JS vs React

This demo outputs lightweight Phlex JS (template literals). The same source can produce React output by adding the `react` filter:

```yaml
# config/ruby2js.yml

# Default: Phlex JS output (template literals)
filters:
  - phlex
  - functions
  - esm

# Alternative: React output (React.createElement)
filters:
  - phlex
  - react
  - functions
  - esm
```

Rebuild after changing the config to see React output. This demonstrates Ruby2JS's "write once, target both" capability.

## Example: Button with Variants

```ruby
# app/components/button.rb
class Button < Phlex::HTML
  VARIANTS = {
    primary: "bg-blue-600 text-white hover:bg-blue-700",
    secondary: "bg-gray-200 text-gray-900 hover:bg-gray-300",
    destructive: "bg-red-600 text-white hover:bg-red-700",
    outline: "border border-gray-300 bg-transparent hover:bg-gray-100",
    ghost: "bg-transparent hover:bg-gray-100"
  }

  SIZES = {
    sm: "px-3 py-1.5 text-sm",
    md: "px-4 py-2 text-base",
    lg: "px-6 py-3 text-lg"
  }

  def initialize(variant: :primary, size: :md, **attrs)
    @variant = variant
    @size = size
    @attrs = attrs
  end

  def view_template(&block)
    button(
      class: "#{VARIANTS[@variant]} #{SIZES[@size]} rounded font-medium",
      **@attrs,
      &block
    )
  end
end
```

## Example: Card (Compound Component)

```ruby
# app/components/card.rb
class Card < Phlex::HTML
  def view_template(&block)
    div(class: "rounded-lg border bg-white shadow-sm", &block)
  end
end

class CardHeader < Phlex::HTML
  def view_template(&block)
    div(class: "flex flex-col space-y-1.5 p-6", &block)
  end
end

class CardTitle < Phlex::HTML
  def view_template(&block)
    h3(class: "text-2xl font-semibold", &block)
  end
end

class CardContent < Phlex::HTML
  def view_template(&block)
    div(class: "p-6 pt-0", &block)
  end
end
```

Usage:

```ruby
render Card.new do
  render CardHeader.new do
    render CardTitle.new { "Card Title" }
  end
  render CardContent.new do
    p { "Card content here." }
  end
end
```

## Project Structure

```
phlex-components/
├── app/
│   ├── components/       # Phlex components
│   │   ├── button.rb
│   │   ├── card.rb
│   │   ├── input.rb
│   │   ├── badge.rb
│   │   ├── alert.rb
│   │   ├── dialog.rb
│   │   ├── tabs.rb
│   │   └── showcase_view.rb
│   └── controllers/      # Stimulus controllers (for Dialog, Tabs)
│       ├── dialog_controller.rb
│       └── tabs_controller.rb
├── config/
│   └── ruby2js.yml       # Transpilation options
├── dist/                 # Generated JavaScript
├── index.html            # Entry point
├── styles.css            # Tailwind-inspired styles
└── package.json
```

## See Also

- [Phlex Filter](/docs/filters/phlex) - Phlex DSL reference
- [React Filter](/docs/filters/react) - React output mode
- [Building UI Components](/docs/users-guide/components) - Portability patterns
