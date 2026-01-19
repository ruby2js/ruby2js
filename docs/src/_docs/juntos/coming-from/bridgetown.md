---
order: 685
title: Coming from Bridgetown
top_section: Juntos
category: juntos/coming-from
hide_in_toc: true
---

Bridgetown already supports Ruby2JS as a built-in option. This guide shows how to use it effectively and add ActiveRecord-like content queries.

{% toc %}

## What You Know → What You Write

| Bridgetown | With Ruby2JS |
|------------|--------------|
| ERB/Ruby templates | Same |
| `index.js` entrypoint | `index.js.rb` entrypoint |
| Stimulus controllers in JS | Stimulus controllers in Ruby |
| `site.collections.posts` | `Post.where(...).order(...)` |
| esbuild bundling | Same, with Ruby2JS plugin |

## Quick Start

Bridgetown documents Ruby2JS support in their [frontend assets guide](https://www.bridgetownrb.com/docs/frontend-assets). Enable it in your esbuild config:

```javascript
// esbuild.config.js
const ruby2js = require("@ruby2js/esbuild-plugin")

module.exports = {
  // ...
  esbuildOptions: {
    entryPoints: ["./frontend/javascript/index.js.rb"],
    plugins: [
      ruby2js()
    ]
  }
}
```

Now rename your entrypoint to Ruby:

```ruby
# frontend/javascript/index.js.rb
import "bridgetown-quick-search/dist"
import "@hotwired/turbo"
import "./controllers"

console.log "Bridgetown is loaded!"
```

## Stimulus Controllers in Ruby

Bridgetown uses Stimulus for interactivity. With Ruby2JS, write your controllers in Ruby:

### Before: JavaScript

```javascript
// frontend/javascript/controllers/post_card_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.addEventListener('click', this.handleClick.bind(this))
  }

  handleClick(event) {
    const slug = this.element.dataset.slug
    window.location.href = `/posts/${slug}/`
  }
}
```

### After: Ruby

```ruby
# frontend/javascript/controllers/post_card_controller.js.rb
import { Controller }, from: "@hotwired/stimulus"

export default class PostCardController < Controller
  def connect
    element.addEventListener('click', handle_click.bind(self))
  end

  def handle_click(event)
    slug = element.dataset[:slug]
    window.location.href = "/posts/#{slug}/"
  end
end
```

Same Stimulus patterns, Ruby syntax.

### More Examples

```ruby
# frontend/javascript/controllers/search_controller.js.rb
import { Controller }, from: "@hotwired/stimulus"

export default class SearchController < Controller
  @targets = [:input, :results]

  def search
    query = input_target.value
    return results_target.innerHTML = "" if query.length < 2

    fetch("/search.json?q=#{encodeURIComponent(query)}")
      .then { |r| r.json() }
      .then { |data| render_results(data) }
  end

  def render_results(posts)
    results_target.innerHTML = posts.map { |p|
      "<a href='#{p[:url]}'>#{p[:title]}</a>"
    }.join("")
  end
end
```

### Stimulus Values and Targets

```ruby
# frontend/javascript/controllers/counter_controller.js.rb
import { Controller }, from: "@hotwired/stimulus"

export default class CounterController < Controller
  @values = { count: { type: Number, default: 0 } }
  @targets = [:display]

  def increment
    self.count_value += 1
  end

  def count_value_changed
    display_target.textContent = count_value.to_s
  end
end
```

## Bridgetown Components

### Ruby Component with JS Behavior

```ruby
# src/_components/accordion.rb
class Accordion < Bridgetown::Component
  def initialize(title:, open: false)
    @title = title
    @open = open
  end
end
```

```erb
<!-- src/_components/accordion.erb -->
<div class="accordion" data-controller="accordion" data-accordion-open-value="<%= @open %>">
  <button data-action="accordion#toggle">
    <%= @title %>
  </button>
  <div data-accordion-target="content">
    <%= content %>
  </div>
</div>
```

```ruby
# frontend/javascript/controllers/accordion_controller.js.rb
import { Controller }, from: "@hotwired/stimulus"

export default class AccordionController < Controller
  @values = { open: Boolean }
  @targets = [:content]

  def connect
    update_visibility
  end

  def toggle
    self.open_value = !open_value
  end

  def open_value_changed
    update_visibility
  end

  def update_visibility
    content_target.hidden = !open_value
  end
end
```

## Query API

Full ActiveRecord-like queries over your content:

```ruby
import { Post, Author, Tag } from 'virtual:content'

# Basic queries
Post.all
Post.where(draft: false)
Post.find_by(slug: 'hello-world')

# Chaining
Post.where(draft: false)
    .where(category: 'tutorials')
    .order(date: :desc)
    .limit(10)

# Relationships
post = Post.find('hello-world')
post.author.name
post.tags.map { |t| t.name }

# Aggregates
Post.count
Post.where(published: true).count
```

## Turbo Integration

Bridgetown often uses Turbo. Write Turbo event handlers in Ruby:

```ruby
# frontend/javascript/turbo.js.rb
import { Turbo }, from: "@hotwired/turbo-rails"

document.addEventListener("turbo:load", -> {
  console.log("Page loaded via Turbo")
})

document.addEventListener("turbo:before-render", ->(event) {
  # Add page transition
  event.detail.newBody.classList.add("fade-in")
})
```

## Islands Architecture

For interactive islands in your static pages:

```ruby
# frontend/javascript/islands/post_filter.js.rb
import { Post } from 'virtual:content'

def init_filter(container)
  input = container.querySelector('input')
  results = container.querySelector('.results')

  input.addEventListener('input', ->(e) {
    query = e.target.value.downcase
    posts = Post.where(draft: false)
                .toArray()
                .select { |p| p[:title].downcase.include?(query) }

    results.innerHTML = posts.map { |p|
      "<a href='/posts/#{p[:slug]}/'>#{p[:title]}</a>"
    }.join("")
  })
end

# Auto-initialize
document.querySelectorAll('[data-island="post-filter"]').each do |el|
  init_filter(el)
end
```

## Configuration

### Basic Setup (esbuild)

Bridgetown's native esbuild configuration:

```javascript
// esbuild.config.js
const ruby2js = require("@ruby2js/esbuild-plugin")

module.exports = {
  globOptions: {
    excludeFilter: /\.(dsd|lit)\.css$/
  },
  esbuildOptions: {
    entryPoints: ["frontend/javascript/index.js.rb"],
    plugins: [
      ruby2js({
        eslevel: 2022,
        filters: ['Functions', 'ESM', 'CamelCase']
      })
    ]
  }
}
```

### With Content Adapter (Optional)

To add ActiveRecord-like queries over your content:

```javascript
// esbuild.config.js
const ruby2js = require("@ruby2js/esbuild-plugin")
const content = require("@ruby2js/content-adapter/esbuild")

module.exports = {
  esbuildOptions: {
    entryPoints: ["frontend/javascript/index.js.rb"],
    plugins: [
      ruby2js(),
      content({ dir: 'src/_posts' })
    ]
  }
}
```

## File Structure

```
src/
  _posts/
    2024-01-15-hello-world.md
    2024-01-20-getting-started.md
  _data/
    authors.yml
  _components/
    post_card.rb
    post_card.erb
frontend/
  javascript/
    index.js.rb                        # Entry point (Ruby)
    controllers/
      post_card_controller.js.rb       # Stimulus controller (Ruby)
      search_controller.js.rb
```

## Benefits for Bridgetown Users

### Same Language Everywhere

You chose Bridgetown because you prefer Ruby. Now your JavaScript is Ruby too:

```ruby
# Ruby in your templates
<%= post.data.title %>

# Ruby in your components
class PostCard < Bridgetown::Component
end

# Ruby in your JavaScript
export default class PostCardController < Controller
end
```

### Familiar Patterns

Rails patterns in your static site:

```ruby
# ActiveRecord-like queries
Post.where(published: true).order(date: :desc)

# Stimulus controllers (already Ruby conventions)
@targets = [:input, :results]
@values = { count: Number }
```

### Full Toolchain

- **Build**: esbuild with Ruby2JS plugin (Bridgetown-supported)
- **Content**: Optional ActiveRecord-like queries with content adapter
- **Interactivity**: Stimulus, Turbo, or vanilla JS—all in Ruby

## Migration Path

1. **Configure esbuild**: Add `@ruby2js/esbuild-plugin` to your config
2. **Update entrypoint**: Change `index.js` to `index.js.rb`
3. **Rename files**: `.js` → `.js.rb` for JavaScript files
4. **Convert syntax**: JavaScript → Ruby (gradual migration)

Your existing ERB templates and Bridgetown components work unchanged.

## Next Steps

- **[Coming from Rails](/docs/juntos/coming-from/rails)** - Full Rails patterns
- **[Coming from 11ty](/docs/juntos/coming-from/eleventy)** - Liquid templates
- **[Stimulus Filter](/docs/filters/stimulus)** - Stimulus-specific transformations

🧪 **Feedback requested** — [Share your experience](https://github.com/ruby2js/ruby2js/discussions)
