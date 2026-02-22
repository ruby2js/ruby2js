---
order: 681
title: Coming from Rails
top_section: Juntos
category: juntos/coming-from
hide_in_toc: true
---

You know Rails. Juntos takes those patterns to platforms Rails can't reach.

{% toc %}

## Why Juntos for Rails Developers?

Rails is powerful but limited to traditional servers. Juntos unlocks:

| Platform | What It Enables | Rails? |
|----------|-----------------|--------|
| **[Browser](/docs/juntos/deploying/browser)** | Offline-first apps, zero infrastructure | No |
| **[Vercel Edge](/docs/juntos/deploying/vercel)** | Global edge, auto-scaling, ~50ms cold starts | No |
| **[Cloudflare Workers](/docs/juntos/deploying/cloudflare)** | Edge computing, ~5ms cold starts | No |
| **[Capacitor](/docs/juntos/deploying/capacitor)** | Native iOS/Android apps | No |
| **[Electron](/docs/juntos/deploying/electron)** | Desktop apps (macOS/Windows/Linux) | No |
| **[Tauri](/docs/juntos/deploying/tauri)** | Lightweight desktop apps (~3MB) | No |

Your Rails knowledge transfers directly—same ActiveRecord patterns, same MVC structure, same conventions.

## Same Models, New Platforms

Your ActiveRecord models work everywhere:

```ruby
# This exact model runs in browser, edge, mobile, and desktop
class Post < ApplicationRecord
  validates :title, presence: true
  has_many :comments, dependent: :destroy
  scope :published, -> { where(published: true) }
end

# Same queries everywhere
@posts = Post.published.order(created_at: :desc).limit(10)
@post = Post.find(params[:id])
@comments = @post.comments.includes(:author)
```

## What You Know → What You Write

| Rails | Juntos |
|-------|--------|
| ActiveRecord models | Same models, transpiled |
| Validations | Same validations |
| Associations | Same associations |
| Concerns | Same concerns, transpiled to factory functions |
| Scopes | Same scopes |
| Controllers | Same MVC pattern |
| `rails routes` | File-based routing |
| Hotwire | Full Turbo/Stimulus support |

## Two Ways to Use Ruby2JS

### 1. Juntos: Rails Patterns, New Platforms

Build complete apps that deploy to browser, edge, mobile, or desktop:

```bash
# Create a new Juntos app
npx create-juntos my-app
cd my-app

# Develop locally with SQLite
bin/juntos up -d sqlite

# Deploy to Vercel Edge with Neon
bin/juntos deploy -t vercel -d neon
```

### 2. Ruby2JS-Rails: Enhance Existing Apps

Add Ruby2JS to your existing Rails app for frontend JavaScript:

```ruby
# Gemfile
gem 'juntos'
```

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "stimulus", "functions"]
}'></div>

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

```erb
<div data-controller="hello">
  <input type="text" placeholder="Your name">
  <button data-action="click->hello#greet">Greet</button>
  <output></output>
</div>
```

## Stimulus Controllers

### Data Attributes

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "stimulus", "functions"]
}'></div>

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

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "stimulus", "functions"]
}'></div>

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

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "stimulus", "functions"]
}'></div>

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

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["esm", "stimulus", "functions"]
}'></div>

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

## Offline-First Apps

Juntos enables offline-first apps that sync with a Rails backend:

```ruby
# Browser app uses IndexedDB
@posts = Post.where(published: true)  # Works offline!

# Same models sync with Rails API when online
Post.sync_with_server  # Push/pull changes
```

This pattern works for:
- Mobile apps in spotty connectivity
- Field data collection
- Event scoring systems
- Any scenario requiring offline capability

## Key Differences from Traditional Rails

### With Juntos: Full ORM Works

Juntos transpiles ActiveRecord patterns—queries work in browser, edge, and mobile:

```ruby
# This works in Juntos (browser, edge, mobile, desktop)
@posts = Post.published.order(created_at: :desc)
@comments = @post.comments.includes(:author)
```

### With Ruby2JS-Rails: API-Based

When adding Ruby2JS to an existing Rails app, frontend code calls your Rails API:

```ruby
# Frontend Stimulus controller calls Rails backend
Post.find(id).then do |post|
  render_post(post)
end
```

### Same Ruby, Different Contexts

```ruby
# These patterns work everywhere
items.select { |i| i.active }.map { |i| i.name }
"Hello, #{user.name}!"
"/posts/#{post.id}/comments"
```

## Deployment

### Juntos: Deploy Anywhere

```bash
bin/juntos deploy -t vercel -d neon    # Edge with Postgres
bin/juntos deploy -t cloudflare -d d1  # Edge with SQLite
bin/juntos deploy -t capacitor         # iOS/Android
bin/juntos deploy -t electron          # Desktop
```

See [Deployment Overview](/docs/juntos/deploying/) for all targets.

### Ruby2JS-Rails: Enhance Existing Apps

```ruby
# config/environments/production.rb
config.ruby2js.preset = true
config.ruby2js.eslevel = 2022
```

The build process transpiles `.rb` files to `.js` automatically.

## Next Steps

### For New Projects (Juntos)

- **[Getting Started](/docs/juntos/getting-started)** - Create your first Juntos app
- **[Deployment Overview](/docs/juntos/deploying/)** - Choose your target platform
- **[Active Record](/docs/juntos/active-record)** - ORM in JavaScript runtimes

### For Existing Rails Apps (Ruby2JS-Rails)

- **[Stimulus Filter](/docs/filters/stimulus)** - Full Stimulus support
- **[Rails Helpers](/docs/filters/rails)** - Rails-compatible helpers
- **[User's Guide](/docs/users-guide/introduction)** - General patterns
