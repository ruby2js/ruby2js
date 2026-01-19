/**
 * @ruby2js/content-adapter
 *
 * ActiveRecord-like query API over in-memory content collections.
 * Designed for build-time materialized markdown content.
 */

/**
 * Creates a queryable collection from an array of records.
 *
 * @param {string} name - Collection name (e.g., 'posts')
 * @param {Array<Object>} records - Array of content records
 * @returns {Collection} - Queryable collection with ActiveRecord-like API
 */
export function createCollection(name, records) {
  return new Collection(name, records);
}

/**
 * Collection class providing ActiveRecord-like query interface.
 */
class Collection {
  constructor(name, records, constraints = {}) {
    this._name = name;
    this._records = records;
    this._constraints = constraints;
    this._belongsToRelations = {};
    this._hasManyRelations = {};
  }

  /**
   * Define a belongs_to relationship.
   * @param {string} attr - Attribute name (e.g., 'author')
   * @param {Collection} target - Target collection (e.g., Author)
   */
  belongsTo(attr, target) {
    this._belongsToRelations[attr] = target;
    return this;
  }

  /**
   * Define a has_many relationship.
   * @param {string} attr - Attribute name (e.g., 'tags')
   * @param {Collection} target - Target collection (e.g., Tag)
   */
  hasMany(attr, target) {
    this._hasManyRelations[attr] = target;
    return this;
  }

  /**
   * Filter records by attribute values.
   * @param {Object} conditions - Key-value pairs to match
   * @returns {Collection} - New collection with filter applied
   */
  where(conditions) {
    if (conditions === undefined) {
      // Return a WhereChain for .where.not() syntax
      return new WhereChain(this);
    }
    return this._chain({ where: [...(this._constraints.where || []), conditions] });
  }

  /**
   * Order records by attribute.
   * @param {Object} ordering - { column: 'asc' | 'desc' }
   * @returns {Collection} - New collection with ordering applied
   */
  order(ordering) {
    return this._chain({ order: ordering });
  }

  /**
   * Limit number of records returned.
   * @param {number} n - Maximum records to return
   * @returns {Collection} - New collection with limit applied
   */
  limit(n) {
    return this._chain({ limit: n });
  }

  /**
   * Skip first n records.
   * @param {number} n - Number of records to skip
   * @returns {Collection} - New collection with offset applied
   */
  offset(n) {
    return this._chain({ offset: n });
  }

  /**
   * Find record by slug (primary key).
   * @param {string} slug - The slug to find
   * @returns {Object|null} - Found record or null
   */
  find(slug) {
    const record = this._records.find(r => r.slug === slug);
    return record ? this._wrapRecord(record) : null;
  }

  /**
   * Find first record matching conditions.
   * @param {Object} conditions - Key-value pairs to match
   * @returns {Object|null} - Found record or null
   */
  find_by(conditions) {
    const results = this.where(conditions).toArray();
    return results.length > 0 ? results[0] : null;
  }

  /**
   * Get first record.
   * @returns {Object|null}
   */
  first() {
    const results = this.limit(1).toArray();
    return results.length > 0 ? results[0] : null;
  }

  /**
   * Get last record.
   * @returns {Object|null}
   */
  last() {
    const all = this.toArray();
    return all.length > 0 ? all[all.length - 1] : null;
  }

  /**
   * Count records.
   * @returns {number}
   */
  count() {
    return this.toArray().length;
  }

  /**
   * Check if any records exist.
   * @returns {boolean}
   */
  exists() {
    return this.count() > 0;
  }

  /**
   * Eager load associations (no-op for in-memory, but keeps API compatible).
   * @param {...string} associations - Association names to load
   * @returns {Collection}
   */
  includes(...associations) {
    // For in-memory collections, this is a no-op since everything is already loaded
    return this;
  }

  /**
   * Execute query and return array of records.
   * @returns {Array<Object>}
   */
  toArray() {
    let results = [...this._records];

    // Apply where conditions
    const whereConditions = this._constraints.where || [];
    for (const conditions of whereConditions) {
      results = results.filter(record => this._matchesConditions(record, conditions));
    }

    // Apply not conditions
    const notConditions = this._constraints.whereNot || [];
    for (const conditions of notConditions) {
      results = results.filter(record => !this._matchesConditions(record, conditions));
    }

    // Apply ordering
    if (this._constraints.order) {
      const [column, direction] = Object.entries(this._constraints.order)[0];
      results.sort((a, b) => {
        const aVal = a[column];
        const bVal = b[column];
        if (aVal < bVal) return direction === 'asc' ? -1 : 1;
        if (aVal > bVal) return direction === 'asc' ? 1 : -1;
        return 0;
      });
    }

    // Apply offset
    if (this._constraints.offset) {
      results = results.slice(this._constraints.offset);
    }

    // Apply limit
    if (this._constraints.limit) {
      results = results.slice(0, this._constraints.limit);
    }

    // Wrap records with relationship resolution
    return results.map(r => this._wrapRecord(r));
  }

  /**
   * Make collection iterable.
   */
  [Symbol.iterator]() {
    return this.toArray()[Symbol.iterator]();
  }

  /**
   * Support for...of and spread.
   */
  forEach(fn) {
    this.toArray().forEach(fn);
  }

  map(fn) {
    return this.toArray().map(fn);
  }

  filter(fn) {
    return this.toArray().filter(fn);
  }

  // Private methods

  _chain(newConstraints) {
    const merged = { ...this._constraints, ...newConstraints };
    if (newConstraints.where && this._constraints.where) {
      merged.where = [...this._constraints.where, ...newConstraints.where];
    }
    if (newConstraints.whereNot && this._constraints.whereNot) {
      merged.whereNot = [...this._constraints.whereNot, ...newConstraints.whereNot];
    }
    const newCollection = new Collection(this._name, this._records, merged);
    newCollection._belongsToRelations = this._belongsToRelations;
    newCollection._hasManyRelations = this._hasManyRelations;
    return newCollection;
  }

  _matchesConditions(record, conditions) {
    for (const [key, value] of Object.entries(conditions)) {
      if (Array.isArray(value)) {
        // IN query: where(tags: ['ruby', 'js']) matches if record.tags includes any
        if (Array.isArray(record[key])) {
          if (!value.some(v => record[key].includes(v))) return false;
        } else {
          if (!value.includes(record[key])) return false;
        }
      } else {
        if (record[key] !== value) return false;
      }
    }
    return true;
  }

  _wrapRecord(record) {
    const wrapped = { ...record };

    // Add belongs_to accessors
    for (const [attr, target] of Object.entries(this._belongsToRelations)) {
      if (record[attr] !== undefined) {
        const foreignKey = record[attr];
        Object.defineProperty(wrapped, attr, {
          get: () => target.find(foreignKey),
          enumerable: true
        });
      }
    }

    // Add has_many accessors
    for (const [attr, target] of Object.entries(this._hasManyRelations)) {
      if (record[attr] !== undefined) {
        const foreignKeys = Array.isArray(record[attr]) ? record[attr] : [record[attr]];
        Object.defineProperty(wrapped, attr, {
          get: () => foreignKeys.map(fk => target.find(fk)).filter(Boolean),
          enumerable: true
        });
      }
    }

    return wrapped;
  }
}

/**
 * WhereChain for .where.not() syntax
 */
class WhereChain {
  constructor(collection) {
    this._collection = collection;
  }

  not(conditions) {
    const newConstraints = {
      whereNot: [...(this._collection._constraints.whereNot || []), conditions]
    };
    return this._collection._chain(newConstraints);
  }
}

export { Collection };
