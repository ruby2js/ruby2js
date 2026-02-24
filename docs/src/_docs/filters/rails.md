---
order: 380
title: Rails
top_section: Filters
category: rails
---

The **Rails** filter transforms idiomatic Rails code into JavaScript, enabling Rails applications to run in browsers and JavaScript runtimes. It handles models, controllers, routes, migrations, seeds, and logging.

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
db/migrate/*.rb           →  dist/db/migrate/*.js
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

### Nested Attributes

```ruby
class Billable < ApplicationRecord
  has_many :questions, dependent: :destroy
  accepts_nested_attributes_for :questions, allow_destroy: true,
    reject_if: proc { |attrs| attrs['question_text'].blank? }
end
```

```javascript
export class Billable extends ApplicationRecord {
  // ... association getter/setter ...

  set questions_attributes(value) {
    if (!this._pending_nested_attributes) this._pending_nested_attributes = {};
    this._pending_nested_attributes.questions = value
  }
};

Billable.accepts_nested_attributes_for("questions", {
  allow_destroy: true,
  reject_if(attrs) { return !attrs.question_text }
});
```

The setter stores incoming nested attribute data for processing during `save()`. After the parent record is persisted, the adapter's `_processNestedAttributes()` method iterates through the pending data, creating, updating, or destroying nested records as appropriate.

**Supported options:** `allow_destroy`, `reject_if`

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
  before_save() {
    this.normalize_title()
  }

  after_create() {
    this.notify_subscribers()
  }

  normalize_title() {
    this.title = title.trim().titleize()
  }
}
```

**Supported callbacks:** `before_validation`, `after_validation`, `before_save`, `after_save`, `before_create`, `after_create`, `before_update`, `after_update`, `before_destroy`, `after_destroy`, `after_commit`, `after_create_commit`, `after_update_commit`, `after_destroy_commit`, `after_save_commit`

{% rendercontent "docs/note", type: "info", title: "Method vs Getter Handling" %}
The model filter intelligently determines whether a `def` should become a JavaScript method (with parentheses) or a getter:

- **Methods**: `validate`, callback invokers (`before_save`, `after_create`, etc.), and callback implementation methods are always generated as methods since they're called by the framework
- **Getters**: Simple property accessors without arguments default to getters

This ensures proper `this.methodName()` call semantics for lifecycle methods while keeping property access clean for simple accessors.
{% endrendercontent %}

### Turbo Streams Broadcasting

The `broadcasts_to` macro provides a declarative way to broadcast model changes to subscribed clients. It automatically generates `after_create_commit`, `after_update_commit`, and `after_destroy_commit` callbacks.

```ruby
class Message < ApplicationRecord
  broadcasts_to -> { "chat_room" }
end
```

```javascript
import { ApplicationRecord } from "./application_record.js";
import { BroadcastChannel } from "../../lib/rails.js";

export class Message extends ApplicationRecord {
};
Message.table_name = "messages";

Message.after_create_commit($record => (
  BroadcastChannel.broadcast("chat_room",
    `<turbo-stream action="append" target="${"messages"}">
      <template>${$record.toHTML()}</template>
    </turbo-stream>`)
));

Message.after_update_commit($record => (
  BroadcastChannel.broadcast("chat_room",
    `<turbo-stream action="replace" target="${`message_${$record.id}`}">
      <template>${$record.toHTML()}</template>
    </turbo-stream>`)
));

Message.after_destroy_commit($record => (
  BroadcastChannel.broadcast("chat_room",
    `<turbo-stream action="remove" target="${`message_${$record.id}`}">
    </turbo-stream>`)
));
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `inserts_by:` | Insert position for new records: `:append` or `:prepend` | `:append` |
| `target:` | DOM element ID for append/prepend operations | Pluralized model name |

**Examples:**

```ruby
# Prepend new messages (newest first)
broadcasts_to -> { "chat_room" }, inserts_by: :prepend

# Custom target element
broadcasts_to -> { "chat_room" }, target: "chat_messages"

# Dynamic stream name using record attributes
broadcasts_to -> { "article_#{article_id}_comments" }
```

**Generated callbacks:**

| Callback | Action | Target |
|----------|--------|--------|
| `after_create_commit` | `append` or `prepend` (based on `inserts_by:`) | Custom target or pluralized model name |
| `after_update_commit` | `replace` | `dom_id` of record (e.g., `message_123`) |
| `after_destroy_commit` | `remove` | `dom_id` of record |

{% rendercontent "docs/note", type: "info", title: "Explicit Callbacks Still Supported" %}
For more control, you can still use explicit `broadcast_*_to` methods in callbacks:

```ruby
class Message < ApplicationRecord
  after_create_commit do
    broadcast_append_to "chat_room", target: "messages", partial: "messages/message"
  end
end
```

See the [Turbo filter](/docs/filters/turbo) for more broadcast methods.
{% endrendercontent %}

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

Rails `arel_table[:column]` references in scopes are simplified to column name strings, which is useful when a column name conflicts with a SQL keyword:

```ruby
class Category < ApplicationRecord
  scope :ordered, -> { order(arel_table[:order]) }
end
```

```javascript
export class Category extends ApplicationRecord {
  static ordered() {
    return this.order("order")
  }
}
```

### Normalizations

Rails `normalizes` declarations generate setter methods that apply the normalization lambda:

```ruby
class Studio < ApplicationRecord
  normalizes :name, with: -> name { name.strip }
end
```

```javascript
export class Studio extends ApplicationRecord {
  set name(value) {
    this.attributes.name = (name => name.trim())(value)
  }
}
```

### Enums

Rails `enum` declarations are transpiled to instance predicate methods, static scope methods, and a frozen values constant.

```ruby
class Export < ApplicationRecord
  enum :status, %w[drafted published].index_by(&:itself), default: :pending
end
```

```javascript
export class Export extends ApplicationRecord {
  drafted() { return this.status === "drafted" }
  static drafted() { return this.where({status: "drafted"}) }

  published() { return this.status === "published" }
  static published() { return this.where({status: "published"}) }
};

Export.statuses = Object.freeze({
  drafted: "drafted",
  published: "published"
})
```

**Value types:**

| Ruby Form | Values | Comparison |
|-----------|--------|------------|
| `%w[...].index_by(&:itself)` | Strings | `this.status === "drafted"` |
| `%i[...].index_by(&:itself)` | Strings | `this.role === "owner"` |
| `%i[pending processing]` | Integers | `this.status === 0` |
| `%w[sign_in sign_up]` | Integers | `this.purpose === 0` |

**Options:**

| Option | Example | Effect |
|--------|---------|--------|
| `prefix: :for` | `enum :purpose, ..., prefix: :for` | Methods named `for_sign_in`, `for_sign_up` |
| `prefix: true` | `enum :status, ..., prefix: true` | Methods named `status_drafted`, `status_published` |
| `scopes: false` | `enum :role, ..., scopes: false` | Only instance predicates, no static scope methods |
| `default:` | `enum :status, ..., default: :pending` | Stored for reference (DB-level concern) |

**Inline `?` and `!` transforms:**

Within the model class, enum predicate and mutator calls are inlined:

```ruby
class Export < ApplicationRecord
  enum :status, %w[drafted published].index_by(&:itself)

  def done?
    published?
  end

  def finish
    published!
  end
end
```

```javascript
export class Export extends ApplicationRecord {
  done() { return this.status === "published" }     // published? inlined
  get finish() { return this.update({status: "published"}) }  // published! inlined
  // ... generated predicates and scopes
}
```

If a method with the same name as an enum value is explicitly defined in the class, the generated predicate is skipped for that value (the user-defined method takes precedence).

### URL Helpers

`include Rails.application.routes.url_helpers` is recognized and stripped from the class body. An import for `polymorphic_url` and `polymorphic_path` is generated instead, providing URL resolution from model instances at runtime.

```ruby
class Webhook::Delivery < ApplicationRecord
  include Rails.application.routes.url_helpers

  def deliver
    url = polymorphic_url(event.eventable)
  end
end
```

```javascript
import { polymorphic_url, polymorphic_path } from "juntos:url-helpers";

export class Delivery extends ApplicationRecord {
  async deliver() {
    let url = polymorphic_url(await this.event().eventable())
  }
}
```

`polymorphic_url(record)` resolves a model instance to its URL path using `constructor.tableName` and `id` (e.g., `"/cards/42"`). Arrays produce nested paths: `polymorphic_url([board, card])` → `"/boards/1/cards/2"`.

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

### Format Negotiation (respond_to)

Controllers can respond to multiple formats using `respond_to`:

```ruby
class ArticlesController < ApplicationController
  def index
    @articles = Article.all

    respond_to do |format|
      format.html
      format.json { render json: @articles }
    end
  end
end
```

```javascript
export const ArticlesController = {
  async index(context) {
    let articles = await Article.all();

    if (context.request.headers.accept?.includes("application/json")) {
      return {json: articles}
    } else {
      return ArticleViews.index({$context: context, articles})
    }
  }
};
```

**Supported formats:**

| Format | Accept Header | Response |
|--------|---------------|----------|
| `format.html` | `text/html` | View render (default) |
| `format.json` | `application/json` | `{json: data}` wrapper |
| `format.turbo_stream` | `text/vnd.turbo-stream.html` | Turbo Stream actions |

JSON responses are wrapped in `{json: ...}` for the runtime to handle serialization. For JSON-only endpoints:

```ruby
respond_to do |format|
  format.json { render json: @articles }
end
```

This generates an Accept header check and returns the JSON wrapper directly.

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
  ]
};
```

**Supported route methods:** `root`, `resources`, `resource`, `get`, `post`, `patch`, `put`, `delete`, `namespace`, `scope`

**Supported options:** `:only`, `:except`, `:path`, `:as`

### Path Helpers with HTTP Methods

Path helpers are generated in a separate `config/paths.js` file. They return callable objects with HTTP methods:

```javascript
// config/paths.js
import { createPathHelper } from 'juntos/path_helper.mjs';

export function articles_path() {
  return createPathHelper('/articles');
}

export function article_path(article) {
  return createPathHelper(`/articles/${extract_id(article)}`);
}
```

Usage in views:

```ruby
# GET request - params become query string
articles_path.get()                      # GET /articles.json
articles_path.get(page: 2)               # GET /articles.json?page=2

# POST request - params become JSON body
articles_path.post(article: { title: 'New' })  # POST /articles.json

# PATCH/DELETE requests
article_path(1).patch(article: { title: 'Updated' })  # PATCH /articles/1.json
article_path(1).delete                   # DELETE /articles/1.json
```

All methods return `Response` objects. Default format is JSON; use `format: 'html'` for HTML responses. CSRF tokens are included automatically for mutating requests.

See [Path Helpers](/docs/juntos/path-helpers) for complete documentation.

## Migration

Transforms Rails migration files (`db/migrate/*.rb`) to JavaScript modules. Each migration becomes a module with an async `up()` function that creates or modifies database tables.

```ruby
# db/migrate/20241231120000_create_articles.rb
class CreateArticles < ActiveRecord::Migration[7.1]
  def change
    create_table :articles do |t|
      t.string :title, null: false
      t.text :body
      t.string :status, default: "draft"
      t.timestamps
    end

    add_index :articles, :status
  end
end
```

```javascript
import { createTable, addIndex } from "../../lib/active_record.mjs";

export const migration = {
  up: async () => {
    await createTable("articles", [
      {name: "id", type: "integer", primaryKey: true, autoIncrement: true},
      {name: "title", type: "string", null: false},
      {name: "body", type: "text"},
      {name: "status", type: "string", default: "draft"},
      {name: "created_at", type: "datetime"},
      {name: "updated_at", type: "datetime"}
    ]);
    await addIndex("articles", ["status"])
  },

  tableSchemas: {
    articles: "++id, title, body, status, created_at, updated_at"
  }
};
```

**Migration Features:**

- **Version tracking** — Migrations are tracked in a `schema_migrations` table, ensuring each migration runs only once
- **Dexie support** — The `tableSchemas` property provides IndexedDB schema strings for Dexie adapter
- **DDL functions** — Uses abstract DDL functions (`createTable`, `addIndex`, `addColumn`, `removeColumn`, `dropTable`) that are implemented by each database adapter

**Supported migration methods:**

| Ruby Method                      | JavaScript Function                |
| -------------------------------- | ---------------------------------- |
| `create_table :name`             | `createTable("name", columns)`     |
| `add_index :table, :column`      | `addIndex("table", ["column"])`    |
| `add_column :table, :col, :type` | `addColumn("table", "col", type)`  |
| `remove_column :table, :col`     | `removeColumn("table", "col")`     |
| `drop_table :name`               | `dropTable("name")`                |

**Supported column types:** `string`, `text`, `integer`, `bigint`, `float`, `decimal`, `boolean`, `date`, `datetime`, `time`, `timestamp`, `binary`, `json`, `jsonb`, `references`

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

**Form with URL:**

`form_with` can specify an explicit URL instead of a model:

```erb
<%= form_with url: "/photos", method: :post, class: "my-form" do |f| %>
  <%= f.text_field :caption %>
  <%= f.submit "Save" %>
<% end %>
```

```javascript
_buf += "<form class=\"my-form\" action=\"/photos\" method=\"post\">";
```

You can also use path helpers:

```erb
<%= form_with url: photos_path, method: :post do |f| %>
  <%= f.text_field :caption %>
<% end %>
```

HTTP method overrides (`:patch`, `:delete`) add a hidden `_method` field:

```erb
<%= form_with url: "/photos/1", method: :delete do |f| %>
  <%= f.submit "Delete" %>
<% end %>
```

```javascript
_buf += "<form action=\"/photos/1\" method=\"post\">";
_buf += "<input type=\"hidden\" name=\"_method\" value=\"delete\">";
```

**Form with class and data attributes:**

Both `form_for` and `form_with` accept `class:` and `data:` options:

```erb
<%= form_with model: @article, class: "contents space-y-4", data: { turbo_frame: "modal" } do |form| %>
  <%= form.text_field :title, class: "input w-full" %>
  <%= form.submit "Save", class: "btn btn-primary" %>
<% end %>
```

**Supported form builder methods:**

| Ruby Method                    | HTML Output                                                                          |
| ------------------------------ | ------------------------------------------------------------------------------------ |
| `f.text_field :name`           | `<input type="text" name="model[name]" id="model_name" value="${model.name ?? ''}">` |
| `f.email_field :email`         | `<input type="email" ... value="${model.email ?? ''}">`                              |
| `f.password_field :pass`       | `<input type="password" ... value="${model.pass ?? ''}">`                            |
| `f.hidden_field :id`           | `<input type="hidden" ... value="${model.id ?? ''}">`                                |
| `f.text_area :body`            | `<textarea name="model[body]" ...>${model.body ?? ''}</textarea>`                    |
| `f.check_box :active`          | `<input type="checkbox" value="1" ...>`                                              |
| `f.radio_button :role, :admin` | `<input type="radio" value="admin" ...>`                                             |
| `f.file_field :avatar`         | `<input type="file" name="model[avatar]" ...>`                                       |
| `f.label :name`                | `<label for="model_name">Name</label>`                                               |
| `f.select :category`           | `<select name="model[category]" ...></select>`                                       |
| `f.collection_select :person`  | `<select name="model[person]" ...></select>`                                         |
| `f.rich_text_area :body`       | `<textarea name="model[body]" ...>${model.body ?? ''}</textarea>`                    |
| `f.submit "Save"`              | `<input type="submit" value="Save">`                                                 |
| `f.button "Click"`             | `<button type="submit">Click</button>`                                               |
| `f.fields_for :items`          | Loop over nested association with nested form builder                                |

Additional input types: `number_field`, `tel_field`, `url_field`, `search_field`, `date_field`, `time_field`, `datetime_local_field`, `month_field`, `week_field`, `color_field`, `range_field`.

Field names accept both symbols and strings: `f.text_field :name` and `f.text_field "name"` produce the same output. Labels also support dynamic expressions: `f.label(@event.open? ? :open : :closed)` generates a `<label>` with the evaluated expression as content.

**HTML attributes on form fields:**

Form builder methods accept standard HTML attributes:

```erb
<%= f.text_field :title, class: "input-lg", id: "article-title", placeholder: "Enter title" %>
<%= f.text_area :body, rows: 4, class: "w-full", required: true %>
<%= f.submit "Save", class: "btn btn-primary" %>
<%= f.label :title, class: "font-bold" %>
```

| Attribute      | Example                              | Description           |
| -------------- | ------------------------------------ | --------------------- |
| `class:`       | `class: "form-control"`              | CSS classes           |
| `id:`          | `id: "custom-id"`                    | Custom element ID     |
| `style:`       | `style: "width: 100%"`               | Inline styles         |
| `placeholder:` | `placeholder: "Enter value"`         | Placeholder text      |
| `required:`    | `required: true`                     | Required field        |
| `disabled:`    | `disabled: true`                     | Disabled field        |
| `readonly:`    | `readonly: true`                     | Read-only field       |
| `autofocus:`   | `autofocus: true`                    | Auto-focus on load    |
| `rows:`        | `rows: 4`                            | Textarea rows         |
| `cols:`        | `cols: 40`                           | Textarea columns      |
| `min:`/`max:`  | `min: 0, max: 100`                   | Number field range    |
| `step:`        | `step: 0.01`                         | Number field step     |

**Conditional classes (Tailwind patterns):**

For Tailwind CSS and similar frameworks, you can use array syntax with conditional hashes:

```erb
<%= f.text_field :title, class: ["input", "w-full", {"border-red-500": @article.errors[:title].any?}] %>
```

This generates a runtime expression that evaluates the condition:

```javascript
`<input class="${"input w-full" + (article.errors.title.any() ? " border-red-500" : "")}" ...>`
```

Multiple conditions are supported:

```erb
<%= f.text_field :email, class: ["input", {"border-red-500": has_error, "opacity-50": disabled}] %>
```

{% rendercontent "docs/note", type: "info" %}
Form fields automatically include the model's current value, enabling edit forms to display existing data without additional code.
{% endrendercontent %}

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

**Link to model objects:**

`link_to` accepts model objects and generates the appropriate path:

```erb
<%= link_to "Show", @article %>
<%= link_to "Show", article %>  <%# local variable from loop %>
```

Both generate: `<a href="/articles/${article.id}" onclick="...">Show</a>`

**Link with class attribute:**

```erb
<%= link_to "Show", @article, class: "btn btn-primary" %>
<%= link_to "Edit", edit_article_path(@article), class: "text-blue-500 hover:underline" %>
```

Conditional classes work the same as form fields:

```erb
<%= link_to "Edit", edit_path, class: ["btn", {"opacity-50": disabled}] %>
```

### Button Helper

`button_to` generates delete buttons with confirmation dialogs:

```erb
<%= button_to "Delete", @article, method: :delete, data: { turbo_confirm: "Are you sure?" } %>
```

```javascript
// Browser target
_buf += `<form style="display:inline"><button type="button" onclick="if(confirm('Are you sure?')) { routes.article.delete(${article.id}) }">Delete</button></form>`;

// Server target
_buf += `<form method="post" action="/articles/${article.id}"><input type="hidden" name="_method" value="delete"><button type="submit" data-confirm="Are you sure?">Delete</button></form>`;
```

**Button with class attributes:**

```erb
<%= button_to "Delete", @article, method: :delete, class: "btn-danger text-white", form_class: "inline-block" %>
```

| Option        | Description                                      |
| ------------- | ------------------------------------------------ |
| `class:`      | CSS classes for the button element               |
| `form_class:` | CSS classes for the wrapping form element        |
| `data: { turbo_confirm: "..." }` | Confirmation dialog message    |

When `form_class:` is provided, the default `style="display:inline"` is omitted, allowing full control over form styling.

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

- **Browser databases** (dexie, indexeddb, sqljs, pglite): Generate `onclick`/`onsubmit` handlers with JavaScript navigation
- **Server databases** (better_sqlite3, pg, mysql2, d1): Generate standard `href`/`action` attributes

```ruby
# Browser target (default)
Ruby2JS.convert(src, filters: [:"rails/helpers", :erb], database: 'dexie')
# => onclick="return navigate(event, '/articles')"

# Server target (Node.js)
Ruby2JS.convert(src, filters: [:"rails/helpers", :erb], database: 'better_sqlite3')
# => href="/articles"

# Server target (Cloudflare Workers)
Ruby2JS.convert(src, filters: [:"rails/helpers", :erb], database: 'd1')
# => href="/articles"
```

### Validation Error Display

When a controller action fails validation and calls `render :new` or `render :edit`, the model with its validation errors is automatically passed to the view. Standard Rails error display patterns work:

```erb
<% if @article.errors && @article.errors.length > 0 %>
  <div class="errors">
    <ul>
      <% @article.errors.each do |error| %>
        <li><%= error %></li>
      <% end %>
    </ul>
  </div>
<% end %>

<%= form_for @article do |f| %>
  <%= f.text_field :title %>
  <%= f.text_area :body %>
  <%= f.submit %>
<% end %>
```

The controller remains idiomatic Rails:

```ruby
def create
  @article = Article.new(article_params)
  if @article.save
    redirect_to @article
  else
    render :new  # Re-renders with @article.errors populated
  end
end
```

The transpiled controller returns the rendered view directly when validation fails, ensuring the model's error state is preserved.

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

| Component | Browser               | Server (Node/Bun/Deno)     | Edge (Cloudflare) |
| --------- | --------------------- | -------------------------- | ----------------- |
| Database  | Dexie, sql.js, PGLite | better-sqlite3, pg, mysql2 | D1                |
| Router    | History API           | HTTP server                | Fetch handler     |
| Renderer  | DOM manipulation      | HTML string                | HTML string       |

## Usage with Other Filters

The Rails filter works best with these companion filters:

```ruby
Ruby2JS.convert(source, filters: [:rails, :esm, :functions, :active_support])
```

| Filter             | Purpose                                                |
| ------------------ | ------------------------------------------------------ |
| **esm**            | ES module imports/exports                              |
| **functions**      | Ruby → JS method mappings (`.each` → `for...of`, etc.) |
| **active_support** | `blank?`, `present?`, `try`, etc.                      |
| **erb**            | ERB templates → render functions                       |
| **camelCase**      | Convert snake_case identifiers                         |

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
- [rails_enum_spec.rb](https://github.com/ruby2js/ruby2js/blob/master/spec/rails_enum_spec.rb)
- [rails_controller_spec.rb](https://github.com/ruby2js/ruby2js/blob/master/spec/rails_controller_spec.rb)
- [rails_routes_spec.rb](https://github.com/ruby2js/ruby2js/blob/master/spec/rails_routes_spec.rb)
- [rails_migration_spec.rb](https://github.com/ruby2js/ruby2js/blob/master/spec/rails_migration_spec.rb)
- [rails_seeds_spec.rb](https://github.com/ruby2js/ruby2js/blob/master/spec/rails_seeds_spec.rb)
- [rails_logger_spec.rb](https://github.com/ruby2js/ruby2js/blob/master/spec/rails_logger_spec.rb)
- [rails_helpers_spec.rb](https://github.com/ruby2js/ruby2js/blob/master/spec/rails_helpers_spec.rb)
{% endrendercontent %}
