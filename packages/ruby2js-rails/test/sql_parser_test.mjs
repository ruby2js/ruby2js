// Tests for SQL Parser (used by Dexie adapter)
//
// Run with: node --test packages/ruby2js-rails/test/sql_parser_test.mjs

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { parseCondition, canParse, toFilterFunction } from '../adapters/sql_parser.mjs';

describe('SQL Parser', () => {
  describe('parseCondition()', () => {
    describe('comparison operators', () => {
      it('parses > operator', () => {
        const result = parseCondition('age > ?', [18]);
        assert.deepEqual(result, {
          column: 'age',
          op: '>',
          values: [18]
        });
      });

      it('parses >= operator', () => {
        const result = parseCondition('score >= ?', [100]);
        assert.deepEqual(result, {
          column: 'score',
          op: '>=',
          values: [100]
        });
      });

      it('parses < operator', () => {
        const result = parseCondition('price < ?', [50]);
        assert.deepEqual(result, {
          column: 'price',
          op: '<',
          values: [50]
        });
      });

      it('parses <= operator', () => {
        const result = parseCondition('quantity <= ?', [10]);
        assert.deepEqual(result, {
          column: 'quantity',
          op: '<=',
          values: [10]
        });
      });

      it('parses = operator', () => {
        const result = parseCondition('status = ?', ['active']);
        assert.deepEqual(result, {
          column: 'status',
          op: '=',
          values: ['active']
        });
      });

      it('parses != operator', () => {
        const result = parseCondition('role != ?', ['guest']);
        assert.deepEqual(result, {
          column: 'role',
          op: '!=',
          values: ['guest']
        });
      });

      it('parses <> operator (normalizes to !=)', () => {
        const result = parseCondition('type <> ?', ['draft']);
        assert.deepEqual(result, {
          column: 'type',
          op: '!=',
          values: ['draft']
        });
      });
    });

    describe('BETWEEN operator', () => {
      it('parses BETWEEN with numbers', () => {
        const result = parseCondition('age BETWEEN ? AND ?', [18, 65]);
        assert.deepEqual(result, {
          column: 'age',
          op: 'between',
          values: [18, 65]
        });
      });

      it('parses BETWEEN with dates', () => {
        const result = parseCondition('created_at BETWEEN ? AND ?', ['2024-01-01', '2024-12-31']);
        assert.deepEqual(result, {
          column: 'created_at',
          op: 'between',
          values: ['2024-01-01', '2024-12-31']
        });
      });

      it('parses BETWEEN case-insensitively', () => {
        const result = parseCondition('score between ? and ?', [0, 100]);
        assert.deepEqual(result, {
          column: 'score',
          op: 'between',
          values: [0, 100]
        });
      });

      it('throws when BETWEEN has insufficient values', () => {
        assert.throws(
          () => parseCondition('age BETWEEN ? AND ?', [18]),
          /BETWEEN requires 2 values/
        );
      });
    });

    describe('whitespace handling', () => {
      it('handles extra whitespace', () => {
        const result = parseCondition('  age   >   ?  ', [18]);
        assert.deepEqual(result, {
          column: 'age',
          op: '>',
          values: [18]
        });
      });

      it('handles no whitespace around operator', () => {
        const result = parseCondition('age>?', [18]);
        assert.deepEqual(result, {
          column: 'age',
          op: '>',
          values: [18]
        });
      });
    });

    describe('unsupported patterns', () => {
      it('returns null for complex conditions', () => {
        const result = parseCondition('age > ? AND status = ?', [18, 'active']);
        assert.equal(result, null);
      });

      it('returns null for OR conditions', () => {
        const result = parseCondition('age > ? OR age < ?', [65, 18]);
        assert.equal(result, null);
      });

      it('returns null for LIKE patterns', () => {
        const result = parseCondition('name LIKE ?', ['%john%']);
        assert.equal(result, null);
      });

      it('returns null for IN clauses', () => {
        const result = parseCondition('id IN (?, ?, ?)', [1, 2, 3]);
        assert.equal(result, null);
      });

      it('returns null for IS NULL', () => {
        const result = parseCondition('deleted_at IS NULL', []);
        assert.equal(result, null);
      });
    });

    describe('error handling', () => {
      it('throws when comparison has no values', () => {
        assert.throws(
          () => parseCondition('age > ?', []),
          /Comparison requires 1 value/
        );
      });
    });
  });

  describe('canParse()', () => {
    it('returns true for supported patterns', () => {
      assert.equal(canParse('age > ?'), true);
      assert.equal(canParse('score >= ?'), true);
      assert.equal(canParse('price < ?'), true);
      assert.equal(canParse('quantity <= ?'), true);
      assert.equal(canParse('status = ?'), true);
      assert.equal(canParse('role != ?'), true);
      assert.equal(canParse('age BETWEEN ? AND ?'), true);
    });

    it('returns false for unsupported patterns', () => {
      assert.equal(canParse('age > ? AND status = ?'), false);
      assert.equal(canParse('name LIKE ?'), false);
      assert.equal(canParse('id IN (?, ?)'), false);
    });
  });

  describe('toFilterFunction()', () => {
    const records = [
      { id: 1, age: 15, score: 80 },
      { id: 2, age: 25, score: 90 },
      { id: 3, age: 35, score: 70 },
      { id: 4, age: 45, score: 85 }
    ];

    it('filters with > operator', () => {
      const filter = toFilterFunction({ column: 'age', op: '>', values: [30] });
      const result = records.filter(filter);
      assert.deepEqual(result.map(r => r.id), [3, 4]);
    });

    it('filters with >= operator', () => {
      const filter = toFilterFunction({ column: 'age', op: '>=', values: [25] });
      const result = records.filter(filter);
      assert.deepEqual(result.map(r => r.id), [2, 3, 4]);
    });

    it('filters with < operator', () => {
      const filter = toFilterFunction({ column: 'age', op: '<', values: [30] });
      const result = records.filter(filter);
      assert.deepEqual(result.map(r => r.id), [1, 2]);
    });

    it('filters with <= operator', () => {
      const filter = toFilterFunction({ column: 'age', op: '<=', values: [25] });
      const result = records.filter(filter);
      assert.deepEqual(result.map(r => r.id), [1, 2]);
    });

    it('filters with = operator', () => {
      const filter = toFilterFunction({ column: 'age', op: '=', values: [25] });
      const result = records.filter(filter);
      assert.deepEqual(result.map(r => r.id), [2]);
    });

    it('filters with != operator', () => {
      const filter = toFilterFunction({ column: 'age', op: '!=', values: [25] });
      const result = records.filter(filter);
      assert.deepEqual(result.map(r => r.id), [1, 3, 4]);
    });

    it('filters with between operator', () => {
      const filter = toFilterFunction({ column: 'age', op: 'between', values: [20, 40] });
      const result = records.filter(filter);
      assert.deepEqual(result.map(r => r.id), [2, 3]);
    });
  });
});

describe('Date handling', () => {
  it('parses date comparison', () => {
    const timestamp = '2024-06-15T10:30:00Z';
    const result = parseCondition('updated_at > ?', [timestamp]);
    assert.deepEqual(result, {
      column: 'updated_at',
      op: '>',
      values: [timestamp]
    });
  });

  it('filters dates correctly', () => {
    const records = [
      { id: 1, created_at: '2024-01-15' },
      { id: 2, created_at: '2024-06-15' },
      { id: 3, created_at: '2024-12-15' }
    ];

    const filter = toFilterFunction({
      column: 'created_at',
      op: '>',
      values: ['2024-03-01']
    });
    const result = records.filter(filter);
    assert.deepEqual(result.map(r => r.id), [2, 3]);
  });

  it('filters date range with BETWEEN', () => {
    const records = [
      { id: 1, created_at: '2024-01-15' },
      { id: 2, created_at: '2024-06-15' },
      { id: 3, created_at: '2024-12-15' }
    ];

    const filter = toFilterFunction({
      column: 'created_at',
      op: 'between',
      values: ['2024-03-01', '2024-09-01']
    });
    const result = records.filter(filter);
    assert.deepEqual(result.map(r => r.id), [2]);
  });
});
