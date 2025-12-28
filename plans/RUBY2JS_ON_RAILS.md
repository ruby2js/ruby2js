# Ruby2JS-on-Rails: Running Rails Applications in JavaScript

## Status: Stage 2b Complete

Run Rails applications entirely in JavaScript - either in the browser (with sql.js) or Node.js. The `app/` directory feels like Rails; the runtime is JavaScript.

**Milestone:** Ruby and selfhost (JavaScript) transpilation now produce **identical output**, verified by automated diff comparison. All Rails filters work in selfhost.

## Primary Goal

**Harden Ruby2JS selfhost** by building a demanding real-world application that exercises the full transpilation pipeline.

The Ruby2JS-on-Rails demo serves as:
- A concrete, testable target that keeps us honest
- A stress test for selfhost filters (ERB, Phlex, functions, ESM)
- A source of discovered gaps that benefit all Ruby2JS users when fixed
- A compelling showcase of Ruby2JS capabilities

## Secondary Goal

Demonstrate that a Rails application can be transpiled via Ruby2JS and run without a Ruby runtime. Target: the classic Rails Getting Started blog tutorial running in a browser.

## Success Metrics

| Metric            | Description                                          |
| ----------------- | ---------------------------------------------------- |
| Selfhost coverage | Filters needed for Ruby2JS-on-Rails work in selfhost |
| Gaps fixed        | Number of Ruby2JS issues discovered and resolved     |
| Demo completeness | Blog tutorial runs in browser                        |
| Community value   | Improvements benefit all Ruby2JS users               |

## Selfhost Hardening Strategy

Building Ruby2JS-on-Rails will exercise these selfhost components:

| Component            | Current Status             | Expected Exercise                   |
| -------------------- | -------------------------- | ----------------------------------- |
| Functions filter     | ✅ Complete (212/212 tests) | Heavy - ActiveRecord patterns       |
| ERB filter           | ✅ Complete (17/17 tests)   | Full - all templates                |
| Phlex filter         | Unknown in selfhost        | Full - Stage 4                      |
| ESM filter           | ✅ Complete (36/36 tests)   | Heavy - module imports              |
| ActiveSupport filter | ✅ Complete (16/16 tests)   | Medium - `blank?`, `present?`, etc. |
| Core transpilation   | ✅ Complete                 | Heavy - classes, methods, blocks    |
| Rails filters        | ✅ Complete                 | Full - all 6 filters working        |

### Expected Gap Discovery

As we build, we'll discover gaps in:
1. **Filter edge cases** - Patterns that work in Ruby but not selfhost
2. **Method mappings** - Ruby methods needing JS equivalents
3. **Class patterns** - Inheritance, modules, concerns
4. **DSL handling** - `has_many`, `validates`, `before_action`, etc.

### Gap Resolution Workflow

```
Build Ruby2JS-on-Rails feature
        ↓
Hit selfhost gap
        ↓
Fix in Ruby2JS (filter or converter)
        ↓
Re-transpile, verify fix
        ↓
All Ruby2JS users benefit
        ↓
Continue building
```

Every gap discovered and fixed is a **primary deliverable**, not a distraction.

## Architecture

```
Rails App (Ruby)
├── app/
│   ├── models/         ← ActiveRecord classes (.rb)
│   ├── controllers/    ← ActionController classes (.rb)
│   └── views/          ← ERB templates or Phlex components
├── config/
│   └── routes.rb       ← Route definitions
└── db/
    └── schema.rb       ← Database schema

        ↓ Ruby2JS transpilation (development: browser, production: build step)

JavaScript
├── models/             ← JS classes over sql.js
├── controllers/        ← JS classes with action methods
├── views/              ← Render functions
├── router.mjs          ← URL routing
├── active_record.mjs   ← ORM implementation
└── application.mjs     ← Bootstrap/glue

        ↓ Runs in

Browser (sql.js + IndexedDB) or Node.js (sql.js + filesystem)
```

## Development vs Production Modes

Like Rails and modern Node frameworks, Ruby2JS-on-Rails supports two modes:

### Development Mode (Live Transpilation)

```
Browser loads index.html
       ↓
Load Ruby2JS + Prism WASM (~500KB)
       ↓
Fetch raw .rb/.erb files from app/
       ↓
Transpile each file via convert()
       ↓
Execute resulting JavaScript
```

**Benefits:**
- Edit Ruby, refresh browser - just like Rails development
- No build step required
- See actual Ruby source in app/ directory
- Maximum "wow factor" - Ruby running live in browser

**Trade-offs:**
- ~1-2 second startup (transpilation time)
- Larger initial download (~500KB for Ruby2JS + Prism)

### Production Mode (Pre-built Bundle)

```
Build step (npm run build)
       ↓
Walk app/ directory
       ↓
Transpile each .rb/.erb file
       ↓
Bundle into dist/app.mjs
       ↓
Browser loads pre-built bundle
```

**Benefits:**
- Fast startup (no transpilation)
- Smaller download (no Ruby2JS/Prism needed)
- Optimized for deployment

**Trade-offs:**
- Requires build step before deployment

### Mode Detection

```javascript
// application.mjs
async function boot() {
  if (await hasPrebuiltBundle()) {
    // Production: load pre-built
    await import('./dist/app.mjs');
  } else {
    // Development: live transpile
    const { convert, initPrism } = await import('./ruby2js.mjs');
    await initPrism();
    await transpileAndLoad('app/models/article.rb');
    await transpileAndLoad('app/controllers/articles_controller.rb');
    // ...
  }
}
```

### The Pitch

> "In development, edit Ruby and refresh - just like Rails.
> For production, run a build step - just like Vite.
> Same app, two modes, familiar to everyone."

## Project Location

```
ruby2js/
└── demo/
    ├── selfhost/           ← Existing selfhost demo
    └── ruby2js-on-rails/        ← This project
        ├── app/
        │   ├── models/
        │   ├── controllers/
        │   └── views/
        ├── config/
        ├── runtime/
        └── ...
```

Location within the Ruby2JS repo keeps it close to selfhost, making gap iteration fast.

## Timeline Summary

| Stage | Description                             | Status                    |
| ----- | --------------------------------------- | ------------------------- |
| 0     | Validation (de-risk assumptions)        | ✅ Complete                |
| 1     | Classic Blog (ERB) - Core Functionality | ✅ Complete                |
| 2a    | Dev Server with hot reload              | ✅ Complete                |
| 2b    | Downloadable demo tarball               | ✅ Complete                |
| 2c    | Browser live transpilation              | Ready (selfhost verified) |
| 3     | Full Rails Getting Started features     | Pending                   |
| 4     | Phlex equivalent                        | Pending                   |

## Six-Stage Plan

---

## Stage 0: Validation

**Timeline:** ~1-2 days
**Goal:** De-risk assumptions before committing to full build

### Validation Tasks

#### Selfhost Filter Verification

- [ ] ERB filter transpiles correctly in selfhost
  ```bash
  cd demo/selfhost
  # Test ERB patterns through selfhost pipeline
  ```
- [ ] Phlex filter transpiles correctly in selfhost
- [ ] ActiveSupport filter basics work (`blank?`, `present?`)

#### sql.js Prototype

- [ ] sql.js loads in browser
- [ ] Basic CRUD works (INSERT, SELECT, UPDATE, DELETE)
- [ ] Foreign key queries work (JOIN, WHERE article_id = ?)
- [ ] Prototype minimal ActiveRecord-like wrapper (~50 lines)

```javascript
// Quick validation:
const db = new SQL.Database();
db.run("CREATE TABLE articles (id INTEGER PRIMARY KEY, title TEXT)");
db.run("INSERT INTO articles (title) VALUES (?)", ["Hello"]);
const result = db.exec("SELECT * FROM articles");
// Does this feel workable?
```

#### Integration Sketch

- [ ] Sketch how controller → view → render will flow
- [ ] Identify any obvious blockers

### Stage 0 Complete When:

- [x] Confident that ERB/Phlex filters work in selfhost (or gaps identified)
- [x] Confident that sql.js meets ActiveRecord needs
- [x] No obvious blockers discovered
- [x] Ready to commit to Stage 1

### Stage 0 Outcome

| Result                  | Action                                 |
| ----------------------- | -------------------------------------- |
| All validations pass    | Proceed to Stage 1                     |
| Selfhost gaps found     | Fix gaps first (this is primary goal!) |
| sql.js limitation found | Evaluate alternatives or workarounds   |
| Blocker discovered      | Reassess plan                          |

---

## Stage 1: Classic Blog with ERB - Core Functionality

**Status:** Complete
**Goal:** Article/Comment CRUD with associations, running in browser

At the end of this stage, you can serve the app with any static server (nginx, `python -m http.server`, etc.) and it works via live transpilation with manual refresh.

### Implementation Approach

Stage 1 was implemented in two phases:

**Phase 1a: Micro-Framework Runtime**
- Built JavaScript runtime with Rails-like APIs (`ApplicationRecord`, `ApplicationController`, etc.)
- Implemented sql.js integration for SQLite in browser
- Created module-based architecture (IIFE pattern) for controllers and routes
- Built path helpers, view rendering, and form handling

**Phase 1b: Rails Filters** (see `plans/RAILS_FILTERS.md`)
- Created `rails/model` filter - transforms `has_many`, `belongs_to`, `validates`, callbacks
- Created `rails/controller` filter - transforms `before_action`, `params`, `redirect_to`
- Created `rails/routes` filter - transforms `Rails.application.routes.draw`, `resources`
- Created `rails/schema` filter - transforms `ActiveRecord::Schema.define`, `create_table`
- Created `rails/seeds` filter - auto-detects model references, generates imports

The demo now uses **idiomatic Rails syntax** in `app/` that the Rails filters transform to the micro-framework runtime. This allows writing standard Rails code that transpiles to browser-ready JavaScript.

**Phase 1c: Developer Experience - Logging & Debugging** (unplanned, emerged as killer feature)

During development, logging emerged as a surprisingly powerful feature that gives the demo a true Rails feel.

- **SQL Logging** - All database operations log to console in Rails style:
  ```
  Article Load  SELECT * FROM articles
  Article Create  INSERT INTO articles (title, body, ...) VALUES (?, ?, ...) [["title","Hello"],["body","..."]]
  ```

- **Rails.logger Support** - Created `rails/logger` filter:
  ```ruby
  Rails.logger.debug "debug message"  # → console.debug("debug message")
  Rails.logger.info "info message"    # → console.info("info message")
  Rails.logger.warn "warning!"        # → console.warn("warning!")
  Rails.logger.error "error!"         # → console.error("error!")
  ```

- **Sourcemaps** - Debug Ruby in the browser! The build script generates sourcemaps with embedded Ruby source:
  - Open DevTools → Sources → find `app/models/article.rb`
  - Set breakpoints directly in Ruby code
  - Step through Ruby source when breakpoints hit
  - See Ruby variable names and expressions

  This is a significant "wow factor" - developers debug in the language they wrote, not the transpiled output.

### Models

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  has_many :comments, dependent: :destroy
  validates :title, presence: true
  validates :body, presence: true, length: { minimum: 10 }
end

# app/models/comment.rb
class Comment < ApplicationRecord
  belongs_to :article
  validates :commenter, presence: true
  validates :body, presence: true
end
```

### Controllers

```ruby
# app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  before_action :set_article, only: [:show, :edit, :update, :destroy]

  def index
    @articles = Article.all
  end

  def show; end

  def new
    @article = Article.new
  end

  def create
    @article = Article.new(article_params)
    if @article.save
      redirect_to @article
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @article.update(article_params)
      redirect_to @article
    else
      render :edit, status: :unprocessable_entity
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

# app/controllers/comments_controller.rb
class CommentsController < ApplicationController
  def create
    @article = Article.find(params[:article_id])
    @comment = @article.comments.create(comment_params)
    redirect_to @article
  end

  def destroy
    @article = Article.find(params[:article_id])
    @comment = @article.comments.find(params[:id])
    @comment.destroy
    redirect_to @article
  end

  private

  def comment_params
    params.require(:comment).permit(:commenter, :body)
  end
end
```

### Routes

```ruby
Rails.application.routes.draw do
  root "articles#index"

  resources :articles do
    resources :comments, only: [:create, :destroy]
  end
end
```

### Views

```
app/views/
├── layouts/
│   └── application.html.erb
├── articles/
│   ├── index.html.erb
│   ├── show.html.erb
│   ├── new.html.erb
│   ├── edit.html.erb
│   └── _form.html.erb
└── comments/
    ├── _comment.html.erb
    └── _form.html.erb
```

### Schema

```ruby
create_table "articles" do |t|
  t.string "title"
  t.text "body"
  t.timestamps
end

create_table "comments" do |t|
  t.string "commenter"
  t.text "body"
  t.references "article", foreign_key: true
  t.timestamps
end
```

### Implementation Tasks

#### ActiveRecord Layer (~600-800 lines)

- [ ] Base `ApplicationRecord` class
- [ ] sql.js integration (SQLite WASM)
- [ ] Schema definition / table creation
- [ ] CRUD operations: `find`, `all`, `create`, `save`, `update`, `destroy`
- [ ] Query builder: `where`, `order`, `limit`
- [ ] Associations: `has_many`, `belongs_to`
- [ ] Association methods: `article.comments`, `comment.article`
- [ ] `dependent: :destroy` handling
- [ ] Validations: `presence`, `length`
- [ ] Dirty tracking / `changed?`
- [ ] Timestamps (`created_at`, `updated_at`)

#### Controller Layer (~200-300 lines)

- [ ] Base `ApplicationController` class
- [ ] `before_action` callbacks
- [ ] `params` object (from URL/form)
- [ ] `render` method (view rendering)
- [ ] `redirect_to` method (navigation)
- [ ] Strong parameters: `require`, `permit`
- [ ] Instance variable binding to views

#### Routing Layer (~150-200 lines)

- [ ] Route definition DSL: `resources`, `root`
- [ ] Nested resources support
- [ ] URL generation: `article_path`, `articles_path`, etc.
- [ ] Path helpers: `new_article_path`, `edit_article_path`
- [ ] Route matching from URL to controller#action
- [ ] History API integration (browser) or request handling (Node.js)

#### View Layer (~100-150 lines)

- [ ] ERB parser (JS-based, ~100-150 lines)
- [ ] ERB filter already handles compiled output
- [ ] Partial rendering (`render partial:`)
- [ ] Layout wrapping
- [ ] Instance variable access in templates
- [ ] Form helpers: `form_with`, `text_field`, `text_area`, `submit`
- [ ] Link helpers: `link_to`

#### Integration (~100 lines)

- [ ] Application bootstrap
- [ ] Load Ruby2JS + Prism WASM
- [ ] Fetch and transpile .rb/.erb files from app/
- [ ] Database initialization
- [ ] Initial page load / routing

### Deliverable

A working blog that can be served by any static file server:

```bash
$ python -m http.server 8000
# Open http://localhost:8000
# Edit app/models/article.rb
# Manually refresh browser
# See changes
```

Files:
```
blog/
├── app/                    ← Ruby source
│   ├── models/
│   ├── controllers/
│   └── views/
├── index.html              ← Entry point
├── runtime/                ← JS runtime (ActiveRecord, Router, etc.)
└── ruby2js.mjs             ← Self-hosted transpiler
```

---

## Stage 2a: Dev Server with Hot Reload

**Status:** Complete
**Goal:** Hot reload development workflow with dual transpilation backend

### Approach

A Node.js dev server that watches for file changes and triggers rebuilds. Supports two transpilation backends via command-line flag:

```bash
# Default: use Ruby for transpilation (full functionality)
npm run dev

# Selfhost: use JavaScript transpilation (for testing/iteration)
npm run dev -- --selfhost
```

This lets us iterate on selfhost support incrementally while maintaining a working dev environment.

### Two Ways to Run

| Command                     | Hot Reload | Transpilation            | Use Case         |
| --------------------------- | ---------- | ------------------------ | ---------------- |
| `npm run dev`               | ✅          | Ruby (shell to build.rb) | Full development |
| `npm run dev -- --selfhost` | ✅          | JavaScript (selfhost)    | Selfhost testing |

### Implementation Tasks

#### Dev Server (~150 lines)

- [ ] Static file server for dist/, lib/, etc.
- [ ] Proper MIME types for .js, .wasm, .html
- [ ] WebSocket server for reload notifications
- [ ] File watcher (chokidar) on app/, config/, db/ directories
- [ ] On change: rebuild → notify browser

#### Transpilation Backends

- [ ] Default: `child_process.exec('ruby scripts/build.rb')`
- [ ] `--selfhost`: JavaScript-based transpilation using selfhost ruby2js.mjs
  - Initially may not support all Rails filters
  - Serves as continuous integration test for selfhost correctness
  - Output can be compared against Ruby backend for verification

#### Browser Reload Client (~30 lines)

- [ ] WebSocket connection to dev server
- [ ] Listen for "reload" messages
- [ ] Trigger page refresh

#### npm Scripts

- [ ] `npm run dev` - Start dev server with Ruby backend
- [ ] `npm run build` - One-shot build (existing scripts/build.rb)

### Deliverables

```bash
$ npm run dev
Dev server: http://localhost:3000
Watching for changes...
Using Ruby transpilation (default)

# Edit app/models/article.rb, save
# Console: Rebuilding... done (0.3s)
# Browser auto-refreshes
```

```bash
$ npm run dev -- --selfhost
Dev server: http://localhost:3000
Watching for changes...
Using selfhost transpilation (experimental)

# Same workflow, but transpilation happens in Node.js
# Useful for testing selfhost filter coverage
```

### Selfhost Testing Workflow

The `--selfhost` flag creates a feedback loop for hardening selfhost:

1. Run `npm run dev -- --selfhost`
2. If output differs from Ruby backend, we've found a selfhost gap
3. Fix the gap in Ruby2JS filters/converter
4. Re-transpile filters to JS
5. Repeat until `--selfhost` produces identical output

### File Structure After Stage 2a

```
ruby2js-on-rails/
├── app/                    ← Ruby source
├── config/
├── db/
├── lib/                    ← JS runtime (rails.js)
├── scripts/
│   └── build.rb            ← Ruby transpilation
├── dev-server.mjs          ← Hot reload server (NEW)
├── package.json            ← npm scripts (NEW)
├── index.html              ← Entry point
└── dist/                   ← Generated (git-ignored)
```

---

## Stage 2b: Downloadable Demo Tarball

**Status:** Complete (selfhost verified)
**Goal:** Ruby-free downloadable demo with selfhost hot reload
**Prerequisite:** Rails filters working in selfhost (Stage 2a `--selfhost` mode) ✅

### Approach

Create a downloadable tarball that anyone can run without installing Ruby:

```bash
curl https://ruby2js.com/demo/ruby2js-on-rails.tar.gz | tar xz
cd ruby2js-on-rails
npm install
npm run dev
```

The tarball includes:
- Pre-built `dist/` (transpiled from Ruby source)
- Ruby source files in `app/`, `config/`, `db/` (for editing)
- Selfhost converter and filters (for hot reload transpilation)
- Modified dev-server that uses local selfhost paths

### Implementation Tasks

#### Dockerfile Addition

- [ ] Build ruby2js-on-rails demo during Docker build (`ruby scripts/build.rb`)
- [ ] Copy selfhost files into tarball (ruby2js.mjs, filters/)
- [ ] Create tarball with correct structure
- [ ] Place tarball in nginx output directory

#### Package Restructure

- [ ] Create `selfhost/` directory within ruby2js-on-rails for standalone use
- [ ] Modify dev-server.mjs paths for standalone mode (detect if selfhost is local)
- [ ] Update package.json: default `npm run dev` uses selfhost mode
- [ ] Add `npm run dev:ruby` for Ruby-based transpilation (development)

#### Tarball Contents

```
ruby2js-on-rails/
├── package.json          # Modified for selfhost-only mode
├── index.html
├── dev-server.mjs        # Hot reload server
├── app/                  # Ruby source (editable)
│   ├── models/
│   ├── controllers/
│   ├── helpers/
│   └── views/
├── config/
├── db/
├── lib/                  # JS runtime (rails.js)
├── dist/                 # Pre-built (for immediate use)
├── public/
└── selfhost/             # Bundled transpiler
    ├── ruby2js.mjs       # Main converter
    ├── filter_runtime.js
    └── filters/          # Transpiled filters
        ├── functions.js
        ├── esm.js
        ├── return.js
        └── rails/
            ├── model.js
            ├── controller.js
            ├── routes.js
            ├── schema.js
            ├── seeds.js
            └── logger.js
```

#### Documentation

- [ ] README.md explains the demo and how to edit Ruby files
- [ ] Link from ruby2js.com demo page
- [ ] Blog post announcing downloadable demo

### Success Criteria

- [ ] Tarball downloadable from ruby2js.com
- [ ] `npm install && npm run dev` works without Ruby
- [ ] Editing .rb files triggers hot reload with selfhost transpilation
- [ ] Demo fully functional (CRUD articles/comments)
- [ ] Sourcemaps work for debugging Ruby in browser

---

## Stage 2c: Browser Live Transpilation

**Status:** Ready to implement (prerequisite met)
**Goal:** True browser-based transpilation without server involvement
**Prerequisite:** Stage 2b's selfhost mode works correctly for all Rails filters ✅

### Approach

Once selfhost transpilation is proven via Stage 2a, move transpilation from Node server to browser:

1. Browser loads ruby2js.mjs + Prism WASM (~500KB)
2. Fetches raw .rb files from app/
3. Transpiles client-side
4. Executes resulting JavaScript

### Prerequisites Met

- ✅ Stage 2b's downloadable demo works (selfhost verified)
- ✅ Rails filters (Model, Controller, Routes, Schema, Seeds, Logger) work in selfhost
- ✅ Ruby and selfhost produce identical output (diff verified)

### Implementation Tasks (Future)

- [ ] Package ruby2js.mjs with Rails filters for browser
- [ ] Prism WASM initialization in browser
- [ ] Fetch .rb files and transpile on demand
- [ ] Module caching (avoid re-transpiling unchanged files)
- [ ] Dev server becomes optional (can use any static server)

### Success Criteria

- [ ] `npm run dev -- --selfhost` produces identical output to Ruby backend
- [ ] All Rails filters transpiled and working in selfhost
- [ ] Browser demo works with `python -m http.server` (no Node required)

---

## Stage 3: Full Rails Getting Started Features

**Timeline:** ~1 week
**Goal:** Feature parity with current Rails Getting Started guide

### Additional Features

| Feature         | Browser                             | Node.js        |
| --------------- | ----------------------------------- | -------------- |
| Flash messages  | ✅ Object passed to views            | ✅ Same         |
| Authentication  | localStorage session                | Cookie session |
| Callbacks       | `before_save`, `after_create`, etc. | Same           |
| Active Storage  | IndexedDB blobs                     | Filesystem     |
| Action Text     | Trix editor (npm)                   | Same           |
| Mailers         | Console stub / EmailJS              | nodemailer     |
| Background jobs | `setTimeout` / `Promise`            | Same           |
| I18n            | Lookup table + `t()` helper         | Same           |
| Caching         | Memory / localStorage               | Same           |
| Concerns        | Ruby2JS handles modules             | Same           |

### Implementation Tasks

#### Flash Messages (~50 lines)

- [ ] Flash object in controller: `flash[:notice]`, `flash[:alert]`
- [ ] Flash display in layout
- [ ] Flash clearing after display

#### Authentication (~150 lines)

- [ ] Session storage (localStorage or cookie)
- [ ] `current_user` helper
- [ ] `authenticated?` helper
- [ ] `allow_unauthenticated_access` declaration
- [ ] Login/logout actions

#### Callbacks (~100 lines)

- [ ] `before_save`, `after_save`
- [ ] `before_create`, `after_create`
- [ ] `before_update`, `after_update`
- [ ] `before_destroy`, `after_destroy`
- [ ] `after_commit` (simplified)

#### Active Storage (~200 lines)

- [ ] `has_one_attached` declaration
- [ ] File input handling
- [ ] Blob storage (IndexedDB for browser, fs for Node)
- [ ] Blob URL generation for display
- [ ] Attachment deletion

#### Action Text (~100 lines)

- [ ] `has_rich_text` declaration
- [ ] Trix editor integration
- [ ] Rich text storage (HTML in text column)
- [ ] `rich_textarea` form helper

#### Mailers (~150 lines)

- [ ] `ApplicationMailer` base class
- [ ] Mailer classes with action methods
- [ ] `mail()` method
- [ ] `deliver_now` (sync)
- [ ] `deliver_later` (async via setTimeout/Promise)
- [ ] Browser: console.log stub or EmailJS
- [ ] Node.js: nodemailer integration

#### Background Jobs (~50 lines)

- [ ] Jobs are just async functions
- [ ] `perform_later` → `setTimeout(() => perform(), 0)`
- [ ] Could use Web Workers for true parallelism (optional)

#### I18n (~100 lines)

- [ ] Translation lookup table (JSON)
- [ ] `t()` / `I18n.t()` helper
- [ ] Interpolation: `t(".title", name: @name)`
- [ ] Locale switching

### Deliverable

Two versions of the same app:
- Browser bundle (IndexedDB, stubbed mail)
- Node.js server (filesystem, real mail)

---

## Stage 4: Phlex Equivalent

**Timeline:** ~2-3 days
**Goal:** Same blog with Phlex views instead of ERB

### Phlex Filter Completion

The Phlex filter exists but needs component composition:

- [ ] `render OtherComponent.new(props)` support
- [ ] Component instances calling other components
- [ ] Passing blocks to components (slots)

### View Conversion

Convert ERB templates to Phlex components:

```ruby
# app/views/articles/index.rb (Phlex)
class Articles::Index < ApplicationView
  def initialize(articles:)
    @articles = articles
  end

  def view_template
    h1 { "Articles" }

    @articles.each do |article|
      div(class: "article") do
        h2 { link_to article.title, article_path(article) }
        p { article.body.truncate(100) }
      end
    end

    link_to "New Article", new_article_path
  end
end
```

```ruby
# app/views/articles/show.rb (Phlex)
class Articles::Show < ApplicationView
  def initialize(article:)
    @article = article
  end

  def view_template
    h1 { @article.title }
    p { @article.body }

    h2 { "Comments" }
    @article.comments.each do |comment|
      render Comments::Comment.new(comment: comment, article: @article)
    end

    render Comments::Form.new(article: @article)

    nav do
      link_to "Edit", edit_article_path(@article)
      link_to "Back", articles_path
    end
  end
end
```

### Implementation Tasks

- [ ] Finish Phlex filter component composition (~150-200 lines)
- [ ] Convert 7 ERB templates to Phlex (~1 day)
- [ ] Verify feature parity with ERB version
- [ ] Test in browser and Node.js

### Deliverable

Same blog functionality, demonstrating that the view layer is pluggable (ERB or Phlex).

---

## Component Inventory

### New JavaScript Runtime Components

| Component               | Lines (est.)   | Stage |
| ----------------------- | -------------- | ----- |
| ActiveRecord base       | 600-800        | 1a    |
| Controller base         | 200-300        | 1a    |
| Router                  | 150-200        | 1a    |
| ERB parser              | 100-150        | 1a    |
| Sourcemap generation    | 20             | 1c    |
| Dev server (hot reload) | 100            | 2     |
| Browser reload client   | 30             | 2     |
| Build script            | 100            | 2     |
| Mode detection          | 50             | 2     |
| Flash messages          | 50             | 3     |
| Authentication          | 150            | 3     |
| Callbacks               | 100            | 3     |
| Active Storage          | 200            | 3     |
| Action Text             | 100            | 3     |
| Mailers                 | 150            | 3     |
| I18n                    | 100            | 3     |
| **Total**               | **~2180-2480** |       |

### Ruby2JS Filter Work

| Filter           | Ruby Status | Selfhost Status        |
| ---------------- | ----------- | ---------------------- |
| ERB              | ✅ Complete  | ✅ Complete (17 tests)  |
| Phlex            | 90%         | Pending transpilation  |
| Functions        | ✅ Complete  | ✅ Complete (212 tests) |
| ESM              | ✅ Complete  | ✅ Complete (36 tests)  |
| ActiveSupport    | ✅ Complete  | ✅ Complete (16 tests)  |
| Return           | ✅ Complete  | ✅ Complete (25 tests)  |
| CJS              | ✅ Complete  | ✅ Complete (21 tests)  |
| Rails/Model      | ✅ Complete  | ✅ Complete (21 tests)  |
| Rails/Controller | ✅ Complete  | ✅ Complete (19 tests)  |
| Rails/Routes     | ✅ Complete  | ✅ Complete             |
| Rails/Schema     | ✅ Complete  | ✅ Complete (25 tests)  |
| Rails/Seeds      | ✅ Complete  | ✅ Complete (6 tests)   |
| Rails/Logger     | ✅ Complete  | ✅ Complete (8 tests)   |

---

## Browser vs Node.js Differences

| Aspect       | Browser                | Node.js                   |
| ------------ | ---------------------- | ------------------------- |
| Database     | sql.js (WASM)          | sql.js or better-sqlite3  |
| File storage | IndexedDB              | Filesystem                |
| Session      | localStorage           | Cookies                   |
| Mail         | Stubbed / external API | nodemailer                |
| HTTP         | History API / fetch    | http.createServer or Hono |
| Entry point  | `<script>`             | `node app.mjs`            |

The goal is **one codebase** with runtime detection for these differences.

---

## Success Criteria

Each stage has two types of success criteria: **selfhost hardening** (primary) and **demo functionality** (secondary).

### Stage 0 Complete When:

**Selfhost Hardening:**
- [x] ERB filter tested in selfhost (works or gaps identified)
- [x] Phlex filter tested in selfhost (works or gaps identified)
- [x] ActiveSupport basics tested in selfhost

**Validation:**
- [x] sql.js prototype demonstrates feasibility
- [x] No blocking issues discovered
- [x] Clear path forward for Stage 1

### Stage 1 Complete When:

**Selfhost Hardening:**
- [x] ERB filter works in selfhost
- [x] Core class/method patterns transpile correctly
- [x] Any discovered gaps are fixed in Ruby2JS

**Demo Functionality:**
- [x] Can create, read, update, delete articles
- [x] Can add and remove comments on articles
- [x] Validations prevent invalid data
- [x] Navigation works (browser back/forward)
- [x] Data persists across page reloads (IndexedDB)
- [x] Works when served by any static file server

### Stage 2a Complete When:

**Demo Functionality:**
- [x] All Stage 1 criteria
- [x] `npm run dev` starts hot reload server
- [x] Edit .rb file → rebuild triggers → browser auto-refreshes
- [x] `npm run build` works (wraps existing scripts/build.rb)
- [x] `--selfhost` flag uses JS-based transpilation

**Selfhost Testing:**
- [x] `--selfhost` mode runs without crashing
- [x] Output can be compared against Ruby backend
- [x] Ruby and selfhost produce identical output (verified by diff)

### Stage 2b Complete When:

**Prerequisite:** Stage 2a's `--selfhost` mode works for Rails filters ✅

**Selfhost Hardening:**
- [x] All Rails filters work in selfhost transpilation
- [x] Gaps discovered during testing are fixed
- [x] Ruby and selfhost produce identical output (19 files, diff verified)

**Demo Functionality:**
- [ ] Tarball downloadable from ruby2js.com/demo/ruby2js-on-rails.tar.gz
- [x] `npm install && npm run dev` works without Ruby installed (selfhost mode)
- [x] Hot reload works with selfhost transpilation
- [x] Full CRUD functionality works out of the box

### Stage 2c Complete When:

**Prerequisite:** Stage 2b's selfhost produces identical output to Ruby backend ✅

**Selfhost Hardening:**
- [x] All Rails filters (Model, Controller, Routes, Schema, Seeds, Logger) work in selfhost
- [x] ESM filter handles all module patterns needed

**Demo Functionality:**
- [ ] Browser loads ruby2js.mjs + Prism WASM
- [ ] Transpiles .rb files client-side
- [ ] Works with any static file server (no Node required)
- [ ] dist/ loads fast (no Ruby2JS/Prism overhead in production mode)

### Stage 3 Complete When:

**Selfhost Hardening:**
- [ ] ActiveSupport filter methods work in selfhost
- [ ] Callback/hook patterns transpile correctly
- [ ] Any discovered gaps are fixed in Ruby2JS

**Demo Functionality:**
- [ ] All Stage 2a criteria
- [ ] User can "log in" (session persists)
- [ ] Flash messages display and clear
- [ ] Rich text editing works (Trix)
- [ ] File attachments work
- [ ] Email "sends" (console in browser, real in Node)
- [ ] Node.js version serves HTTP

### Stage 4 Complete When:

**Selfhost Hardening:**
- [ ] Phlex filter works in selfhost
- [ ] Component composition patterns transpile correctly
- [ ] Any discovered gaps are fixed in Ruby2JS

**Demo Functionality:**
- [ ] All Stage 1-3 functionality works with Phlex views
- [ ] Phlex components can render other components
- [ ] Same demo, two view syntaxes, proven interchangeable

---

## Open Questions

1. ~~**Packaging:** Single HTML file vs. small bundle with assets?~~ **Resolved:** Both modes - development (raw files) and production (bundled)
2. **Persistence:** Auto-save to IndexedDB, or explicit "save to file"?
3. **Node.js framework:** Raw `http`, Hono, or none for v1?
4. **Testing:** Port Rails system tests, or separate JS tests?
5. **Demo hosting:** GitHub Pages? Standalone download?
6. ~~**Hot reload:** Add file watching for true Rails-like development experience?~~ **Resolved:** Stage 2a includes dev server with hot reload
7. **CI Integration:** Add ruby2js-on-rails tests to CI? (Leaning yes, decide after Stage 1)

---

## Future Possibilities

After Stage 3:

- **Oxidizer conventions** - `resources :x, from: :y`, smart link helpers
- **More associations** - `has_one`, `has_many :through`
- **Database migrations** - Schema versioning
- **Production deployment** - Cloudflare Workers, Deno Deploy
- **rubymonolith/demo** - Full port as stretch goal

### Hotwire Integration

Hotwire (Turbo + Stimulus) is a natural fit for Ruby2JS-on-Rails since it's already JavaScript-based:

**Stimulus** - Ruby2JS already has a `stimulus` filter that transforms Ruby controller classes to Stimulus-compatible JavaScript. This should work out of the box with minimal adaptation.

**Turbo Drive** - Could replace or enhance the current Router, providing:
- Automatic link interception and fetch-based navigation
- Form submission handling
- Progress bar and loading states
- Browser history management

**Turbo Frames** - Partial page updates within `<turbo-frame>` elements:
- Controllers could render individual frames
- Frame-scoped navigation without full page loads

**Turbo Streams** - Real-time DOM updates via the pattern:
```javascript
Turbo.renderStreamMessage(`
  <turbo-stream action="append" target="comments">
    <template>${commentHTML}</template>
  </turbo-stream>
`)
```

Stream actions (`append`, `prepend`, `replace`, `update`, `remove`, `before`, `after`) provide fine-grained control for CRUD operations. This pattern works well with Ruby2JS-on-Rails since we control both the "server" (in-browser controller) and client.

**Implementation approach:**
1. Import `@hotwired/turbo` from CDN or npm
2. Adapt controller `render` to optionally return Turbo Stream responses
3. Use Turbo Drive for navigation (replacing or complementing current Router)
4. Stimulus controllers remain Ruby, transpiled via existing filter

---

## References

- [Rails Getting Started Guide](https://guides.rubyonrails.org/getting_started.html)
- [sql.js](https://sql.js.org/) - SQLite compiled to WASM
- [Trix Editor](https://trix-editor.org/) - Rich text editor
- [Ruby2JS ERB Filter](../docs/src/_docs/filters/erb.md)
- [Ruby2JS Phlex Filter](../docs/src/_docs/filters/phlex.md)
