---
order: 25.5
title: Rails
top_section: Filters
category: rails
next_page_order: 26
---

The **Rails** filter transforms idiomatic Rails code into JavaScript, enabling Rails applications to run in browsers and JavaScript runtimes. It handles models, controllers, routes, database schema, seeds, and logging.

{% rendercontent "docs/note", title: "Meta-Filter" %}
The `rails` filter loads all Rails sub-filters together. For most use cases, this is what you want:

```ruby
Ruby2JS.convert(source, filters: [:rails, :esm, :functions])
```

Individual sub-filters can be loaded separately if needed (e.g., `rails/model`, `rails/controller`).
{% endrendercontent %}

## Overview

The Rails filter enables a powerful workflow: write standard Rails code that transpiles to browser-ready JavaScript. The same Ruby source can run on the server (with PostgreSQL) and in the browser (with IndexedDB).

```
app/models/article.rb     →  dist/models/article.js
app/controllers/...       →  dist/controllers/...
app/views/...html.erb     →  dist/views/...js
config/routes.rb          →  dist/routes.js
db/schema.rb              →  dist/schema.js
```

See the [Ruby2JS on Rails](https://intertwingly.net/blog/2025/12/21/Ruby2JS-on-Rails.html) blog post for a complete walkthrough.

## Models

Transforms ActiveRecord model classes with associations, validations, callbacks, and scopes.

### Associations

```ruby
class Article < ApplicationRecord
  has_many :comments, dependent: :destroy
  belongs_to :author, optional: true
end
```

```javascript
import ApplicationRecord from "./application_record.js";
import Comment from "./comment.js";
import Author from "./author.js";

export class Article extends ApplicationRecord {
  static table_name = "articles";

  get comments() {
    let _id = this.id;
    return Comment.where({article_id: _id})
  }

  get author() {
    return this._attributes["author_id"]
      ? Author.find(this._attributes["author_id"])
      : null
  }

  async destroy() {
    for (let record of await(this.comments)) {
      await record.destroy()
    };
    return await super.destroy()
  }
}
```

**Supported association options:**
- `has_many` — `:class_name`, `:foreign_key`, `:dependent`
- `belongs_to` — `:class_name`, `:foreign_key`, `:optional`
- `has_one` — `:class_name`, `:foreign_key`

### Validations

```ruby
class Article < ApplicationRecord
  validates :title, presence: true
  validates :body, length: { minimum: 10 }
  validates :status, inclusion: { in: %w[draft published] }
end
```

```javascript
export class Article extends ApplicationRecord {
  static _validations = {
    title: {presence: true},
    body: {length: {minimum: 10}},
    status: {inclusion: {in: ["draft", "published"]}}
  };
}
```

**Supported validations:** `presence`, `length`, `format`, `inclusion`, `exclusion`, `numericality`, `uniqueness`

### Callbacks

```ruby
class Article < ApplicationRecord
  before_save :normalize_title
  after_create :notify_subscribers

  private

  def normalize_title
    self.title = title.strip.titleize
  end
end
```

```javascript
export class Article extends ApplicationRecord {
  static _callbacks = {
    before_save: ["normalize_title"],
    after_create: ["notify_subscribers"]
  };

  normalize_title() {
    this.title = title.trim().titleize()
  }
}
```

**Supported callbacks:** `before_validation`, `after_validation`, `before_save`, `after_save`, `before_create`, `after_create`, `before_update`, `after_update`, `before_destroy`, `after_destroy`

### Scopes

```ruby
class Article < ApplicationRecord
  scope :published, -> { where(status: 'published') }
  scope :recent, -> { order(created_at: :desc).limit(10) }
end
```

```javascript
export class Article extends ApplicationRecord {
  static published() {
    return this.where({status: "published"})
  }

  static recent() {
    return this.order({created_at: "desc"}).limit(10)
  }
}
```

## Controllers

Transforms Rails controllers to JavaScript modules with async action functions.

```ruby
class ArticlesController < ApplicationController
  before_action :set_article, only: [:show, :edit, :update, :destroy]

  def index
    @articles = Article.all
    render 'articles/index', articles: @articles
  end

  def show
    render 'articles/show', article: @article
  end

  def create
    @article = Article.new(article_params)
    if @article.save
      redirect_to @article
    else
      render 'articles/new', article: @article
    end
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

```javascript
import Article from "../models/article.js";
import * as views from "../views/articles/index.js";

export const ArticlesController = {
  before_action: {
    set_article: ["show", "edit", "update", "destroy"]
  },

  async index() {
    let articles = await Article.all();
    return views.index({articles})
  },

  async show(id) {
    let article = await this.set_article(id);
    return views.show({article})
  },

  async create(params) {
    let article = new Article(params.article);
    if (await article.save()) {
      return {redirect_to: `/articles/${article.id}`}
    } else {
      return views.$new({article})
    }
  },

  async set_article(id) {
    return await Article.find(id)
  }
};
```

**Key transformations:**
- Controller class → exported module object
- Instance methods → async functions
- `@ivar` assignments → local variables
- `params[:id]` → function parameter
- `render` → view function call
- `redirect_to` → redirect object
- `new` action → `$new` (reserved word)

## Routes

Transforms `config/routes.rb` to a JavaScript router configuration.

```ruby
Rails.application.routes.draw do
  root 'articles#index'

  resources :articles do
    resources :comments, only: [:create, :destroy]
  end
end
```

```javascript
import { Router } from "./router.js";
import * as ArticlesController from "./controllers/articles_controller.js";
import * as CommentsController from "./controllers/comments_controller.js";

export const Routes = {
  routes: [
    {method: "GET", path: "/", action: ArticlesController.index},
    {method: "GET", path: "/articles", action: ArticlesController.index},
    {method: "GET", path: "/articles/new", action: ArticlesController.$new},
    {method: "POST", path: "/articles", action: ArticlesController.create},
    {method: "GET", path: "/articles/:id", action: ArticlesController.show},
    {method: "GET", path: "/articles/:id/edit", action: ArticlesController.edit},
    {method: "PATCH", path: "/articles/:id", action: ArticlesController.update},
    {method: "DELETE", path: "/articles/:id", action: ArticlesController.destroy},
    {method: "POST", path: "/articles/:article_id/comments", action: CommentsController.create},
    {method: "DELETE", path: "/articles/:article_id/comments/:id", action: CommentsController.destroy}
  ],

  articles_path() { return "/articles" },
  new_article_path() { return "/articles/new" },
  article_path(id) { return `/articles/${id}` },
  edit_article_path(id) { return `/articles/${id}/edit` }
};
```

**Supported route methods:** `root`, `resources`, `resource`, `get`, `post`, `patch`, `put`, `delete`, `namespace`, `scope`

**Supported options:** `:only`, `:except`, `:path`, `:as`

## Schema

Transforms `db/schema.rb` to JavaScript for IndexedDB or SQLite setup.

```ruby
ActiveRecord::Schema.define(version: 2024_01_15_000000) do
  create_table "articles", force: :cascade do |t|
    t.string "title", null: false
    t.text "body"
    t.string "status", default: "draft"
    t.timestamps
  end

  create_table "comments", force: :cascade do |t|
    t.references "article", null: false, foreign_key: true
    t.text "body"
    t.timestamps
  end
end
```

```javascript
export const Schema = {
  version: 2024_01_15_000000,

  tables: {
    articles: {
      columns: {
        id: {type: "integer", primaryKey: true, autoIncrement: true},
        title: {type: "string", null: false},
        body: {type: "text"},
        status: {type: "string", default: "draft"},
        created_at: {type: "datetime"},
        updated_at: {type: "datetime"}
      }
    },

    comments: {
      columns: {
        id: {type: "integer", primaryKey: true, autoIncrement: true},
        article_id: {type: "integer", null: false, references: "articles"},
        body: {type: "text"},
        created_at: {type: "datetime"},
        updated_at: {type: "datetime"}
      }
    }
  }
};
```

**Supported column types:** `string`, `text`, `integer`, `float`, `decimal`, `boolean`, `date`, `datetime`, `time`, `binary`, `references`

## Seeds

Transforms `db/seeds.rb` to a JavaScript module.

```ruby
Article.create!(title: "Welcome", body: "Hello, world!")
Article.create!(title: "Getting Started", body: "Let's begin...")
```

```javascript
import Article from "./models/article.js";

export async function run() {
  await Article.create({title: "Welcome", body: "Hello, world!"});
  await Article.create({title: "Getting Started", body: "Let's begin..."});
}
```

## Helpers

Transforms Rails view helpers into HTML-generating JavaScript. Use with the [ERB filter](/docs/filters/erb).

{% rendercontent "docs/note", type: "info" %}
When using both filters, `rails/helpers` must come BEFORE `erb` in the filter list for method overrides to work correctly.
{% endrendercontent %}

### Form Helpers

```ruby
# With Ruby2JS::Erubi for proper block handling
template = '<%= form_for @user do |f| %><%= f.text_field :name %><% end %>'
src = Ruby2JS::Erubi.new(template).src
Ruby2JS.convert(src, filters: [:"rails/helpers", :erb])
```

```javascript
function render({ user }) {
  let _buf = "";
  _buf += "<form data-model=\"user\">";
  _buf += "<input type=\"text\" name=\"user[name]\" id=\"user_name\">";
  _buf += "</form>";
  return _buf
}
```

**Supported form builder methods:**

| Ruby Method | HTML Output |
|-------------|-------------|
| `f.text_field :name` | `<input type="text" name="model[name]" id="model_name">` |
| `f.email_field :email` | `<input type="email" ...>` |
| `f.password_field :pass` | `<input type="password" ...>` |
| `f.hidden_field :id` | `<input type="hidden" ...>` |
| `f.text_area :body` | `<textarea name="model[body]" ...></textarea>` |
| `f.check_box :active` | `<input type="checkbox" value="1" ...>` |
| `f.radio_button :role, :admin` | `<input type="radio" value="admin" ...>` |
| `f.label :name` | `<label for="model_name">Name</label>` |
| `f.select :category` | `<select name="model[category]" ...></select>` |
| `f.submit "Save"` | `<input type="submit" value="Save">` |
| `f.button "Click"` | `<button type="submit">Click</button>` |

Additional input types: `number_field`, `tel_field`, `url_field`, `search_field`, `date_field`, `time_field`, `datetime_local_field`, `month_field`, `week_field`, `color_field`, `range_field`.

### Link Helper

```ruby
erb_src = '_buf = ::String.new; _buf << link_to("Articles", "/articles").to_s; _buf.to_s'
Ruby2JS.convert(erb_src, filters: [:"rails/helpers", :erb])
```

```javascript
function render() {
  let _buf = "";
  _buf += "<a href=\"/articles\" onclick=\"return navigate(event, '/articles')\">Articles</a>";
  return _buf
}
```

### Truncate Helper

```ruby
erb_src = '_buf = ::String.new; _buf << truncate(@body, length: 100).to_s; _buf.to_s'
Ruby2JS.convert(erb_src, filters: [:"rails/helpers", :erb])
```

```javascript
function render({ body }) {
  let _buf = "";
  _buf += truncate(body, {length: 100});
  return _buf
}
```

### Browser vs Server Target

The helpers filter detects the target environment based on the `database` option:

- **Browser databases** (dexie, indexeddb, sqljs): Generate `onclick`/`onsubmit` handlers with JavaScript navigation
- **Server databases** (better_sqlite3, pg): Generate standard `href`/`action` attributes

```ruby
# Browser target (default)
Ruby2JS.convert(src, filters: [:"rails/helpers", :erb], database: 'dexie')
# => onclick="return navigate(event, '/articles')"

# Server target
Ruby2JS.convert(src, filters: [:"rails/helpers", :erb], database: 'better_sqlite3')
# => href="/articles"
```

## Logger

Maps Rails logger calls to console methods.

```ruby
Rails.logger.debug "Processing request"
Rails.logger.info "User logged in"
Rails.logger.warn "Rate limit approaching"
Rails.logger.error "Failed to save"
```

```javascript
console.debug("Processing request");
console.info("User logged in");
console.warn("Rate limit approaching");
console.error("Failed to save");
```

## Runtime Requirements

The transpiled JavaScript requires runtime implementations of:

- **ApplicationRecord** — Base model class with `find`, `where`, `create`, `save`, `destroy`, etc.
- **ApplicationController** — Base controller with routing integration
- **Router** — URL matching and History API integration

These are provided by the [Ruby2JS on Rails demo](https://github.com/ruby2js/ruby2js/tree/master/demo/ruby2js-on-rails) runtime, which uses:

| Component | Browser | Server |
|-----------|---------|--------|
| Database | Dexie (IndexedDB) | better-sqlite3, pg |
| Router | History API | HTTP server |
| Renderer | DOM manipulation | HTML string |

## Usage with Other Filters

The Rails filter works best with these companion filters:

```ruby
Ruby2JS.convert(source, filters: [:rails, :esm, :functions, :active_support])
```

| Filter | Purpose |
|--------|---------|
| **esm** | ES module imports/exports |
| **functions** | Ruby → JS method mappings (`.each` → `for...of`, etc.) |
| **active_support** | `blank?`, `present?`, `try`, etc. |
| **erb** | ERB templates → render functions |
| **camelCase** | Convert snake_case identifiers |

## Limitations

{% rendercontent "docs/note", type: "warning", title: "Not Full Rails" %}
This filter transpiles Rails *patterns*, not the full Rails framework. Some features cannot be supported:

- **Metaprogramming** — No `method_missing`, `define_method`, `class_eval`
- **Server-only features** — Action Mailer, Action Cable (server component), Active Job (background workers)
- **Database features** — Complex SQL, migrations at runtime, database-specific functions
- **Asset pipeline** — Handled separately by your build tool
{% endrendercontent %}

The goal is enabling offline-first applications and static deployment, not replacing Rails entirely.

{% rendercontent "docs/note", extra_margin: true %}
Spec files for each sub-filter:
- [rails_model_spec.rb](https://github.com/ruby2js/ruby2js/blob/master/spec/rails_model_spec.rb)
- [rails_controller_spec.rb](https://github.com/ruby2js/ruby2js/blob/master/spec/rails_controller_spec.rb)
- [rails_routes_spec.rb](https://github.com/ruby2js/ruby2js/blob/master/spec/rails_routes_spec.rb)
- [rails_schema_spec.rb](https://github.com/ruby2js/ruby2js/blob/master/spec/rails_schema_spec.rb)
- [rails_seeds_spec.rb](https://github.com/ruby2js/ruby2js/blob/master/spec/rails_seeds_spec.rb)
- [rails_logger_spec.rb](https://github.com/ruby2js/ruby2js/blob/master/spec/rails_logger_spec.rb)
- [rails_helpers_spec.rb](https://github.com/ruby2js/ruby2js/blob/master/spec/rails_helpers_spec.rb)
{% endrendercontent %}
