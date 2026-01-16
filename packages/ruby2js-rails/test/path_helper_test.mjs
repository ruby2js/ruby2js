// Tests for Path Helper (createPathHelper)
//
// Run with: node --test packages/ruby2js-rails/test/path_helper_test.mjs

import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';

import { createPathHelper } from '../path_helper.mjs';

describe('createPathHelper()', () => {
  describe('string coercion', () => {
    it('toString() returns the path', () => {
      const helper = createPathHelper('/articles');
      assert.equal(helper.toString(), '/articles');
    });

    it('valueOf() returns the path', () => {
      const helper = createPathHelper('/articles');
      assert.equal(helper.valueOf(), '/articles');
    });

    it('works with template literals', () => {
      const helper = createPathHelper('/articles');
      assert.equal(`${helper}`, '/articles');
    });

    it('works with string concatenation', () => {
      const helper = createPathHelper('/articles');
      assert.equal(helper + '/new', '/articles/new');
    });
  });

  describe('HTTP methods exist', () => {
    it('has get method', () => {
      const helper = createPathHelper('/articles');
      assert.equal(typeof helper.get, 'function');
    });

    it('has post method', () => {
      const helper = createPathHelper('/articles');
      assert.equal(typeof helper.post, 'function');
    });

    it('has put method', () => {
      const helper = createPathHelper('/articles');
      assert.equal(typeof helper.put, 'function');
    });

    it('has patch method', () => {
      const helper = createPathHelper('/articles');
      assert.equal(typeof helper.patch, 'function');
    });

    it('has delete method', () => {
      const helper = createPathHelper('/articles');
      assert.equal(typeof helper.delete, 'function');
    });
  });

  describe('with mocked fetch', () => {
    let originalFetch;
    let fetchCalls;

    beforeEach(() => {
      fetchCalls = [];
      originalFetch = globalThis.fetch;
      globalThis.fetch = mock.fn((url, options) => {
        fetchCalls.push({ url, options });
        return Promise.resolve(new Response('{}', { status: 200 }));
      });
    });

    afterEach(() => {
      globalThis.fetch = originalFetch;
    });

    describe('GET requests', () => {
      it('builds URL with .json format by default', async () => {
        const helper = createPathHelper('/articles');
        await helper.get();
        assert.equal(fetchCalls[0].url, '/articles.json');
        assert.equal(fetchCalls[0].options.method, 'GET');
      });

      it('builds URL with explicit format', async () => {
        const helper = createPathHelper('/articles');
        await helper.get({ format: 'html' });
        assert.equal(fetchCalls[0].url, '/articles.html');
      });

      it('appends query parameters', async () => {
        const helper = createPathHelper('/articles');
        await helper.get({ page: 2, limit: 10 });
        assert.equal(fetchCalls[0].url, '/articles.json?page=2&limit=10');
      });

      it('sets Accept header for JSON', async () => {
        const helper = createPathHelper('/articles');
        await helper.get();
        assert.equal(fetchCalls[0].options.headers['Accept'], 'application/json');
      });

      it('sets Accept header for HTML', async () => {
        const helper = createPathHelper('/articles');
        await helper.get({ format: 'html' });
        assert.equal(fetchCalls[0].options.headers['Accept'], 'text/html');
      });

      it('sets Accept header for turbo_stream', async () => {
        const helper = createPathHelper('/articles');
        await helper.get({ format: 'turbo_stream' });
        assert.equal(fetchCalls[0].options.headers['Accept'], 'text/vnd.turbo-stream.html');
      });

      it('uses same-origin credentials', async () => {
        const helper = createPathHelper('/articles');
        await helper.get();
        assert.equal(fetchCalls[0].options.credentials, 'same-origin');
      });
    });

    describe('POST requests', () => {
      it('builds URL with .json format by default', async () => {
        const helper = createPathHelper('/articles');
        await helper.post({ title: 'New Article' });
        assert.equal(fetchCalls[0].url, '/articles.json');
        assert.equal(fetchCalls[0].options.method, 'POST');
      });

      it('sends JSON body', async () => {
        const helper = createPathHelper('/articles');
        await helper.post({ title: 'New Article' });
        assert.equal(fetchCalls[0].options.body, '{"title":"New Article"}');
        assert.equal(fetchCalls[0].options.headers['Content-Type'], 'application/json');
      });

      it('excludes format from body', async () => {
        const helper = createPathHelper('/articles');
        await helper.post({ format: 'html', title: 'New' });
        assert.equal(fetchCalls[0].url, '/articles.html');
        assert.equal(fetchCalls[0].options.body, '{"title":"New"}');
      });

      it('omits body when no params', async () => {
        const helper = createPathHelper('/articles');
        await helper.post();
        assert.equal(fetchCalls[0].options.body, undefined);
      });
    });

    describe('PATCH requests', () => {
      it('sends PATCH method', async () => {
        const helper = createPathHelper('/articles/1');
        await helper.patch({ title: 'Updated' });
        assert.equal(fetchCalls[0].options.method, 'PATCH');
        assert.equal(fetchCalls[0].options.body, '{"title":"Updated"}');
      });
    });

    describe('PUT requests', () => {
      it('sends PUT method', async () => {
        const helper = createPathHelper('/articles/1');
        await helper.put({ title: 'Replaced' });
        assert.equal(fetchCalls[0].options.method, 'PUT');
        assert.equal(fetchCalls[0].options.body, '{"title":"Replaced"}');
      });
    });

    describe('DELETE requests', () => {
      it('sends DELETE method', async () => {
        const helper = createPathHelper('/articles/1');
        await helper.delete();
        assert.equal(fetchCalls[0].options.method, 'DELETE');
        assert.equal(fetchCalls[0].url, '/articles/1.json');
      });
    });
  });

  describe('CSRF token handling', () => {
    let originalFetch;
    let originalDocument;
    let fetchCalls;

    beforeEach(() => {
      fetchCalls = [];
      originalFetch = globalThis.fetch;
      originalDocument = globalThis.document;

      globalThis.fetch = mock.fn((url, options) => {
        fetchCalls.push({ url, options });
        return Promise.resolve(new Response('{}', { status: 200 }));
      });

      // Mock document with CSRF meta tag
      globalThis.document = {
        querySelector: (selector) => {
          if (selector === 'meta[name="csrf-token"]') {
            return { content: 'test-csrf-token-123' };
          }
          return null;
        }
      };
    });

    afterEach(() => {
      globalThis.fetch = originalFetch;
      globalThis.document = originalDocument;
    });

    it('includes CSRF token in POST requests', async () => {
      const helper = createPathHelper('/articles');
      await helper.post({ title: 'New' });
      assert.equal(fetchCalls[0].options.headers['X-Authenticity-Token'], 'test-csrf-token-123');
    });

    it('includes CSRF token in PATCH requests', async () => {
      const helper = createPathHelper('/articles/1');
      await helper.patch({ title: 'Updated' });
      assert.equal(fetchCalls[0].options.headers['X-Authenticity-Token'], 'test-csrf-token-123');
    });

    it('includes CSRF token in PUT requests', async () => {
      const helper = createPathHelper('/articles/1');
      await helper.put({ title: 'Replaced' });
      assert.equal(fetchCalls[0].options.headers['X-Authenticity-Token'], 'test-csrf-token-123');
    });

    it('includes CSRF token in DELETE requests', async () => {
      const helper = createPathHelper('/articles/1');
      await helper.delete();
      assert.equal(fetchCalls[0].options.headers['X-Authenticity-Token'], 'test-csrf-token-123');
    });

    it('does NOT include CSRF token in GET requests', async () => {
      const helper = createPathHelper('/articles');
      await helper.get();
      assert.equal(fetchCalls[0].options.headers['X-Authenticity-Token'], undefined);
    });
  });
});
