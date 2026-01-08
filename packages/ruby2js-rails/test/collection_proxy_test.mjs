// CollectionProxy Unit Tests
//
// Tests for the CollectionProxy class that mirrors Rails' ActiveRecord::Associations::CollectionProxy.
// See plans/COLLECTION_PROXY.md for the implementation plan.

import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { CollectionProxy } from '../adapters/collection_proxy.mjs';

describe('CollectionProxy', () => {
  let mockOwner;
  let mockAssociation;
  let MockModel;
  let proxy;
  let mockRecords;

  beforeEach(() => {
    mockOwner = { id: 1 };
    mockAssociation = { name: 'comments', type: 'has_many', foreignKey: 'post_id' };

    // Mock model with static where method
    MockModel = class Comment {
      constructor(attrs) {
        Object.assign(this, attrs);
      }
      static where(conditions) {
        // Return a mock relation with chainable methods
        const mockRelation = {
          _conditions: conditions,
          count: async () => 3,
          first: async () => mockRelation._isEmpty ? null : new Comment({ id: 1, body: 'First' }),
          last: async () => mockRelation._isEmpty ? null : new Comment({ id: 3, body: 'Last' }),
          where: function(conds) { return this; },
          order: function(opts) { return this; },
          limit: function(n) { return this; },
          offset: function(n) { return this; },
          includes: function(...assocs) { return this; },
          select: function(...fields) { return this; },
          then: function(resolve) { return resolve([new Comment({ id: 1 })]); },
          _isEmpty: false,
          setEmpty: function() { this._isEmpty = true; return this; }
        };
        return mockRelation;
      }
      async save() { return true; }
    };

    mockRecords = [
      new MockModel({ id: 1, body: 'Comment 1', post_id: 1 }),
      new MockModel({ id: 2, body: 'Comment 2', post_id: 1 }),
      new MockModel({ id: 3, body: 'Comment 3', post_id: 1 })
    ];

    proxy = new CollectionProxy(mockOwner, mockAssociation, MockModel);
  });

  describe('initialization', () => {
    it('starts unloaded', () => {
      assert.equal(proxy.loaded, false);
      assert.equal(proxy._records, null);
    });

    it('stores owner, association, and model', () => {
      assert.equal(proxy._owner, mockOwner);
      assert.deepEqual(proxy._association, mockAssociation);
      assert.equal(proxy._model, MockModel);
    });
  });

  describe('loading', () => {
    it('load() sets records and marks as loaded', () => {
      proxy.load(mockRecords);

      assert.equal(proxy.loaded, true);
      assert.deepEqual(proxy._records, mockRecords);
    });

    it('load() returns self for chaining', () => {
      const result = proxy.load(mockRecords);
      assert.equal(result, proxy);
    });
  });

  describe('counting', () => {
    beforeEach(() => {
      proxy.load(mockRecords);
    });

    it('size returns record count', () => {
      assert.equal(proxy.size, 3);
    });

    it('length returns record count', () => {
      assert.equal(proxy.length, 3);
    });

    it('size returns 0 when not loaded', () => {
      const unloaded = new CollectionProxy(mockOwner, mockAssociation, MockModel);
      assert.equal(unloaded.size, 0);
    });

    it('empty returns true when no records', () => {
      proxy.load([]);
      assert.equal(proxy.empty, true);
    });

    it('empty returns false when has records', () => {
      assert.equal(proxy.empty, false);
    });

    it('isEmpty() returns same as empty', () => {
      assert.equal(proxy.isEmpty(), proxy.empty);
    });

    it('any returns true when has records', () => {
      assert.equal(proxy.any, true);
    });

    it('any returns false when empty', () => {
      proxy.load([]);
      assert.equal(proxy.any, false);
    });

    it('count() returns async count from model', async () => {
      const count = await proxy.count();
      assert.equal(count, 3);
    });
  });

  describe('building', () => {
    it('build() creates record with foreign key set', () => {
      const record = proxy.build({ body: 'New comment' });

      assert.equal(record.body, 'New comment');
      assert.equal(record.post_id, 1);
    });

    it('build() with no params still sets foreign key', () => {
      const record = proxy.build();
      assert.equal(record.post_id, 1);
    });

    it('create() saves and adds to records', async () => {
      proxy.load([]);
      const record = await proxy.create({ body: 'Created comment' });

      assert.equal(record.body, 'Created comment');
      assert.equal(record.post_id, 1);
      assert.equal(proxy._records.length, 1);
    });
  });

  describe('finding', () => {
    beforeEach(() => {
      proxy.load(mockRecords);
    });

    it('first() returns first loaded record', async () => {
      const first = await proxy.first();
      assert.equal(first.id, 1);
    });

    it('last() returns last loaded record', async () => {
      const last = await proxy.last();
      assert.equal(last.id, 3);
    });

    it('first() returns null for empty collection', async () => {
      proxy.load([]);
      const first = await proxy.first();
      assert.equal(first, null);
    });

    it('last() returns null for empty collection', async () => {
      proxy.load([]);
      const last = await proxy.last();
      assert.equal(last, null);
    });
  });

  describe('chaining (returns Relation)', () => {
    it('where() returns scoped relation', () => {
      const result = proxy.where({ active: true });
      assert.ok(result); // Returns relation-like object
    });

    it('order() returns scoped relation', () => {
      const result = proxy.order({ created_at: 'desc' });
      assert.ok(result);
    });

    it('limit() returns scoped relation', () => {
      const result = proxy.limit(10);
      assert.ok(result);
    });

    it('offset() returns scoped relation', () => {
      const result = proxy.offset(5);
      assert.ok(result);
    });

    it('includes() returns scoped relation', () => {
      const result = proxy.includes('author');
      assert.ok(result);
    });

    it('select() returns scoped relation', () => {
      const result = proxy.select('id', 'body');
      assert.ok(result);
    });

    it('toRelation() creates relation with foreign key scope', () => {
      const rel = proxy.toRelation();
      assert.ok(rel);
    });

    it('all() is alias for toRelation()', () => {
      const rel1 = proxy.toRelation();
      const rel2 = proxy.all();
      // Both should return relation-like objects
      assert.ok(rel1);
      assert.ok(rel2);
    });
  });

  describe('enumerable', () => {
    beforeEach(() => {
      proxy.load(mockRecords);
    });

    it('supports for...of iteration', () => {
      const bodies = [];
      for (const record of proxy) {
        bodies.push(record.body);
      }
      assert.deepEqual(bodies, ['Comment 1', 'Comment 2', 'Comment 3']);
    });

    it('forEach() iterates over records', () => {
      const bodies = [];
      proxy.forEach(r => bodies.push(r.body));
      assert.deepEqual(bodies, ['Comment 1', 'Comment 2', 'Comment 3']);
    });

    it('map() transforms records', () => {
      const ids = proxy.map(r => r.id);
      assert.deepEqual(ids, [1, 2, 3]);
    });

    it('filter() filters records', () => {
      const filtered = proxy.filter(r => r.id > 1);
      assert.equal(filtered.length, 2);
    });

    it('some() checks if any match', () => {
      assert.equal(proxy.some(r => r.id === 2), true);
      assert.equal(proxy.some(r => r.id === 99), false);
    });

    it('every() checks if all match', () => {
      assert.equal(proxy.every(r => r.post_id === 1), true);
      assert.equal(proxy.every(r => r.id === 1), false);
    });

    it('reduce() accumulates values', () => {
      const sum = proxy.reduce((acc, r) => acc + r.id, 0);
      assert.equal(sum, 6);
    });

    it('at() returns record at index', () => {
      assert.equal(proxy.at(0).id, 1);
      assert.equal(proxy.at(1).id, 2);
      assert.equal(proxy.at(2).id, 3);
    });

    it('at() returns undefined for out of bounds', () => {
      assert.equal(proxy.at(99), undefined);
    });

    it('toArray() returns records array', () => {
      const arr = proxy.toArray();
      assert.equal(Array.isArray(arr), true);
      assert.equal(arr.length, 3);
    });

    it('records getter returns records', () => {
      assert.deepEqual(proxy.records, mockRecords);
    });

    it('records getter returns empty array when not loaded', () => {
      const unloaded = new CollectionProxy(mockOwner, mockAssociation, MockModel);
      assert.deepEqual(unloaded.records, []);
    });
  });

  describe('thenable', () => {
    it('returns loaded records when already loaded', async () => {
      proxy.load(mockRecords);
      const records = await proxy;
      assert.deepEqual(records, mockRecords);
    });

    it('works with Promise.resolve', async () => {
      proxy.load(mockRecords);
      const records = await Promise.resolve(proxy);
      assert.deepEqual(records, mockRecords);
    });
  });

  describe('Symbol.toStringTag', () => {
    it('returns CollectionProxy', () => {
      assert.equal(proxy[Symbol.toStringTag], 'CollectionProxy');
    });
  });
});
