// ActiveRecord SQL Base Class - Shared logic for all SQL database adapters
//
// This file contains SQL-specific ActiveRecord functionality shared across
// SQLite, PostgreSQL, and MySQL adapters:
// - Finder methods (all, find, findBy, where, first, last, order, count)
// - Relation execution (_executeRelation, _executeCount)
// - Mutation methods (_insert, _update, destroy, reload)
// - SQL building helpers (_buildWhere, _param)
//
// Each adapter extends a dialect class (SQLite, Postgres, MySQL) which extends this.
// Adapters implement only:
// - static async _execute(sql, params) - run query, return raw result
// - static _getRows(result) - extract rows array from result
// - static _getLastInsertId(result) - get auto-generated ID after insert

import { ActiveRecordBase } from './active_record_base.mjs';
import { Relation } from './relation.mjs';

export class ActiveRecordSQL extends ActiveRecordBase {
  // --- Dialect hooks (override in dialect subclass) ---

  // Use $1, $2 style placeholders (Postgres) vs ? (SQLite, MySQL)
  static get useNumberedParams() { return false; }

  // Use RETURNING id clause (Postgres) vs lastInsertRowid (SQLite)
  static get returningId() { return false; }

  // --- Driver hooks (each adapter implements) ---

  static async _execute(sql, params) {
    throw new Error('Subclass must implement _execute(sql, params)');
  }

  static _getRows(result) {
    throw new Error('Subclass must implement _getRows(result)');
  }

  static _getLastInsertId(result) {
    throw new Error('Subclass must implement _getLastInsertId(result)');
  }

  // --- Class Methods (chainable - return Relation) ---

  // Returns a Relation that can be chained or awaited
  static all() {
    return new Relation(this);
  }

  // Returns a Relation with conditions
  static where(conditions) {
    return new Relation(this).where(conditions);
  }

  // Returns a Relation with ordering
  static order(options) {
    return new Relation(this).order(options);
  }

  // Returns a Relation with limit
  static limit(n) {
    return new Relation(this).limit(n);
  }

  // Returns a Relation with offset
  static offset(n) {
    return new Relation(this).offset(n);
  }

  // --- Class Methods (terminal - execute immediately) ---

  static async find(id) {
    const sql = `SELECT * FROM ${this.tableName} WHERE id = ${this._param(1)}`;
    const result = await this._execute(sql, [id]);
    const rows = this._getRows(result);
    if (rows.length === 0) {
      throw new Error(`${this.name} not found with id=${id}`);
    }
    return new this(rows[0]);
  }

  static async findBy(conditions) {
    const { sql: whereSql, values } = this._buildWhere(conditions);
    const result = await this._execute(
      `SELECT * FROM ${this.tableName} WHERE ${whereSql} LIMIT 1`,
      values
    );
    const rows = this._getRows(result);
    return rows.length > 0 ? new this(rows[0]) : null;
  }

  // Convenience methods that delegate to Relation
  static async first() {
    return new Relation(this).first();
  }

  static async last() {
    return new Relation(this).last();
  }

  static async count() {
    return new Relation(this).count();
  }

  // --- Relation Execution (called by Relation class) ---

  // Execute a Relation and return model instances
  static async _executeRelation(rel) {
    const { sql, values } = this._buildRelationSQL(rel);
    const result = await this._execute(sql, values);
    return this._getRows(result).map(row => new this(row));
  }

  // Execute a COUNT query for a Relation
  static async _executeCount(rel) {
    const { sql, values } = this._buildRelationSQL(rel, { count: true });
    const result = await this._execute(sql, values);
    return parseInt(this._getRows(result)[0].count);
  }

  // Build SQL from a Relation object
  static _buildRelationSQL(rel, options = {}) {
    const values = [];
    let paramIndex = 1;

    // SELECT clause
    let sql = options.count
      ? `SELECT COUNT(*) as count FROM ${this.tableName}`
      : `SELECT * FROM ${this.tableName}`;

    // WHERE clause
    if (rel._conditions.length > 0) {
      const whereParts = [];
      for (const cond of rel._conditions) {
        for (const [key, value] of Object.entries(cond)) {
          if (Array.isArray(value)) {
            // IN clause: where({id: [1, 2, 3]})
            const placeholders = value.map(() => this._param(paramIndex++)).join(', ');
            whereParts.push(`${key} IN (${placeholders})`);
            values.push(...value.map(v => this._formatValue(v)));
          } else if (value === null) {
            // IS NULL
            whereParts.push(`${key} IS NULL`);
          } else {
            // Simple equality
            whereParts.push(`${key} = ${this._param(paramIndex++)}`);
            values.push(this._formatValue(value));
          }
        }
      }
      sql += ` WHERE ${whereParts.join(' AND ')}`;
    }

    // ORDER BY (skip for count queries)
    if (!options.count && rel._order) {
      const [col, dir] = this._parseOrder(rel._order);
      sql += ` ORDER BY ${col} ${dir}`;
    }

    // LIMIT (skip for count queries)
    if (!options.count && rel._limit != null) {
      sql += ` LIMIT ${rel._limit}`;
    }

    // OFFSET (skip for count queries)
    if (!options.count && rel._offset != null) {
      sql += ` OFFSET ${rel._offset}`;
    }

    return { sql, values };
  }

  // Parse order option into [column, direction]
  static _parseOrder(order) {
    if (typeof order === 'string') {
      return [order, 'ASC'];
    }
    const col = Object.keys(order)[0];
    const dir = (order[col] === 'desc' || order[col] === ':desc') ? 'DESC' : 'ASC';
    return [col, dir];
  }

  // --- Instance Methods ---

  async destroy() {
    if (!this._persisted) return false;
    await this.constructor._execute(
      `DELETE FROM ${this.constructor.tableName} WHERE id = ${this.constructor._param(1)}`,
      [this.id]
    );
    this._persisted = false;
    console.log(`  ${this.constructor.name} Destroy (id: ${this.id})`);
    await this._runCallbacks('after_destroy_commit');
    return true;
  }

  async reload() {
    if (!this.id) return this;
    const fresh = await this.constructor.find(this.id);
    this.attributes = fresh.attributes;
    // Also update direct properties
    for (const [key, value] of Object.entries(this.attributes)) {
      if (key !== 'id') {
        this[key] = value;
      }
    }
    return this;
  }

  // --- Private helpers ---

  async _insert() {
    const cols = [];
    const placeholders = [];
    const values = [];
    let i = 1;

    for (const [key, value] of Object.entries(this.attributes)) {
      if (key === 'id') continue;
      cols.push(key);
      placeholders.push(this.constructor._param(i++));
      values.push(this.constructor._formatValue(value));
    }

    let sql = `INSERT INTO ${this.constructor.tableName} (${cols.join(', ')}) VALUES (${placeholders.join(', ')})`;
    if (this.constructor.returningId) {
      sql += ' RETURNING id';
    }

    console.debug(`  ${this.constructor.name} Create  ${sql}`, values);

    const result = await this.constructor._execute(sql, values);

    this.id = this.constructor._getLastInsertId(result);
    this.attributes.id = this.id;
    this._persisted = true;
    console.log(`  ${this.constructor.name} Create (id: ${this.id})`);
    return true;
  }

  async _update() {
    const sets = [];
    const values = [];
    let i = 1;

    for (const [key, value] of Object.entries(this.attributes)) {
      if (key === 'id') continue;
      sets.push(`${key} = ${this.constructor._param(i++)}`);
      values.push(this.constructor._formatValue(value));
    }
    values.push(this.id);

    const sql = `UPDATE ${this.constructor.tableName} SET ${sets.join(', ')} WHERE id = ${this.constructor._param(i)}`;
    console.debug(`  ${this.constructor.name} Update  ${sql}`, values);

    await this.constructor._execute(sql, values);

    console.log(`  ${this.constructor.name} Update (id: ${this.id})`);
    return true;
  }

  // --- Static helpers ---

  // Generate placeholder for parameter at position n (1-indexed)
  static _param(n) {
    return this.useNumberedParams ? `$${n}` : '?';
  }

  // Build WHERE clause from conditions object (for findBy)
  static _buildWhere(conditions) {
    const clauses = [];
    const values = [];
    let i = 1;
    for (const [key, value] of Object.entries(conditions)) {
      clauses.push(`${key} = ${this._param(i++)}`);
      values.push(this._formatValue(value));
    }
    return { sql: clauses.join(' AND '), values };
  }

  // Format a value for binding (override in dialect for booleans)
  static _formatValue(val) {
    return val;
  }

  static _resultToModels(rows) {
    return rows.map(row => new this(row));
  }
}
