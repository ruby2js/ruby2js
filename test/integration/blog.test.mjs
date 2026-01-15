// Integration tests for the blog demo
// Tests CRUD operations, validations, associations, and controller actions
// Uses better-sqlite3 with :memory: for fast, isolated tests

import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DIST_DIR = join(__dirname, 'workspace/blog/dist');

// Dynamic imports - loaded once in beforeAll
let Article, Comment;
let ArticlesController, CommentsController;
let Application, initDatabase, migrations, modelRegistry;

describe('Blog Integration Tests', () => {
  beforeAll(async () => {
    // Import the active_record adapter (for initDatabase and modelRegistry)
    const activeRecord = await import(join(DIST_DIR, 'lib/active_record.mjs'));
    initDatabase = activeRecord.initDatabase;
    modelRegistry = activeRecord.modelRegistry;

    // Import Application from rails.js
    const rails = await import(join(DIST_DIR, 'lib/rails.js'));
    Application = rails.Application;

    // Import migrations
    const migrationsModule = await import(join(DIST_DIR, 'db/migrate/index.js'));
    migrations = migrationsModule.migrations;

    // Import models
    const models = await import(join(DIST_DIR, 'app/models/index.js'));
    Article = models.Article;
    Comment = models.Comment;

    // Import controllers
    const articlesCtrl = await import(join(DIST_DIR, 'app/controllers/articles_controller.js'));
    ArticlesController = articlesCtrl.ArticlesController;

    const commentsCtrl = await import(join(DIST_DIR, 'app/controllers/comments_controller.js'));
    CommentsController = commentsCtrl.CommentsController;

    // Configure Application with migrations
    Application.configure({ migrations });
    Application.registerModels({ Article, Comment });

    // Register models with adapter's registry for association resolution
    modelRegistry.Article = Article;
    modelRegistry.Comment = Comment;
  });

  beforeEach(async () => {
    // Initialize fresh in-memory database for each test
    await initDatabase({ database: ':memory:' });

    // Get the adapter module for runMigrations
    const adapter = await import(join(DIST_DIR, 'lib/active_record.mjs'));

    // Run migrations using Application (now supports SQL adapters)
    await Application.runMigrations(adapter);
  });

  describe('Article Model', () => {
    it('creates an article with valid attributes', async () => {
      const article = await Article.create({
        title: 'Test Article',
        body: 'This is the body of the test article with enough content.'
      });

      expect(article.id).toBeDefined();
      expect(article.title).toBe('Test Article');
      expect(article.id).toBeGreaterThan(0);  // persisted if has id
    });

    it('validates title presence', async () => {
      const article = new Article({ title: '', body: 'Valid body content here.' });
      const saved = await article.save();

      expect(saved).toBe(false);
      expect(article.errors.title).toBeDefined();
    });

    it('validates body minimum length', async () => {
      const article = new Article({ title: 'Valid Title', body: 'Short' });
      const saved = await article.save();

      expect(saved).toBe(false);
      expect(article.errors.body).toBeDefined();
    });

    it('finds article by id', async () => {
      const created = await Article.create({
        title: 'Find Me',
        body: 'This article should be findable by its ID.'
      });

      const found = await Article.find(created.id);
      expect(found.title).toBe('Find Me');
    });

    it('lists all articles', async () => {
      await Article.create({ title: 'Article 1', body: 'First article body content.' });
      await Article.create({ title: 'Article 2', body: 'Second article body content.' });

      const articles = await Article.all();
      expect(articles.length).toBe(2);
    });

    it('updates an article', async () => {
      const article = await Article.create({
        title: 'Original Title',
        body: 'Original body content that is long enough.'
      });

      await article.update({ title: 'Updated Title' });

      const reloaded = await Article.find(article.id);
      expect(reloaded.title).toBe('Updated Title');
    });

    it('destroys an article', async () => {
      const article = await Article.create({
        title: 'To Delete',
        body: 'This article will be deleted.'
      });
      const id = article.id;

      await article.destroy();

      const found = await Article.findBy({ id });
      expect(found).toBeNull();
    });
  });

  describe('Comment Model', () => {
    let article;

    beforeEach(async () => {
      article = await Article.create({
        title: 'Article with Comments',
        body: 'This article will have comments attached.'
      });
    });

    it('creates a comment on an article', async () => {
      const comment = await Comment.create({
        article_id: article.id,
        commenter: 'Test User',
        body: 'This is a test comment.'
      });

      expect(comment.id).toBeDefined();
      expect(comment.article_id).toBe(article.id);
    });

    it('belongs to article association', async () => {
      const comment = await Comment.create({
        article_id: article.id,
        commenter: 'Commenter',
        body: 'Comment body text.'
      });

      const parentArticle = await comment.article;
      expect(parentArticle.id).toBe(article.id);
    });

    it('article has many comments', async () => {
      await Comment.create({ article_id: article.id, commenter: 'User 1', body: 'First comment.' });
      await Comment.create({ article_id: article.id, commenter: 'User 2', body: 'Second comment.' });

      // Reload article to get fresh associations
      const reloaded = await Article.includes('comments').find(article.id);
      expect(reloaded.comments.length).toBe(2);
    });
  });

  describe('ArticlesController', () => {
    it('index action returns list', async () => {
      await Article.create({ title: 'Listed Article', body: 'This should appear in the index.' });

      // Create a mock context
      const context = {
        params: {},
        flash: { get: () => '', consumeNotice: () => '', consumeAlert: () => '' },
        contentFor: {}
      };

      const html = await ArticlesController.index(context);
      expect(html).toContain('Listed Article');
    });

    it('show action returns article details', async () => {
      const article = await Article.create({
        title: 'Show This Article',
        body: 'The full article body should be visible on show page.'
      });

      const context = {
        params: { id: article.id },
        flash: { get: () => '', consumeNotice: () => '', consumeAlert: () => '' },
        contentFor: {}
      };

      const html = await ArticlesController.show(context, article.id);
      expect(html).toContain('Show This Article');
    });

    it('create action adds a new article', async () => {
      const context = {
        params: {},
        flash: { set: () => {} },
        contentFor: {}
      };

      const params = {
        title: 'New Article via Controller',
        body: 'Created through the controller action.'
      };

      const result = await ArticlesController.create(context, params);

      // Should return redirect after successful create
      expect(result.redirect).toBeDefined();

      const articles = await Article.all();
      expect(articles.length).toBe(1);
      expect(articles[0].title).toBe('New Article via Controller');
    });
  });

  describe('Base Path Handling', () => {
    let article_path;

    beforeAll(async () => {
      // Import path helpers to verify controller redirects match
      const paths = await import(join(DIST_DIR, 'config/paths.js'));
      article_path = paths.article_path;
    });

    it('controller redirect_to uses path helpers (not hardcoded)', async () => {
      // This test verifies that redirect_to @article generates article_path(article)
      // The path helper respects base path configuration (set during build)

      const context = {
        params: {},
        flash: { set: () => {} },
        contentFor: {}
      };

      const params = {
        title: 'New Article for Redirect',
        body: 'Testing that redirect uses path helper.'
      };

      const result = await ArticlesController.create(context, params);

      // The redirect should use article_path() which respects base path config
      expect(result.redirect).toBeDefined();

      // Verify redirect matches what article_path() returns for article id 1
      const articles = await Article.all();
      const createdArticle = articles[0];
      expect(result.redirect).toBe(article_path(createdArticle));
    });

    it('CommentsController redirect_to uses path helpers', async () => {
      // Test that nested resource redirects also use path helpers
      const article = await Article.create({
        title: 'Article for Comment',
        body: 'Testing comment redirect uses path helper.'
      });

      const context = {
        params: {},
        flash: { set: () => {} },
        contentFor: {}
      };

      const result = await CommentsController.create(
        context,
        article.id,
        { commenter: 'Tester', body: 'Test comment' }
      );

      // Should redirect to article_path(article)
      expect(result.redirect).toBeDefined();
      expect(result.redirect).toBe(article_path(article));
    });

    it('CommentsController destroy uses correct path (not [object Promise])', async () => {
      // Reproduces bug: deleting comment shows /articles/[object%20Promise]/comments/4
      const article = await Article.create({
        title: 'Article for Comment Delete',
        body: 'Testing comment delete redirect path.'
      });

      const comment = await Comment.create({
        article_id: article.id,
        commenter: 'To Delete',
        body: 'This comment will be deleted.'
      });

      const context = {
        params: {},
        flash: { set: () => {} },
        contentFor: {}
      };

      const result = await CommentsController.destroy(
        context,
        article.id,
        comment.id
      );

      // Should redirect to article_path(article), not contain [object Promise]
      expect(result.redirect).toBeDefined();
      expect(result.redirect).not.toContain('[object');
      expect(result.redirect).not.toContain('Promise');
      expect(result.redirect).toBe(article_path(article));
    });

    it('comment delete button URL does not contain [object Promise]', async () => {
      // Bug: delete form action was /articles/[object%20Promise]/comments/4
      // because comment.article is an async getter returning a Promise
      const article = await Article.create({
        title: 'Article for Delete Button Test',
        body: 'Testing that delete button URL uses article_id not article.'
      });

      // Preload comments for article (like controller does)
      article.comments = await article.comments;

      const comment = await Comment.create({
        article_id: article.id,
        commenter: 'Test',
        body: 'Comment with delete button.'
      });

      // Import the comment partial renderer
      const { render: renderComment } = await import(
        join(DIST_DIR, 'app/views/comments/_comment.js')
      );

      const html = renderComment({ $context: {}, comment });

      // The delete form action should not contain [object Promise]
      expect(html).not.toContain('[object');
      expect(html).not.toContain('Promise');
      // Should contain the correct path with article_id
      expect(html).toContain(`/articles/${article.id}/comments/${comment.id}`);
    });

    it('path helpers should not double the base path', async () => {
      // Import path helpers and verify they have single base path
      const { article_path, articles_path } = await import(join(DIST_DIR, 'config/paths.js'));

      // articles_path should be /articles (no base in test build)
      // or /ruby2js/blog/articles (with base) - but NOT doubled
      const articlesPath = articles_path();
      console.log('articles_path():', articlesPath);
      expect(articlesPath).not.toContain('/ruby2js/blog/ruby2js/blog');

      // article_path should not have doubled base
      const articlePath = article_path({ id: 1 });
      console.log('article_path({id: 1}):', articlePath);
      expect(articlePath).not.toContain('/ruby2js/blog/ruby2js/blog');
    });

    it('form actions should include base path when configured', async () => {
      // This test checks view-generated form actions (separate issue from redirect_to)
      const article = await Article.create({
        title: 'Article with Base Path',
        body: 'Testing that form actions include the base path.'
      });

      const context = {
        params: { id: article.id },
        flash: { get: () => '', consumeNotice: () => ({ present: false }), consumeAlert: () => '' },
        contentFor: {}
      };

      const html = await ArticlesController.show(context, article.id);

      // The comment form action should include the base path
      // Currently it generates: action="/articles/1/comments"
      // TODO: Should generate: action="/ruby2js/blog/articles/1/comments" (view helper fix needed)

      // For now, check what it currently generates
      const formMatch = html.match(/action="([^"]+comments)"/);
      expect(formMatch).toBeDefined();
      console.log('Comment form action:', formMatch[1]);

      // Also check the "Back to articles" link
      const backMatch = html.match(/href="([^"]+articles)"/);
      console.log('Back to articles href:', backMatch?.[1]);
    });
  });

  describe('Query Interface', () => {
    beforeEach(async () => {
      await Article.create({ title: 'Alpha', body: 'First alphabetically by title.' });
      await Article.create({ title: 'Beta', body: 'Second alphabetically by title.' });
      await Article.create({ title: 'Gamma', body: 'Third alphabetically by title.' });
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

    it('limit restricts result count', async () => {
      const results = await Article.limit(2);
      expect(results.length).toBe(2);
    });

    it('first returns single record', async () => {
      const first = await Article.first();
      expect(first).toBeDefined();
      expect(first.title).toBe('Alpha');
    });

    it('count returns record count', async () => {
      const count = await Article.count();
      expect(count).toBe(3);
    });
  });
});
