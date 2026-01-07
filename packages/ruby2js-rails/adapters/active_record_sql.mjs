// ActiveRecord SQL Base Class - Shared logic for all SQL database adapters
//
// This file contains SQL-specific ActiveRecord functionality shared across
// SQLite, PostgreSQL, and MySQL adapters:
// - Finder methods (all, find, findBy, where, first, last, order, count)
// - Mutation methods (_insert, _update, destroy, reload)
// - SQL building helpers (_buildWhere, _param)
//
// Each adapter extends a dialect class (SQLite, Postgres, MySQL) which extends this.
// Adapters implement only:
// - static async _execute(sql, params) - run query, return raw result
// - static _getRows(result) - extract rows array from result
// - static _getLastInsertId(result) - get auto-generated ID after insert

import { ActiveRecordBase } from './active_record_base.mjs';

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

  // --- Class Methods (finders) ---

  static async all() {
    const result = await this._execute(`SELECT * FROM ${this.tableName}`);
    return this._getRows(result).map(row => new this(row));
  }

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

  static async where(conditions) {
    const { sql: whereSql, values } = this._buildWhere(conditions);
    const result = await this._execute(
      `SELECT * FROM ${this.tableName} WHERE ${whereSql}`,
      values
    );
    return this._getRows(result).map(row => new this(row));
  }

  static async count() {
    const result = await this._execute(
      `SELECT COUNT(*) as count FROM ${this.tableName}`
    );
    return parseInt(this._getRows(result)[0].count);
  }

  static async first() {
    const result = await this._execute(
      `SELECT * FROM ${this.tableName} ORDER BY id ASC LIMIT 1`
    );
    const rows = this._getRows(result);
    return rows.length > 0 ? new this(rows[0]) : null;
  }

  static async last() {
    const result = await this._execute(
      `SELECT * FROM ${this.tableName} ORDER BY id DESC LIMIT 1`
    );
    const rows = this._getRows(result);
    return rows.length > 0 ? new this(rows[0]) : null;
  }

  // Order records by column - returns array of models
  // Usage: Message.order({created_at: 'asc'}) or Message.order('created_at')
  static async order(options) {
    let column, direction;
    if (typeof options === 'string') {
      column = options;
      direction = 'ASC';
    } else {
      column = Object.keys(options)[0];
      direction = (options[column] === 'desc' || options[column] === ':desc') ? 'DESC' : 'ASC';
    }
    const result = await this._execute(
      `SELECT * FROM ${this.tableName} ORDER BY ${column} ${direction}`
    );
    return this._getRows(result).map(row => new this(row));
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

  // Build WHERE clause from conditions object
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
