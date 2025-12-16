# Rails Filters: Idiomatic Rails to JavaScript

## Status: Planning

## Overview

Transform idiomatic Rails code into JavaScript using AST filters. Rails developers write familiar Rails patterns; filters transform them into the proven micro-framework AST that runs in browser/Node.js.

### The Insight

We have two validated pieces:
1. **Target**: A micro-framework (modules with class methods, explicit view calls) that runs in browser
2. **Source**: Idiomatic Rails (classes with instance methods, implicit rendering, conventions)

Filters bridge the gap at the AST level. No runtime Rails - just compile-time transformation.

```
Idiomatic Rails    →    Rails Filters    →    Micro-framework AST    →    JavaScript
(familiar DX)           (compile-time)        (proven working)            (runtime)
```

### Why Filters?

1. **Proven pattern** - Ruby2JS already does this (Functions filter maps `select` → `filter`)
2. **Testable** - Each transformation is isolated and verifiable
3. **Incremental** - Build one filter at a time
4. **Composable** - Filters combine in pipeline
5. **Pitfall absorption** - Filters emit safe patterns, avoiding documented issues

## Architecture

### Filter Pipeline Order

```
Source Ruby (Rails idioms)
        ↓
[rails/controller]  ← Runs early, emits safe patterns
[rails/model]
[rails/routes]
[rails/schema]
        ↓
[functions]         ← Standard Ruby2JS filters
[esm]
[return]
        ↓
Converter           ← AST to JavaScript
        ↓
JavaScript Output
```

Rails filters run **early** in the pipeline, before Functions filter. This allows them to emit patterns that avoid known pitfalls.

### Pitfall Absorption Strategy

Rails filters transform idioms AND avoid documented transpilation issues:

| TRANSPILATION_NOTES Issue | Filter Strategy |
|---------------------------|-----------------|
| `index` → `indexOf` collision | Emit `index!` - converter drops bang, Functions ignores |
| `<<` operator not supported | Emit `push()` directly |
| `valid?` gets `.bind(this)` | Emit `is_valid` internally |
| `@attribute` shadowing | Emit `self.attribute` for parent access |
| Hash iteration `each` | Emit `Object.keys().each` pattern |
| `empty?` issues | Emit `.length == 0` |
| `class << self` not supported | Emit `def self.method` pattern |
| `chomp` no JS equivalent | Emit `gsub(/x$/, '')` |

Filters become an **abstraction layer** - Rails developers write natural Ruby, filters handle the translation to safe intermediate AST.

## Filter Specifications

---

### rails/controller

**Purpose:** Transform Rails controller classes into micro-framework modules.

#### Input (Idiomatic Rails)

```ruby
class ArticlesController < ApplicationController
  before_action :set_article, only: [:show, :edit, :update, :destroy]

  def index
    @articles = Article.all
  end

  def show
  end

  def new
    @article = Article.new
  end

  def create
    @article = Article.new(article_params)
    if @article.save
      redirect_to @article
    else
      render :new
    end
  end

  def update
    if @article.update(article_params)
      redirect_to @article
    else
      render :edit
    end
  end

  def destroy
    @article.destroy
    redirect_to articles_path
  end

  private

  def set_article
    @article = Article.find(params[:id])
  end

  def article_params
    params.require(:article).permit(:title, :body)
  end
end
```

#### Output (Micro-framework AST equivalent)

```ruby
export module ArticlesController
  def self.index!
    articles = Article.all
    ArticleViews.index!({ articles: articles })
  end

  def self.show(id)
    article = Article.find(id)
    ArticleViews.show({ article: article })
  end

  def self.new_form
    article = { errors: [] }
    ArticleViews.new_article({ article: article })
  end

  def self.create(params)
    article = Article.create(params)
    if article.id
      { redirect: "/articles/#{article.id}" }
    else
      { html: ArticleViews.new_article({ article: article }) }
    end
  end

  def self.update(id, params)
    article = Article.find(id)
    Object.keys(params).each { |k| article[k] = params[k] }
    if article.save
      { redirect: "/articles/#{id}" }
    else
      { html: ArticleViews.edit({ article: article }) }
    end
  end

  def self.destroy(id)
    article = Article.find(id)
    article.destroy
    { redirect: "/articles" }
  end
end
```

#### Transformations

| Rails Pattern | Micro-framework Output |
|---------------|----------------------|
| `class XController < ApplicationController` | `export module XController` |
| `def action` (instance method) | `def self.action` (class method) |
| `def index` | `def self.index!` (bang avoids Functions filter) |
| `@articles = ...` | `articles = ...` (collect ivars for view params) |
| Implicit render (no render call) | Explicit `XViews.action({ ivars })` |
| `render :action` | `XViews.action({ ivars })` |
| `redirect_to @article` | `{ redirect: "/articles/#{article.id}" }` |
| `redirect_to articles_path` | `{ redirect: "/articles" }` |
| `params[:id]` | Method parameter `id` |
| `params.require(:x).permit(:a, :b)` | Direct params hash access |
| `before_action :method, only: [...]` | Inline method call at start of actions |
| Private methods | Removed or inlined |

#### Detection

Filter activates when it sees:
- Class inheriting from `ApplicationController` or `*Controller < *`
- Class name ending in `Controller`

---

### rails/model

**Purpose:** Transform ActiveRecord model DSL into micro-framework patterns.

#### Input (Idiomatic Rails)

```ruby
class Article < ApplicationRecord
  has_many :comments, dependent: :destroy
  belongs_to :author, optional: true

  validates :title, presence: true
  validates :body, presence: true, length: { minimum: 10 }

  before_save :normalize_title
  after_create :notify_subscribers

  scope :published, -> { where(status: 'published') }
  scope :recent, -> { order(created_at: :desc).limit(10) }

  private

  def normalize_title
    self.title = title.strip.titleize
  end
end
```

#### Output (Micro-framework AST equivalent)

```ruby
export class Article < ApplicationRecord
  def self.table_name
    'articles'
  end

  # has_many :comments, dependent: :destroy
  def comments
    Comment.where({ article_id: self.id })
  end

  def destroy
    self.comments.each { |c| c.destroy }
    super.destroy
  end

  # belongs_to :author
  def author
    Author.find(self.author_id) rescue nil
  end

  # validates
  def validate
    validates_presence_of('title')
    validates_presence_of('body')
    validates_length_of('body', { minimum: 10 })
  end

  # before_save callback
  def before_save
    normalize_title
  end

  # after_create callback
  def after_create
    notify_subscribers
  end

  # scope :published
  def self.published
    self.where({ status: 'published' })
  end

  # scope :recent
  def self.recent
    self.order({ created_at: 'desc' }).limit(10)
  end

  def normalize_title
    self.title = self.title.strip
  end

  # Attribute accessors
  def title
    self.attributes['title']
  end

  def title=(value)
    self.attributes['title'] = value
  end

  # ... other attributes
end
```

#### Transformations

| Rails Pattern | Micro-framework Output |
|---------------|----------------------|
| `class X < ApplicationRecord` | `export class X < ApplicationRecord` |
| `has_many :comments` | `def comments; Comment.where({...}); end` |
| `has_many :x, dependent: :destroy` | Override `destroy` to cascade |
| `belongs_to :author` | `def author; Author.find(self.author_id); end` |
| `validates :x, presence: true` | `validates_presence_of('x')` in `validate` method |
| `validates :x, length: {...}` | `validates_length_of('x', {...})` |
| `before_save :method` | Call method in `before_save` hook |
| `after_create :method` | Call method in `after_create` hook |
| `scope :name, -> { query }` | `def self.name; query; end` |

#### Detection

Filter activates when it sees:
- Class inheriting from `ApplicationRecord`
- Presence of `has_many`, `belongs_to`, `validates`, `scope` calls

---

### rails/routes

**Purpose:** Transform Rails route DSL into route definitions.

#### Input (Idiomatic Rails)

```ruby
Rails.application.routes.draw do
  root "articles#index"

  resources :articles do
    resources :comments, only: [:create, :destroy]
  end

  get 'about', to: 'pages#about'
  post 'contact', to: 'pages#contact'
end
```

#### Output (Micro-framework AST equivalent)

```ruby
export module Routes
  def self.routes
    [
      { path: '/', controller: 'ArticlesController', action: 'index!' },
      { path: '/articles', controller: 'ArticlesController', action: 'index!', method: 'GET' },
      { path: '/articles/new', controller: 'ArticlesController', action: 'new_form', method: 'GET' },
      { path: '/articles/:id', controller: 'ArticlesController', action: 'show', method: 'GET' },
      { path: '/articles/:id/edit', controller: 'ArticlesController', action: 'edit', method: 'GET' },
      { path: '/articles', controller: 'ArticlesController', action: 'create', method: 'POST' },
      { path: '/articles/:id', controller: 'ArticlesController', action: 'update', method: 'PATCH' },
      { path: '/articles/:id', controller: 'ArticlesController', action: 'destroy', method: 'DELETE' },
      { path: '/articles/:article_id/comments', controller: 'CommentsController', action: 'create', method: 'POST' },
      { path: '/articles/:article_id/comments/:id', controller: 'CommentsController', action: 'destroy', method: 'DELETE' },
      { path: '/about', controller: 'PagesController', action: 'about', method: 'GET' },
      { path: '/contact', controller: 'PagesController', action: 'contact', method: 'POST' }
    ]
  end

  # Path helpers
  def self.root_path
    '/'
  end

  def self.articles_path
    '/articles'
  end

  def self.article_path(article)
    "/articles/#{extract_id(article)}"
  end

  def self.new_article_path
    '/articles/new'
  end

  def self.edit_article_path(article)
    "/articles/#{extract_id(article)}/edit"
  end

  def self.article_comments_path(article)
    "/articles/#{extract_id(article)}/comments"
  end

  def self.extract_id(obj)
    (obj && obj.id) || obj
  end
end
```

#### Transformations

| Rails Pattern | Micro-framework Output |
|---------------|----------------------|
| `Rails.application.routes.draw do` | `export module Routes` |
| `root "x#y"` | Route entry + `root_path` helper |
| `resources :articles` | 7 RESTful route entries + path helpers |
| `resources :x, only: [...]` | Subset of routes |
| Nested `resources` | Prefixed paths with parent param |
| `get 'path', to: 'c#a'` | Single route entry |
| `post`, `patch`, `delete` | Route with method |

#### Detection

Filter activates when it sees:
- `Rails.application.routes.draw` block
- Or file named `routes.rb` in config/

---

### rails/schema

**Purpose:** Transform ActiveRecord schema DSL into SQL.

#### Input (Idiomatic Rails)

```ruby
ActiveRecord::Schema.define do
  create_table "articles" do |t|
    t.string "title", null: false
    t.text "body"
    t.integer "author_id"
    t.string "status", default: "draft"
    t.timestamps
  end

  create_table "comments" do |t|
    t.references "article", foreign_key: true
    t.string "commenter"
    t.text "body"
    t.timestamps
  end

  add_index "articles", ["author_id"]
  add_index "articles", ["status", "created_at"]
end
```

#### Output (Micro-framework AST equivalent)

```ruby
export module Schema
  def self.create_tables(db)
    db.run(%{
      CREATE TABLE IF NOT EXISTS articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT,
        author_id INTEGER,
        status TEXT DEFAULT 'draft',
        created_at TEXT,
        updated_at TEXT
      )
    })

    db.run(%{
      CREATE TABLE IF NOT EXISTS comments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        article_id INTEGER NOT NULL,
        commenter TEXT,
        body TEXT,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (article_id) REFERENCES articles(id)
      )
    })

    db.run(%{ CREATE INDEX IF NOT EXISTS idx_articles_author_id ON articles(author_id) })
    db.run(%{ CREATE INDEX IF NOT EXISTS idx_articles_status_created ON articles(status, created_at) })
  end
end
```

#### Transformations

| Rails Pattern | SQL Output |
|---------------|------------|
| `create_table "x"` | `CREATE TABLE IF NOT EXISTS x` |
| `t.string "col"` | `col TEXT` |
| `t.text "col"` | `col TEXT` |
| `t.integer "col"` | `col INTEGER` |
| `t.boolean "col"` | `col INTEGER` (0/1) |
| `t.datetime "col"` | `col TEXT` (ISO format) |
| `t.timestamps` | `created_at TEXT, updated_at TEXT` |
| `null: false` | `NOT NULL` |
| `default: value` | `DEFAULT 'value'` |
| `t.references "x"` | `x_id INTEGER, FOREIGN KEY` |
| `add_index "t", ["cols"]` | `CREATE INDEX` |

#### Detection

Filter activates when it sees:
- `ActiveRecord::Schema.define` block
- Or file named `schema.rb` in db/ or config/

---

### rails/erb (existing)

The ERB filter already exists and handles template transpilation. It transforms ERB buffer patterns into render functions.

**Enhancement needed:** Accept instance variables and generate proper destructured parameters matching controller output.

### View Strategy: ERB (and Phlex) Only

The current demo supports two view approaches:
1. **Ruby Module views** - Explicit modules with methods returning HTML strings
2. **ERB templates** - Standard `.html.erb` files transpiled to render functions

With Rails filters in place, **Ruby Module views become an implementation detail**:

| Layer | Developer Writes | Filter Produces |
|-------|------------------|-----------------|
| Controllers | Rails classes | Module with class methods |
| Views | ERB templates | Render functions |
| Models | ActiveRecord DSL | ApplicationRecord subclass |

The Ruby Module approach was valuable for:
- Proving the micro-framework works
- Documenting the compilation target
- Understanding generated AST

Going forward:
- **ERB** is the primary view format (familiar to Rails developers)
- **Phlex** will be added as an alternative (Stage 4)
- **Ruby Module views** are removed from the demo UI - they're what gets generated, not written

The demo toggle changes from "Ruby Module / ERB" to "ERB / Phlex" (once Phlex is implemented).

---

## Filter Interaction

### Naming Conventions

Filters need to agree on naming:

| Concept | Convention |
|---------|------------|
| Controller module | `{Resource}Controller` |
| View module | `{Resource}Views` |
| Model class | `{Resource}` (singular) |
| Table name | `{resources}` (plural) |
| Path helpers | `{resource}_path`, `{resources}_path` |

### View Discovery

Controller filter needs to know view naming:
1. Controller `ArticlesController` → Views `ArticleViews`
2. Action `index` → View method `index!` (with bang to avoid collision)
3. Action `new` → View method `new_article` (convention for `new` reserved word)

### Parameter Passing

Controllers collect instance variables and pass to views:
```ruby
# Controller emits:
ArticleViews.show({ article: article, comments: comments })

# View expects (ERB filter generates):
function render({ article, comments }) { ... }
```

---

## Testing Strategy

### Unit Tests (per filter)

Each filter has isolated tests:

```ruby
describe Ruby2JS::Filter::Rails::Controller do
  def to_js(source)
    Ruby2JS.convert(source, filters: [Ruby2JS::Filter::Rails::Controller])
  end

  it "converts instance methods to class methods" do
    source = <<~RUBY
      class ArticlesController < ApplicationController
        def index
          @articles = Article.all
        end
      end
    RUBY

    result = to_js(source)
    expect(result).to include('def self.index!')
    expect(result).to include('ArticleViews.index!')
  end

  it "transforms redirect_to" do
    # ...
  end
end
```

### Integration Tests

Full pipeline tests with all Rails filters:

```ruby
describe "Rails filter pipeline" do
  def to_js(source)
    Ruby2JS.convert(source, filters: [
      Ruby2JS::Filter::Rails::Controller,
      Ruby2JS::Filter::Rails::Model,
      Ruby2JS::Filter::Functions,
      Ruby2JS::Filter::ESM,
      Ruby2JS::Filter::Return
    ])
  end

  it "produces working controller JavaScript" do
    # Full controller → JS → eval → works
  end
end
```

### Demo Tests

The Rails-in-JS demo serves as an integration test:
- Write idiomatic Rails
- Apply filters
- Run in browser
- Verify CRUD works

---

## Delivery Order

### Phase 1: rails/controller (highest value)

The controller filter provides the most visible Rails experience improvement.

**Tasks:**
1. Basic class → module transformation
2. Instance method → class method
3. Instance variable collection
4. Implicit view call injection
5. `redirect_to` transformation
6. `render` transformation
7. `params` transformation
8. `before_action` support
9. Private method handling

**Deliverable:** Write idiomatic Rails controllers, get working JavaScript.

### Phase 2: rails/model

Model DSL support for associations and validations.

**Tasks:**
1. `has_many` transformation
2. `belongs_to` transformation
3. `dependent: :destroy` support
4. `validates` DSL transformation
5. Callback support (`before_save`, etc.)
6. `scope` transformation

**Deliverable:** Write idiomatic Rails models, get working JavaScript.

### Phase 3: rails/routes

Route DSL for path helpers and route definitions.

**Tasks:**
1. `resources` expansion
2. Nested resources
3. Path helper generation
4. Custom routes (`get`, `post`, etc.)
5. `root` route

**Deliverable:** Write idiomatic `routes.rb`, get working router.

### Phase 4: rails/schema

Schema DSL for database setup.

**Tasks:**
1. `create_table` transformation
2. Column type mapping
3. `timestamps` support
4. `references` and foreign keys
5. Index creation

**Deliverable:** Write idiomatic `schema.rb`, get working database setup.

---

## Success Criteria

### Phase 1 Complete When:

- [ ] Controller filter transforms idiomatic Rails controller
- [ ] Instance variables automatically passed to views
- [ ] `redirect_to` produces correct output
- [ ] `before_action` works for listed actions
- [ ] Demo works with idiomatic controller (no manual micro-framework code)

### Phase 2 Complete When:

- [ ] Model filter transforms `has_many`, `belongs_to`
- [ ] `validates` DSL produces working validations
- [ ] Callbacks execute at correct times
- [ ] Scopes produce chainable queries
- [ ] Demo models are idiomatic Rails

### Phase 3 Complete When:

- [ ] `resources :x` generates all 7 RESTful routes
- [ ] Nested resources work
- [ ] Path helpers are generated and usable
- [ ] Demo routes.rb is idiomatic Rails

### Phase 4 Complete When:

- [ ] `create_table` generates valid SQL
- [ ] All common column types supported
- [ ] Demo schema.rb is idiomatic Rails

### Overall Success:

The Rails-in-JS demo can be rewritten using **idiomatic Rails patterns** (as shown in the original RAILS_IN_JS.md plan Stage 1), and the filters transform it to working JavaScript.

A Rails developer should look at the code and say "that's just Rails."

---

## Open Questions

1. **Filter registration:** Separate gem? Part of core Ruby2JS? Opt-in?
2. **Error messages:** How to report when Rails patterns can't be transformed?
3. **Partial support:** Which Rails features are out of scope?
4. **View helper methods:** `link_to`, `form_with` - filter or runtime?
5. **Testing Rails code:** Can we run the same tests in Ruby and JS?

---

## References

- [RAILS_IN_JS.md](./RAILS_IN_JS.md) - Original demo plan with idiomatic Rails examples
- [TRANSPILATION_NOTES.md](../demo/rails-in-js/TRANSPILATION_NOTES.md) - Documented pitfalls to absorb
- [Ruby2JS Filters Documentation](https://www.ruby2js.com/docs/filters)
- [Rails Getting Started Guide](https://guides.rubyonrails.org/getting_started.html)
