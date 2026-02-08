// ActiveRecord adapter for RPC (Remote Procedure Call)
// This adapter proxies all database operations to the server via RPC
// Used when the browser needs to work with a server-side database
//
// This file is copied to dist/lib/active_record.mjs at build time for 'rpc' adapter

import { rpc, RPCError } from 'ruby2js-rails/rpc/client.mjs';
import { ActiveRecordBase, attr_accessor, initTimePolyfill } from 'ruby2js-rails/adapters/active_record_base.mjs';
import { Relation } from 'ruby2js-rails/adapters/relation.mjs';
import { CollectionProxy } from 'ruby2js-rails/adapters/collection_proxy.mjs';
import { Reference, HasOneReference } from 'ruby2js-rails/adapters/reference.mjs';

// Re-export shared utilities
export { attr_accessor, CollectionProxy, Reference, HasOneReference, RPCError };

// Model registry for association resolution (populated by Application.registerModels)
export const modelRegistry = {};

// Configuration injected at build time
const RPC_CONFIG = {};

// Initialize the RPC client (called by Application.initDatabase)
export async function initDatabase(options = {}) {
  // Time polyfill for Ruby compatibility
  if (typeof window !== 'undefined') {
    initTimePolyfill(window);
  }

  // RPC doesn't need local database initialization
  // The server handles all database operations
  console.log('RPC adapter initialized');
  return true;
}

// Schema operations are no-ops for RPC - server handles schema
export function defineSchema(version = 1) {
  // No-op - server manages schema
}

export async function openDatabase() {
  // No-op - server manages database connections
  return true;
}

export function registerSchema(tableName, schema) {
  // No-op - server manages schema
}

export function execSQL(sql) {
  // Not supported on RPC client
  console.warn('execSQL not supported on RPC client');
  return [];
}

export function createTable(tableName, columns, options = {}) {
  // No-op - server manages schema
}

export function addIndex(tableName, columns, options = {}) {
  // No-op - server manages schema
}

export function addColumn(tableName, columnName, columnType) {
  // No-op - server manages schema
}

export function removeColumn(tableName, columnName) {
  // No-op - server manages schema
}

export function dropTable(tableName) {
  // No-op - server manages schema
}

export function getDatabase() {
  return null; // No local database
}

// Close database connection (no-op for RPC - server manages database)
export async function closeDatabase() {
  // RPC has no local database to close
}

export async function query(sql, params = []) {
  // Not supported - use model methods instead
  console.warn('Direct SQL queries not supported on RPC client');
  return [];
}

export async function execute(sql, params = []) {
  // Not supported - use model methods instead
  console.warn('Direct SQL execute not supported on RPC client');
  return { changes: 0 };
}

export async function insert(tableName, data) {
  // Not supported - use Model.create() instead
  console.warn('Direct insert not supported on RPC client');
}

// RPC-based ActiveRecord implementation
export class ActiveRecord extends ActiveRecordBase {
  // --- Class Methods (chainable - return Relation) ---

  static all() {
    return new Relation(this);
  }

  static where(conditionOrSql, ...values) {
    return new Relation(this).where(conditionOrSql, ...values);
  }

  static order(options) {
    return new Relation(this).order(options);
  }

  static limit(n) {
    return new Relation(this).limit(n);
  }

  static includes(...associations) {
    return new Relation(this).includes(...associations);
  }

  // --- Class Methods (terminal - execute via RPC) ---

  static async find(id) {
    const data = await rpc(`${this.name}.find`, [id]);
    return new this(data);
  }

  static async findBy(conditions) {
    const data = await rpc(`${this.name}.findBy`, [conditions]);
    return data ? new this(data) : null;
  }

  static async first() {
    return new Relation(this).first();
  }

  static async last() {
    return new Relation(this).last();
  }

  static async count() {
    return new Relation(this).count();
  }

  // Create a new record via RPC
  static async create(attrs = {}) {
    // Run before_validation and before_save callbacks locally
    // (actual validation happens on server too)
    const instance = new this(attrs);
    await instance._runCallbacks('before_validation');
    await instance._runCallbacks('before_save');
    await instance._runCallbacks('before_create');

    // Send to server
    const data = await rpc(`${this.name}.create`, [attrs]);

    // Update instance with server response (includes id)
    Object.assign(instance.attributes, data);
    instance.id = data.id;
    instance._persisted = true;

    // Run after callbacks
    await instance._runCallbacks('after_create');
    await instance._runCallbacks('after_save');
    await instance._runCallbacks('after_create_commit');

    console.log(`  ${this.name} Create (id: ${instance.id})`);
    return instance;
  }

  // --- Relation execution (called by Relation) ---

  static async _executeRelation(rel) {
    // Build query parameters for RPC
    const params = {
      conditions: rel._conditions,
      rawConditions: rel._rawConditions,
      order: rel._order,
      limit: rel._limit,
      offset: rel._offset,
      includes: rel._includes
    };

    // If simple query with just conditions, use where
    if (rel._conditions.length > 0 || (rel._rawConditions && rel._rawConditions.length > 0)) {
      const conditions = rel._conditions.length > 0 ? Object.assign({}, ...rel._conditions) : null;
      const rows = await rpc(`${this.name}.where`, [conditions || params]);
      const records = rows.map(row => new this(row));

      // Apply client-side ordering/limit if needed
      if (rel._order) {
        const [col, dir] = this._parseOrder(rel._order);
        records.sort((a, b) => {
          const aVal = a[col] || a.attributes[col];
          const bVal = b[col] || b.attributes[col];
          if (aVal < bVal) return dir === 'asc' ? -1 : 1;
          if (aVal > bVal) return dir === 'asc' ? 1 : -1;
          return 0;
        });
      }

      if (rel._offset != null) {
        records.splice(0, rel._offset);
      }
      if (rel._limit != null) {
        records.splice(rel._limit);
      }

      // Load associations if needed
      if (rel._includes && rel._includes.length > 0) {
        await this._loadAssociations(records, rel._includes);
      }

      return records;
    }

    // All records
    const rows = await rpc(`${this.name}.all`, []);
    const records = rows.map(row => new this(row));

    // Apply ordering
    if (rel._order) {
      const [col, dir] = this._parseOrder(rel._order);
      records.sort((a, b) => {
        const aVal = a[col] || a.attributes[col];
        const bVal = b[col] || b.attributes[col];
        if (aVal < bVal) return dir === 'asc' ? -1 : 1;
        if (aVal > bVal) return dir === 'asc' ? 1 : -1;
        return 0;
      });
    }

    if (rel._offset != null) {
      records.splice(0, rel._offset);
    }
    if (rel._limit != null) {
      records.splice(rel._limit);
    }

    if (rel._includes && rel._includes.length > 0) {
      await this._loadAssociations(records, rel._includes);
    }

    return records;
  }

  static async _executeCount(rel) {
    const records = await this._executeRelation(rel);
    return records.length;
  }

  static _parseOrder(order) {
    if (typeof order === 'string') {
      return [order, 'asc'];
    }
    const col = Object.keys(order)[0];
    let dir = order[col];
    if (dir === ':desc') dir = 'desc';
    if (dir === ':asc') dir = 'asc';
    return [col, dir];
  }

  // --- Association loading (can be done client-side or delegated to server) ---

  static async _loadAssociations(records, includes) {
    if (records.length === 0) return;

    for (const include of includes) {
      if (typeof include === 'string') {
        await this._loadAssociation(records, include);
      } else if (typeof include === 'object') {
        for (const assocName of Object.keys(include)) {
          await this._loadAssociation(records, assocName);
        }
      }
    }
  }

  static async _loadAssociation(records, assocName) {
    const associations = this.associations || {};
    const assoc = associations[assocName];

    if (!assoc) {
      console.warn(`Association '${assocName}' not defined on ${this.name}`);
      return;
    }

    const AssocModel = this._resolveModel(assoc.model);
    if (!AssocModel) {
      console.warn(`Could not resolve model for association '${assocName}'`);
      return;
    }

    if (assoc.type === 'has_many') {
      await this._loadHasMany(records, assocName, assoc, AssocModel);
    } else if (assoc.type === 'belongs_to') {
      await this._loadBelongsTo(records, assocName, assoc, AssocModel);
    }
  }

  static async _loadHasMany(records, assocName, assoc, AssocModel) {
    const pkValues = records.map(r => r.id).filter(v => v != null);
    if (pkValues.length === 0) return;

    const foreignKey = assoc.foreignKey || `${this._singularize(this.table_name)}_id`;

    // Fetch via RPC
    const related = await rpc(`${AssocModel.name}.where`, [{ [foreignKey]: pkValues }]);

    const relatedByFk = new Map();
    for (const r of related) {
      const fk = r[foreignKey];
      if (!relatedByFk.has(fk)) {
        relatedByFk.set(fk, []);
      }
      relatedByFk.get(fk).push(new AssocModel(r));
    }

    for (const record of records) {
      const relatedRecords = relatedByFk.get(record.id) || [];
      const fk = assoc.foreignKey || `${this._singularize(this.table_name)}_id`;
      const proxy = new CollectionProxy(record, { name: assocName, type: 'has_many', foreignKey: fk }, AssocModel);
      proxy.load(relatedRecords);
      record[`_${assocName}`] = proxy;
    }
  }

  static async _loadBelongsTo(records, assocName, assoc, AssocModel) {
    const foreignKey = assoc.foreignKey || `${assocName}_id`;
    const fkValues = [...new Set(
      records.map(r => r[foreignKey] || r.attributes?.[foreignKey]).filter(v => v != null)
    )];

    if (fkValues.length === 0) {
      for (const record of records) {
        record[assocName] = null;
      }
      return;
    }

    // Fetch via RPC
    const related = await rpc(`${AssocModel.name}.where`, [{ id: fkValues }]);
    const relatedById = new Map(related.map(r => [r.id, new AssocModel(r)]));

    for (const record of records) {
      const fk = record[foreignKey] || record.attributes?.[foreignKey];
      record[assocName] = relatedById.get(fk) || null;
    }
  }

  static _resolveModel(modelOrName) {
    if (typeof modelOrName === 'function') return modelOrName;
    if (typeof modelOrName === 'string') return modelRegistry[modelOrName];
    return modelOrName;
  }

  static _singularize(name) {
    if (name.endsWith('ies')) return name.slice(0, -3) + 'y';
    if (name.endsWith('s')) return name.slice(0, -1);
    return name;
  }

  // --- Instance Methods ---

  async save() {
    await this._runCallbacks('before_validation');
    if (!this._validate()) return false;

    await this._runCallbacks('before_save');

    if (this._persisted) {
      await this._runCallbacks('before_update');
      await this._update();
      await this._runCallbacks('after_update');
    } else {
      await this._runCallbacks('before_create');
      await this._insert();
      await this._runCallbacks('after_create');
    }

    await this._runCallbacks('after_save');
    await this._runCallbacks(this._persisted ? 'after_update_commit' : 'after_create_commit');
    return true;
  }

  async update(attrs) {
    Object.assign(this.attributes, attrs);
    for (const [key, value] of Object.entries(attrs)) {
      this[key] = value;
    }
    return await this.save();
  }

  async destroy() {
    if (!this._persisted) return false;

    await rpc(`${this.constructor.name}.destroy`, [this.id]);
    this._persisted = false;

    console.log(`  ${this.constructor.name} Destroy (id: ${this.id})`);
    await this._runCallbacks('after_destroy_commit');
    return true;
  }

  async reload() {
    if (!this.id) return this;
    const fresh = await this.constructor.find(this.id);
    this.attributes = fresh.attributes;
    for (const [key, value] of Object.entries(this.attributes)) {
      if (key !== 'id') {
        this[key] = value;
      }
    }
    return this;
  }

  // --- Private helpers ---

  async _insert() {
    const attrs = { ...this.attributes };
    delete attrs.id;

    console.debug(`  ${this.constructor.name} Create`, attrs);

    const data = await rpc(`${this.constructor.name}.create`, [attrs]);
    this.id = data.id;
    this.attributes.id = data.id;
    Object.assign(this.attributes, data);
    this._persisted = true;

    console.log(`  ${this.constructor.name} Create (id: ${this.id})`);
    return true;
  }

  async _update() {
    const attrs = { ...this.attributes };

    console.debug(`  ${this.constructor.name} Update`, attrs);

    const data = await rpc(`${this.constructor.name}.save`, [this.id, attrs]);
    Object.assign(this.attributes, data);

    console.log(`  ${this.constructor.name} Update (id: ${this.id})`);
    return true;
  }

  static _buildWhere(conditions) {
    return conditions;
  }

  static _resultToModels(rows) {
    return rows.map(row => new this(row));
  }
}
