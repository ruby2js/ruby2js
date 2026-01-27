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

import { ActiveRecordBase } from 'ruby2js-rails/adapters/active_record_base.mjs';
import { Relation } from 'ruby2js-rails/adapters/relation.mjs';
import { CollectionProxy } from 'ruby2js-rails/adapters/collection_proxy.mjs';
import { singularize } from 'ruby2js-rails/adapters/inflector.mjs';

// Model registry for association resolution (populated by Application.registerModels)
export const modelRegistry = {};

// Re-export CollectionProxy for use by models
export { CollectionProxy };

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
  // where({active: true}) - hash conditions
  // where('updated_at > ?', timestamp) - raw SQL with placeholder
  static where(conditionOrSql, ...values) {
    return new Relation(this).where(conditionOrSql, ...values);
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

  // Returns a Relation with selected columns
  static select(...columns) {
    return new Relation(this).select(...columns);
  }

  // Returns a Relation with distinct
  static distinct() {
    return new Relation(this).distinct();
  }

  // Returns a Relation with eager-loaded associations
  static includes(...associations) {
    return new Relation(this).includes(...associations);
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

  // Check if any records exist
  static async exists() {
    return new Relation(this).exists();
  }

  // Return values instead of model instances
  static async pluck(...columns) {
    return new Relation(this).pluck(...columns);
  }

  // --- Relation Execution (called by Relation class) ---

  // Execute a Relation and return model instances
  static async _executeRelation(rel) {
    const { sql, values } = this._buildRelationSQL(rel);
    const result = await this._execute(sql, values);
    const records = this._getRows(result).map(row => new this(row));

    // Load included associations if any
    if (rel._includes && rel._includes.length > 0) {
      await this._loadAssociations(records, rel._includes);
    }

    return records;
  }

  // Execute a COUNT query for a Relation
  static async _executeCount(rel) {
    const { sql, values } = this._buildRelationSQL(rel, { count: true });
    const result = await this._execute(sql, values);
    return parseInt(this._getRows(result)[0].count);
  }

  // Execute an EXISTS query for a Relation
  static async _executeExists(rel) {
    // Use LIMIT 1 and check if any row returned
    const limitedRel = Object.create(rel);
    limitedRel._limit = 1;
    limitedRel._select = ['1'];  // Minimal select for performance
    const { sql, values } = this._buildRelationSQL(limitedRel);
    const result = await this._execute(sql, values);
    return this._getRows(result).length > 0;
  }

  // Execute a PLUCK query for a Relation (returns values, not models)
  static async _executePluck(rel, columns) {
    const pluckRel = Object.create(rel);
    pluckRel._select = columns;
    const { sql, values } = this._buildRelationSQL(pluckRel);
    const result = await this._execute(sql, values);
    const rows = this._getRows(result);

    // Single column: return flat array of values
    if (columns.length === 1) {
      return rows.map(row => row[columns[0]]);
    }
    // Multiple columns: return array of arrays
    return rows.map(row => columns.map(col => row[col]));
  }

  // --- Association Loading ---

  // Resolve a model name or class to a model class
  // Uses module-level modelRegistry (populated by Application.registerModels)
  static _resolveModel(modelOrName) {
    if (typeof modelOrName === 'string') {
      const model = modelRegistry[modelOrName];
      if (!model) {
        throw new Error(`Model '${modelOrName}' not found in registry. Did you forget to call Application.registerModels()?`);
      }
      return model;
    }
    return modelOrName;
  }

  // Load associations for a set of records
  // includes can be: ['posts', 'comments'] or [{ posts: 'comments' }] or [{ posts: ['comments', 'tags'] }]
  static async _loadAssociations(records, includes) {
    if (records.length === 0) return;

    for (const include of includes) {
      if (typeof include === 'string') {
        // Simple include: 'posts'
        await this._loadAssociation(records, include);
      } else if (typeof include === 'object') {
        // Nested include: { posts: 'comments' } or { posts: ['comments', 'tags'] }
        const keys = Object.keys(include);
        for (const assocName of keys) {
          // Load the association first
          await this._loadAssociation(records, assocName);

          // Then load nested associations on the loaded records
          const nested = include[assocName];
          const nestedIncludes = Array.isArray(nested) ? nested : [nested];

          // Collect all associated records
          const assocRecords = [];
          for (const record of records) {
            const assocValue = record[assocName];
            if (assocValue instanceof CollectionProxy) {
              assocRecords.push(...assocValue.toArray());
            } else if (Array.isArray(assocValue)) {
              assocRecords.push(...assocValue);
            } else if (assocValue) {
              assocRecords.push(assocValue);
            }
          }

          // Load nested associations on the collected records
          if (assocRecords.length > 0) {
            const AssocModel = this._getAssociationModel(assocName);
            if (AssocModel) {
              await AssocModel._loadAssociations(assocRecords, nestedIncludes);
            }
          }
        }
      }
    }
  }

  // Get the model class for an association name
  static _getAssociationModel(assocName) {
    const associations = this.associations || {};
    const assoc = associations[assocName];
    if (!assoc) return null;
    return this._resolveModel(assoc.model);
  }

  // Load a single association for a set of records
  static async _loadAssociation(records, assocName) {
    const associations = this.associations || {};
    const assoc = associations[assocName];

    if (!assoc) {
      console.warn(`Association '${assocName}' not defined on ${this.name}`);
      return;
    }

    const AssocModel = this._resolveModel(assoc.model);

    if (assoc.type === 'belongs_to') {
      await this._loadBelongsTo(records, assocName, assoc, AssocModel);
    } else if (assoc.type === 'has_many') {
      await this._loadHasMany(records, assocName, assoc, AssocModel);
    } else if (assoc.type === 'has_one') {
      await this._loadHasOne(records, assocName, assoc, AssocModel);
    }
  }

  // Load belongs_to association (e.g., Post belongs_to User)
  static async _loadBelongsTo(records, assocName, assoc, AssocModel) {
    // Collect unique foreign key values
    const foreignKey = assoc.foreignKey || `${assocName}_id`;
    const fkValues = [...new Set(
      records.map(r => r[foreignKey] || r.attributes?.[foreignKey]).filter(v => v != null)
    )];

    if (fkValues.length === 0) {
      // No foreign keys, set all to null
      for (const record of records) {
        record[assocName] = null;
      }
      return;
    }

    // Single query for all related records
    const related = await AssocModel.where({ id: fkValues });
    const relatedById = new Map(related.map(r => [r.id, r]));

    // Attach to parent records
    for (const record of records) {
      const fk = record[foreignKey] || record.attributes?.[foreignKey];
      record[assocName] = relatedById.get(fk) || null;
    }
  }

  // Load has_many association (e.g., User has_many Posts)
  static async _loadHasMany(records, assocName, assoc, AssocModel) {
    // Collect primary key values
    const pkValues = records.map(r => r.id).filter(v => v != null);

    // Foreign key on the associated model
    const foreignKey = assoc.foreignKey || `${singularize(this.name).toLowerCase()}_id`;

    if (pkValues.length === 0) {
      // No parent records, still set empty CollectionProxy
      for (const record of records) {
        const proxy = new CollectionProxy(record, { name: assocName, type: 'has_many', foreignKey }, AssocModel);
        proxy.load([]);
        record[`_${assocName}`] = proxy;
      }
      return;
    }

    // Single query for all related records
    const related = await AssocModel.where({ [foreignKey]: pkValues });

    // Group by foreign key
    const relatedByFk = new Map();
    for (const r of related) {
      const fk = r[foreignKey] || r.attributes?.[foreignKey];
      if (!relatedByFk.has(fk)) {
        relatedByFk.set(fk, []);
      }
      relatedByFk.get(fk).push(r);
    }

    // Attach to parent records as CollectionProxy
    for (const record of records) {
      const related = relatedByFk.get(record.id) || [];
      const proxy = new CollectionProxy(record, { name: assocName, type: 'has_many', foreignKey }, AssocModel);
      proxy.load(related);
      record[`_${assocName}`] = proxy;
    }
  }

  // Load has_one association (e.g., User has_one Profile)
  static async _loadHasOne(records, assocName, assoc, AssocModel) {
    // Similar to has_many but only take first result
    const pkValues = records.map(r => r.id).filter(v => v != null);

    if (pkValues.length === 0) {
      for (const record of records) {
        record[assocName] = null;
      }
      return;
    }

    const foreignKey = assoc.foreignKey || `${singularize(this.name).toLowerCase()}_id`;
    const related = await AssocModel.where({ [foreignKey]: pkValues });

    const relatedByFk = new Map();
    for (const r of related) {
      const fk = r[foreignKey] || r.attributes?.[foreignKey];
      if (!relatedByFk.has(fk)) {
        relatedByFk.set(fk, r);
      }
    }

    for (const record of records) {
      record[assocName] = relatedByFk.get(record.id) || null;
    }
  }

  // Build SQL from a Relation object
  static _buildRelationSQL(rel, options = {}) {
    const values = [];
    let paramIndex = { value: 1 }; // Use object so _buildConditionSQL can mutate it

    // SELECT clause
    let sql;
    if (options.count) {
      // COUNT query: handle DISTINCT specially
      if (rel._distinct) {
        const cols = rel._select && rel._select.length > 0
          ? rel._select.join(', ')
          : '*';
        sql = `SELECT COUNT(DISTINCT ${cols}) as count FROM ${this.tableName}`;
      } else {
        sql = `SELECT COUNT(*) as count FROM ${this.tableName}`;
      }
    } else {
      // Regular query
      const distinct = rel._distinct ? 'DISTINCT ' : '';
      const cols = rel._select && rel._select.length > 0
        ? rel._select.join(', ')
        : '*';
      sql = `SELECT ${distinct}${cols} FROM ${this.tableName}`;
    }

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

    // Build raw SQL conditions (from where('col > ?', value))
    if (rel._rawConditions && rel._rawConditions.length > 0) {
      for (const raw of rel._rawConditions) {
        // Replace ? placeholders with proper parameter markers
        let sqlPart = raw.sql;
        for (const val of raw.values) {
          sqlPart = sqlPart.replace('?', this._param(paramIndex.value++));
          values.push(this._formatValue(val));
        }
        allWhereParts.push(sqlPart);
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
    if (val instanceof Date) return val.toISOString();
    return val;
  }

  static _resultToModels(rows) {
    return rows.map(row => new this(row));
  }
}
