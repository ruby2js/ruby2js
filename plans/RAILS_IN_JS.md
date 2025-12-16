# Rails-in-JS: Running Rails Applications in JavaScript

## Status: Planning

Run Rails applications entirely in JavaScript - either in the browser (with sql.js) or Node.js. The `app/` directory feels like Rails; the runtime is JavaScript.

## Primary Goal

**Harden Ruby2JS selfhost** by building a demanding real-world application that exercises the full transpilation pipeline.

The Rails-in-JS demo serves as:
- A concrete, testable target that keeps us honest
- A stress test for selfhost filters (ERB, Phlex, functions, ESM)
- A source of discovered gaps that benefit all Ruby2JS users when fixed
- A compelling showcase of Ruby2JS capabilities

## Secondary Goal

Demonstrate that a Rails application can be transpiled via Ruby2JS and run without a Ruby runtime. Target: the classic Rails Getting Started blog tutorial running in a browser.

## Success Metrics

| Metric | Description |
|--------|-------------|
| Selfhost coverage | Filters needed for Rails-in-JS work in selfhost |
| Gaps fixed | Number of Ruby2JS issues discovered and resolved |
| Demo completeness | Blog tutorial runs in browser |
| Community value | Improvements benefit all Ruby2JS users |

## Selfhost Hardening Strategy

Building Rails-in-JS will exercise these selfhost components:

| Component | Current Status | Expected Exercise |
|-----------|----------------|-------------------|
| Functions filter | 94% (190/203 tests) | Heavy - ActiveRecord patterns |
| ERB filter | Unknown in selfhost | Full - all templates |
| Phlex filter | Unknown in selfhost | Full - Stage 4 |
| ESM filter | Partial | Heavy - module imports |
| ActiveSupport filter | Unknown in selfhost | Medium - `blank?`, `present?`, etc. |
| Core transpilation | Solid | Heavy - classes, methods, blocks |

### Expected Gap Discovery

As we build, we'll discover gaps in:
1. **Filter edge cases** - Patterns that work in Ruby but not selfhost
2. **Method mappings** - Ruby methods needing JS equivalents
3. **Class patterns** - Inheritance, modules, concerns
4. **DSL handling** - `has_many`, `validates`, `before_action`, etc.

### Gap Resolution Workflow

```
Build Rails-in-JS feature
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

Like Rails and modern Node frameworks, Rails-in-JS supports two modes:

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
    └── rails-in-js/        ← This project
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

| Stage | Description | Timeline |
|-------|-------------|----------|
| 0 | Validation (de-risk assumptions) | ~1-2 days |
| 1 | Classic Blog (ERB) - Core Functionality | ~1 week |
| 2 | Developer Experience (hot reload, build) | ~3-4 days |
| 3 | Full Rails Getting Started features | ~1 week |
| 4 | Phlex equivalent | ~2-3 days |
| **Total** | | **~4 weeks** |

## Five-Stage Plan

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

- [ ] Confident that ERB/Phlex filters work in selfhost (or gaps identified)
- [ ] Confident that sql.js meets ActiveRecord needs
- [ ] No obvious blockers discovered
- [ ] Ready to commit to Stage 1

### Stage 0 Outcome

| Result | Action |
|--------|--------|
| All validations pass | Proceed to Stage 1 |
| Selfhost gaps found | Fix gaps first (this is primary goal!) |
| sql.js limitation found | Evaluate alternatives or workarounds |
| Blocker discovered | Reassess plan |

---

## Stage 1: Classic Blog with ERB - Core Functionality

**Timeline:** ~1 week
**Goal:** Article/Comment CRUD with associations, running in browser

At the end of this stage, you can serve the app with any static server (nginx, `python -m http.server`, etc.) and it works via live transpilation with manual refresh.

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

## Stage 2: Developer Experience

**Timeline:** ~3-4 days
**Goal:** Full development workflow with hot reload and production builds

### Three Ways to Run

| Command | Hot Reload | Live Transpile | Use Case |
|---------|------------|----------------|----------|
| `npm run dev` | ✅ | ✅ | Development |
| `python -m http.server` | ❌ | ✅ | Quick testing |
| `npm run build` → nginx | ❌ | ❌ | Production |

### Hot Reload Dev Server (~120 lines)

```javascript
// dev-server.mjs
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { watch } from 'chokidar';

// Static file server + WebSocket + file watcher
// When .rb/.erb changes → notify browser → auto refresh
```

### Implementation Tasks

#### Dev Server (~100 lines)

- [ ] Static file server for app/, runtime/, etc.
- [ ] Proper MIME types for .rb, .erb, .wasm
- [ ] WebSocket server for reload notifications
- [ ] File watcher (chokidar) on app/ directory
- [ ] Broadcast "reload" on .rb/.erb changes

#### Browser Reload Client (~30 lines)

- [ ] WebSocket connection to dev server
- [ ] Listen for "reload" messages
- [ ] Trigger page refresh (or smart module reload)

#### Production Build Script (~100 lines)

- [ ] `npm run build` command
- [ ] Walk app/ directory
- [ ] Transpile each .rb/.erb file
- [ ] Bundle into dist/app.mjs
- [ ] Copy runtime dependencies to dist/
- [ ] Generate dist/index.html (no Ruby2JS needed)

#### Mode Detection (~50 lines)

- [ ] Check if dist/app.mjs exists
- [ ] Production: load pre-built bundle
- [ ] Development: load Ruby2JS and transpile

### Deliverables

**Development mode (`npm run dev`):**
```bash
$ npm run dev
Dev server: http://localhost:3000
Watching app/ for changes...

# Edit app/models/article.rb, save
# Browser auto-refreshes
# See changes instantly
```

**Production mode (`npm run build`):**
```bash
$ npm run build
Transpiling app/models/article.rb
Transpiling app/models/comment.rb
...
Bundle created: dist/app.mjs (loading: 45KB)

$ npx serve dist/
# or deploy dist/ to nginx, S3, GitHub Pages
```

### File Structure After Stage 2

```
blog/
├── app/                    ← Ruby source (always present)
│   ├── models/
│   ├── controllers/
│   └── views/
├── runtime/                ← JS runtime
├── index.html              ← Entry point (detects mode)
├── ruby2js.mjs             ← Self-hosted transpiler
├── dev-server.mjs          ← Hot reload server
├── build.mjs               ← Production bundler
├── package.json            ← npm run dev, npm run build
└── dist/                   ← Generated (git-ignored)
    ├── index.html
    ├── runtime/
    └── app.mjs
```

---

## Stage 3: Full Rails Getting Started Features

**Timeline:** ~1 week
**Goal:** Feature parity with current Rails Getting Started guide

### Additional Features

| Feature | Browser | Node.js |
|---------|---------|---------|
| Flash messages | ✅ Object passed to views | ✅ Same |
| Authentication | localStorage session | Cookie session |
| Callbacks | `before_save`, `after_create`, etc. | Same |
| Active Storage | IndexedDB blobs | Filesystem |
| Action Text | Trix editor (npm) | Same |
| Mailers | Console stub / EmailJS | nodemailer |
| Background jobs | `setTimeout` / `Promise` | Same |
| I18n | Lookup table + `t()` helper | Same |
| Caching | Memory / localStorage | Same |
| Concerns | Ruby2JS handles modules | Same |

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

| Component | Lines (est.) | Stage |
|-----------|-------------|-------|
| ActiveRecord base | 600-800 | 1 |
| Controller base | 200-300 | 1 |
| Router | 150-200 | 1 |
| ERB parser | 100-150 | 1 |
| Dev server (hot reload) | 100 | 2 |
| Browser reload client | 30 | 2 |
| Build script | 100 | 2 |
| Mode detection | 50 | 2 |
| Flash messages | 50 | 3 |
| Authentication | 150 | 3 |
| Callbacks | 100 | 3 |
| Active Storage | 200 | 3 |
| Action Text | 100 | 3 |
| Mailers | 150 | 3 |
| I18n | 100 | 3 |
| **Total** | **~2180-2480** | |

### Ruby2JS Filter Work

| Filter | Status | Work Needed |
|--------|--------|-------------|
| ERB | ✅ Exists | Minimal |
| Phlex | 90% | Component composition |
| Functions | ✅ Exists | None |
| ESM | ✅ Exists | None |
| ActiveSupport | ✅ Exists | None |

---

## Browser vs Node.js Differences

| Aspect | Browser | Node.js |
|--------|---------|---------|
| Database | sql.js (WASM) | sql.js or better-sqlite3 |
| File storage | IndexedDB | Filesystem |
| Session | localStorage | Cookies |
| Mail | Stubbed / external API | nodemailer |
| HTTP | History API / fetch | http.createServer or Hono |
| Entry point | `<script>` | `node app.mjs` |

The goal is **one codebase** with runtime detection for these differences.

---

## Success Criteria

Each stage has two types of success criteria: **selfhost hardening** (primary) and **demo functionality** (secondary).

### Stage 0 Complete When:

**Selfhost Hardening:**
- [ ] ERB filter tested in selfhost (works or gaps identified)
- [ ] Phlex filter tested in selfhost (works or gaps identified)
- [ ] ActiveSupport basics tested in selfhost

**Validation:**
- [ ] sql.js prototype demonstrates feasibility
- [ ] No blocking issues discovered
- [ ] Clear path forward for Stage 1

### Stage 1 Complete When:

**Selfhost Hardening:**
- [ ] ERB filter works in selfhost
- [ ] Core class/method patterns transpile correctly
- [ ] Any discovered gaps are fixed in Ruby2JS

**Demo Functionality:**
- [ ] Can create, read, update, delete articles
- [ ] Can add and remove comments on articles
- [ ] Validations prevent invalid data
- [ ] Navigation works (browser back/forward)
- [ ] Data persists across page reloads (IndexedDB)
- [ ] Works when served by any static file server

### Stage 2 Complete When:

**Selfhost Hardening:**
- [ ] Build script uses selfhost transpilation
- [ ] ESM filter handles all module patterns needed

**Demo Functionality:**
- [ ] All Stage 1 criteria
- [ ] `npm run dev` starts hot reload server
- [ ] Edit .rb file → browser auto-refreshes → see changes
- [ ] `npm run build` produces working dist/
- [ ] dist/ works when served by any static file server
- [ ] dist/ loads fast (no Ruby2JS/Prism overhead)

### Stage 3 Complete When:

**Selfhost Hardening:**
- [ ] ActiveSupport filter methods work in selfhost
- [ ] Callback/hook patterns transpile correctly
- [ ] Any discovered gaps are fixed in Ruby2JS

**Demo Functionality:**
- [ ] All Stage 2 criteria
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
6. ~~**Hot reload:** Add file watching for true Rails-like development experience?~~ **Resolved:** Stage 2 includes dev server with hot reload
7. **CI Integration:** Add rails-in-js tests to CI? (Leaning yes, decide after Stage 1)

---

## Future Possibilities

After Stage 3:

- **Oxidizer conventions** - `resources :x, from: :y`, smart link helpers
- **Turbo/Hotwire** - Real-time updates
- **More associations** - `has_one`, `has_many :through`
- **Database migrations** - Schema versioning
- **Production deployment** - Cloudflare Workers, Deno Deploy
- **rubymonolith/demo** - Full port as stretch goal

---

## References

- [Rails Getting Started Guide](https://guides.rubyonrails.org/getting_started.html)
- [sql.js](https://sql.js.org/) - SQLite compiled to WASM
- [Trix Editor](https://trix-editor.org/) - Rich text editor
- [Ruby2JS ERB Filter](../docs/src/_docs/filters/erb.md)
- [Ruby2JS Phlex Filter](../docs/src/_docs/filters/phlex.md)
