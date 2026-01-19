import { test, describe } from 'node:test';
import assert from 'node:assert';
import { createCollection } from '../src/index.js';

describe('createCollection', () => {
  const posts = createCollection('posts', [
    { slug: 'hello', title: 'Hello World', date: '2024-01-01', draft: false, author: 'alice' },
    { slug: 'world', title: 'World', date: '2024-01-02', draft: true, author: 'bob' },
    { slug: 'foo', title: 'Foo Bar', date: '2024-01-03', draft: false, author: 'alice' },
    { slug: 'baz', title: 'Baz Qux', date: '2024-01-04', draft: false, author: 'charlie' }
  ]);

  const authors = createCollection('authors', [
    { slug: 'alice', name: 'Alice' },
    { slug: 'bob', name: 'Bob' },
    { slug: 'charlie', name: 'Charlie' }
  ]);

  test('toArray returns all records', () => {
    const all = posts.toArray();
    assert.strictEqual(all.length, 4);
  });

  test('where filters by condition', () => {
    const published = posts.where({ draft: false }).toArray();
    assert.strictEqual(published.length, 3);
  });

  test('where.not excludes by condition', () => {
    const notDraft = posts.where().not({ draft: true }).toArray();
    assert.strictEqual(notDraft.length, 3);
  });

  test('where chains multiple conditions', () => {
    const result = posts.where({ draft: false }).where({ author: 'alice' }).toArray();
    assert.strictEqual(result.length, 2);
  });

  test('order sorts ascending', () => {
    const sorted = posts.order({ date: 'asc' }).toArray();
    assert.strictEqual(sorted[0].slug, 'hello');
    assert.strictEqual(sorted[3].slug, 'baz');
  });

  test('order sorts descending', () => {
    const sorted = posts.order({ date: 'desc' }).toArray();
    assert.strictEqual(sorted[0].slug, 'baz');
    assert.strictEqual(sorted[3].slug, 'hello');
  });

  test('limit restricts result count', () => {
    const limited = posts.limit(2).toArray();
    assert.strictEqual(limited.length, 2);
  });

  test('offset skips records', () => {
    const offset = posts.offset(2).toArray();
    assert.strictEqual(offset.length, 2);
    assert.strictEqual(offset[0].slug, 'foo');
  });

  test('limit and offset work together', () => {
    const paged = posts.offset(1).limit(2).toArray();
    assert.strictEqual(paged.length, 2);
    assert.strictEqual(paged[0].slug, 'world');
    assert.strictEqual(paged[1].slug, 'foo');
  });

  test('find returns record by slug', () => {
    const post = posts.find('hello');
    assert.strictEqual(post.title, 'Hello World');
  });

  test('find returns null for missing slug', () => {
    const post = posts.find('nonexistent');
    assert.strictEqual(post, null);
  });

  test('find_by returns first matching record', () => {
    const post = posts.find_by({ author: 'alice' });
    assert.strictEqual(post.slug, 'hello');
  });

  test('find_by returns null when no match', () => {
    const post = posts.find_by({ author: 'nobody' });
    assert.strictEqual(post, null);
  });

  test('first returns first record', () => {
    const post = posts.first();
    assert.strictEqual(post.slug, 'hello');
  });

  test('last returns last record', () => {
    const post = posts.last();
    assert.strictEqual(post.slug, 'baz');
  });

  test('count returns record count', () => {
    assert.strictEqual(posts.count(), 4);
    assert.strictEqual(posts.where({ draft: false }).count(), 3);
  });

  test('exists returns true when records exist', () => {
    assert.strictEqual(posts.exists(), true);
    assert.strictEqual(posts.where({ draft: false }).exists(), true);
  });

  test('exists returns false when no records', () => {
    assert.strictEqual(posts.where({ author: 'nobody' }).exists(), false);
  });

  test('collection is iterable', () => {
    const slugs = [];
    for (const post of posts.where({ draft: false })) {
      slugs.push(post.slug);
    }
    assert.strictEqual(slugs.length, 3);
  });

  test('map works on collection', () => {
    const titles = posts.limit(2).map(p => p.title);
    assert.deepStrictEqual(titles, ['Hello World', 'World']);
  });

  test('filter works on collection', () => {
    const filtered = posts.toArray().filter(p => p.author === 'alice');
    assert.strictEqual(filtered.length, 2);
  });

  test('chained query methods', () => {
    const result = posts
      .where({ draft: false })
      .order({ date: 'desc' })
      .limit(2)
      .toArray();

    assert.strictEqual(result.length, 2);
    assert.strictEqual(result[0].slug, 'baz');
    assert.strictEqual(result[1].slug, 'foo');
  });
});

describe('relationships', () => {
  const authors = createCollection('authors', [
    { slug: 'alice', name: 'Alice' },
    { slug: 'bob', name: 'Bob' }
  ]);

  const tags = createCollection('tags', [
    { slug: 'ruby', name: 'Ruby' },
    { slug: 'js', name: 'JavaScript' }
  ]);

  const posts = createCollection('posts', [
    { slug: 'hello', title: 'Hello', author: 'alice', tags: ['ruby', 'js'] },
    { slug: 'world', title: 'World', author: 'bob', tags: ['js'] }
  ]);

  posts.belongsTo('author', authors);
  posts.hasMany('tags', tags);

  test('belongsTo resolves relationship', () => {
    const post = posts.find('hello');
    const author = post.author;
    assert.strictEqual(author.name, 'Alice');
  });

  test('hasMany resolves relationship', () => {
    const post = posts.find('hello');
    const postTags = post.tags;
    assert.strictEqual(postTags.length, 2);
    assert.strictEqual(postTags[0].name, 'Ruby');
    assert.strictEqual(postTags[1].name, 'JavaScript');
  });

  test('relationship resolution in query results', () => {
    const result = posts.where({ author: 'alice' }).first();
    assert.strictEqual(result.author.name, 'Alice');
  });
});

describe('where with arrays', () => {
  const posts = createCollection('posts', [
    { slug: 'a', tags: ['ruby', 'js'] },
    { slug: 'b', tags: ['python'] },
    { slug: 'c', tags: ['ruby'] }
  ]);

  test('array IN query matches any value', () => {
    const result = posts.where({ tags: ['ruby'] }).toArray();
    assert.strictEqual(result.length, 2);
  });

  test('array attribute matches if contains any', () => {
    const result = posts.where({ tags: ['js', 'python'] }).toArray();
    assert.strictEqual(result.length, 2); // 'a' has js, 'b' has python
  });
});
