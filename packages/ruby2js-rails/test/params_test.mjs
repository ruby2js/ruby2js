// Tests for Rails-style nested parameter parsing
//
// Run with: node --test packages/ruby2js-rails/test/params_test.mjs

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { setNestedParam } from '../rails_server.js';

describe('setNestedParam()', () => {
  describe('nested params (Rails-style)', () => {
    it('parses article[title] into params.article.title', () => {
      const params = {};
      setNestedParam(params, 'article[title]', 'Hello World');
      assert.deepEqual(params, { article: { title: 'Hello World' } });
    });

    it('parses multiple fields into same model', () => {
      const params = {};
      setNestedParam(params, 'article[title]', 'Hello');
      setNestedParam(params, 'article[body]', 'World');
      assert.deepEqual(params, { article: { title: 'Hello', body: 'World' } });
    });

    it('parses fields from different models', () => {
      const params = {};
      setNestedParam(params, 'article[title]', 'Hello');
      setNestedParam(params, 'comment[body]', 'Nice post');
      assert.deepEqual(params, {
        article: { title: 'Hello' },
        comment: { body: 'Nice post' }
      });
    });
  });

  describe('non-nested params', () => {
    it('preserves simple keys without brackets', () => {
      const params = {};
      setNestedParam(params, 'authenticity_token', 'abc123');
      assert.deepEqual(params, { authenticity_token: 'abc123' });
    });

    it('handles _method override', () => {
      const params = {};
      setNestedParam(params, '_method', 'PATCH');
      assert.deepEqual(params, { _method: 'PATCH' });
    });
  });

  describe('mixed params', () => {
    it('handles typical form submission with nested and flat params', () => {
      const params = {};
      setNestedParam(params, 'authenticity_token', 'token123');
      setNestedParam(params, 'article[title]', 'My Title');
      setNestedParam(params, 'article[body]', 'My Body');

      assert.deepEqual(params, {
        authenticity_token: 'token123',
        article: { title: 'My Title', body: 'My Body' }
      });
    });
  });

  describe('edge cases', () => {
    it('handles empty values', () => {
      const params = {};
      setNestedParam(params, 'article[title]', '');
      assert.deepEqual(params, { article: { title: '' } });
    });

    it('handles keys with underscores', () => {
      const params = {};
      setNestedParam(params, 'user_profile[first_name]', 'John');
      assert.deepEqual(params, { user_profile: { first_name: 'John' } });
    });

    it('overwrites duplicate keys', () => {
      const params = {};
      setNestedParam(params, 'article[title]', 'First');
      setNestedParam(params, 'article[title]', 'Second');
      assert.deepEqual(params, { article: { title: 'Second' } });
    });
  });
});

describe('controller article_params pattern', () => {
  // This tests the pattern used by transpiled Rails controllers:
  // function article_params(params) { return params.article ?? {} }

  function article_params(params) {
    return params.article ?? {};
  }

  it('extracts nested article params', () => {
    const params = {};
    setNestedParam(params, 'article[title]', 'Test Title');
    setNestedParam(params, 'article[body]', 'Test Body');

    const extracted = article_params(params);
    assert.deepEqual(extracted, { title: 'Test Title', body: 'Test Body' });
  });

  it('returns empty object when article key is missing', () => {
    const params = { authenticity_token: 'abc' };
    const extracted = article_params(params);
    assert.deepEqual(extracted, {});
  });
});
