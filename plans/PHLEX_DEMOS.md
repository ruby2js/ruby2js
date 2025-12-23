# Phlex Demos Plan

Three demos to prove Ruby2JS + Phlex handles real applications, not toys.

## Strategic Goals

| Demo | Message | Audience |
|------|---------|----------|
| **Stimulus Showcase** | Interactive UIs without React | Developers evaluating Hotwire vs React |
| **shadcn Components** | Build design systems | Teams building component libraries |
| **rubymonolith Blog** | Complete apps work | Anyone asking "but does it scale?" |

Together they cover the spectrum: **widget → design system → application**.

## Sequencing Rationale

The Stimulus Showcase is hardest because it requires both Phlex and Stimulus filters to work and self-host. Once that's done, subsequent demos primarily exercise already-working code.

```
Demo 1: Stimulus Showcase     ████████████████████  (investment)
Demo 2: shadcn Components     ██████                (incremental)
Demo 3: rubymonolith Blog     ████████              (validation)
```

---

## Prerequisites

Before any demo can work, infrastructure changes are needed.

### P1: Enable Custom Filters in ruby2js.yml

**Problem:** The current `build.rb` hardcodes Rails filters and ignores the `filters:` key:

```ruby
# Current code in demo/ruby2js-on-rails/scripts/build.rb (lines 223-224)
# Don't override filters - they're hardcoded for the demo
next if sym_key == :filters
```

**Solution:** Enable filter selection via YAML configuration.

#### P1.1: Update build.rb to accept filters from YAML

```ruby
# Remove the filter restriction
def build_options
  base = load_ruby2js_config
  options = { **OPTIONS }

  base.each do |key, value|
    sym_key = key.to_s.to_sym
    options[sym_key] = value
  end

  # Handle filter names -> filter modules
  if options[:filters].is_a?(Array) && options[:filters].first.is_a?(String)
    options[:filters] = resolve_filters(options[:filters])
  end

  options
end

def resolve_filters(filter_names)
  filter_names.map do |name|
    case name.downcase
    when 'phlex' then Ruby2JS::Filter::Phlex
    when 'stimulus' then Ruby2JS::Filter::Stimulus
    when 'functions' then Ruby2JS::Filter::Functions
    when 'esm' then Ruby2JS::Filter::ESM
    when 'return' then Ruby2JS::Filter::Return
    when 'camelcase' then Ruby2JS::Filter::CamelCase
    # Rails sub-filters
    when 'rails/model' then Ruby2JS::Filter::Rails::Model
    when 'rails/controller' then Ruby2JS::Filter::Rails::Controller
    when 'rails/routes' then Ruby2JS::Filter::Rails::Routes
    when 'rails/schema' then Ruby2JS::Filter::Rails::Schema
    when 'rails/seeds' then Ruby2JS::Filter::Rails::Seeds
    when 'rails/helpers' then Ruby2JS::Filter::Rails::Helpers
    when 'erb' then Ruby2JS::Filter::Erb
    else
      raise "Unknown filter: #{name}"
    end
  end
end
```

#### P1.2: Example ruby2js.yml for Phlex demos

```yaml
# config/ruby2js.yml for phlex-stimulus demo
default: &default
  eslevel: 2022
  comparison: identity
  autoexports: true
  include:
    - class
    - call
  filters:
    - phlex
    - stimulus
    - functions
    - esm

development:
  <<: *default

production:
  <<: *default
  strict: true
```

### P2: Transpile Phlex and Stimulus Filters for Self-Hosting

**Problem:** Demos must run in browser without Ruby. The Phlex and Stimulus filters must be transpiled to JavaScript.

**Current status:**

| Component | Self-host Status | Location |
|-----------|------------------|----------|
| `phlex` filter | Not yet transpiled | `lib/ruby2js/filter/phlex.rb` |
| `stimulus` filter | Not yet transpiled | `lib/ruby2js/filter/stimulus.rb` |
| `pnode` converter | **NOT IN BUNDLE** | `lib/ruby2js/converter/pnode.rb` |
| `on_pnode` handler | **NOT IN BUNDLE** | `lib/ruby2js/filter/processor.rb` |
| `functions` | Works | `demo/selfhost/filters/functions.js` |
| `esm` | Works | `demo/selfhost/filters/esm.js` |

**Critical:** The pnode converter is required for Phlex output. Verified zero matches for "pnode" in `ruby2js.js`.

**Solution:** Add Phlex, Stimulus, AND pnode converter to the selfhost build pipeline.

#### P2.1: Add filters to selfhost transpilation

Update `demo/selfhost/Rakefile` or build scripts to include:

```ruby
# Transpile phlex filter
transpile_filter('phlex')

# Transpile stimulus filter
transpile_filter('stimulus')
```

#### P2.2: Validate filter output

```bash
# Test that transpiled filters produce same output as Ruby filters
cd demo/selfhost
node -e "
  import { convert } from './ruby2js.mjs';
  import './filters/phlex.js';
  import './filters/stimulus.js';

  const result = convert('class Foo < Phlex::HTML; def view_template; div { \"hi\" }; end; end', {
    filters: ['phlex']
  });
  console.log(result);
"
```

### P3: Update ruby2js-rails Package

**Problem:** The `ruby2js-rails` npm package bundles the selfhost transpiler and filters. It needs to include the new Phlex and Stimulus filters.

**Solution:** After P2, rebuild and publish the package:

```bash
# In demo/selfhost
npm run build

# Update the tarball
# (process depends on how ruby2js-rails is published)
```

### P4: JavaScript Build Integration

**Problem:** The self-hosted build.mjs needs to load filters dynamically based on ruby2js.yml.

**Current:** Filters are hardcoded in the transpiled build.mjs.

**Solution:** Update the JavaScript build to:

1. Read `filters:` from ruby2js.yml
2. Dynamically import required filters
3. Pass them to the converter

```javascript
// In build.mjs (conceptual)
async function loadFilters(filterNames) {
  const filters = [];
  for (const name of filterNames) {
    const module = await import(`./filters/${name.toLowerCase()}.js`);
    filters.push(module.default || module[Object.keys(module)[0]]);
  }
  return filters;
}

const config = yaml.load(fs.readFileSync('config/ruby2js.yml'));
const filterNames = config.default?.filters || config.filters || [];
const filters = await loadFilters(filterNames);
```

### Prerequisites Checklist

| ID | Task | Estimate | Blocks |
|----|------|----------|--------|
| P1.1 | Remove hardcoded filter restriction in build.rb | 30 min | M1 |
| P1.2 | Add filter name → module resolution | 30 min | M1 |
| P2.1 | Add pnode converter to selfhost bundle | 1-2 hours | M1 |
| P2.2 | Transpile Phlex filter to JS | 1-2 hours | M1 |
| P2.3 | Transpile Stimulus filter to JS | 1-2 hours | M1 |
| P2.4 | Validate transpiled filters match Ruby output | 1 hour | M1 |
| P3 | Update ruby2js-rails package | 30 min | M1 |
| P4 | Dynamic filter loading in build.mjs | 1 hour | M1 |

**Total prerequisite work: 7-10 hours**

This is front-loaded work that must complete before M1 can begin.

---

## Demo 1: Stimulus Showcase

**Purpose:** Prove Phlex + Stimulus = React alternative

**Filters exercised:** `phlex`, `stimulus`, `esm`, `functions`

### Components

| Component | Phlex Patterns | Stimulus Patterns |
|-----------|----------------|-------------------|
| Counter | Basic div, span, button | targets, actions, state |
| Toggle | Conditional classes | classList manipulation |
| Tabs | Multiple children, active state | Multiple targets, data values |
| Modal | Backdrop, nested content | show/hide, click-outside |
| Dropdown | Positioning, menu items | Focus management, keyboard |
| Accordion | Multiple expandable sections | Multiple instances, outlets |

### Structure

```
demo/phlex-stimulus/
├── app/
│   ├── components/
│   │   ├── counter_view.rb
│   │   ├── toggle_view.rb
│   │   ├── tabs_view.rb
│   │   ├── modal_view.rb
│   │   ├── dropdown_view.rb
│   │   └── accordion_view.rb
│   └── controllers/
│       ├── counter_controller.rb
│       ├── toggle_controller.rb
│       ├── tabs_controller.rb
│       ├── modal_controller.rb
│       ├── dropdown_controller.rb
│       └── accordion_controller.rb
├── index.html
├── styles.css
└── package.json
```

### Example: Counter

**Phlex view (`counter_view.rb`):**
```ruby
class CounterView < Phlex::HTML
  def view_template
    div(data_controller: "counter", class: "counter") do
      button(data_action: "click->counter#decrement", class: "btn") { "-" }
      span(data_counter_target: "display", class: "count") { "0" }
      button(data_action: "click->counter#increment", class: "btn") { "+" }
    end
  end
end
```

**Stimulus controller (`counter_controller.rb`):**
```ruby
class CounterController < Stimulus::Controller
  def connect
    @count = 0
  end

  def increment
    @count += 1
    displayTarget.textContent = @count.to_s
  end

  def decrement
    @count -= 1
    displayTarget.textContent = @count.to_s
  end
end
```

### Example: Modal

**Phlex view (`modal_view.rb`):**
```ruby
class ModalView < Phlex::HTML
  def initialize(title:, trigger_text: "Open")
    @title = title
    @trigger_text = trigger_text
  end

  def view_template(&content)
    div(data_controller: "modal") do
      button(data_action: "click->modal#open", class: "btn") { @trigger_text }

      div(data_modal_target: "backdrop", class: "modal-backdrop hidden") do
        div(class: "modal-content", data_action: "click->modal#stopPropagation") do
          div(class: "modal-header") do
            h2 { @title }
            button(data_action: "click->modal#close", class: "modal-close") { "×" }
          end
          div(class: "modal-body", &content)
        end
      end
    end
  end
end
```

**Stimulus controller (`modal_controller.rb`):**
```ruby
class ModalController < Stimulus::Controller
  def open
    backdropTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  end

  def close
    backdropTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  end

  def stopPropagation(event)
    event.stopPropagation
  end

  def backdropClick(event)
    close if event.target == backdropTarget
  end

  def keydown(event)
    close if event.key == "Escape"
  end
end
```

### Example: Tabs

**Phlex view (`tabs_view.rb`):**
```ruby
class TabsView < Phlex::HTML
  def initialize(tabs:)
    @tabs = tabs  # [{label: "Tab 1", content: "Content 1"}, ...]
  end

  def view_template
    div(data_controller: "tabs", data_tabs_index_value: "0") do
      div(class: "tab-list", role: "tablist") do
        @tabs.each_with_index do |tab, i|
          button(
            data_tabs_target: "tab",
            data_action: "click->tabs#select",
            data_index: i,
            role: "tab",
            class: "tab-button"
          ) { tab[:label] }
        end
      end

      div(class: "tab-panels") do
        @tabs.each_with_index do |tab, i|
          div(
            data_tabs_target: "panel",
            role: "tabpanel",
            class: "tab-panel"
          ) { tab[:content] }
        end
      end
    end
  end
end
```

**Stimulus controller (`tabs_controller.rb`):**
```ruby
class TabsController < Stimulus::Controller
  def connect
    showTab(indexValue || 0)
  end

  def select(event)
    index = event.currentTarget.dataset.index.to_i
    showTab(index)
  end

  def showTab(index)
    tabTargets.each_with_index do |tab, i|
      if i == index
        tab.classList.add("active")
        tab.setAttribute("aria-selected", "true")
      else
        tab.classList.remove("active")
        tab.setAttribute("aria-selected", "false")
      end
    end

    panelTargets.each_with_index do |panel, i|
      panel.classList.toggle("hidden", i != index)
    end
  end
end
```

### Implementation Steps

1. **Setup infrastructure**
   - [ ] Create `demo/phlex-stimulus/` directory
   - [ ] Create `package.json` with `ruby2js-rails` dependency
   - [ ] Create `index.html` showcase page
   - [ ] Create basic `styles.css`

2. **Implement Counter (simplest)**
   - [ ] Write `counter_view.rb`
   - [ ] Write `counter_controller.rb`
   - [ ] Test transpilation
   - [ ] Debug any Phlex filter issues
   - [ ] Debug any Stimulus filter issues
   - [ ] Verify in browser

3. **Implement Toggle**
   - [ ] Write view and controller
   - [ ] Test classList manipulation

4. **Implement Tabs**
   - [ ] Write view and controller
   - [ ] Test values, multiple targets

5. **Implement Modal**
   - [ ] Write view and controller
   - [ ] Test event handling, keyboard support

6. **Implement Dropdown**
   - [ ] Write view and controller
   - [ ] Test click-outside, focus management

7. **Implement Accordion**
   - [ ] Write view and controller
   - [ ] Test multiple instances

8. **Self-hosting validation**
   - [ ] Ensure Phlex filter self-hosts
   - [ ] Ensure Stimulus filter self-hosts
   - [ ] Test demo runs with self-hosted transpiler

---

## Demo 2: shadcn Components

**Purpose:** Prove component libraries with variants work

**Filters exercised:** `phlex`, `stimulus` (for Dialog/Tabs), `functions`

### Components

| Component | Patterns Demonstrated |
|-----------|----------------------|
| Button | Variants (primary, secondary, destructive, outline, ghost), sizes |
| Card | Compound components (Card, CardHeader, CardTitle, CardContent, CardFooter) |
| Input | Form integration, disabled state, placeholder |
| Badge | Simple variants |
| Alert | Variants, icon slot, dismissible |
| Dialog | Portal-like behavior, Stimulus integration |
| Tabs | Compound component, Stimulus integration |

### Structure

```
demo/phlex-components/
├── app/
│   ├── components/
│   │   ├── button.rb
│   │   ├── card.rb
│   │   ├── input.rb
│   │   ├── badge.rb
│   │   ├── alert.rb
│   │   ├── dialog.rb
│   │   └── tabs.rb
│   ├── controllers/
│   │   ├── dialog_controller.rb
│   │   └── tabs_controller.rb
│   └── views/
│       └── showcase_view.rb
├── index.html
├── styles.css              # Tailwind-inspired utility classes
└── package.json
```

### Example: Button with Variants

```ruby
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

  def initialize(variant: :primary, size: :md, disabled: false, **attrs)
    @variant = variant
    @size = size
    @disabled = disabled
    @attrs = attrs
  end

  def view_template(&block)
    classes = "inline-flex items-center justify-center rounded font-medium transition-colors #{VARIANTS[@variant]} #{SIZES[@size]}"
    classes += " opacity-50 cursor-not-allowed" if @disabled

    button(class: classes, disabled: @disabled, **@attrs, &block)
  end
end
```

### Example: Card (Compound Component)

```ruby
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
  def initialize(as: :h3)
    @tag = as
  end

  def view_template(&block)
    send(@tag, class: "text-2xl font-semibold leading-none tracking-tight", &block)
  end
end

class CardDescription < Phlex::HTML
  def view_template(&block)
    p(class: "text-sm text-gray-500", &block)
  end
end

class CardContent < Phlex::HTML
  def view_template(&block)
    div(class: "p-6 pt-0", &block)
  end
end

class CardFooter < Phlex::HTML
  def view_template(&block)
    div(class: "flex items-center p-6 pt-0", &block)
  end
end
```

### Example: Showcase View

```ruby
class ShowcaseView < Phlex::HTML
  def view_template
    div(class: "container mx-auto py-10") do
      h1(class: "text-3xl font-bold mb-8") { "Component Library" }

      section(class: "mb-12") do
        h2(class: "text-xl font-semibold mb-4") { "Buttons" }
        div(class: "flex gap-4 flex-wrap") do
          render Button.new(variant: :primary) { "Primary" }
          render Button.new(variant: :secondary) { "Secondary" }
          render Button.new(variant: :destructive) { "Destructive" }
          render Button.new(variant: :outline) { "Outline" }
          render Button.new(variant: :ghost) { "Ghost" }
        end

        div(class: "flex gap-4 mt-4") do
          render Button.new(size: :sm) { "Small" }
          render Button.new(size: :md) { "Medium" }
          render Button.new(size: :lg) { "Large" }
        end
      end

      section(class: "mb-12") do
        h2(class: "text-xl font-semibold mb-4") { "Cards" }
        render Card.new do
          render CardHeader.new do
            render CardTitle.new { "Card Title" }
            render CardDescription.new { "Card description goes here." }
          end
          render CardContent.new do
            p { "Card content with some example text." }
          end
          render CardFooter.new do
            render Button.new { "Action" }
          end
        end
      end
    end
  end
end
```

### Implementation Steps

1. **Setup**
   - [ ] Create `demo/phlex-components/` directory
   - [ ] Copy infrastructure from Demo 1
   - [ ] Add Tailwind-inspired styles

2. **Implement primitives**
   - [ ] Button with variants
   - [ ] Badge
   - [ ] Input

3. **Implement compound components**
   - [ ] Card family
   - [ ] Alert

4. **Implement interactive components**
   - [ ] Dialog (reuse Stimulus controller from Demo 1)
   - [ ] Tabs (reuse Stimulus controller from Demo 1)

5. **Build showcase page**
   - [ ] ShowcaseView displaying all components
   - [ ] Interactive examples

---

## Demo 3: rubymonolith Blog

**Purpose:** Prove complete apps work

**Filters exercised:** `phlex`, `stimulus`, `esm`, `functions`, rails filters

### Architecture

Based on [rubymonolith/demo](https://github.com/rubymonolith/demo) patterns:

- Inline view classes nested in controllers
- ApplicationView base class with helpers
- Smart route helpers (`show(@post)` infers path)
- Form abstractions
- Layout composition

### Structure

```
demo/phlex-blog/
├── app/
│   ├── controllers/
│   │   ├── application_controller.rb
│   │   ├── posts_controller.rb
│   │   └── comments_controller.rb
│   ├── models/
│   │   ├── application_record.rb
│   │   ├── post.rb
│   │   └── comment.rb
│   ├── views/
│   │   ├── application_view.rb
│   │   ├── application_layout.rb
│   │   └── components/
│   │       ├── nav.rb
│   │       ├── card.rb
│   │       ├── post_form.rb
│   │       └── comment_form.rb
│   └── helpers/
│       └── route_helpers.rb
├── config/
│   ├── routes.rb
│   ├── database.yml
│   └── schema.rb
├── index.html
└── package.json
```

### Example: Controller with Inline Views

```ruby
class PostsController < ApplicationController

  class Index < ApplicationView
    attr_accessor :posts

    def title = "All Posts"

    def view_template
      h1 { title }

      @posts.each do |post|
        render Card.new do
          h2 { link_to post.title, show(post) }
          p(class: "text-gray-600") { truncate(post.body, length: 100) }
          p(class: "text-sm text-gray-400") do
            "#{time_ago(post.created_at)} ago"
          end
        end
      end

      p(class: "mt-6") do
        render Button.new { link_to "New Post", new_path(Post) }
      end
    end
  end

  class Show < ApplicationView
    attr_accessor :post

    def title = @post.title

    def view_template
      article do
        h1 { @post.title }
        p(class: "text-gray-500 mb-4") { "Posted #{time_ago(@post.created_at)} ago" }
        div(class: "prose") { @post.body }
      end

      section(class: "mt-8") do
        h2 { "Comments (#{@post.comments.length})" }

        @post.comments.each do |comment|
          render CommentCard.new(comment: comment, post: @post)
        end

        h3(class: "mt-6") { "Add a Comment" }
        render CommentForm.new(post: @post)
      end

      nav(class: "mt-8 flex gap-4") do
        link_to "Edit", edit_path(@post)
        link_to "Back to Posts", index_path(Post)
        link_to "Delete", delete_path(@post),
          data: { action: "click->confirm#show", confirm_message: "Delete this post?" }
      end
    end
  end

  class New < ApplicationView
    attr_accessor :post

    def title = "New Post"

    def view_template
      h1 { title }
      render PostForm.new(post: @post, action: create_path(Post), method: :post)
      p { link_to "Back", index_path(Post) }
    end
  end

  class Edit < ApplicationView
    attr_accessor :post

    def title = "Edit: #{@post.title}"

    def view_template
      h1 { title }
      render PostForm.new(post: @post, action: update_path(@post), method: :patch)
      p { link_to "Back", show(@post) }
    end
  end

  # Controller actions
  def index
    @posts = Post.all
    render Index.new(posts: @posts)
  end

  def show
    @post = Post.find(params[:id])
    render Show.new(post: @post)
  end

  def new
    @post = Post.new
    render New.new(post: @post)
  end

  def create
    @post = Post.new(post_params)
    if @post.save
      redirect_to show(@post)
    else
      render New.new(post: @post)
    end
  end

  def edit
    @post = Post.find(params[:id])
    render Edit.new(post: @post)
  end

  def update
    @post = Post.find(params[:id])
    if @post.update(post_params)
      redirect_to show(@post)
    else
      render Edit.new(post: @post)
    end
  end

  def destroy
    @post = Post.find(params[:id])
    @post.destroy
    redirect_to index_path(Post)
  end

  private

  def post_params
    params.require(:post).permit(:title, :body)
  end
end
```

### Example: ApplicationView

```ruby
class ApplicationView < Phlex::HTML
  include RouteHelpers

  attr_accessor :flash

  def around_template(&block)
    render ApplicationLayout.new(title: title) do
      if flash&.any?
        flash.each do |type, message|
          render Alert.new(variant: type) { message }
        end
      end
      yield
    end
  end

  def title = "Blog"

  def link_to(text, path, **attrs)
    a(href: path, **attrs) { text }
  end

  def truncate(text, length:)
    return "" unless text
    text.length > length ? "#{text[0...length]}..." : text
  end

  def time_ago(time)
    seconds = Time.now - time
    case seconds
    when 0..59 then "#{seconds.to_i}s"
    when 60..3599 then "#{(seconds / 60).to_i}m"
    when 3600..86399 then "#{(seconds / 3600).to_i}h"
    else "#{(seconds / 86400).to_i}d"
    end
  end
end
```

### Example: PostForm

```ruby
class PostForm < Phlex::HTML
  def initialize(post:, action:, method: :post)
    @post = post
    @action = action
    @method = method
  end

  def view_template
    form(action: @action, method: @method == :post ? "post" : "post") do
      input(type: "hidden", name: "_method", value: @method) if @method != :post

      if @post.errors&.any?
        render Alert.new(variant: :destructive) do
          ul do
            @post.errors.each { |e| li { e } }
          end
        end
      end

      div(class: "mb-4") do
        label(for: "title", class: "block font-medium mb-1") { "Title" }
        render Input.new(
          type: "text",
          name: "post[title]",
          id: "title",
          value: @post.title,
          required: true
        )
      end

      div(class: "mb-4") do
        label(for: "body", class: "block font-medium mb-1") { "Body" }
        textarea(
          name: "post[body]",
          id: "body",
          class: "w-full border rounded p-2 min-h-32",
          required: true
        ) { @post.body }
      end

      render Button.new(type: "submit") do
        @post.persisted? ? "Update Post" : "Create Post"
      end
    end
  end
end
```

### Implementation Steps

1. **Setup**
   - [ ] Create `demo/phlex-blog/` directory
   - [ ] Copy infrastructure from Demo 1
   - [ ] Reuse components from Demo 2 (Button, Card, Input, Alert)

2. **Core views**
   - [ ] ApplicationView with helpers
   - [ ] ApplicationLayout
   - [ ] RouteHelpers module

3. **Post views**
   - [ ] Index, Show, New, Edit inline views
   - [ ] PostForm component

4. **Comment views**
   - [ ] CommentCard component
   - [ ] CommentForm component

5. **Controller integration**
   - [ ] PostsController with actions
   - [ ] CommentsController

6. **Model integration**
   - [ ] Post model (reuse from rails demo)
   - [ ] Comment model

7. **Polish**
   - [ ] Navigation component
   - [ ] Flash messages
   - [ ] Confirmation dialog (Stimulus)

---

## Success Criteria

### Demo 1: Stimulus Showcase
- [ ] All 6 components render correctly
- [ ] All interactions work (click, keyboard)
- [ ] Both filters self-host successfully
- [ ] Demo runs in browser without Ruby

### Demo 2: shadcn Components
- [ ] All 7 components render correctly
- [ ] Variants work (visual verification)
- [ ] Compound components compose correctly
- [ ] Reuses Stimulus controllers from Demo 1

### Demo 3: rubymonolith Blog
- [ ] Full CRUD works (create, read, update, delete posts)
- [ ] Comments work
- [ ] Forms validate and show errors
- [ ] Navigation works
- [ ] Matches functionality of existing rails demo

---

## Self-Hosting Requirements

For all demos to run in browser (without Ruby), these filters must self-host:

| Filter | Status | Notes |
|--------|--------|-------|
| `phlex` | Needs validation | Core of all demos |
| `stimulus` | Needs validation | Required for interactivity |
| `esm` | Already works | Import/export |
| `functions` | Already works | Ruby → JS methods |

### Validation Process

1. Transpile filter to JS using selfhost filter
2. Run demo with transpiled filter
3. Compare output to Ruby-transpiled version
4. Fix any discrepancies

---

## Milestones

| Milestone | Deliverable | Dependencies | Estimate |
|-----------|-------------|--------------|----------|
| **M0** | **Prerequisites complete** | — | **7-10 hours** |
| M0.1 | Filter selection in ruby2js.yml works | — | 1 hour |
| M0.2 | pnode converter added to selfhost bundle | — | 1-2 hours |
| M0.3 | Phlex filter transpiled to JS | M0.2 | 1-2 hours |
| M0.4 | Stimulus filter transpiled to JS | M0.1 | 1-2 hours |
| M0.5 | Dynamic filter loading in build.mjs | M0.3, M0.4 | 1 hour |
| M0.6 | ruby2js-rails package updated | M0.5 | 30 min |
| **M1** | **Counter + Toggle working** | **M0** | **2-4 hours** |
| M2 | All 6 Stimulus components | M1 | 2-3 hours |
| M3 | Stimulus demo self-hosts | M2 | 2-6 hours |
| **M4** | **Button + Card components** | **M3** | **1 hour** |
| M5 | All shadcn components | M4 | 2 hours |
| **M6** | **Blog Index + Show views** | **M5** | **2 hours** |
| M7 | Full blog CRUD | M6 | 2-3 hours |
| M8 | All demos published | M7 | 1-2 hours |

**Total: 21-33 hours** (roughly 3-4 working days)

---

## Open Questions

1. **Tailwind vs custom CSS?**
   - shadcn uses Tailwind heavily
   - Could use Tailwind CDN or minimal custom CSS
   - Recommendation: Start with custom CSS, add Tailwind if needed

2. **Component reuse across demos?**
   - Demo 3 could import components from Demo 2
   - Or each demo could be self-contained
   - Recommendation: Self-contained for clarity, note that reuse is possible

3. **Ruby2JS-rails package updates?**
   - Demos depend on `ruby2js-rails` npm package
   - May need package updates for new filter features
   - Track needed changes during development
