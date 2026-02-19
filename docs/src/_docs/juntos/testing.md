---
order: 618
title: Testing
top_section: Juntos
category: juntos
---

# Testing Juntos Applications

Write tests in JavaScript for your transpiled Juntos applications using Vitest and in-memory databases.

{% toc %}

## Why Test in JavaScript?

Juntos transpiles your Rails code to JavaScript. The `dist/` directory contains what actually runs—ES2022 classes, async/await, standard modules. Testing the transpiled output ensures you're testing what you ship.

| Approach | Pros | Cons |
|----------|------|------|
| Ruby tests (Minitest/RSpec) | Familiar Rails patterns | Tests Ruby, not the JS that runs |
| JavaScript tests (Vitest) | Tests actual runtime code | Different syntax |

JavaScript testing also catches transpilation issues—if Ruby2JS produces incorrect JavaScript, your tests will fail.

## Setup

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

## Project Structure

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

## Testing Models

### Basic CRUD

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

### Testing Validations

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

### Testing Associations

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

### Testing Query Interface

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

## Testing Controllers

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

### Testing Turbo Stream Responses

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

## Testing Path Helpers

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

## In-Memory Database Pattern

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

## Testing React Components

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

### Testing Controllers with React Views

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

## Running Tests

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

## Debugging Tests

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
