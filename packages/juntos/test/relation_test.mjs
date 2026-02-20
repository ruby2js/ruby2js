// Tests for Relation class and SQL building
//
// Run with: node --test packages/juntos/test/relation_test.mjs

import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { Relation } from '../adapters/relation.mjs';
import { ActiveRecordSQL, modelRegistry } from '../adapters/active_record_sql.mjs';
import { singularize, pluralize } from '../adapters/inflector.mjs';

// --- Mock Model Classes ---

// Mock model using ? placeholders (SQLite/MySQL style)
class MockModel extends ActiveRecordSQL {
  static tableName = 'users';
  static get useNumberedParams() { return false; }

  static _executedQueries = [];

  static async _execute(sql, params) {
    this._executedQueries.push({ sql, params });
    return { rows: [] };
  }

  static _getRows(result) {
    return result.rows;
  }

  static _getLastInsertId(result) {
    return 1;
  }

  static resetQueries() {
    this._executedQueries = [];
  }
}

// Mock model using $1, $2 placeholders (Postgres style)
class MockPostgresModel extends ActiveRecordSQL {
  static tableName = 'posts';
  static get useNumberedParams() { return true; }

  static _executedQueries = [];

  static async _execute(sql, params) {
    this._executedQueries.push({ sql, params });
    return { rows: [] };
  }

  static _getRows(result) {
    return result.rows;
  }

  static _getLastInsertId(result) {
    return 1;
  }

  static resetQueries() {
    this._executedQueries = [];
  }
}

// --- Relation Class Tests ---

describe('Relation', () => {
  describe('constructor', () => {
    it('initializes with empty state', () => {
      const rel = new Relation(MockModel);
      assert.equal(rel.model, MockModel);
      assert.deepEqual(rel._conditions, []);
      assert.deepEqual(rel._orConditions, []);
      assert.equal(rel._order, null);
      assert.equal(rel._limit, null);
      assert.equal(rel._offset, null);
      assert.equal(rel._select, null);
      assert.equal(rel._distinct, false);
    });
  });

  describe('chainable methods', () => {
    it('where() adds conditions and returns new Relation', () => {
      const rel1 = new Relation(MockModel);
      const rel2 = rel1.where({ active: true });

      // Original unchanged
      assert.deepEqual(rel1._conditions, []);
      // New has condition
      assert.deepEqual(rel2._conditions, [{ active: true }]);
      // Different instances
      assert.notEqual(rel1, rel2);
    });

    it('where() chains multiple conditions', () => {
      const rel = new Relation(MockModel)
        .where({ active: true })
        .where({ role: 'admin' });

      assert.deepEqual(rel._conditions, [
        { active: true },
        { role: 'admin' }
      ]);
    });

    it('order() sets ordering and returns new Relation', () => {
      const rel1 = new Relation(MockModel);
      const rel2 = rel1.order('name');

      assert.equal(rel1._order, null);
      assert.equal(rel2._order, 'name');
      assert.notEqual(rel1, rel2);
    });

    it('order() accepts object with direction', () => {
      const rel = new Relation(MockModel).order({ created_at: 'desc' });
      assert.deepEqual(rel._order, { created_at: 'desc' });
    });

    it('limit() sets limit and returns new Relation', () => {
      const rel1 = new Relation(MockModel);
      const rel2 = rel1.limit(10);

      assert.equal(rel1._limit, null);
      assert.equal(rel2._limit, 10);
      assert.notEqual(rel1, rel2);
    });

    it('offset() sets offset and returns new Relation', () => {
      const rel1 = new Relation(MockModel);
      const rel2 = rel1.offset(20);

      assert.equal(rel1._offset, null);
      assert.equal(rel2._offset, 20);
      assert.notEqual(rel1, rel2);
    });

    it('chains all methods together', () => {
      const rel = new Relation(MockModel)
        .where({ active: true })
        .where({ role: 'admin' })
        .order({ name: 'asc' })
        .limit(10)
        .offset(5);

      assert.deepEqual(rel._conditions, [{ active: true }, { role: 'admin' }]);
      assert.deepEqual(rel._order, { name: 'asc' });
      assert.equal(rel._limit, 10);
      assert.equal(rel._offset, 5);
    });
  });

  describe('_clone()', () => {
    it('creates independent copy', () => {
      const rel1 = new Relation(MockModel)
        .where({ active: true })
        .order('name')
        .limit(5);

      const rel2 = rel1._clone();

      // Same values
      assert.deepEqual(rel1._conditions, rel2._conditions);
      assert.equal(rel1._order, rel2._order);
      assert.equal(rel1._limit, rel2._limit);

      // But independent arrays
      rel2._conditions.push({ extra: true });
      assert.equal(rel1._conditions.length, 1);
      assert.equal(rel2._conditions.length, 2);
    });
  });

  describe('_reverseOrder()', () => {
    it('reverses string order to desc', () => {
      const rel = new Relation(MockModel);
      const reversed = rel._reverseOrder('name');
      assert.deepEqual(reversed, { name: 'desc' });
    });

    it('reverses desc to asc', () => {
      const rel = new Relation(MockModel);
      const reversed = rel._reverseOrder({ created_at: 'desc' });
      assert.deepEqual(reversed, { created_at: 'asc' });
    });

    it('reverses asc to desc', () => {
      const rel = new Relation(MockModel);
      const reversed = rel._reverseOrder({ updated_at: 'asc' });
      assert.deepEqual(reversed, { updated_at: 'desc' });
    });
  });

  describe('thenable interface', () => {
    beforeEach(() => {
      MockModel.resetQueries();
    });

    it('has then() method', () => {
      const rel = new Relation(MockModel);
      assert.equal(typeof rel.then, 'function');
    });

    it('await triggers toArray()', async () => {
      const results = await new Relation(MockModel).where({ active: true });
      assert.ok(Array.isArray(results));
      assert.equal(MockModel._executedQueries.length, 1);
    });
  });

  describe('async iterator', () => {
    beforeEach(() => {
      MockModel.resetQueries();
    });

    it('supports for-await-of', async () => {
      const rel = new Relation(MockModel);
      const items = [];
      for await (const item of rel) {
        items.push(item);
      }
      assert.ok(Array.isArray(items));
    });
  });
});

// --- SQL Building Tests ---

describe('ActiveRecordSQL._buildRelationSQL', () => {
  describe('basic queries', () => {
    it('builds SELECT * for empty relation', () => {
      const rel = new Relation(MockModel);
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users');
      assert.deepEqual(values, []);
    });

    it('builds COUNT(*) when count option is true', () => {
      const rel = new Relation(MockModel);
      const { sql, values } = MockModel._buildRelationSQL(rel, { count: true });

      assert.equal(sql, 'SELECT COUNT(*) as count FROM users');
      assert.deepEqual(values, []);
    });
  });

  describe('WHERE clause', () => {
    it('builds simple equality condition', () => {
      const rel = new Relation(MockModel).where({ active: true });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE active = ?');
      assert.deepEqual(values, [true]);
    });

    it('builds multiple conditions with AND', () => {
      const rel = new Relation(MockModel)
        .where({ active: true })
        .where({ role: 'admin' });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE active = ? AND role = ?');
      assert.deepEqual(values, [true, 'admin']);
    });

    it('builds IN clause for array values', () => {
      const rel = new Relation(MockModel).where({ id: [1, 2, 3] });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE id IN (?, ?, ?)');
      assert.deepEqual(values, [1, 2, 3]);
    });

    it('builds IS NULL for null values', () => {
      const rel = new Relation(MockModel).where({ deleted_at: null });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE deleted_at IS NULL');
      assert.deepEqual(values, []);
    });

    it('combines multiple condition types', () => {
      const rel = new Relation(MockModel)
        .where({ active: true, role: ['admin', 'moderator'] })
        .where({ deleted_at: null });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE active = ? AND role IN (?, ?) AND deleted_at IS NULL');
      assert.deepEqual(values, [true, 'admin', 'moderator']);
    });
  });

  describe('ORDER BY clause', () => {
    it('builds ORDER BY with string column (ASC)', () => {
      const rel = new Relation(MockModel).order('name');
      const { sql } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users ORDER BY name ASC');
    });

    it('builds ORDER BY with object (desc)', () => {
      const rel = new Relation(MockModel).order({ created_at: 'desc' });
      const { sql } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users ORDER BY created_at DESC');
    });

    it('builds ORDER BY with :desc symbol style', () => {
      const rel = new Relation(MockModel).order({ name: ':desc' });
      const { sql } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users ORDER BY name DESC');
    });

    it('skips ORDER BY for count queries', () => {
      const rel = new Relation(MockModel).order('name');
      const { sql } = MockModel._buildRelationSQL(rel, { count: true });

      assert.equal(sql, 'SELECT COUNT(*) as count FROM users');
    });
  });

  describe('LIMIT and OFFSET', () => {
    it('builds LIMIT clause', () => {
      const rel = new Relation(MockModel).limit(10);
      const { sql } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users LIMIT 10');
    });

    it('builds OFFSET clause', () => {
      const rel = new Relation(MockModel).offset(20);
      const { sql } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users OFFSET 20');
    });

    it('builds LIMIT and OFFSET together', () => {
      const rel = new Relation(MockModel).limit(10).offset(20);
      const { sql } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users LIMIT 10 OFFSET 20');
    });

    it('skips LIMIT and OFFSET for count queries', () => {
      const rel = new Relation(MockModel).limit(10).offset(20);
      const { sql } = MockModel._buildRelationSQL(rel, { count: true });

      assert.equal(sql, 'SELECT COUNT(*) as count FROM users');
    });
  });

  describe('complete queries', () => {
    it('builds complex query with all clauses', () => {
      const rel = new Relation(MockModel)
        .where({ active: true })
        .where({ role: 'admin' })
        .order({ created_at: 'desc' })
        .limit(10)
        .offset(5);
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql,
        'SELECT * FROM users WHERE active = ? AND role = ? ORDER BY created_at DESC LIMIT 10 OFFSET 5'
      );
      assert.deepEqual(values, [true, 'admin']);
    });
  });
});

describe('PostgreSQL numbered parameters', () => {
  it('uses $1, $2 style placeholders', () => {
    const rel = new Relation(MockPostgresModel)
      .where({ active: true })
      .where({ role: 'admin' });
    const { sql, values } = MockPostgresModel._buildRelationSQL(rel);

    assert.equal(sql, 'SELECT * FROM posts WHERE active = $1 AND role = $2');
    assert.deepEqual(values, [true, 'admin']);
  });

  it('numbers IN clause placeholders correctly', () => {
    const rel = new Relation(MockPostgresModel)
      .where({ status: 'active' })
      .where({ id: [1, 2, 3] });
    const { sql, values } = MockPostgresModel._buildRelationSQL(rel);

    assert.equal(sql, 'SELECT * FROM posts WHERE status = $1 AND id IN ($2, $3, $4)');
    assert.deepEqual(values, ['active', 1, 2, 3]);
  });
});

// --- NOT Conditions Tests ---

describe('NOT conditions', () => {
  describe('not() method', () => {
    it('adds NOT conditions and returns new Relation', () => {
      const rel1 = new Relation(MockModel);
      const rel2 = rel1.not({ role: 'guest' });

      // Original unchanged
      assert.deepEqual(rel1._notConditions, []);
      // New has NOT condition
      assert.deepEqual(rel2._notConditions, [{ role: 'guest' }]);
      // Different instances
      assert.notEqual(rel1, rel2);
    });

    it('chains multiple NOT conditions', () => {
      const rel = new Relation(MockModel)
        .not({ deleted: true })
        .not({ banned: true });

      assert.deepEqual(rel._notConditions, [
        { deleted: true },
        { banned: true }
      ]);
    });

    it('combines with where() conditions', () => {
      const rel = new Relation(MockModel)
        .where({ active: true })
        .not({ role: 'guest' });

      assert.deepEqual(rel._conditions, [{ active: true }]);
      assert.deepEqual(rel._notConditions, [{ role: 'guest' }]);
    });
  });

  describe('SQL building', () => {
    it('builds NOT clause for single condition', () => {
      const rel = new Relation(MockModel).not({ deleted: true });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE NOT (deleted = ?)');
      assert.deepEqual(values, [true]);
    });

    it('builds NOT clause with multiple fields', () => {
      const rel = new Relation(MockModel).not({ deleted: true, banned: true });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE NOT (deleted = ? AND banned = ?)');
      assert.deepEqual(values, [true, true]);
    });

    it('combines WHERE and NOT correctly', () => {
      const rel = new Relation(MockModel)
        .where({ active: true })
        .not({ role: 'guest' });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE active = ? AND NOT (role = ?)');
      assert.deepEqual(values, [true, 'guest']);
    });

    it('handles NOT with IN clause', () => {
      const rel = new Relation(MockModel).not({ role: ['guest', 'banned'] });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE NOT (role IN (?, ?))');
      assert.deepEqual(values, ['guest', 'banned']);
    });

    it('handles NOT with NULL', () => {
      const rel = new Relation(MockModel).not({ deleted_at: null });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE NOT (deleted_at IS NULL)');
      assert.deepEqual(values, []);
    });
  });
});

// --- OR Conditions Tests ---

describe('OR conditions', () => {
  describe('or() method', () => {
    it('accepts conditions object directly', () => {
      const rel = new Relation(MockModel)
        .where({ admin: true })
        .or({ moderator: true });

      assert.deepEqual(rel._conditions, [{ admin: true }]);
      assert.deepEqual(rel._orConditions, [[{ moderator: true }]]);
    });

    it('accepts another Relation', () => {
      const rel1 = new Relation(MockModel).where({ admin: true });
      const rel2 = new Relation(MockModel).where({ moderator: true });
      const combined = rel1.or(rel2);

      assert.deepEqual(combined._conditions, [{ admin: true }]);
      assert.deepEqual(combined._orConditions, [[{ moderator: true }]]);
    });

    it('chains multiple OR conditions', () => {
      const rel = new Relation(MockModel)
        .where({ admin: true })
        .or({ moderator: true })
        .or({ editor: true });

      assert.deepEqual(rel._orConditions, [
        [{ moderator: true }],
        [{ editor: true }]
      ]);
    });
  });

  describe('SQL building', () => {
    it('builds OR with base condition', () => {
      const rel = new Relation(MockModel)
        .where({ admin: true })
        .or({ moderator: true });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE (admin = ?) OR (moderator = ?)');
      assert.deepEqual(values, [true, true]);
    });

    it('builds multiple OR alternatives', () => {
      const rel = new Relation(MockModel)
        .where({ admin: true })
        .or({ moderator: true })
        .or({ editor: true });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE (admin = ?) OR (moderator = ?) OR (editor = ?)');
      assert.deepEqual(values, [true, true, true]);
    });

    it('builds OR with Relation containing multiple conditions', () => {
      const rel = new Relation(MockModel)
        .where({ active: true })
        .or(new Relation(MockModel).where({ role: 'admin' }).where({ verified: true }));
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE (active = ?) OR (role = ? AND verified = ?)');
      assert.deepEqual(values, [true, 'admin', true]);
    });

    it('handles OR only (no base conditions)', () => {
      const rel = new Relation(MockModel)
        .or({ admin: true })
        .or({ moderator: true });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE (admin = ?) OR (moderator = ?)');
      assert.deepEqual(values, [true, true]);
    });
  });
});

// --- Combined NOT and OR Tests ---

describe('NOT and OR combined', () => {
  it('builds WHERE with NOT and OR', () => {
    const rel = new Relation(MockModel)
      .where({ active: true })
      .not({ banned: true })
      .or({ admin: true });
    const { sql, values } = MockModel._buildRelationSQL(rel);

    assert.equal(sql, 'SELECT * FROM users WHERE (active = ? AND NOT (banned = ?)) OR (admin = ?)');
    assert.deepEqual(values, [true, true, true]);
  });
});

// --- ActiveRecord Static Method Tests ---

describe('ActiveRecordSQL static methods', () => {
  beforeEach(() => {
    MockModel.resetQueries();
  });

  describe('all()', () => {
    it('returns a Relation', () => {
      const rel = MockModel.all();
      assert.ok(rel instanceof Relation);
      assert.equal(rel.model, MockModel);
    });
  });

  describe('where()', () => {
    it('returns a Relation with conditions', () => {
      const rel = MockModel.where({ active: true });
      assert.ok(rel instanceof Relation);
      assert.deepEqual(rel._conditions, [{ active: true }]);
    });
  });

  describe('order()', () => {
    it('returns a Relation with ordering', () => {
      const rel = MockModel.order('name');
      assert.ok(rel instanceof Relation);
      assert.equal(rel._order, 'name');
    });
  });

  describe('limit()', () => {
    it('returns a Relation with limit', () => {
      const rel = MockModel.limit(5);
      assert.ok(rel instanceof Relation);
      assert.equal(rel._limit, 5);
    });
  });

  describe('offset()', () => {
    it('returns a Relation with offset', () => {
      const rel = MockModel.offset(10);
      assert.ok(rel instanceof Relation);
      assert.equal(rel._offset, 10);
    });
  });

  describe('chaining from static methods', () => {
    it('chains where().order().limit()', async () => {
      await MockModel.where({ active: true }).order('name').limit(5);

      assert.equal(MockModel._executedQueries.length, 1);
      const { sql, params } = MockModel._executedQueries[0];
      assert.equal(sql, 'SELECT * FROM users WHERE active = ? ORDER BY name ASC LIMIT 5');
      assert.deepEqual(params, [true]);
    });
  });
});

// --- Terminal Method Tests ---

describe('Terminal methods', () => {
  // Create a model with test data
  class MockModelWithData extends ActiveRecordSQL {
    static tableName = 'items';
    static get useNumberedParams() { return false; }

    static _testData = [
      { id: 1, name: 'First' },
      { id: 2, name: 'Second' },
      { id: 3, name: 'Third' }
    ];

    static async _execute(sql, params) {
      // Simple simulation - return all data or filtered
      if (sql.includes('COUNT')) {
        return { rows: [{ count: this._testData.length }], type: 'count' };
      }
      return { rows: this._testData, type: 'select' };
    }

    static _getRows(result) {
      return result.rows;
    }

    static _getLastInsertId(result) {
      return 1;
    }

    constructor(attrs) {
      super(attrs);
      Object.assign(this, attrs);
    }
  }

  describe('first()', () => {
    it('returns first record', async () => {
      const item = await new Relation(MockModelWithData).first();
      assert.equal(item.id, 1);
      assert.equal(item.name, 'First');
    });

    it('returns null for empty result', async () => {
      class EmptyModel extends MockModelWithData {
        static _testData = [];
      }
      const item = await new Relation(EmptyModel).first();
      assert.equal(item, null);
    });
  });

  describe('last()', () => {
    it('returns last record (uses reversed order)', async () => {
      const item = await new Relation(MockModelWithData).last();
      // Note: with mock data this returns first since we don't actually reorder
      assert.ok(item !== null);
    });
  });

  describe('count()', () => {
    it('returns count of records', async () => {
      const count = await new Relation(MockModelWithData).count();
      assert.equal(count, 3);
    });
  });

  describe('toArray()', () => {
    it('returns array of model instances', async () => {
      const items = await new Relation(MockModelWithData).toArray();
      assert.equal(items.length, 3);
      assert.ok(items[0] instanceof MockModelWithData);
    });
  });

  describe('find() within relation', () => {
    it('finds by id within scoped relation', async () => {
      const item = await new Relation(MockModelWithData).find(1);
      assert.equal(item.id, 1);
    });

    it('throws when not found', async () => {
      class EmptyModel extends MockModelWithData {
        static name = 'EmptyModel';
        static _testData = [];
      }
      await assert.rejects(
        async () => await new Relation(EmptyModel).find(999),
        /EmptyModel not found with id=999/
      );
    });
  });

  describe('findBy() within relation', () => {
    it('finds by conditions', async () => {
      const item = await new Relation(MockModelWithData).findBy({ name: 'First' });
      assert.ok(item !== null);
    });

    it('returns null when not found', async () => {
      class EmptyModel extends MockModelWithData {
        static _testData = [];
      }
      const item = await new Relation(EmptyModel).findBy({ name: 'Nonexistent' });
      assert.equal(item, null);
    });
  });
});

// --- Edge Cases ---

describe('Edge cases', () => {
  describe('empty conditions', () => {
    it('handles empty where object', () => {
      const rel = new Relation(MockModel).where({});
      const { sql, values } = MockModel._buildRelationSQL(rel);

      // Empty condition object shouldn't add WHERE clause
      assert.equal(sql, 'SELECT * FROM users');
      assert.deepEqual(values, []);
    });
  });

  describe('zero values', () => {
    it('handles limit(0)', () => {
      const rel = new Relation(MockModel).limit(0);
      const { sql } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users LIMIT 0');
    });

    it('handles offset(0)', () => {
      const rel = new Relation(MockModel).offset(0);
      const { sql } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users OFFSET 0');
    });
  });

  describe('empty IN clause', () => {
    it('handles empty array in where', () => {
      const rel = new Relation(MockModel).where({ id: [] });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      // Empty IN clause
      assert.equal(sql, 'SELECT * FROM users WHERE id IN ()');
      assert.deepEqual(values, []);
    });
  });

  describe('special values', () => {
    it('handles numeric string values', () => {
      const rel = new Relation(MockModel).where({ code: '123' });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE code = ?');
      assert.deepEqual(values, ['123']);
    });

    it('handles zero as value', () => {
      const rel = new Relation(MockModel).where({ count: 0 });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE count = ?');
      assert.deepEqual(values, [0]);
    });

    it('handles false as value', () => {
      const rel = new Relation(MockModel).where({ active: false });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE active = ?');
      assert.deepEqual(values, [false]);
    });

    it('handles empty string as value', () => {
      const rel = new Relation(MockModel).where({ name: '' });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE name = ?');
      assert.deepEqual(values, ['']);
    });
  });
});

// --- Phase 3: Query Refinement Tests ---

describe('SELECT columns', () => {
  describe('select() method', () => {
    it('sets selected columns and returns new Relation', () => {
      const rel1 = new Relation(MockModel);
      const rel2 = rel1.select('id', 'name');

      assert.equal(rel1._select, null);
      assert.deepEqual(rel2._select, ['id', 'name']);
      assert.notEqual(rel1, rel2);
    });

    it('chains with other methods', () => {
      const rel = new Relation(MockModel)
        .select('id', 'name')
        .where({ active: true })
        .limit(10);

      assert.deepEqual(rel._select, ['id', 'name']);
      assert.deepEqual(rel._conditions, [{ active: true }]);
      assert.equal(rel._limit, 10);
    });
  });

  describe('SQL building', () => {
    it('builds SELECT with specific columns', () => {
      const rel = new Relation(MockModel).select('id', 'name');
      const { sql } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT id, name FROM users');
    });

    it('builds SELECT with single column', () => {
      const rel = new Relation(MockModel).select('name');
      const { sql } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT name FROM users');
    });

    it('combines SELECT with WHERE', () => {
      const rel = new Relation(MockModel)
        .select('id', 'email')
        .where({ active: true });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT id, email FROM users WHERE active = ?');
      assert.deepEqual(values, [true]);
    });
  });
});

describe('DISTINCT', () => {
  describe('distinct() method', () => {
    it('sets distinct flag and returns new Relation', () => {
      const rel1 = new Relation(MockModel);
      const rel2 = rel1.distinct();

      assert.equal(rel1._distinct, false);
      assert.equal(rel2._distinct, true);
      assert.notEqual(rel1, rel2);
    });

    it('chains with select()', () => {
      const rel = new Relation(MockModel).distinct().select('role');

      assert.equal(rel._distinct, true);
      assert.deepEqual(rel._select, ['role']);
    });
  });

  describe('SQL building', () => {
    it('builds SELECT DISTINCT *', () => {
      const rel = new Relation(MockModel).distinct();
      const { sql } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT DISTINCT * FROM users');
    });

    it('builds SELECT DISTINCT with columns', () => {
      const rel = new Relation(MockModel).distinct().select('role');
      const { sql } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT DISTINCT role FROM users');
    });

    it('builds COUNT DISTINCT', () => {
      const rel = new Relation(MockModel).distinct();
      const { sql } = MockModel._buildRelationSQL(rel, { count: true });

      assert.equal(sql, 'SELECT COUNT(DISTINCT *) as count FROM users');
    });

    it('builds COUNT DISTINCT with column', () => {
      const rel = new Relation(MockModel).distinct().select('role');
      const { sql } = MockModel._buildRelationSQL(rel, { count: true });

      assert.equal(sql, 'SELECT COUNT(DISTINCT role) as count FROM users');
    });
  });
});

describe('exists()', () => {
  // Mock model that tracks SQL and returns data
  class MockExistsModel extends ActiveRecordSQL {
    static tableName = 'items';
    static get useNumberedParams() { return false; }
    static _lastQuery = null;

    static async _execute(sql, params) {
      this._lastQuery = { sql, params };
      // Return one row if not checking for nonexistent
      if (sql.includes('nonexistent')) {
        return { rows: [] };
      }
      return { rows: [{ '1': 1 }] };
    }

    static _getRows(result) {
      return result.rows;
    }

    static _getLastInsertId(result) {
      return 1;
    }
  }

  it('returns true when records exist', async () => {
    const result = await new Relation(MockExistsModel).where({ active: true }).exists();
    assert.equal(result, true);
  });

  it('returns false when no records exist', async () => {
    class EmptyModel extends MockExistsModel {
      static async _execute(sql, params) {
        return { rows: [] };
      }
    }
    const result = await new Relation(EmptyModel).exists();
    assert.equal(result, false);
  });

  it('uses LIMIT 1 for efficiency', async () => {
    await new Relation(MockExistsModel).exists();
    assert.ok(MockExistsModel._lastQuery.sql.includes('LIMIT 1'));
  });

  it('selects minimal columns', async () => {
    await new Relation(MockExistsModel).exists();
    assert.ok(MockExistsModel._lastQuery.sql.includes('SELECT 1'));
  });
});

describe('pluck()', () => {
  class MockPluckModel extends ActiveRecordSQL {
    static tableName = 'items';
    static get useNumberedParams() { return false; }
    static _lastQuery = null;

    static async _execute(sql, params) {
      this._lastQuery = { sql, params };
      // Return mock data based on selected columns
      if (sql.includes('SELECT name')) {
        return { rows: [{ name: 'Alice' }, { name: 'Bob' }, { name: 'Carol' }] };
      }
      if (sql.includes('SELECT id, name')) {
        return { rows: [
          { id: 1, name: 'Alice' },
          { id: 2, name: 'Bob' },
          { id: 3, name: 'Carol' }
        ]};
      }
      return { rows: [] };
    }

    static _getRows(result) {
      return result.rows;
    }

    static _getLastInsertId(result) {
      return 1;
    }
  }

  describe('single column', () => {
    it('returns flat array of values', async () => {
      const names = await new Relation(MockPluckModel).pluck('name');

      assert.deepEqual(names, ['Alice', 'Bob', 'Carol']);
    });

    it('executes SELECT with the column', async () => {
      await new Relation(MockPluckModel).pluck('name');

      assert.ok(MockPluckModel._lastQuery.sql.includes('SELECT name'));
    });
  });

  describe('multiple columns', () => {
    it('returns array of arrays', async () => {
      const values = await new Relation(MockPluckModel).pluck('id', 'name');

      assert.deepEqual(values, [
        [1, 'Alice'],
        [2, 'Bob'],
        [3, 'Carol']
      ]);
    });

    it('executes SELECT with all columns', async () => {
      await new Relation(MockPluckModel).pluck('id', 'name');

      assert.ok(MockPluckModel._lastQuery.sql.includes('SELECT id, name'));
    });
  });

  describe('with conditions', () => {
    it('combines pluck with where', async () => {
      await new Relation(MockPluckModel).where({ active: true }).pluck('name');

      assert.ok(MockPluckModel._lastQuery.sql.includes('WHERE active = ?'));
      assert.ok(MockPluckModel._lastQuery.sql.includes('SELECT name'));
    });
  });
});

describe('Static convenience methods', () => {
  beforeEach(() => {
    MockModel.resetQueries();
  });

  describe('select()', () => {
    it('returns a Relation with selected columns', () => {
      const rel = MockModel.select('id', 'name');
      assert.ok(rel instanceof Relation);
      assert.deepEqual(rel._select, ['id', 'name']);
    });
  });

  describe('distinct()', () => {
    it('returns a Relation with distinct flag', () => {
      const rel = MockModel.distinct();
      assert.ok(rel instanceof Relation);
      assert.equal(rel._distinct, true);
    });
  });

  describe('exists()', () => {
    it('executes and returns boolean', async () => {
      const result = await MockModel.exists();
      // Will be false since mock returns empty
      assert.equal(typeof result, 'boolean');
    });
  });

  describe('pluck()', () => {
    it('executes and returns array', async () => {
      const result = await MockModel.pluck('name');
      assert.ok(Array.isArray(result));
    });
  });

  describe('chaining select with distinct', () => {
    it('chains select().distinct()', async () => {
      await MockModel.select('role').distinct().where({ active: true });

      assert.equal(MockModel._executedQueries.length, 1);
      const { sql } = MockModel._executedQueries[0];
      assert.equal(sql, 'SELECT DISTINCT role FROM users WHERE active = ?');
    });

    it('chains distinct().select()', async () => {
      await MockModel.distinct().select('role');

      assert.equal(MockModel._executedQueries.length, 1);
      const { sql } = MockModel._executedQueries[0];
      assert.equal(sql, 'SELECT DISTINCT role FROM users');
    });
  });
});

// --- Phase 4: Associations Tests ---

describe('includes() method', () => {
  it('adds includes and returns new Relation', () => {
    const rel1 = new Relation(MockModel);
    const rel2 = rel1.includes('posts');

    assert.deepEqual(rel1._includes, []);
    assert.deepEqual(rel2._includes, ['posts']);
    assert.notEqual(rel1, rel2);
  });

  it('chains multiple includes', () => {
    const rel = new Relation(MockModel)
      .includes('posts')
      .includes('comments');

    assert.deepEqual(rel._includes, ['posts', 'comments']);
  });

  it('accepts multiple associations in one call', () => {
    const rel = new Relation(MockModel).includes('posts', 'comments');

    assert.deepEqual(rel._includes, ['posts', 'comments']);
  });

  it('accepts nested includes as objects', () => {
    const rel = new Relation(MockModel).includes({ posts: 'comments' });

    assert.deepEqual(rel._includes, [{ posts: 'comments' }]);
  });

  it('clones includes array', () => {
    const rel1 = new Relation(MockModel).includes('posts');
    const rel2 = rel1._clone();

    rel2._includes.push('comments');
    assert.deepEqual(rel1._includes, ['posts']);
    assert.deepEqual(rel2._includes, ['posts', 'comments']);
  });
});

describe('Association loading', () => {
  // Mock models with associations
  let queryLog = [];

  class Author extends ActiveRecordSQL {
    static tableName = 'authors';
    static get useNumberedParams() { return false; }

    static associations = {
      posts: { type: 'has_many', model: 'Post', foreignKey: 'author_id' },
      profile: { type: 'has_one', model: 'Profile', foreignKey: 'author_id' }
    };

    static _testData = [
      { id: 1, name: 'Alice' },
      { id: 2, name: 'Bob' },
      { id: 3, name: 'Carol' }
    ];

    static async _execute(sql, params) {
      queryLog.push({ sql, params });
      if (sql.includes('FROM authors')) {
        return { rows: this._testData };
      }
      return { rows: [] };
    }

    static _getRows(result) { return result.rows; }
    static _getLastInsertId(result) { return 1; }

    constructor(attrs) {
      super(attrs);
      Object.assign(this, attrs);
    }

    get posts() { return this._posts; }
  }

  class Post extends ActiveRecordSQL {
    static tableName = 'posts';
    static get useNumberedParams() { return false; }

    static associations = {
      author: { type: 'belongs_to', model: 'Author', foreignKey: 'author_id' },
      comments: { type: 'has_many', model: 'Comment', foreignKey: 'post_id' }
    };

    static _testData = [
      { id: 1, title: 'Post 1', author_id: 1 },
      { id: 2, title: 'Post 2', author_id: 1 },
      { id: 3, title: 'Post 3', author_id: 2 }
    ];

    static async _execute(sql, params) {
      queryLog.push({ sql, params });
      if (sql.includes('FROM posts')) {
        // Filter by author_id if IN clause is present
        if (sql.includes('author_id IN')) {
          const ids = params || [];
          return { rows: this._testData.filter(p => ids.includes(p.author_id)) };
        }
        return { rows: this._testData };
      }
      return { rows: [] };
    }

    static _getRows(result) { return result.rows; }
    static _getLastInsertId(result) { return 1; }

    constructor(attrs) {
      super(attrs);
      Object.assign(this, attrs);
    }

    get comments() { return this._comments; }
  }

  class Comment extends ActiveRecordSQL {
    static tableName = 'comments';
    static get useNumberedParams() { return false; }

    static associations = {
      post: { type: 'belongs_to', model: 'Post', foreignKey: 'post_id' }
    };

    static _testData = [
      { id: 1, body: 'Comment 1', post_id: 1 },
      { id: 2, body: 'Comment 2', post_id: 1 },
      { id: 3, body: 'Comment 3', post_id: 2 }
    ];

    static async _execute(sql, params) {
      queryLog.push({ sql, params });
      if (sql.includes('FROM comments')) {
        if (sql.includes('post_id IN')) {
          const ids = params || [];
          return { rows: this._testData.filter(c => ids.includes(c.post_id)) };
        }
        return { rows: this._testData };
      }
      return { rows: [] };
    }

    static _getRows(result) { return result.rows; }
    static _getLastInsertId(result) { return 1; }

    constructor(attrs) {
      super(attrs);
      Object.assign(this, attrs);
    }
  }

  class Profile extends ActiveRecordSQL {
    static tableName = 'profiles';
    static get useNumberedParams() { return false; }

    static associations = {
      author: { type: 'belongs_to', model: 'Author', foreignKey: 'author_id' }
    };

    static _testData = [
      { id: 1, bio: 'Alice bio', author_id: 1 },
      { id: 2, bio: 'Bob bio', author_id: 2 }
    ];

    static async _execute(sql, params) {
      queryLog.push({ sql, params });
      if (sql.includes('FROM profiles')) {
        if (sql.includes('author_id IN')) {
          const ids = params || [];
          return { rows: this._testData.filter(p => ids.includes(p.author_id)) };
        }
        return { rows: this._testData };
      }
      return { rows: [] };
    }

    static _getRows(result) { return result.rows; }
    static _getLastInsertId(result) { return 1; }

    constructor(attrs) {
      super(attrs);
      Object.assign(this, attrs);
    }
  }

  // Register models before tests
  beforeEach(() => {
    queryLog = [];
    modelRegistry['Author'] = Author;
    modelRegistry['Post'] = Post;
    modelRegistry['Comment'] = Comment;
    modelRegistry['Profile'] = Profile;
  });

  describe('belongs_to', () => {
    it('loads belongs_to association', async () => {
      // Setup: make Post return data with author_id
      const originalExecute = Post._execute;
      Post._execute = async (sql, params) => {
        queryLog.push({ sql, params });
        if (sql.includes('FROM posts')) {
          return { rows: [{ id: 1, title: 'Test Post', author_id: 1 }] };
        }
        if (sql.includes('FROM authors')) {
          return { rows: [{ id: 1, name: 'Alice' }] };
        }
        return { rows: [] };
      };
      Author._execute = async (sql, params) => {
        queryLog.push({ sql, params });
        if (sql.includes('FROM authors')) {
          return { rows: [{ id: 1, name: 'Alice' }] };
        }
        return { rows: [] };
      };

      const posts = await Post.includes('author');

      assert.equal(posts.length, 1);
      assert.equal(posts[0].author.name, 'Alice');
      assert.ok(posts[0].author instanceof Author);

      // Restore
      Post._execute = originalExecute;
    });

    it('handles null foreign key', async () => {
      const originalExecute = Post._execute;
      Post._execute = async (sql, params) => {
        queryLog.push({ sql, params });
        if (sql.includes('FROM posts')) {
          return { rows: [{ id: 1, title: 'Orphan Post', author_id: null }] };
        }
        return { rows: [] };
      };

      const posts = await Post.includes('author');

      assert.equal(posts.length, 1);
      assert.equal(posts[0].author, null);

      Post._execute = originalExecute;
    });
  });

  describe('has_many', () => {
    it('loads has_many association', async () => {
      const originalAuthorExecute = Author._execute;
      const originalPostExecute = Post._execute;

      Author._execute = async (sql, params) => {
        queryLog.push({ sql, params });
        return { rows: [{ id: 1, name: 'Alice' }] };
      };
      Post._execute = async (sql, params) => {
        queryLog.push({ sql, params });
        if (sql.includes('author_id IN')) {
          return { rows: [
            { id: 1, title: 'Post 1', author_id: 1 },
            { id: 2, title: 'Post 2', author_id: 1 }
          ]};
        }
        return { rows: [] };
      };

      const authors = await Author.includes('posts');

      assert.equal(authors.length, 1);
      assert.equal(authors[0].posts.length, 2);
      assert.equal(authors[0].posts.at(0).title, 'Post 1');
      assert.ok(authors[0].posts.at(0) instanceof Post);

      Author._execute = originalAuthorExecute;
      Post._execute = originalPostExecute;
    });

    it('returns empty array for no matches', async () => {
      const originalAuthorExecute = Author._execute;
      const originalPostExecute = Post._execute;

      Author._execute = async (sql, params) => {
        return { rows: [{ id: 99, name: 'New Author' }] };
      };
      Post._execute = async (sql, params) => {
        return { rows: [] };
      };

      const authors = await Author.includes('posts');

      assert.equal(authors.length, 1);
      assert.deepEqual(authors[0].posts.toArray(), []);

      Author._execute = originalAuthorExecute;
      Post._execute = originalPostExecute;
    });
  });

  describe('has_one', () => {
    it('loads has_one association', async () => {
      const originalAuthorExecute = Author._execute;
      const originalProfileExecute = Profile._execute;

      Author._execute = async (sql, params) => {
        return { rows: [{ id: 1, name: 'Alice' }] };
      };
      Profile._execute = async (sql, params) => {
        if (sql.includes('author_id IN')) {
          return { rows: [{ id: 1, bio: 'Alice bio', author_id: 1 }] };
        }
        return { rows: [] };
      };

      const authors = await Author.includes('profile');

      assert.equal(authors.length, 1);
      assert.equal(authors[0].profile.bio, 'Alice bio');
      assert.ok(authors[0].profile instanceof Profile);

      Author._execute = originalAuthorExecute;
      Profile._execute = originalProfileExecute;
    });
  });

  describe('nested includes', () => {
    it('loads nested associations', async () => {
      const originalAuthorExecute = Author._execute;
      const originalPostExecute = Post._execute;
      const originalCommentExecute = Comment._execute;

      Author._execute = async (sql, params) => {
        return { rows: [{ id: 1, name: 'Alice' }] };
      };
      Post._execute = async (sql, params) => {
        if (sql.includes('author_id IN')) {
          return { rows: [{ id: 1, title: 'Post 1', author_id: 1 }] };
        }
        return { rows: [] };
      };
      Comment._execute = async (sql, params) => {
        if (sql.includes('post_id IN')) {
          return { rows: [
            { id: 1, body: 'Comment 1', post_id: 1 },
            { id: 2, body: 'Comment 2', post_id: 1 }
          ]};
        }
        return { rows: [] };
      };

      const authors = await Author.includes({ posts: 'comments' });

      assert.equal(authors.length, 1);
      assert.equal(authors[0].posts.length, 1);
      assert.equal(authors[0].posts.at(0).comments.length, 2);
      assert.equal(authors[0].posts.at(0).comments.at(0).body, 'Comment 1');

      Author._execute = originalAuthorExecute;
      Post._execute = originalPostExecute;
      Comment._execute = originalCommentExecute;
    });

    it('supports array of nested includes', async () => {
      const originalAuthorExecute = Author._execute;
      const originalPostExecute = Post._execute;
      const originalProfileExecute = Profile._execute;

      Author._execute = async (sql, params) => {
        return { rows: [{ id: 1, name: 'Alice' }] };
      };
      Post._execute = async (sql, params) => {
        if (sql.includes('author_id IN')) {
          return { rows: [{ id: 1, title: 'Post 1', author_id: 1 }] };
        }
        return { rows: [] };
      };
      Profile._execute = async (sql, params) => {
        if (sql.includes('author_id IN')) {
          return { rows: [{ id: 1, bio: 'Bio', author_id: 1 }] };
        }
        return { rows: [] };
      };

      const authors = await Author.includes('posts', 'profile');

      assert.equal(authors.length, 1);
      assert.equal(authors[0].posts.length, 1);
      assert.equal(authors[0].profile.bio, 'Bio');

      Author._execute = originalAuthorExecute;
      Post._execute = originalPostExecute;
      Profile._execute = originalProfileExecute;
    });
  });

  describe('N+1 prevention', () => {
    it('uses batch loading for belongs_to', async () => {
      const originalPostExecute = Post._execute;
      const originalAuthorExecute = Author._execute;

      Post._execute = async (sql, params) => {
        queryLog.push({ sql, params });
        return { rows: [
          { id: 1, title: 'Post 1', author_id: 1 },
          { id: 2, title: 'Post 2', author_id: 2 },
          { id: 3, title: 'Post 3', author_id: 1 }
        ]};
      };
      Author._execute = async (sql, params) => {
        queryLog.push({ sql, params });
        // Should receive both author IDs in one query
        if (sql.includes('id IN')) {
          return { rows: [
            { id: 1, name: 'Alice' },
            { id: 2, name: 'Bob' }
          ]};
        }
        return { rows: [] };
      };

      queryLog = [];
      const posts = await Post.includes('author');

      // Should be 2 queries: one for posts, one for authors (batch)
      assert.equal(queryLog.length, 2);
      assert.ok(queryLog[1].sql.includes('id IN'));

      Post._execute = originalPostExecute;
      Author._execute = originalAuthorExecute;
    });

    it('uses batch loading for has_many', async () => {
      const originalAuthorExecute = Author._execute;
      const originalPostExecute = Post._execute;

      Author._execute = async (sql, params) => {
        queryLog.push({ sql, params });
        return { rows: [
          { id: 1, name: 'Alice' },
          { id: 2, name: 'Bob' }
        ]};
      };
      Post._execute = async (sql, params) => {
        queryLog.push({ sql, params });
        if (sql.includes('author_id IN')) {
          return { rows: [
            { id: 1, title: 'Post 1', author_id: 1 },
            { id: 2, title: 'Post 2', author_id: 2 },
            { id: 3, title: 'Post 3', author_id: 1 }
          ]};
        }
        return { rows: [] };
      };

      queryLog = [];
      const authors = await Author.includes('posts');

      // Should be 2 queries: one for authors, one for posts (batch)
      assert.equal(queryLog.length, 2);
      assert.ok(queryLog[1].sql.includes('author_id IN'));

      // Verify correct assignment
      assert.equal(authors[0].posts.length, 2); // Alice has 2 posts
      assert.equal(authors[1].posts.length, 1); // Bob has 1 post

      Author._execute = originalAuthorExecute;
      Post._execute = originalPostExecute;
    });
  });

  describe('static includes() method', () => {
    it('returns a Relation with includes', () => {
      const rel = Author.includes('posts');
      assert.ok(rel instanceof Relation);
      assert.deepEqual(rel._includes, ['posts']);
    });

    it('chains with other methods', async () => {
      const originalExecute = Author._execute;
      Author._execute = async (sql, params) => {
        queryLog.push({ sql, params });
        return { rows: [] };
      };
      Post._execute = async () => ({ rows: [] });

      queryLog = [];
      await Author.where({ active: true }).includes('posts').limit(5);

      assert.equal(queryLog.length, 1);
      assert.ok(queryLog[0].sql.includes('WHERE active = ?'));
      assert.ok(queryLog[0].sql.includes('LIMIT 5'));

      Author._execute = originalExecute;
    });
  });
});

describe('Model registry', () => {
  it('registers and retrieves models', () => {
    class TestModel extends ActiveRecordSQL {
      static tableName = 'tests';
    }

    modelRegistry['TestModel'] = TestModel;

    const resolved = ActiveRecordSQL._resolveModel('TestModel');
    assert.equal(resolved, TestModel);
  });

  it('throws for unregistered model', () => {
    assert.throws(
      () => ActiveRecordSQL._resolveModel('NonexistentModel'),
      /not found in registry/
    );
  });

  it('returns model class directly if passed a class', () => {
    class DirectModel extends ActiveRecordSQL {
      static tableName = 'direct';
    }

    const resolved = ActiveRecordSQL._resolveModel(DirectModel);
    assert.equal(resolved, DirectModel);
  });
});

describe('Inflector', () => {
  describe('singularize', () => {
    it('removes trailing s', () => {
      assert.equal(singularize('users'), 'user');
      assert.equal(singularize('posts'), 'post');
    });

    it('handles -ies suffix', () => {
      assert.equal(singularize('categories'), 'category');
      assert.equal(singularize('entries'), 'entry');
    });

    it('handles -es suffix', () => {
      assert.equal(singularize('boxes'), 'box');
      assert.equal(singularize('matches'), 'match');
    });

    it('leaves singular words unchanged', () => {
      assert.equal(singularize('user'), 'user');
      assert.equal(singularize('post'), 'post');
    });

    it('handles irregular words', () => {
      assert.equal(singularize('people'), 'person');
      assert.equal(singularize('children'), 'child');
      assert.equal(singularize('men'), 'man');
      assert.equal(singularize('women'), 'woman');
    });

    it('handles uncountable words', () => {
      assert.equal(singularize('sheep'), 'sheep');
      assert.equal(singularize('fish'), 'fish');
      assert.equal(singularize('species'), 'species');
    });

    it('preserves capitalization', () => {
      assert.equal(singularize('People'), 'Person');
      assert.equal(singularize('Children'), 'Child');
    });
  });

  describe('pluralize', () => {
    it('adds trailing s', () => {
      assert.equal(pluralize('user'), 'users');
      assert.equal(pluralize('post'), 'posts');
    });

    it('handles -y suffix', () => {
      assert.equal(pluralize('category'), 'categories');
      assert.equal(pluralize('entry'), 'entries');
    });

    it('handles -x, -ch, -sh suffix', () => {
      assert.equal(pluralize('box'), 'boxes');
      assert.equal(pluralize('match'), 'matches');
      assert.equal(pluralize('bush'), 'bushes');
    });

    it('handles irregular words', () => {
      assert.equal(pluralize('person'), 'people');
      assert.equal(pluralize('child'), 'children');
      assert.equal(pluralize('man'), 'men');
      assert.equal(pluralize('woman'), 'women');
    });

    it('handles uncountable words', () => {
      assert.equal(pluralize('sheep'), 'sheep');
      assert.equal(pluralize('fish'), 'fish');
      assert.equal(pluralize('species'), 'species');
    });

    it('preserves capitalization', () => {
      assert.equal(pluralize('Person'), 'People');
      assert.equal(pluralize('Child'), 'Children');
    });
  });
});

// --- Raw SQL Conditions Tests ---

describe('Raw SQL conditions', () => {
  describe('where() with string SQL', () => {
    it('stores raw condition with values', () => {
      const rel = new Relation(MockModel)
        .where('updated_at > ?', '2024-01-01');

      assert.deepEqual(rel._rawConditions, [
        { sql: 'updated_at > ?', values: ['2024-01-01'] }
      ]);
    });

    it('stores multiple raw conditions', () => {
      const rel = new Relation(MockModel)
        .where('created_at > ?', '2024-01-01')
        .where('created_at < ?', '2024-12-31');

      assert.equal(rel._rawConditions.length, 2);
      assert.deepEqual(rel._rawConditions[0], { sql: 'created_at > ?', values: ['2024-01-01'] });
      assert.deepEqual(rel._rawConditions[1], { sql: 'created_at < ?', values: ['2024-12-31'] });
    });

    it('handles multiple placeholders', () => {
      const rel = new Relation(MockModel)
        .where('created_at BETWEEN ? AND ?', '2024-01-01', '2024-12-31');

      assert.deepEqual(rel._rawConditions, [
        { sql: 'created_at BETWEEN ? AND ?', values: ['2024-01-01', '2024-12-31'] }
      ]);
    });

    it('mixes with hash conditions', () => {
      const rel = new Relation(MockModel)
        .where({ active: true })
        .where('score > ?', 100);

      assert.deepEqual(rel._conditions, [{ active: true }]);
      assert.deepEqual(rel._rawConditions, [{ sql: 'score > ?', values: [100] }]);
    });

    it('clones raw conditions', () => {
      const rel1 = new Relation(MockModel).where('age > ?', 18);
      const rel2 = rel1._clone();

      rel2._rawConditions.push({ sql: 'age < ?', values: [65] });
      assert.equal(rel1._rawConditions.length, 1);
      assert.equal(rel2._rawConditions.length, 2);
    });
  });

  describe('SQL building with raw conditions', () => {
    it('builds single raw condition (? placeholders)', () => {
      const rel = new Relation(MockModel)
        .where('updated_at > ?', '2024-01-01');
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE updated_at > ?');
      assert.deepEqual(values, ['2024-01-01']);
    });

    it('builds multiple raw conditions', () => {
      const rel = new Relation(MockModel)
        .where('created_at > ?', '2024-01-01')
        .where('created_at < ?', '2024-12-31');
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE created_at > ? AND created_at < ?');
      assert.deepEqual(values, ['2024-01-01', '2024-12-31']);
    });

    it('builds raw condition with multiple placeholders', () => {
      const rel = new Relation(MockModel)
        .where('age BETWEEN ? AND ?', 18, 65);
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE age BETWEEN ? AND ?');
      assert.deepEqual(values, [18, 65]);
    });

    it('combines hash and raw conditions', () => {
      const rel = new Relation(MockModel)
        .where({ active: true })
        .where('score > ?', 100);
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE active = ? AND score > ?');
      assert.deepEqual(values, [true, 100]);
    });

    it('combines raw with NOT and OR conditions', () => {
      const rel = new Relation(MockModel)
        .where({ active: true })
        .where('score > ?', 100)
        .not({ banned: true });
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE active = ? AND NOT (banned = ?) AND score > ?');
      assert.deepEqual(values, [true, true, 100]);
    });

    it('works with ORDER, LIMIT, OFFSET', () => {
      const rel = new Relation(MockModel)
        .where('updated_at > ?', '2024-01-01')
        .order({ created_at: 'desc' })
        .limit(10)
        .offset(5);
      const { sql, values } = MockModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM users WHERE updated_at > ? ORDER BY created_at DESC LIMIT 10 OFFSET 5');
      assert.deepEqual(values, ['2024-01-01']);
    });
  });

  describe('PostgreSQL numbered parameters with raw conditions', () => {
    it('converts ? to $n placeholders', () => {
      const rel = new Relation(MockPostgresModel)
        .where('updated_at > ?', '2024-01-01');
      const { sql, values } = MockPostgresModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM posts WHERE updated_at > $1');
      assert.deepEqual(values, ['2024-01-01']);
    });

    it('numbers placeholders correctly with multiple raw conditions', () => {
      const rel = new Relation(MockPostgresModel)
        .where('created_at > ?', '2024-01-01')
        .where('created_at < ?', '2024-12-31');
      const { sql, values } = MockPostgresModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM posts WHERE created_at > $1 AND created_at < $2');
      assert.deepEqual(values, ['2024-01-01', '2024-12-31']);
    });

    it('numbers placeholders correctly for multiple values in one condition', () => {
      const rel = new Relation(MockPostgresModel)
        .where('age BETWEEN ? AND ?', 18, 65);
      const { sql, values } = MockPostgresModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM posts WHERE age BETWEEN $1 AND $2');
      assert.deepEqual(values, [18, 65]);
    });

    it('numbers correctly when combining hash and raw conditions', () => {
      const rel = new Relation(MockPostgresModel)
        .where({ active: true })
        .where('score > ?', 100)
        .where({ role: 'admin' });
      const { sql, values } = MockPostgresModel._buildRelationSQL(rel);

      assert.equal(sql, 'SELECT * FROM posts WHERE active = $1 AND role = $2 AND score > $3');
      assert.deepEqual(values, [true, 'admin', 100]);
    });
  });

  describe('Static where() with raw SQL', () => {
    beforeEach(() => {
      MockModel.resetQueries();
    });

    it('accepts raw SQL condition', async () => {
      await MockModel.where('updated_at > ?', '2024-01-01');

      assert.equal(MockModel._executedQueries.length, 1);
      const { sql, params } = MockModel._executedQueries[0];
      assert.equal(sql, 'SELECT * FROM users WHERE updated_at > ?');
      assert.deepEqual(params, ['2024-01-01']);
    });

    it('chains with other methods', async () => {
      await MockModel
        .where({ active: true })
        .where('score > ?', 100)
        .order('name')
        .limit(5);

      assert.equal(MockModel._executedQueries.length, 1);
      const { sql, params } = MockModel._executedQueries[0];
      assert.equal(sql, 'SELECT * FROM users WHERE active = ? AND score > ? ORDER BY name ASC LIMIT 5');
      assert.deepEqual(params, [true, 100]);
    });
  });
});

// =============================================================================
// toSQL() introspection
// =============================================================================

describe('toSQL()', () => {
  beforeEach(() => {
    MockModel.resetQueries();
    MockPostgresModel.resetQueries();
  });

  it('returns sql and values without executing', () => {
    const rel = MockModel.where({ active: true }).order('name').limit(10);
    const { sql, values } = rel.toSQL();

    assert.equal(sql, 'SELECT * FROM users WHERE active = ? ORDER BY name ASC LIMIT 10');
    assert.deepEqual(values, [true]);
    // No query should have been executed
    assert.equal(MockModel._executedQueries.length, 0);
  });

  it('works with postgres numbered params', () => {
    const rel = MockPostgresModel.where({ title: 'hello', published: true });
    const { sql, values } = rel.toSQL();

    assert.equal(sql, 'SELECT * FROM posts WHERE title = $1 AND published = $2');
    assert.deepEqual(values, ['hello', true]);
    assert.equal(MockPostgresModel._executedQueries.length, 0);
  });

  it('works with NOT conditions', () => {
    const rel = MockModel.where({ active: true }).not({ role: 'guest' });
    const { sql, values } = rel.toSQL();

    assert.equal(sql, 'SELECT * FROM users WHERE active = ? AND NOT (role = ?)');
    assert.deepEqual(values, [true, 'guest']);
  });

  it('works with raw SQL conditions', () => {
    const rel = MockModel.where('score > ?', 100).order({ name: 'desc' });
    const { sql, values } = rel.toSQL();

    assert.equal(sql, 'SELECT * FROM users WHERE score > ? ORDER BY name DESC');
    assert.deepEqual(values, [100]);
  });

  it('works with distinct and select', () => {
    const rel = MockModel.distinct().select('name', 'email');
    const { sql, values } = rel.toSQL();

    assert.equal(sql, 'SELECT DISTINCT name, email FROM users');
    assert.deepEqual(values, []);
  });

  it('throws for models without _buildRelationSQL', () => {
    const fakeModel = { name: 'FakeModel' };
    const rel = new Relation(fakeModel);
    assert.throws(() => rel.toSQL(), /requires a model that extends ActiveRecordSQL/);
  });
});

// =============================================================================
// Comprehensive toSQL() query pattern tests
// =============================================================================

describe('toSQL() query patterns', () => {
  // Model with associations for join testing
  class Article extends ActiveRecordSQL {
    static tableName = 'articles';
    static get useNumberedParams() { return false; }
    static associations = {
      author: { type: 'belongs_to', model: 'Author', foreignKey: 'author_id' },
      comments: { type: 'has_many', model: 'Comment', foreignKey: 'article_id' },
      category: { type: 'belongs_to', model: 'Category', foreignKey: 'category_id' }
    };
    static async _execute() { return { rows: [] }; }
    static _getRows(r) { return r.rows; }
    static _getLastInsertId() { return 1; }
  }

  class ArticlePg extends ActiveRecordSQL {
    static tableName = 'articles';
    static get useNumberedParams() { return true; }
    static associations = Article.associations;
    static async _execute() { return { rows: [] }; }
    static _getRows(r) { return r.rows; }
    static _getLastInsertId() { return 1; }
  }

  modelRegistry['Article'] = Article;

  describe('WHERE patterns', () => {
    it('single equality', () => {
      const { sql, values } = MockModel.where({ name: 'Alice' }).toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE name = ?');
      assert.deepEqual(values, ['Alice']);
    });

    it('multiple equalities (AND)', () => {
      const { sql, values } = MockModel.where({ name: 'Alice', active: true }).toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE name = ? AND active = ?');
      assert.deepEqual(values, ['Alice', true]);
    });

    it('IN clause with array', () => {
      const { sql, values } = MockModel.where({ role: ['admin', 'mod'] }).toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE role IN (?, ?)');
      assert.deepEqual(values, ['admin', 'mod']);
    });

    it('IS NULL for null value', () => {
      const { sql } = MockModel.where({ deleted_at: null }).toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE deleted_at IS NULL');
    });

    it('NOT conditions', () => {
      const { sql, values } = MockModel.where({ active: true }).not({ role: 'guest' }).toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE active = ? AND NOT (role = ?)');
      assert.deepEqual(values, [true, 'guest']);
    });

    it('NOT IS NULL', () => {
      const { sql } = MockModel.where().not({ deleted_at: null }).toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE NOT (deleted_at IS NULL)');
    });

    it('NOT IN clause', () => {
      const { sql, values } = MockModel.where().not({ id: [1, 2, 3] }).toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE NOT (id IN (?, ?, ?))');
      assert.deepEqual(values, [1, 2, 3]);
    });

    it('OR conditions', () => {
      const { sql, values } = MockModel.where({ admin: true }).or({ moderator: true }).toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE (admin = ?) OR (moderator = ?)');
      assert.deepEqual(values, [true, true]);
    });

    it('OR with Relation', () => {
      const rel = MockModel.where({ admin: true }).or(MockModel.where({ role: 'mod', active: true }));
      const { sql, values } = rel.toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE (admin = ?) OR (role = ? AND active = ?)');
      assert.deepEqual(values, [true, 'mod', true]);
    });

    it('raw SQL with placeholder', () => {
      const { sql, values } = MockModel.where('age > ?', 21).toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE age > ?');
      assert.deepEqual(values, [21]);
    });

    it('raw SQL with multiple placeholders', () => {
      const { sql, values } = MockModel.where('age > ? AND age < ?', 18, 65).toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE age > ? AND age < ?');
      assert.deepEqual(values, [18, 65]);
    });

    it('chained where calls (AND)', () => {
      const { sql, values } = MockModel.where({ active: true }).where({ role: 'admin' }).toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE active = ? AND role = ?');
      assert.deepEqual(values, [true, 'admin']);
    });

    it('mixed hash and raw SQL', () => {
      const { sql, values } = MockModel.where({ active: true }).where('score > ?', 100).toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE active = ? AND score > ?');
      assert.deepEqual(values, [true, 100]);
    });
  });

  describe('ORDER patterns', () => {
    it('string column (ASC default)', () => {
      const { sql } = MockModel.order('name').toSQL();
      assert.equal(sql, 'SELECT * FROM users ORDER BY name ASC');
    });

    it('object with desc', () => {
      const { sql } = MockModel.order({ created_at: 'desc' }).toSQL();
      assert.equal(sql, 'SELECT * FROM users ORDER BY created_at DESC');
    });

    it('symbol-style :desc', () => {
      const { sql } = MockModel.order({ name: ':desc' }).toSQL();
      assert.equal(sql, 'SELECT * FROM users ORDER BY name DESC');
    });
  });

  describe('LIMIT and OFFSET', () => {
    it('limit only', () => {
      const { sql } = MockModel.limit(10).toSQL();
      assert.equal(sql, 'SELECT * FROM users LIMIT 10');
    });

    it('offset only', () => {
      const { sql } = MockModel.offset(20).toSQL();
      assert.equal(sql, 'SELECT * FROM users OFFSET 20');
    });

    it('limit + offset', () => {
      const { sql } = MockModel.limit(10).offset(20).toSQL();
      assert.equal(sql, 'SELECT * FROM users LIMIT 10 OFFSET 20');
    });
  });

  describe('SELECT and DISTINCT', () => {
    it('select specific columns', () => {
      const { sql } = MockModel.select('name', 'email').toSQL();
      assert.equal(sql, 'SELECT name, email FROM users');
    });

    it('distinct', () => {
      const { sql } = MockModel.distinct().toSQL();
      assert.equal(sql, 'SELECT DISTINCT * FROM users');
    });

    it('distinct with select', () => {
      const { sql } = MockModel.distinct().select('name').toSQL();
      assert.equal(sql, 'SELECT DISTINCT name FROM users');
    });
  });

  describe('JOIN patterns', () => {
    it('simple belongs_to join', () => {
      const { sql } = Article.joins('author').toSQL();
      assert.match(sql, /INNER JOIN authors ON articles\.author_id = authors\.id/);
    });

    it('simple has_many join', () => {
      const { sql } = Article.joins('comments').toSQL();
      assert.match(sql, /INNER JOIN comments ON comments\.article_id = articles\.id/);
    });

    it('join uses table.* for select', () => {
      const { sql } = Article.joins('comments').toSQL();
      assert.match(sql, /SELECT articles\.\*/);
    });

    it('missing() uses LEFT JOIN + IS NULL', () => {
      const { sql } = Article.where().missing('comments').toSQL();
      assert.match(sql, /LEFT JOIN comments/);
      assert.match(sql, /comments\.id IS NULL/);
    });
  });

  describe('complex combinations', () => {
    it('where + order + limit + offset', () => {
      const { sql, values } = MockModel
        .where({ active: true })
        .order({ name: 'asc' })
        .limit(10)
        .offset(20)
        .toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE active = ? ORDER BY name ASC LIMIT 10 OFFSET 20');
      assert.deepEqual(values, [true]);
    });

    it('where + not + or + order', () => {
      const { sql, values } = MockModel
        .where({ active: true })
        .not({ banned: true })
        .or({ role: 'admin' })
        .order('name')
        .toSQL();
      assert.match(sql, /WHERE.*active.*OR.*role/);
      assert.deepEqual(values, [true, true, 'admin']);
    });

    it('join + where + select + distinct', () => {
      const { sql, values } = Article
        .joins('comments')
        .where({ published: true })
        .select('title')
        .distinct()
        .toSQL();
      assert.match(sql, /SELECT DISTINCT title FROM articles/);
      assert.match(sql, /INNER JOIN comments/);
      assert.match(sql, /WHERE published = \?/);
      assert.deepEqual(values, [true]);
    });

    it('where with raw + hash + not + limit', () => {
      const { sql, values } = MockModel
        .where({ active: true })
        .where('score > ?', 50)
        .not({ role: 'bot' })
        .limit(5)
        .toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE active = ? AND NOT (role = ?) AND score > ? LIMIT 5');
      assert.deepEqual(values, [true, 'bot', 50]);
    });
  });

  describe('postgres numbered params', () => {
    it('uses $1, $2 for all patterns', () => {
      const { sql, values } = ArticlePg
        .where({ published: true })
        .where('views > ?', 100)
        .not({ draft: true })
        .toSQL();
      assert.match(sql, /published = \$1/);
      assert.match(sql, /NOT \(draft = \$2\)/);
      assert.match(sql, /views > \$3/);
      assert.deepEqual(values, [true, true, 100]);
    });

    it('numbers IN clause params correctly', () => {
      const { sql, values } = ArticlePg
        .where({ status: ['published', 'archived'] })
        .toSQL();
      assert.match(sql, /status IN \(\$1, \$2\)/);
      assert.deepEqual(values, ['published', 'archived']);
    });
  });
});

// =============================================================================
// Phase 5: Runtime expansion tests
// =============================================================================

import { Rollback } from '../adapters/active_record_sql.mjs';

// --- update_all ---

describe('update_all', () => {
  beforeEach(() => {
    MockModel.resetQueries();
    MockPostgresModel.resetQueries();
  });

  it('builds UPDATE with SET and WHERE', async () => {
    await MockModel.where({ role: 'guest' }).updateAll({ status: 'inactive' });

    assert.equal(MockModel._executedQueries.length, 1);
    const { sql, params } = MockModel._executedQueries[0];
    assert.equal(sql, 'UPDATE users SET status = ? WHERE role = ?');
    assert.deepEqual(params, ['inactive', 'guest']);
  });

  it('builds UPDATE without WHERE for unscoped', async () => {
    await MockModel.updateAll({ active: false });

    assert.equal(MockModel._executedQueries.length, 1);
    const { sql, params } = MockModel._executedQueries[0];
    assert.equal(sql, 'UPDATE users SET active = ?');
    assert.deepEqual(params, [false]);
  });

  it('builds UPDATE with multiple SET columns', async () => {
    await MockModel.where({ id: 1 }).updateAll({ name: 'Bob', role: 'admin' });

    const { sql, params } = MockModel._executedQueries[0];
    assert.equal(sql, 'UPDATE users SET name = ?, role = ? WHERE id = ?');
    assert.deepEqual(params, ['Bob', 'admin', 1]);
  });

  it('works with postgres numbered params', async () => {
    await MockPostgresModel.where({ draft: true }).updateAll({ published: true });

    const { sql, params } = MockPostgresModel._executedQueries[0];
    assert.equal(sql, 'UPDATE posts SET published = $1 WHERE draft = $2');
    assert.deepEqual(params, [true, true]);
  });

  it('works with raw SQL conditions', async () => {
    await MockModel.where('score > ?', 100).updateAll({ featured: true });

    const { sql, params } = MockModel._executedQueries[0];
    assert.equal(sql, 'UPDATE users SET featured = ? WHERE score > ?');
    assert.deepEqual(params, [true, 100]);
  });

  it('has snake_case alias', async () => {
    await MockModel.where({ id: 1 }).update_all({ name: 'test' });
    assert.equal(MockModel._executedQueries.length, 1);
  });

  it('is available as static method', async () => {
    await MockModel.updateAll({ active: false });
    assert.equal(MockModel._executedQueries.length, 1);
  });

  it('static method accepts conditions', async () => {
    await MockModel.updateAll({ status: 'banned' }, { role: 'spam' });
    assert.equal(MockModel._executedQueries.length, 1);
    const { sql } = MockModel._executedQueries[0];
    assert.match(sql, /UPDATE users SET status = \? WHERE role = \?/);
  });
});

// --- transaction ---

describe('transaction', () => {
  class TransactionModel extends ActiveRecordSQL {
    static tableName = 'items';
    static get useNumberedParams() { return false; }
    static _executedQueries = [];

    static async _execute(sql, params) {
      this._executedQueries.push({ sql, params });
      return { rows: [] };
    }

    static _getRows(result) { return result.rows; }
    static _getLastInsertId(result) { return 1; }

    static resetQueries() {
      this._executedQueries = [];
    }
  }

  beforeEach(() => {
    TransactionModel.resetQueries();
  });

  it('wraps callback in BEGIN/COMMIT', async () => {
    await TransactionModel.transaction(async () => {
      await TransactionModel._execute('INSERT INTO items VALUES (?)', [1]);
    });

    const queries = TransactionModel._executedQueries.map(q => q.sql);
    assert.deepEqual(queries, ['BEGIN', 'INSERT INTO items VALUES (?)', 'COMMIT']);
  });

  it('returns callback result on success', async () => {
    const result = await TransactionModel.transaction(async () => {
      return 42;
    });
    assert.equal(result, 42);
  });

  it('rolls back on error and re-throws', async () => {
    await assert.rejects(
      async () => {
        await TransactionModel.transaction(async () => {
          throw new Error('boom');
        });
      },
      /boom/
    );

    const queries = TransactionModel._executedQueries.map(q => q.sql);
    assert.deepEqual(queries, ['BEGIN', 'ROLLBACK']);
  });

  it('rolls back silently on Rollback error', async () => {
    const result = await TransactionModel.transaction(async () => {
      throw new Rollback();
    });

    assert.equal(result, undefined);
    const queries = TransactionModel._executedQueries.map(q => q.sql);
    assert.deepEqual(queries, ['BEGIN', 'ROLLBACK']);
  });

  it('Rollback is exported and has correct name', () => {
    const err = new Rollback();
    assert.equal(err.name, 'Rollback');
    assert.ok(err instanceof Error);
  });
});

// --- group() ---

describe('group()', () => {
  describe('chainable method', () => {
    it('sets _group and returns new Relation', () => {
      const rel1 = new Relation(MockModel);
      const rel2 = rel1.group('status');

      assert.equal(rel1._group, null);
      assert.equal(rel2._group, 'status');
      assert.notEqual(rel1, rel2);
    });

    it('accepts multiple columns', () => {
      const rel = new Relation(MockModel).group('status', 'role');
      assert.deepEqual(rel._group, ['status', 'role']);
    });

    it('clones _group', () => {
      const rel1 = new Relation(MockModel).group('status');
      const rel2 = rel1._clone();
      assert.equal(rel2._group, 'status');
    });
  });

  describe('SQL building', () => {
    it('builds GROUP BY clause', () => {
      const { sql } = MockModel.group('status').toSQL();
      assert.equal(sql, 'SELECT * FROM users GROUP BY status');
    });

    it('builds GROUP BY with multiple columns', () => {
      const { sql } = MockModel.group('status', 'role').toSQL();
      assert.equal(sql, 'SELECT * FROM users GROUP BY status, role');
    });

    it('combines GROUP BY with WHERE', () => {
      const { sql, values } = MockModel.where({ active: true }).group('role').toSQL();
      assert.equal(sql, 'SELECT * FROM users WHERE active = ? GROUP BY role');
      assert.deepEqual(values, [true]);
    });

    it('GROUP BY comes before ORDER BY', () => {
      const { sql } = MockModel.group('role').order('role').toSQL();
      assert.equal(sql, 'SELECT * FROM users GROUP BY role ORDER BY role ASC');
    });
  });

  describe('group().count()', () => {
    class GroupCountModel extends ActiveRecordSQL {
      static tableName = 'users';
      static get useNumberedParams() { return false; }
      static _lastQuery = null;

      static async _execute(sql, params) {
        this._lastQuery = { sql, params };
        // Return grouped count data
        return { rows: [
          { status: 'active', count: 42 },
          { status: 'inactive', count: 18 },
          { status: 'pending', count: 5 }
        ]};
      }

      static _getRows(result) { return result.rows; }
      static _getLastInsertId(result) { return 1; }
    }

    it('returns {key: count} hash', async () => {
      const result = await GroupCountModel.group('status').count();

      assert.deepEqual(result, {
        active: 42,
        inactive: 18,
        pending: 5
      });
    });

    it('executes SELECT with group column and COUNT', async () => {
      await GroupCountModel.group('status').count();

      assert.ok(GroupCountModel._lastQuery.sql.includes('status, COUNT(*)'));
      assert.ok(GroupCountModel._lastQuery.sql.includes('GROUP BY status'));
    });
  });

  describe('group().sum()', () => {
    class GroupSumModel extends ActiveRecordSQL {
      static tableName = 'orders';
      static get useNumberedParams() { return false; }
      static _lastQuery = null;

      static async _execute(sql, params) {
        this._lastQuery = { sql, params };
        return { rows: [
          { status: 'completed', sum: 1500 },
          { status: 'pending', sum: 300 }
        ]};
      }

      static _getRows(result) { return result.rows; }
      static _getLastInsertId(result) { return 1; }
    }

    it('returns {key: sum} hash', async () => {
      const result = await GroupSumModel.group('status').sum('amount');

      assert.deepEqual(result, {
        completed: 1500,
        pending: 300
      });
    });

    it('executes SELECT with group column and SUM', async () => {
      await GroupSumModel.group('status').sum('amount');

      assert.ok(GroupSumModel._lastQuery.sql.includes('SUM(amount)'));
      assert.ok(GroupSumModel._lastQuery.sql.includes('GROUP BY status'));
    });
  });

  describe('static group()', () => {
    it('returns a Relation with group', () => {
      const rel = MockModel.group('status');
      assert.ok(rel instanceof Relation);
      assert.equal(rel._group, 'status');
    });
  });
});

// --- Nested hash joins ---

describe('Nested hash joins', () => {
  // Models for testing nested joins
  class Studio extends ActiveRecordSQL {
    static tableName = 'studios';
    static get useNumberedParams() { return false; }
    static associations = {
      entries: { type: 'has_many', model: 'Entry' }
    };
    static async _execute() { return { rows: [] }; }
    static _getRows(r) { return r.rows; }
    static _getLastInsertId() { return 1; }
  }

  class Entry extends ActiveRecordSQL {
    static tableName = 'entries';
    static get useNumberedParams() { return false; }
    static associations = {
      studio: { type: 'belongs_to', model: 'Studio', foreignKey: 'studio_id' },
      lead: { type: 'belongs_to', model: 'Person', foreignKey: 'lead_id' },
      follow: { type: 'belongs_to', model: 'Person', foreignKey: 'follow_id' }
    };
    static async _execute() { return { rows: [] }; }
    static _getRows(r) { return r.rows; }
    static _getLastInsertId() { return 1; }
  }

  class Person extends ActiveRecordSQL {
    static tableName = 'people';
    static get useNumberedParams() { return false; }
    static associations = {};
    static async _execute() { return { rows: [] }; }
    static _getRows(r) { return r.rows; }
    static _getLastInsertId() { return 1; }
  }

  // Register models
  modelRegistry['Studio'] = Studio;
  modelRegistry['Entry'] = Entry;
  modelRegistry['Person'] = Person;

  it('joins simple string association', () => {
    const { sql } = Studio.joins('entries').toSQL();
    assert.match(sql, /INNER JOIN entries ON entries\.studio_id = studios\.id/);
  });

  it('joins nested hash: {entry: :lead}', () => {
    const { sql } = Studio.joins({ entries: 'lead' }).toSQL();
    assert.match(sql, /INNER JOIN entries ON entries\.studio_id = studios\.id/);
    assert.match(sql, /INNER JOIN people ON entries\.lead_id = people\.id/);
  });

  it('joins nested hash with array: {entry: [:lead, :follow]}', () => {
    // Note: both lead and follow point to Person (same table)
    // This will produce two joins to the same table - valid SQL with aliases in more complex cases
    const { sql } = Studio.joins({ entries: ['lead', 'follow'] }).toSQL();
    assert.match(sql, /INNER JOIN entries/);
    // Both lead and follow are belongs_to Person
    const joinCount = (sql.match(/INNER JOIN people/g) || []).length;
    assert.equal(joinCount, 2);
  });
});

// --- WHERE on joined table columns ---

describe('WHERE on joined table columns', () => {
  class Card extends ActiveRecordSQL {
    static tableName = 'cards';
    static get useNumberedParams() { return false; }
    static associations = {
      studio: { type: 'belongs_to', model: 'StudioModel', foreignKey: 'studio_id' }
    };
    static async _execute() { return { rows: [] }; }
    static _getRows(r) { return r.rows; }
    static _getLastInsertId() { return 1; }
  }

  class StudioModel extends ActiveRecordSQL {
    static tableName = 'studios';
    static get useNumberedParams() { return false; }
    static associations = {};
    static async _execute() { return { rows: [] }; }
    static _getRows(r) { return r.rows; }
    static _getLastInsertId() { return 1; }
  }

  modelRegistry['StudioModel'] = StudioModel;

  it('builds WHERE with table-qualified column', () => {
    const { sql, values } = Card.joins('studio').where({ studios: { id: 456 } }).toSQL();

    assert.match(sql, /INNER JOIN studios/);
    assert.match(sql, /WHERE studios\.id = \?/);
    assert.deepEqual(values, [456]);
  });

  it('builds WHERE with multiple table-qualified columns', () => {
    const { sql, values } = Card.joins('studio')
      .where({ studios: { name: 'Test', active: true } }).toSQL();

    assert.match(sql, /studios\.name = \?/);
    assert.match(sql, /studios\.active = \?/);
    assert.deepEqual(values, ['Test', true]);
  });

  it('builds WHERE with IN on joined table', () => {
    const { sql, values } = Card.joins('studio')
      .where({ studios: { id: [1, 2, 3] } }).toSQL();

    assert.match(sql, /studios\.id IN \(\?, \?, \?\)/);
    assert.deepEqual(values, [1, 2, 3]);
  });

  it('builds WHERE with IS NULL on joined table', () => {
    const { sql } = Card.joins('studio')
      .where({ studios: { deleted_at: null } }).toSQL();

    assert.match(sql, /studios\.deleted_at IS NULL/);
  });

  it('combines table-qualified and regular WHERE', () => {
    const { sql, values } = Card.joins('studio')
      .where({ active: true })
      .where({ studios: { name: 'Test' } }).toSQL();

    assert.match(sql, /active = \?/);
    assert.match(sql, /studios\.name = \?/);
    assert.deepEqual(values, [true, 'Test']);
  });
});

// --- any() ---

describe('any()', () => {
  class AnyModel extends ActiveRecordSQL {
    static tableName = 'items';
    static get useNumberedParams() { return false; }

    static async _execute(sql, params) {
      return { rows: [{ '1': 1 }] };
    }
    static _getRows(result) { return result.rows; }
    static _getLastInsertId() { return 1; }
  }

  it('returns true when records exist', async () => {
    const result = await new Relation(AnyModel).any();
    assert.equal(result, true);
  });

  it('returns false when no records exist', async () => {
    class EmptyModel extends AnyModel {
      static async _execute() { return { rows: [] }; }
    }
    const result = await new Relation(EmptyModel).any();
    assert.equal(result, false);
  });

  it('is available as static method', async () => {
    const result = await AnyModel.any();
    assert.equal(result, true);
  });
});

// --- pick() ---

describe('pick()', () => {
  class PickModel extends ActiveRecordSQL {
    static tableName = 'items';
    static get useNumberedParams() { return false; }
    static _lastQuery = null;

    static async _execute(sql, params) {
      this._lastQuery = { sql, params };
      if (sql.includes('SELECT name')) {
        return { rows: [{ name: 'Alice' }] };
      }
      if (sql.includes('SELECT id, name')) {
        return { rows: [{ id: 1, name: 'Alice' }] };
      }
      return { rows: [] };
    }
    static _getRows(result) { return result.rows; }
    static _getLastInsertId() { return 1; }
  }

  it('returns single value for one column', async () => {
    const result = await new Relation(PickModel).pick('name');
    assert.equal(result, 'Alice');
  });

  it('returns array for multiple columns', async () => {
    const result = await new Relation(PickModel).pick('id', 'name');
    assert.deepEqual(result, [1, 'Alice']);
  });

  it('returns null when no records', async () => {
    class EmptyModel extends PickModel {
      static async _execute() { return { rows: [] }; }
    }
    const result = await new Relation(EmptyModel).pick('name');
    assert.equal(result, null);
  });

  it('uses LIMIT 1', async () => {
    await new Relation(PickModel).pick('name');
    assert.ok(PickModel._lastQuery.sql.includes('LIMIT 1'));
  });

  it('is available as static method', async () => {
    const result = await PickModel.pick('name');
    assert.equal(result, 'Alice');
  });
});

// --- sole() ---

describe('sole()', () => {
  it('returns the single record', async () => {
    class SingleModel extends ActiveRecordSQL {
      static tableName = 'items';
      static get useNumberedParams() { return false; }
      static async _execute() { return { rows: [{ id: 1, name: 'Only' }] }; }
      static _getRows(result) { return result.rows; }
      static _getLastInsertId() { return 1; }
      constructor(attrs) { super(attrs); Object.assign(this, attrs); }
    }

    const item = await new Relation(SingleModel).sole();
    assert.equal(item.name, 'Only');
  });

  it('throws when no records', async () => {
    class EmptyModel extends ActiveRecordSQL {
      static tableName = 'items';
      static name = 'EmptyModel';
      static get useNumberedParams() { return false; }
      static async _execute() { return { rows: [] }; }
      static _getRows(result) { return result.rows; }
      static _getLastInsertId() { return 1; }
    }

    await assert.rejects(
      async () => await new Relation(EmptyModel).sole(),
      /no records found/
    );
  });

  it('throws when multiple records', async () => {
    class MultiModel extends ActiveRecordSQL {
      static tableName = 'items';
      static name = 'MultiModel';
      static get useNumberedParams() { return false; }
      static async _execute() { return { rows: [{ id: 1 }, { id: 2 }] }; }
      static _getRows(result) { return result.rows; }
      static _getLastInsertId() { return 1; }
      constructor(attrs) { super(attrs); Object.assign(this, attrs); }
    }

    await assert.rejects(
      async () => await new Relation(MultiModel).sole(),
      /more than one record found/
    );
  });

  it('is available as static method', async () => {
    class SoleModel extends ActiveRecordSQL {
      static tableName = 'items';
      static get useNumberedParams() { return false; }
      static async _execute() { return { rows: [{ id: 1 }] }; }
      static _getRows(result) { return result.rows; }
      static _getLastInsertId() { return 1; }
      constructor(attrs) { super(attrs); Object.assign(this, attrs); }
    }

    const item = await SoleModel.sole();
    assert.equal(item.id, 1);
  });
});

// --- findByBang / find_by! ---

describe('findByBang (find_by!)', () => {
  class FindModel extends ActiveRecordSQL {
    static tableName = 'items';
    static name = 'FindModel';
    static get useNumberedParams() { return false; }
    static async _execute(sql) {
      if (sql.includes('name')) {
        return { rows: [{ id: 1, name: 'Found' }] };
      }
      return { rows: [] };
    }
    static _getRows(result) { return result.rows; }
    static _getLastInsertId() { return 1; }
    constructor(attrs) { super(attrs); Object.assign(this, attrs); }
  }

  it('returns record when found', async () => {
    const item = await new Relation(FindModel).findByBang({ name: 'Found' });
    assert.equal(item.name, 'Found');
  });

  it('throws when not found', async () => {
    class EmptyFindModel extends ActiveRecordSQL {
      static tableName = 'items';
      static name = 'EmptyFindModel';
      static get useNumberedParams() { return false; }
      static async _execute() { return { rows: [] }; }
      static _getRows(result) { return result.rows; }
      static _getLastInsertId() { return 1; }
    }
    await assert.rejects(
      async () => await new Relation(EmptyFindModel).findByBang({ name: 'missing' }),
      /EmptyFindModel not found/
    );
  });

  it('has snake_case alias', async () => {
    const item = await new Relation(FindModel).find_by_bang({ name: 'Found' });
    assert.equal(item.name, 'Found');
  });

  it('is available as static method', async () => {
    const item = await FindModel.findByBang({ name: 'Found' });
    assert.equal(item.name, 'Found');
  });
});

// --- destroyBy ---

describe('destroyBy', () => {
  let destroyedIds = [];

  class DestroyModel extends ActiveRecordSQL {
    static tableName = 'items';
    static get useNumberedParams() { return false; }
    static async _execute() { return { rows: [{ id: 1 }, { id: 2 }] }; }
    static _getRows(result) { return result.rows; }
    static _getLastInsertId() { return 1; }

    constructor(attrs) {
      super(attrs);
      Object.assign(this, attrs);
      this._persisted = true;
    }

    async destroy() {
      destroyedIds.push(this.id);
      return true;
    }
  }

  beforeEach(() => {
    destroyedIds = [];
  });

  it('finds and destroys matching records', async () => {
    const records = await new Relation(DestroyModel).destroyBy({ status: 'old' });
    assert.equal(records.length, 2);
    assert.deepEqual(destroyedIds, [1, 2]);
  });

  it('has snake_case alias', async () => {
    await new Relation(DestroyModel).destroy_by({ status: 'old' });
    assert.deepEqual(destroyedIds, [1, 2]);
  });

  it('is available as static method', async () => {
    await DestroyModel.destroyBy({ status: 'old' });
    assert.deepEqual(destroyedIds, [1, 2]);
  });
});
