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
    let paramIndex = { value: 1 }; // Use object so _buildConditionSQL can mutate it

    // SELECT clause
    let sql = options.count
      ? `SELECT COUNT(*) as count FROM ${this.tableName}`
      : `SELECT * FROM ${this.tableName}`;

    // Collect all WHERE clause parts
    const allWhereParts = [];

    // Build AND conditions (from where())
    if (rel._conditions.length > 0) {
      const { parts, vals } = this._buildConditionsSQL(rel._conditions, paramIndex);
      if (parts.length > 0) {
        allWhereParts.push(parts.join(' AND '));
        values.push(...vals);
      }
    }

    // Build NOT conditions (from not())
    if (rel._notConditions && rel._notConditions.length > 0) {
      const { parts, vals } = this._buildConditionsSQL(rel._notConditions, paramIndex);
      if (parts.length > 0) {
        // Wrap each NOT condition and negate it
        allWhereParts.push(`NOT (${parts.join(' AND ')})`);
        values.push(...vals);
      }
    }

    // Build OR conditions (from or())
    if (rel._orConditions && rel._orConditions.length > 0) {
      for (const orGroup of rel._orConditions) {
        const { parts, vals } = this._buildConditionsSQL(orGroup, paramIndex);
        if (parts.length > 0) {
          // Each OR group is wrapped in parentheses
          allWhereParts.push(`(${parts.join(' AND ')})`);
          values.push(...vals);
        }
      }
    }

    // Combine WHERE parts
    if (allWhereParts.length > 0) {
      // If we have OR conditions, we need special handling:
      // The first parts (AND and NOT) form the base, OR groups are alternatives
      if (rel._orConditions && rel._orConditions.length > 0) {
        // Get the base conditions (AND + NOT)
        const baseCount = (rel._conditions.length > 0 ? 1 : 0) +
                          (rel._notConditions && rel._notConditions.length > 0 ? 1 : 0);
        const baseParts = allWhereParts.slice(0, baseCount);
        const orParts = allWhereParts.slice(baseCount);

        if (baseParts.length > 0 && orParts.length > 0) {
          // Combine base with OR: (base) AND (or1 OR or2)
          // But actually the semantic is: base AND (base OR alt1 OR alt2)
          // Rails semantics: where(a).or(where(b)) means (a) OR (b)
          // So we need: (baseParts) OR (orParts joined with OR)
          const baseSQL = baseParts.join(' AND ');
          sql += ` WHERE (${baseSQL}) OR ${orParts.join(' OR ')}`;
        } else if (orParts.length > 0) {
          // Only OR conditions
          sql += ` WHERE ${orParts.join(' OR ')}`;
        } else {
          // Only base conditions
          sql += ` WHERE ${baseParts.join(' AND ')}`;
        }
      } else {
        // No OR conditions, just AND everything
        sql += ` WHERE ${allWhereParts.join(' AND ')}`;
      }
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

  // Build SQL clauses from an array of condition objects
  // Returns { parts: string[], vals: any[] }
  static _buildConditionsSQL(conditions, paramIndex) {
    const parts = [];
    const vals = [];

    for (const cond of conditions) {
      for (const [key, value] of Object.entries(cond)) {
        if (Array.isArray(value)) {
          // IN clause: where({id: [1, 2, 3]})
          const placeholders = value.map(() => this._param(paramIndex.value++)).join(', ');
          parts.push(`${key} IN (${placeholders})`);
          vals.push(...value.map(v => this._formatValue(v)));
        } else if (value === null) {
          // IS NULL
          parts.push(`${key} IS NULL`);
        } else {
          // Simple equality
          parts.push(`${key} = ${this._param(paramIndex.value++)}`);
          vals.push(this._formatValue(value));
        }
      }
    }

    return { parts, vals };
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
