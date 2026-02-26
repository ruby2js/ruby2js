---
order: 618
title: Testing
top_section: Juntos
category: juntos
---

# Testing Juntos Applications

Write tests in Ruby or JavaScript for your transpiled Juntos applications using Vitest and in-memory databases.

{% toc %}

## Why Test in JavaScript?

Juntos transpiles your Rails code to JavaScript. The `dist/` directory contains what actually runs—ES2022 classes, async/await, standard modules. Testing the transpiled output ensures you're testing what you ship.

| Approach | Pros | Cons |
|----------|------|------|
| Ruby tests via `juntos test` | Familiar Rails patterns, tests the JS that runs | Requires Juntos CLI |
| JavaScript tests (Vitest) | Direct control, no transpilation layer | Different syntax from Rails |

JavaScript testing catches transpilation issues—if Ruby2JS produces incorrect JavaScript, your tests will fail. With `juntos test`, you get both: write familiar Rails tests that are transpiled and run against the actual JavaScript output.

## Writing Tests in Ruby

The recommended approach is to write standard Rails tests that run under both `rails test` and `juntos test`. The Rails test filter transpiles Minitest assertions, controller actions, and test structure to Vitest equivalents automatically.

### Running Tests

```bash
# Run transpiled tests with Vitest
npx juntos test -d sqlite

# Same tests work with Rails
bundle exec rails test
```

### Model Tests

Standard Rails model tests transpile directly:

```ruby
class MessageTest < ActiveSupport::TestCase
  test "creates a message with valid attributes" do
    message = messages(:one)
    assert_not_nil message.id
    assert_equal "Alice", message.username
  end

  test "validates username presence" do
    message = Message.new(username: "", body: "Valid body")
    assert_not message.save
  end
end
```

### Controller Tests

Integration tests with HTTP methods, assertions, and DOM checks:

```ruby
class MessagesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get messages_url
    assert_response :success
    assert_select "h1", "Chat Room"
    assert_select "#messages" do
      assert_select "div", minimum: 1
    end
  end

  test "should create message" do
    assert_difference("Message.count") do
      post messages_url, params: { message: { username: "Carol", body: "Hello!" } }
    end
    assert_redirected_to messages_path
  end
end
```

The filter transforms `get`, `post`, etc. into controller action calls, `assert_response` and `assert_redirected_to` into `expect()` calls, and `assert_select` into DOM queries using jsdom.

### System Tests

Write Capybara-style system tests that run in jsdom without a browser. Use `visit`, `fill_in`, `click_button`, and assertion helpers — same API as Rails system tests:

```ruby
class ChatSystemTest < ApplicationSystemTestCase
  test "clears input after sending message" do
    visit messages_url
    fill_in "Your name", with: "Alice"
    fill_in "Type a message...", with: "Hello!"
    click_button "Send"
    assert_field "Type a message...", with: ""
  end

  test "creates message and displays it" do
    visit messages_url
    fill_in "Your name", with: "Alice"
    fill_in "Type a message...", with: "Hello!"
    click_button "Send"
    visit messages_url
    assert_selector "#messages", text: "Hello!"
  end
end
```

Place system tests in `test/system/`. They work under both `rails test:system` (Selenium) and `juntos test` (jsdom + fetch interceptor).

**How it works:**

- `visit messages_url` — fetches the page via the fetch interceptor (routes to your controller action), renders the HTML into `document.body`, auto-discovers `data-controller` attributes, and starts Stimulus controllers
- `fill_in "placeholder", with: "value"` — finds an input by placeholder text, label, or name, then sets its value
- `click_button "Send"` — finds the button, builds `FormData` from its parent form, submits via `fetch`, and handles Turbo Stream responses or redirects
- `assert_field`, `assert_selector`, `assert_text` — DOM assertions using `querySelector` and `textContent`
- Stimulus controllers are auto-registered from `test/setup.mjs` — `juntos test` discovers controllers in `app/javascript/controllers/` and calls `registerController()` at setup time
- DOM cleanup runs automatically after each test via `afterEach(() => cleanup())`

**Capybara methods transpiled:**

| Ruby | JavaScript |
|------|-----------|
| `visit messages_url` | `await visit(messages_path())` |
| `fill_in "Name", with: "Alice"` | `await fillIn("Name", "Alice")` |
| `click_button "Send"` | `await clickButton("Send")` |
| `assert_field "Name", with: ""` | `expect(findField("Name").value).toBe("")` |
| `assert_selector "#el", text: "Hi"` | `expect(document.querySelector("#el").textContent).toContain("Hi")` |
| `assert_text "Welcome"` | `expect(document.body.textContent).toContain("Welcome")` |
| `assert_no_selector ".error"` | `expect(document.querySelector(".error")).toBeNull()` |

### Testing Stimulus Controllers

For unit-testing individual Stimulus controller methods (rather than full user flows), use `connect_stimulus` inside an integration test:

```ruby
class MessagesControllerTest < ActionDispatch::IntegrationTest
  test "clears input after form submission" do
    skip unless defined? Document
    get messages_url
    connect_stimulus "chat", ChatController

    body_input = document.querySelector("[data-chat-target='body']")
    body_input.value = "Hello!"
    form = document.querySelector("form")
    form.dispatchEvent(Event.new("turbo:submit-end", bubbles: true))

    assert_equal "", body_input.value
  end
end
```

**How it works:**

- `skip unless defined? Document` — skips under Rails (no DOM), runs under Juntos (jsdom)
- `connect_stimulus "chat", ChatController` — renders the response HTML into `document.body`, starts a Stimulus `Application`, and registers the controller. The `@vitest-environment jsdom` directive is emitted automatically.
- `await_mutations` — yields to the event loop so Stimulus `MutationObserver` callbacks fire
- Standard DOM APIs (`querySelector`, `dispatchEvent`, `appendChild`) work in jsdom
- `vi.fn()` creates a Vitest mock function for verifying calls
- Stimulus cleanup (`Application.stop()`, clearing `document.body`) runs automatically after each test

### What Gets Transpiled

| Ruby | JavaScript |
|------|-----------|
| `skip` | `return` |
| `defined? Document` | `typeof Document !== "undefined"` |
| `connect_stimulus "chat", ChatController` | innerHTML + Application.start + register + await |
| `await_mutations` | `await new Promise(resolve => setTimeout(resolve, 0))` |
| `Event.new("turbo:submit-end", bubbles: true)` | `new Event("turbo:submit-end", {bubbles: true})` |
| `assert_equal "", input.value` | `expect(input.value).toBe("")` |
| `assert_select "h1", "text"` | DOM querySelector + expect |

## Writing Tests in JavaScript

If you prefer writing tests directly in JavaScript, or need more control over the test setup, you can write Vitest tests manually.

### Setup

Create a test directory with Vitest and better-sqlite3:

```bash
mkdir -p test/integration
cd test/integration
npm init -y
npm install --save-dev vitest better-sqlite3
```

Create `vitest.config.mjs`:

```javascript
import { defineConfig } from 'vitest/config';
import { resolve } from 'path';

export default defineConfig({
  test: {
    testTimeout: 30000,
  },
  resolve: {
    alias: {
      // Point to juntos in your built dist
      'juntos': resolve(__dirname, 'workspace/myapp/dist/node_modules/juntos')
    }
  }
});
```

Add test scripts to `package.json`:

```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest"
  }
}
```

### Project Structure

```
test/integration/
├── package.json
├── vitest.config.mjs
├── app.test.mjs          # Your tests
└── workspace/
    └── myapp/
        └── dist/         # Built Juntos app (juntos build -d sqlite -t node)
```

Build your app for testing:

```bash
cd myapp
bin/juntos build -d sqlite -t node
```

### Testing Models

#### Basic CRUD

```javascript
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DIST_DIR = join(__dirname, 'workspace/myapp/dist');

let Article, initDatabase, migrations, Application;

describe('Article Model', () => {
  beforeAll(async () => {
    // Import the database adapter
    const activeRecord = await import(join(DIST_DIR, 'lib/active_record.mjs'));
    initDatabase = activeRecord.initDatabase;

    // Import Application for migrations
    const rails = await import(join(DIST_DIR, 'lib/rails.js'));
    Application = rails.Application;

    // Import migrations
    const migrationsModule = await import(join(DIST_DIR, 'db/migrate/index.js'));
    migrations = migrationsModule.migrations;

    // Import models
    const models = await import(join(DIST_DIR, 'app/models/index.js'));
    Article = models.Article;

    // Configure application
    Application.configure({ migrations });
    Application.registerModels({ Article });
  });

  beforeEach(async () => {
    // Fresh in-memory database for each test
    await initDatabase({ database: ':memory:' });
    const adapter = await import(join(DIST_DIR, 'lib/active_record.mjs'));
    await Application.runMigrations(adapter);
  });

  it('creates an article', async () => {
    const article = await Article.create({
      title: 'Hello World',
      body: 'This is my first article.'
    });

    expect(article.id).toBeDefined();
    expect(article.title).toBe('Hello World');
  });

  it('finds an article by id', async () => {
    const created = await Article.create({ title: 'Find Me', body: 'Content' });
    const found = await Article.find(created.id);

    expect(found.title).toBe('Find Me');
  });

  it('updates an article', async () => {
    const article = await Article.create({ title: 'Original', body: 'Content' });
    await article.update({ title: 'Updated' });

    const reloaded = await Article.find(article.id);
    expect(reloaded.title).toBe('Updated');
  });

  it('destroys an article', async () => {
    const article = await Article.create({ title: 'Delete Me', body: 'Content' });
    const id = article.id;

    await article.destroy();

    const found = await Article.findBy({ id });
    expect(found).toBeNull();
  });
});
```

#### Testing Validations

```javascript
it('validates title presence', async () => {
  const article = new Article({ title: '', body: 'Some content here' });
  const saved = await article.save();

  expect(saved).toBe(false);
  expect(article.errors.title).toBeDefined();
});

it('validates body length', async () => {
  const article = new Article({ title: 'Valid Title', body: 'Short' });
  const saved = await article.save();

  expect(saved).toBe(false);
  expect(article.errors.body).toBeDefined();
});
```

#### Testing Associations

```javascript
describe('Associations', () => {
  let Comment;

  beforeAll(async () => {
    const models = await import(join(DIST_DIR, 'app/models/index.js'));
    Comment = models.Comment;
    Application.registerModels({ Article, Comment });
  });

  it('article has many comments', async () => {
    const article = await Article.create({ title: 'With Comments', body: 'Content here' });
    await Comment.create({ article_id: article.id, body: 'First comment' });
    await Comment.create({ article_id: article.id, body: 'Second comment' });

    const comments = await article.comments;
    expect(comments.length).toBe(2);
  });

  it('comment belongs to article', async () => {
    const article = await Article.create({ title: 'Parent', body: 'Content here' });
    const comment = await Comment.create({ article_id: article.id, body: 'Child' });

    const parent = await comment.article;
    expect(parent.id).toBe(article.id);
  });

  it('destroys dependent comments', async () => {
    const article = await Article.create({ title: 'Cascade', body: 'Content here' });
    await Comment.create({ article_id: article.id, body: 'Will be deleted' });

    await article.destroy();

    const orphans = await Comment.where({ article_id: article.id });
    expect(orphans.length).toBe(0);
  });
});
```

#### Testing Query Interface

```javascript
describe('Query Interface', () => {
  beforeEach(async () => {
    await Article.create({ title: 'Alpha', body: 'First article content' });
    await Article.create({ title: 'Beta', body: 'Second article content' });
    await Article.create({ title: 'Gamma', body: 'Third article content' });
  });

  it('where filters by attributes', async () => {
    const results = await Article.where({ title: 'Beta' });
    expect(results.length).toBe(1);
    expect(results[0].title).toBe('Beta');
  });

  it('order sorts results', async () => {
    const results = await Article.order({ title: 'desc' });
    expect(results[0].title).toBe('Gamma');
    expect(results[2].title).toBe('Alpha');
  });

  it('limit restricts count', async () => {
    const results = await Article.limit(2);
    expect(results.length).toBe(2);
  });

  it('first returns single record', async () => {
    const first = await Article.first();
    expect(first).toBeDefined();
    expect(first.id).toBe(1);
  });

  it('count returns total', async () => {
    const count = await Article.count();
    expect(count).toBe(3);
  });

  it('findBy returns matching record', async () => {
    const article = await Article.findBy({ title: 'Beta' });
    expect(article.title).toBe('Beta');
  });

  it('chains where, order, limit', async () => {
    await Article.create({ title: 'Alpha 2', body: 'Another alpha article' });

    const results = await Article.where({ title: 'Alpha' })
      .order({ id: 'desc' })
      .limit(1);

    expect(results.length).toBe(1);
  });
});
```

### Testing Controllers

Controllers need a mock context object simulating the request environment:

```javascript
describe('ArticlesController', () => {
  let ArticlesController;

  beforeAll(async () => {
    const ctrl = await import(join(DIST_DIR, 'app/controllers/articles_controller.js'));
    ArticlesController = ctrl.ArticlesController;
  });

  it('index returns article list', async () => {
    await Article.create({ title: 'Listed', body: 'Content for listing' });

    const context = {
      params: {},
      flash: {
        get: () => '',
        consumeNotice: () => '',
        consumeAlert: () => ''
      },
      contentFor: {}
    };

    const html = await ArticlesController.index(context);

    expect(html).toContain('Listed');
  });

  it('create adds new article', async () => {
    const context = {
      params: {},
      flash: { set: () => {} },
      contentFor: {},
      request: { headers: { accept: 'text/html' } }
    };

    const params = {
      title: 'New Article',
      body: 'Created via controller test'
    };

    await ArticlesController.create(context, params);

    const articles = await Article.all();
    expect(articles.length).toBe(1);
    expect(articles[0].title).toBe('New Article');
  });

  it('show displays single article', async () => {
    const article = await Article.create({ title: 'Show Me', body: 'Detailed content' });

    const context = {
      params: { id: article.id },
      flash: {
        get: () => '',
        consumeNotice: () => '',
        consumeAlert: () => ''
      },
      contentFor: {}
    };

    const html = await ArticlesController.show(context);

    expect(html).toContain('Show Me');
    expect(html).toContain('Detailed content');
  });
});
```

#### Testing Turbo Stream Responses

For controllers that return Turbo Streams:

```javascript
it('create returns turbo stream for turbo requests', async () => {
  const context = {
    params: {},
    flash: { set: () => {} },
    contentFor: {},
    request: {
      headers: { accept: 'text/vnd.turbo-stream.html' }
    }
  };

  const result = await ArticlesController.create(context, {
    title: 'Turbo Article',
    body: 'Content for turbo stream'
  });

  expect(result.turbo_stream).toBeDefined();
  expect(result.turbo_stream).toContain('turbo-stream');
});
```

### Testing Path Helpers

```javascript
describe('Path Helpers', () => {
  let articles_path, article_path, edit_article_path;

  beforeAll(async () => {
    const paths = await import(join(DIST_DIR, 'config/paths.js'));
    articles_path = paths.articles_path;
    article_path = paths.article_path;
    edit_article_path = paths.edit_article_path;
  });

  it('articles_path returns index path', () => {
    expect(articles_path()).toBe('/articles');
  });

  it('article_path returns show path', () => {
    expect(article_path(42)).toBe('/articles/42');
    expect(article_path({ id: 42 })).toBe('/articles/42');
  });

  it('edit_article_path returns edit path', () => {
    expect(edit_article_path(42)).toBe('/articles/42/edit');
  });

  it('nested paths work correctly', async () => {
    const paths = await import(join(DIST_DIR, 'config/paths.js'));
    const { article_comments_path } = paths;

    expect(article_comments_path(1)).toBe('/articles/1/comments');
  });
});
```

### In-Memory Database Pattern

The key pattern for fast, isolated tests:

```javascript
beforeEach(async () => {
  // Create fresh database for each test
  await initDatabase({ database: ':memory:' });

  // Re-import adapter to get fresh connection
  const adapter = await import(join(DIST_DIR, 'lib/active_record.mjs'));

  // Run migrations
  await Application.runMigrations(adapter);
});
```

Each test gets a clean slate. No cleanup needed. Tests can run in parallel without interference.

### Testing React Components

Applications using RBX files with React (like the workflow demo) need jsdom for DOM simulation:

```bash
npm install --save-dev jsdom
```

Update `vitest.config.mjs`:

```javascript
import { defineConfig } from 'vitest/config';
import { resolve } from 'path';

export default defineConfig({
  test: {
    testTimeout: 30000,
    environment: 'jsdom',  // Enable DOM simulation
    css: false,            // Mock CSS imports
  },
  resolve: {
    alias: {
      'juntos': resolve(__dirname, 'workspace/myapp/dist/node_modules/juntos'),
      // Map absolute imports used by React components
      '/lib/': resolve(__dirname, 'workspace/myapp/dist/lib') + '/',
      '/app/': resolve(__dirname, 'workspace/myapp/dist/app') + '/',
    }
  }
});
```

The `/lib/` and `/app/` aliases resolve absolute imports like `import JsonStreamProvider from '/lib/JsonStreamProvider.js'` that React components use.

#### Testing Controllers with React Views

Controllers that return React component output work the same way:

```javascript
describe('WorkflowsController', () => {
  it('show renders workflow canvas', async () => {
    const workflow = await Workflow.create({ name: 'Test Flow' });

    const context = {
      params: { id: workflow.id },
      flash: { get: () => '', consumeNotice: () => '', consumeAlert: () => '' },
      contentFor: {}
    };

    const result = await WorkflowsController.show(context, workflow.id);

    // React components return rendered output
    expect(result).toBeDefined();
  });
});
```

### Running Tests

```bash
# Run all tests
npm test

# Run specific test file
npm test -- articles.test.mjs

# Watch mode during development
npm run test:watch

# Run with verbose output
npm test -- --reporter=verbose
```

### Debugging Tests

When a test fails, check:

1. **Import paths** — Ensure DIST_DIR points to your built app
2. **Missing migrations** — Run `bin/juntos build` to regenerate `dist/`
3. **Context mocks** — Controllers expect specific context properties
4. **Async/await** — Model methods are async; don't forget `await`

Add console logging to debug:

```javascript
it('debug example', async () => {
  const article = await Article.create({ title: 'Debug', body: 'Content' });
  console.log('Created:', article);
  console.log('Errors:', article.errors);

  const all = await Article.all();
  console.log('All articles:', all);
});
```

## Next Steps

- See [Active Record](/docs/juntos/active-record) for the full query interface, validations, and callbacks
- See the [Architecture](/docs/juntos/architecture) to understand what gets generated
- Check [Demo Applications](/docs/juntos/demos/) for complete test examples
- Review the Ruby2JS [integration tests](https://github.com/ruby2js/ruby2js/tree/master/test/integration) for real-world patterns
