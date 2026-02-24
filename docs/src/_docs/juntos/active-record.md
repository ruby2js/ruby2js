---
order: 616
title: Active Record
top_section: Juntos
category: juntos
---

# Active Record

Juntos implements an Active Record-compatible query interface that works across all database adapters. The same Ruby code runs against IndexedDB in browsers, SQLite on Node.js, or PostgreSQL on the edge.

{% toc %}

## Overview

Models in Juntos extend `ApplicationRecord` and support familiar Rails patterns:

```ruby
class Article < ApplicationRecord
  has_many :comments, dependent: :destroy
  belongs_to :author
  validates :title, presence: true
end
```

The query interface mirrors Rails:

```ruby
# Find records
article = Article.find(1)
article = Article.find_by(slug: "hello-world")

# Query with conditions
@articles = Article.where(status: "published")
                   .order(created_at: :desc)
                   .limit(10)

# Eager load associations
@articles = Article.includes(:comments).all
```

## Finders

### find(id)

Finds a record by primary key. Raises an error if not found:

```ruby
article = Article.find(1)
article = Article.find(params[:id])
```

### find_by(conditions)

Finds the first record matching conditions. Returns `nil` if not found:

```ruby
article = Article.find_by(slug: "hello-world")
article = Article.find_by(status: "published", featured: true)
```

### find_by!(conditions)

Like `find_by`, but raises an error if no record is found:

```ruby
article = Article.find_by!(slug: "hello-world")  # Error if not found
```

### find_or_create_by(attributes)

Finds the first record matching attributes, or creates one:

```ruby
tag = Tag.find_or_create_by(name: "ruby")
```

### all

Returns all records:

```ruby
articles = Article.all
```

### first / last

Returns the first or last record by primary key:

```ruby
oldest = Article.first
newest = Article.last
```

### count

Returns the number of records:

```ruby
total = Article.count
published = Article.where(status: "published").count
```

### exists?

Returns `true` if any matching records exist:

```ruby
Article.exists?(1)                           # By ID
Article.where(status: "draft").exists?       # By conditions
```

## Query Builder

Chainable methods return a `Relation` that executes when iterated or terminated:

### where(conditions)

Filters records by conditions:

```ruby
# Hash conditions
Article.where(status: "published")
Article.where(status: "published", featured: true)

# Raw SQL conditions (SQL adapters only)
Article.where("created_at > ?", 1.week.ago)
Article.where("status = ? AND priority > ?", "active", 5)
```

### where.not(conditions)

Excludes records matching conditions:

```ruby
Article.where.not(status: "draft")
Article.where(featured: true).where.not(status: "archived")
```

### or(relation)

Combines conditions with OR:

```ruby
Article.where(status: "published").or(Article.where(featured: true))
```

### order(columns)

Sorts results:

```ruby
Article.order(:created_at)                   # ASC (default)
Article.order(created_at: :desc)             # DESC
Article.order(status: :asc, created_at: :desc)  # Multiple columns
```

### limit(count) / offset(count)

Paginates results:

```ruby
Article.limit(10)                            # First 10
Article.limit(10).offset(20)                 # Records 21-30
Article.order(created_at: :desc).limit(5)    # Latest 5
```

### select(columns)

Selects specific columns:

```ruby
Article.select(:id, :title)
Article.select(:id, :title, :created_at).where(status: "published")
```

### distinct

Returns unique records:

```ruby
Article.select(:author_id).distinct
Comment.where(approved: true).distinct
```

### includes(associations)

Eager loads associations to avoid N+1 queries:

```ruby
# Single association
Article.includes(:comments).all

# Multiple associations
Article.includes(:comments, :author).all

# Then access without additional queries
articles.each do |article|
  article.comments.each { |c| puts c.body }  # No N+1
end
```

### joins(associations)

Performs INNER JOINs on associations:

```ruby
# Simple join
Article.joins(:comments).where(comments: { approved: true })

# Nested joins
Studio.joins(entries: [:lead, :follow])
```

### group(columns)

Groups results for aggregate queries:

```ruby
# Count by group
Article.group(:status).count
# => { "published" => 42, "draft" => 18 }

# Sum by group
Order.group(:status).sum(:amount)
# => { "completed" => 1500, "pending" => 300 }
```

### missing(associations)

Finds records missing an associated record (LEFT JOIN ... WHERE IS NULL):

```ruby
Article.where.missing(:comments)  # Articles with no comments
```

## Terminal Methods

These methods execute the query and return results:

### pluck(columns)

Returns an array of values for the specified columns:

```ruby
Article.pluck(:id)                           # [1, 2, 3]
Article.pluck(:id, :title)                   # [[1, "First"], [2, "Second"]]
Article.where(status: "published").pluck(:title)
```

### pick(columns)

Returns a single value (or array) from the first matching record:

```ruby
Article.where(featured: true).pick(:title)   # "Hello World"
Article.pick(:id, :title)                    # [1, "Hello World"]
```

### sole

Returns exactly one record. Raises if zero or more than one found:

```ruby
admin = User.where(role: "admin").sole  # Error if 0 or 2+ admins
```

### any?

Returns `true` if any matching records exist (alias for `exists?`):

```ruby
Article.where(status: "published").any?
```

### to_a

Executes the query and returns an array of records:

```ruby
articles = Article.where(status: "published").to_a
```

## Bulk Operations

### update_all(attributes)

Updates all matching records directly with SQL (no callbacks):

```ruby
Article.where(status: "draft").update_all(status: "archived")
User.update_all(active: false)
```

### delete_all

Deletes all matching records directly with SQL (no callbacks):

```ruby
Article.where(status: "archived").delete_all
```

### destroy_all

Loads each matching record and calls `destroy` (runs callbacks):

```ruby
Article.where(status: "archived").destroy_all
```

### destroy_by(conditions)

Finds and destroys records matching conditions:

```ruby
Article.destroy_by(status: "spam")
```

## Transactions

Wrap multiple operations in a database transaction:

```ruby
Article.transaction do
  article.update!(status: "published")
  Notification.create!(message: "New article!")
  # If either fails, both are rolled back
end
```

Raise `ActiveRecord::Rollback` to abort silently:

```ruby
Article.transaction do
  article.update!(status: "published")
  raise ActiveRecord::Rollback if some_condition?
  # Transaction is rolled back, no error raised
end
```

Transactions use real `BEGIN`/`COMMIT`/`ROLLBACK` SQL on all SQL adapters.

## Raw SQL Conditions

SQL adapters (SQLite, PostgreSQL, MySQL) support parameterized queries:

```ruby
# Single parameter
Article.where("views > ?", 100)

# Multiple parameters
Article.where("created_at BETWEEN ? AND ?", start_date, end_date)

# LIKE queries
Article.where("title LIKE ?", "%Ruby%")
```

### WHERE on Joined Tables

When using `joins`, reference columns on joined tables with a nested hash:

```ruby
Article.joins(:comments).where(comments: { approved: true })
Card.joins(:studio).where(studios: { id: studio_id, active: true })
```

**Note:** For Dexie (IndexedDB), simple conditions (`>`, `<`, `>=`, `<=`, `=`) are translated to Dexie's query API. Complex conditions fall back to JavaScript filtering after fetching.

## Associations

### has_many

Declares a one-to-many relationship:

```ruby
class Article < ApplicationRecord
  has_many :comments
  has_many :comments, dependent: :destroy    # Delete comments when article deleted
  has_many :comments, foreign_key: :post_id  # Custom foreign key
end
```

### belongs_to

Declares the inverse of has_many or has_one:

```ruby
class Comment < ApplicationRecord
  belongs_to :article
  belongs_to :article, optional: true        # Allow nil
  belongs_to :post, class_name: "Article"    # Custom class
end
```

### has_one

Declares a one-to-one relationship:

```ruby
class User < ApplicationRecord
  has_one :profile
  has_one :profile, dependent: :destroy
end
```

### has_many :through

Declares a many-to-many relationship through a join model:

```ruby
class Studio < ApplicationRecord
  has_many :studio1_pairs, class_name: "StudioPair", foreign_key: "studio2_id"
  has_many :studio1s, through: :studio1_pairs, source: :studio1, class_name: "Studio"
end
```

The `:through` option names the intermediate has_many association, `:source` identifies the foreign key on the join model (appends `_id`), and `:class_name` specifies the target model. Without `:source`, the association name is singularized (e.g., `tags` → `tag_id`).

### alias_attribute

Creates a getter/setter alias for a column, useful when a column name collides with a JavaScript built-in (e.g., `sort` vs `Array.prototype.sort`):

```ruby
class Judge < ApplicationRecord
  alias_attribute :sort_order, :sort
end
```

The database column remains unchanged — `sort_order` reads and writes the underlying `sort` column.

## CollectionProxy

Accessing a has_many association returns a `CollectionProxy` with query methods:

### size / length / count

```ruby
article.comments.size      # Synchronous when eagerly loaded
article.comments.count     # Always queries database
```

### build(attributes)

Creates a new associated record with the foreign key pre-set:

```ruby
comment = article.comments.build(body: "Great post!")
comment.article_id  # Already set to article.id
comment.save
```

### create(attributes)

Builds and saves in one step:

```ruby
article.comments.create(body: "Great post!")
```

### where / order / limit

CollectionProxy supports chainable queries:

```ruby
article.comments.where(approved: true)
article.comments.order(created_at: :desc).limit(5)
article.comments.where(approved: true).count
```

### Bulk operations

```ruby
article.comments.update_all(approved: true)
article.comments.delete_all
article.comments.destroy_all
article.comments.find_or_create_by(body: "Welcome!")
```

## Instance Methods

### new / create

```ruby
# Build without saving
article = Article.new(title: "Draft", body: "...")

# Build and save
article = Article.create(title: "Published", body: "...")

# Create with validation check
article = Article.create!(title: "")  # Raises on validation failure
```

### save / save!

Persists a new record or saves changes to an existing one:

```ruby
article = Article.new(title: "Hello")
article.save                # Returns true/false

article.title = "Updated"
article.save!               # Raises on failure
```

### update / update!

Updates attributes and saves:

```ruby
article.update(title: "New Title")
article.update!(title: "New Title")  # Raises on failure
```

### destroy / destroy!

Deletes the record from the database:

```ruby
article.destroy
article.destroy!            # Raises on failure
```

Respects `dependent: :destroy` on associations.

### reload

Refreshes attributes from the database:

```ruby
article.reload
```

### new_record? / persisted?

Check record state:

```ruby
article = Article.new
article.new_record?   # true
article.persisted?    # false

article.save
article.new_record?   # false
article.persisted?    # true
```

## Validations

Validations run before save and populate the `errors` collection:

```ruby
class Article < ApplicationRecord
  validates :title, presence: true
  validates :body, length: { minimum: 10 }
  validates :slug, uniqueness: true
  validates :status, inclusion: { in: %w[draft published archived] }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates_associated :comments
end
```

### Checking Validity

```ruby
article = Article.new(title: "")
article.valid?        # false
article.invalid?      # true
article.errors        # { title: ["can't be blank"] }
```

### Supported Validations

| Validation | Options |
|------------|---------|
| `presence` | `true` |
| `length` | `minimum`, `maximum`, `in`, `is` |
| `uniqueness` | `true`, `scope` |
| `inclusion` | `in` |
| `exclusion` | `in` |
| `format` | `with` (regex) |
| `numericality` | `only_integer`, `greater_than`, `less_than`, etc. |

## Callbacks

Callbacks execute at specific points in the record lifecycle:

```ruby
class Article < ApplicationRecord
  before_validation :normalize_title
  before_save :set_published_at
  after_create :notify_subscribers
  after_create_commit { broadcast_append_to "articles" }
  before_destroy :cleanup_attachments
end
```

### Supported Callbacks

| Callback | Timing |
|----------|--------|
| `before_validation` | Before validation runs |
| `after_validation` | After validation completes |
| `before_save` | Before insert or update |
| `after_save` | After insert or update |
| `before_create` | Before insert (new records only) |
| `after_create` | After insert |
| `before_update` | Before update (existing records only) |
| `after_update` | After update |
| `before_destroy` | Before delete |
| `after_destroy` | After delete |
| `after_create_commit` | After transaction commits (insert) |
| `after_update_commit` | After transaction commits (update) |
| `after_destroy_commit` | After transaction commits (delete) |

## Concerns

Concerns let you extract shared model behavior into reusable modules:

```ruby
# app/models/concerns/trackable.rb
module Trackable
  extend ActiveSupport::Concern

  included do
    has_many :tracks
    after_update :record_change
  end

  def record_change
    tracks.create(changed_at: Time.current)
  end
end
```

Include concerns in your models:

```ruby
class Article < ApplicationRecord
  include Trackable
  has_many :comments
end
```

Concerns transpile to **subclass factory functions** that compose via JavaScript class inheritance:

```javascript
// concerns/trackable.js
const Trackable = (Base) => class extends Base {
  static associations = { ...super.associations, tracks: { type: "has_many" } };
  static callbacks = [...super.callbacks, ["after_update", "record_change"]];

  record_change() {
    return this.tracks.create({ changed_at: new Date() });
  }
};

// article.js
class Article extends Trackable(ApplicationRecord) {
  static associations = { ...super.associations, comments: { type: "has_many" } };
}
```

Multiple concerns compose naturally — `include A; include B` becomes `extends B(A(ApplicationRecord))`, matching Ruby's method resolution order. Concerns can also include other concerns.

## Limitations

Juntos implements the most commonly used Active Record features. The following are **not yet supported**:

### Query Methods

- `having` — Filter on aggregate results
- `eager_load` / `preload` — Use `includes`
- `reorder` / `unscope` — Query modification
- `find_each` / `find_in_batches` — Batch processing

### Advanced Features

- Complex Arel predicates (e.g., `arel_table`, `Arel.sql`)
- Subqueries
- CTEs (Common Table Expressions)
- Window functions
### Associations

- `has_and_belongs_to_many` — Many-to-many without join model
- Polymorphic associations

For complex queries, consider using raw SQL conditions or implementing the logic in your controller.

## Target-Specific Behavior

The same Ruby code works across all targets, but execution differs:

### Browser Target (Dexie, sql.js)

Queries execute directly against the local database:

```
Article.where(status: "published")
    │
    └──▶ Dexie query against IndexedDB
         or sql.js query against SQLite/WASM
```

### Server Target (Node.js, Cloudflare)

Browser-side model calls become RPC requests:

```
Browser                              Server
───────                              ──────
Article.where(status: "published")
    │
    ├──▶ POST /__rpc                 ──▶ SQLite/PostgreSQL query
         X-RPC-Action: Article.where      │
         Body: { args: [...] }            │
                                          ▼
    ◀── { result: [...] }           ◀── Query results
```

See [Architecture](/docs/juntos/architecture) for details on the RPC transport, or the [Workflow Builder demo](/docs/juntos/demos/workflow-builder) for a working example.

## Next Steps

- **[Path Helpers](/docs/juntos/path-helpers)** — Server Functions-style controller access
- **[Architecture](/docs/juntos/architecture)** — How models are generated
- **[Testing](/docs/juntos/testing)** — Test your model layer
- **[Hotwire](/docs/juntos/hotwire)** — Real-time updates with `broadcast_*` callbacks
