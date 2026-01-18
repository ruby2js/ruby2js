---
order: 681
title: Coming from Rails
top_section: Juntos
category: juntos/coming-from
hide_in_toc: true
---

# Coming from Rails

If you know Rails, Ruby2JS lets you write frontend JavaScript using Ruby—the same language you use on the backend.

{% toc %}

## What You Know → What You Write

| Rails | Ruby2JS |
|-------|---------|
| ERB templates | ERB templates (same!) |
| Stimulus controllers | Stimulus controllers in Ruby |
| Turbo | Works unchanged |
| ActiveRecord models | JavaScript model classes |
| `rails routes` | File-based routing |
| Hotwire | Full support |

## Quick Start

**1. Add Ruby2JS to your Rails app:**

```ruby
# Gemfile
gem 'ruby2js-rails'
```

**2. Write Stimulus controllers in Ruby:**

```ruby
# app/javascript/controllers/hello_controller.rb
class HelloController < Stimulus::Controller
  def connect
    element.textContent = "Hello, Ruby2JS!"
  end

  def greet
    name = element.querySelector("input").value
    element.querySelector("output").textContent = "Hello, #{name}!"
  end
end
```

**3. Use in your view (unchanged):**

```erb
<div data-controller="hello">
  <input type="text" placeholder="Your name">
  <button data-action="click->hello#greet">Greet</button>
  <output></output>
</div>
```

## Stimulus Controllers

### Data Attributes

```ruby
# app/javascript/controllers/slideshow_controller.rb
class SlideshowController < Stimulus::Controller
  targets %i[slide]
  values index: { type: Number, default: 0 }

  def next
    self.index_value = (index_value + 1) % slide_targets.length
    show_current_slide
  end

  def previous
    self.index_value = (index_value - 1) % slide_targets.length
    show_current_slide
  end

  private

  def show_current_slide
    slide_targets.each_with_index do |slide, i|
      slide.hidden = i != index_value
    end
  end
end
```

### Outlets

```ruby
class SearchController < Stimulus::Controller
  outlets %i[results]

  def search
    query = element.querySelector("input").value
    results_outlet.update(query)
  end
end

class ResultsController < Stimulus::Controller
  def update(query)
    fetch("/search?q=#{query}")
      .then(->(r) { r.text })
      .then(->(html) { element.innerHTML = html })
  end
end
```

## ActiveRecord-Style Models

```ruby
# app/javascript/models/post.rb
class Post
  include ActiveModel

  attribute :id, :integer
  attribute :title, :string
  attribute :body, :string
  attribute :published, :boolean, default: false

  validates :title, presence: true

  def self.all
    fetch('/api/posts')
      .then(->(r) { r.json })
      .then(->(data) { data.map { |d| new(d) } })
  end

  def self.find(id)
    fetch("/api/posts/#{id}")
      .then(->(r) { r.json })
      .then(->(data) { new(data) })
  end

  def save
    if persisted?
      update
    else
      create
    end
  end

  def destroy
    fetch("/api/posts/#{id}", method: 'DELETE')
  end

  private

  def create
    fetch('/api/posts',
      method: 'POST',
      body: JSON.stringify(attributes)
    )
  end

  def update
    fetch("/api/posts/#{id}",
      method: 'PATCH',
      body: JSON.stringify(attributes)
    )
  end
end
```

## Turbo Integration

Ruby2JS works seamlessly with Turbo:

```ruby
# app/javascript/controllers/form_controller.rb
class FormController < Stimulus::Controller
  def submit(event)
    event.preventDefault

    form = event.target
    fetch(form.action, method: form.method, body: FormData.new(form))
      .then(->(r) { r.text })
      .then(->(html) {
        Turbo.renderStreamMessage(html)
      })
  end
end
```

### Turbo Streams

```erb
<!-- Standard Turbo Stream responses work unchanged -->
<turbo-stream action="append" target="posts">
  <template>
    <%= render @post %>
  </template>
</turbo-stream>
```

## View Components

Use ViewComponent or Phlex with Ruby2JS:

```ruby
# app/components/counter_component.rb (Ruby, runs on server)
class CounterComponent < ViewComponent::Base
  def initialize(initial: 0)
    @initial = initial
  end
end
```

```erb
<!-- app/components/counter_component.html.erb -->
<div data-controller="counter" data-counter-count-value="<%= @initial %>">
  <span data-counter-target="display"><%= @initial %></span>
  <button data-action="counter#increment">+</button>
</div>
```

```ruby
# app/javascript/controllers/counter_controller.rb
class CounterController < Stimulus::Controller
  values count: Number
  targets %i[display]

  def increment
    self.count_value += 1
    display_target.textContent = count_value
  end
end
```

## The Ruby Advantage

### Same Language, Same Patterns

```ruby
# Backend (Rails)
class PostsController < ApplicationController
  def create
    @post = Post.new(post_params)
    if @post.save
      redirect_to @post
    else
      render :new
    end
  end
end

# Frontend (Ruby2JS)
class PostFormController < Stimulus::Controller
  def submit
    post = Post.new(form_data)
    if post.valid?
      post.save.then { navigate_to(post) }
    else
      show_errors(post.errors)
    end
  end
end
```

### Familiar Iteration

```ruby
# Both work the same way
items.each do |item|
  puts item.name
end

items.select { |i| i.active }.map { |i| i.name }

items.find { |i| i.id == target_id }
```

### String Interpolation

```ruby
# Works everywhere
"Hello, #{user.name}!"
"/posts/#{post.id}/comments"
```

## Key Differences

### No Server-Side Execution

Ruby2JS code runs in the browser, not on the server:

```ruby
# This WON'T work - no database access in browser
Post.where(published: true)  # ❌

# Use API calls instead
fetch('/api/posts?published=true')  # ✓
```

### Async Operations

Browser operations are async:

```ruby
# Rails (synchronous)
@post = Post.find(params[:id])
render :show

# Ruby2JS (asynchronous)
Post.find(id).then do |post|
  render_post(post)
end
```

### File Organization

```
app/
  javascript/
    controllers/      # Stimulus controllers (.rb)
    models/           # JavaScript model classes (.rb)
    components/       # Reusable JS components (.rb)
```

## Deployment

Works with your existing Rails deployment:

```ruby
# config/environments/production.rb
config.ruby2js.preset = true
config.ruby2js.eslevel = 2022
```

The build process transpiles `.rb` files to `.js` automatically.

## Migration Path

1. **Start with Stimulus**: Convert one controller at a time
2. **Keep ERB**: Your views don't change
3. **Add models**: Extract API logic into model classes
4. **Gradual adoption**: Mix JavaScript and Ruby2JS freely

## Next Steps

- **[Stimulus Filter](/docs/filters/stimulus)** - Full Stimulus support
- **[Rails Helpers](/docs/filters/rails)** - Rails-compatible helpers
- **[Ruby2JS on Rails](/docs/users-guide/ruby2js-on-rails)** - Setup guide
- **[User's Guide](/docs/users-guide/introduction)** - General patterns
