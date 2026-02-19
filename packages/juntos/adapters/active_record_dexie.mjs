// ActiveRecord adapter for Dexie.js (IndexedDB wrapper)
// This file is copied to dist/lib/active_record.mjs at build time
// Dexie is ~50KB vs sql.js at ~2.7MB WASM

import Dexie from 'dexie';
import { ActiveRecordBase, attr_accessor, initTimePolyfill } from 'juntos/adapters/active_record_base.mjs';
import { parseCondition, applyToDexie, toFilterFunction, canParse } from 'juntos/adapters/sql_parser.mjs';
import { Relation } from 'juntos/adapters/relation.mjs';
import { CollectionProxy } from 'juntos/adapters/collection_proxy.mjs';
import { Reference, HasOneReference } from 'juntos/adapters/reference.mjs';

// Re-export shared utilities
export { attr_accessor, CollectionProxy, Reference, HasOneReference };

// Model registry for association resolution (populated by Application.registerModels)
export const modelRegistry = {};

// Configuration injected at build time
const DB_CONFIG = {};

let db = null;

// Schema registry - models register their table schemas here
const tableSchemas = {};

// Register a table schema (called by model classes)
export function registerSchema(tableName, schema) {
  tableSchemas[tableName] = schema;
}

// Initialize the database
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };
  const dbName = config.database || 'ruby2js_rails';

  db = new Dexie(dbName);

  // Time polyfill for Ruby compatibility (use globalThis for SSR compatibility)
  initTimePolyfill(globalThis);

  return db;
}

// Define schema version (call after all models are loaded)
export function defineSchema(version = 1) {
  if (Object.keys(tableSchemas).length > 0) {
    db.version(version).stores(tableSchemas);
  }
}

// Open the database (call after defineSchema)
export async function openDatabase() {
  await db.open();
  return db;
}

// Execute raw SQL - not supported in Dexie (legacy, use createTable/addIndex)
export function execSQL(sql) {
  // No-op for Dexie - schemas are registered by model classes via registerSchema()
  return [];
}

// Abstract DDL interface - Dexie schemas are registered by model classes
// These functions are called by the transpiled schema.js but are no-ops for Dexie
// because Dexie uses registerSchema() from model classes instead.
export function createTable(tableName, columns, options = {}) {
  // No-op - Dexie models self-register their schemas via registerSchema()
  // The schema is already set up before create_tables() is called
}

export function addIndex(tableName, columns, options = {}) {
  // No-op - Dexie indexes are defined in registerSchema()
  // Example: registerSchema('articles', '++id, title, created_at')
}

export function addColumn(tableName, columnName, columnType) {
  // No-op - Dexie schema changes require version upgrades
  // For browser apps, columns are added via registerSchema() before db.open()
}

export function removeColumn(tableName, columnName) {
  // No-op - Dexie schema changes require version upgrades
}

export function dropTable(tableName) {
  // No-op - Dexie schema changes require version upgrades
  // To drop a table, set it to null in the next version: db.version(2).stores({ tableName: null })
}

// Get the raw database instance
export function getDatabase() {
  return db;
}

// Query interface for rails_base.js migration system
// For Dexie, we simulate SQL queries for schema_migrations table
export async function query(sql, params = []) {
  // Only handle schema_migrations queries
  if (sql.includes('schema_migrations')) {
    try {
      const table = db.table('schema_migrations');
      const results = await table.toArray();
      return results;
    } catch (e) {
      // Table doesn't exist yet
      throw e;
    }
  }
  return [];
}

// Execute interface for rails_base.js migration system
// For Dexie, we simulate SQL executes for schema_migrations table
export async function execute(sql, params = []) {
  if (sql.includes('CREATE TABLE') && sql.includes('schema_migrations')) {
    // Dexie handles schema via version stores, but we need a runtime table
    // Add schema_migrations to the schema if not present
    if (!tableSchemas['schema_migrations']) {
      tableSchemas['schema_migrations'] = 'version';
    }
    return { changes: 0 };
  }
  return { changes: 0 };
}

// Insert a row - Dexie native API
export async function insert(tableName, data) {
  await db.table(tableName).add(data);
}

// Close database connection (no-op for Dexie - IndexedDB manages connections)
export async function closeDatabase() {
  // Dexie/IndexedDB connections don't need explicit closing
}

// Dexie-specific ActiveRecord implementation
export class ActiveRecord extends ActiveRecordBase {
  // Get the Dexie table for this model
  static get table() {
    return db.table(this.tableName);
  }

  // --- Class Methods (chainable - return Relation) ---

  // Returns a Relation that can be chained or awaited
  static all() {
    return new Relation(this);
  }

  // Returns a Relation with conditions
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

  // Returns a Relation with eager-loaded associations
  static includes(...associations) {
    return new Relation(this).includes(...associations);
  }

  // --- Class Methods (terminal - execute immediately) ---

  static async find(id) {
    const row = await this.table.get(Number(id));
    if (!row) {
      throw new Error(`${this.name} not found with id=${id}`);
    }
    return new this(row);
  }

  static async findBy(conditions) {
    const row = await this.table.where(conditions).first();
    return row ? new this(row) : null;
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

  // --- Relation execution (called by Relation) ---

  // Execute a Relation query and return model instances
  static async _executeRelation(rel) {
    let rows;

    // Build the Dexie query
    let collection = this.table;

    // Separate Range conditions from regular conditions
    // Dexie's where() doesn't support Range objects
    const regularConditions = {};
    const rangeFilters = [];

    if (rel._conditions.length > 0) {
      for (const cond of rel._conditions) {
        for (const [key, value] of Object.entries(cond)) {
          if (this._isRange(value)) {
            // Range condition - will be applied as filter
            rangeFilters.push(this._buildRangeFilter(key, value));
          } else {
            // Regular condition - can use Dexie's where()
            regularConditions[key] = value;
          }
        }
      }
    }

    // Apply regular conditions via Dexie's where()
    if (Object.keys(regularConditions).length > 0) {
      collection = collection.where(regularConditions);
    }

    // Apply raw SQL conditions via filter
    if (rel._rawConditions && rel._rawConditions.length > 0) {
      // Get all rows first, then filter (Dexie limitation)
      rows = await collection.toArray();
      for (const raw of rel._rawConditions) {
        const parsed = parseCondition(raw.sql, raw.values);
        if (parsed) {
          const filterFn = toFilterFunction(parsed);
          rows = rows.filter(filterFn);
        }
      }
    } else {
      rows = await collection.toArray();
    }

    // Apply Range filters
    for (const filterFn of rangeFilters) {
      rows = rows.filter(filterFn);
    }

    // Apply ordering (in-memory for now)
    if (rel._order) {
      const [col, dir] = this._parseOrder(rel._order);
      rows.sort((a, b) => {
        const aVal = a[col];
        const bVal = b[col];
        if (aVal < bVal) return dir === 'asc' ? -1 : 1;
        if (aVal > bVal) return dir === 'asc' ? 1 : -1;
        return 0;
      });
    }

    // Apply offset and limit
    if (rel._offset != null) {
      rows = rows.slice(rel._offset);
    }
    if (rel._limit != null) {
      rows = rows.slice(0, rel._limit);
    }

    // Convert to model instances
    const records = rows.map(row => new this(row));

    // Load included associations if any
    if (rel._includes && rel._includes.length > 0) {
      await this._loadAssociations(records, rel._includes);
    }

    return records;
  }

  // Execute a COUNT query for a Relation
  static async _executeCount(rel) {
    // For simplicity, get all matching records and count
    // Could be optimized with Dexie's count() if no complex filters
    if (rel._conditions.length === 0 && (!rel._rawConditions || rel._rawConditions.length === 0)) {
      return await this.table.count();
    }
    const records = await this._executeRelation(rel);
    return records.length;
  }

  // Parse order option into [column, direction]
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

  // Check if value is a $Range object (duck-type check)
  // Supports both _prefixed props (from transpiled Ruby) and non-prefixed (direct JS)
  static _isRange(value) {
    if (value === null || typeof value !== 'object') return false;
    // Check for transpiled Ruby $Range (_begin, _end, _excludeEnd)
    if ('_begin' in value && '_end' in value && '_excludeEnd' in value) return true;
    // Check for direct JS Range (begin, end, excludeEnd)
    if ('begin' in value && 'end' in value && 'excludeEnd' in value) return true;
    return false;
  }

  // Get Range properties (handles both _prefixed and non-prefixed)
  static _getRangeProps(range) {
    if ('_begin' in range) {
      return { begin: range._begin, end: range._end, excludeEnd: range._excludeEnd };
    }
    return { begin: range.begin, end: range.end, excludeEnd: range.excludeEnd };
  }

  // Build a filter function for a Range condition
  // Returns a function that takes a row and returns true if it matches
  static _buildRangeFilter(column, range) {
    const { begin, end, excludeEnd } = this._getRangeProps(range);
    const hasBegin = begin !== null;
    const hasEnd = end !== null;

    if (hasBegin && hasEnd) {
      if (excludeEnd) {
        // Exclusive range: 1...10 → column >= 1 AND column < 10
        return (row) => row[column] >= begin && row[column] < end;
      } else {
        // Inclusive range: 1..10 → column >= 1 AND column <= 10
        return (row) => row[column] >= begin && row[column] <= end;
      }
    } else if (hasBegin) {
      // Endless range: 18.. → column >= 18
      return (row) => row[column] >= begin;
    } else if (hasEnd) {
      // Beginless range: ..65 or ...65
      if (excludeEnd) {
        // ...65 → column < 65
        return (row) => row[column] < end;
      } else {
        // ..65 → column <= 65
        return (row) => row[column] <= end;
      }
    } else {
      // Both null - match everything (edge case)
      return () => true;
    }
  }

  // --- Association loading ---

  // Load associations for a set of records
  static async _loadAssociations(records, includes) {
    if (records.length === 0) return;

    for (const include of includes) {
      if (typeof include === 'string') {
        await this._loadAssociation(records, include);
      } else if (typeof include === 'object') {
        // Nested include: { posts: 'comments' }
        for (const assocName of Object.keys(include)) {
          await this._loadAssociation(records, assocName);
          // TODO: nested loading
        }
      }
    }
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

  // Load has_many association
  static async _loadHasMany(records, assocName, assoc, AssocModel) {
    const pkValues = records.map(r => r.id).filter(v => v != null);
    if (pkValues.length === 0) return;

    // Determine foreign key (e.g., article_id for Article has_many comments)
    // Use table_name (not class name) to avoid minification issues
    const foreignKey = assoc.foreignKey || `${this._singularize(this.table_name)}_id`;

    // Fetch all related records in one query
    const related = await AssocModel.table.where(foreignKey).anyOf(pkValues).toArray();

    // Group by foreign key
    const relatedByFk = new Map();
    for (const r of related) {
      const fk = r[foreignKey];
      if (!relatedByFk.has(fk)) {
        relatedByFk.set(fk, []);
      }
      relatedByFk.get(fk).push(new AssocModel(r));
    }

    // Attach to parent records as CollectionProxy (sets _comments so getter returns cached value)
    for (const record of records) {
      const relatedRecords = relatedByFk.get(record.id) || [];
      const fk = assoc.foreignKey || `${this._singularize(this.table_name)}_id`;
      const proxy = new CollectionProxy(record, { name: assocName, type: 'has_many', foreignKey: fk }, AssocModel);
      proxy.load(relatedRecords);
      record[`_${assocName}`] = proxy;
    }
  }

  // Load belongs_to association
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

    // Fetch all related records
    const related = await AssocModel.table.where('id').anyOf(fkValues).toArray();
    const relatedById = new Map(related.map(r => [r.id, new AssocModel(r)]));

    for (const record of records) {
      const fk = record[foreignKey] || record.attributes?.[foreignKey];
      record[assocName] = relatedById.get(fk) || null;
    }
  }

  // Resolve model class from name or class
  static _resolveModel(modelOrName) {
    if (typeof modelOrName === 'function') return modelOrName;
    // String reference - look up from model registry
    if (typeof modelOrName === 'string') return modelRegistry[modelOrName];
    return modelOrName;
  }

  // Simple singularize (articles -> article)
  static _singularize(name) {
    if (name.endsWith('ies')) return name.slice(0, -3) + 'y';
    if (name.endsWith('s')) return name.slice(0, -1);
    return name;
  }

  // --- Instance Methods ---

  async destroy() {
    if (!this._persisted) return false;
    await this.constructor.table.delete(this.id);
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
    const attrs = { ...this.attributes };
    delete attrs.id;  // Let Dexie auto-generate the id

    console.debug(`  ${this.constructor.name} Create`, attrs);

    const id = await this.constructor.table.add(attrs);
    this.id = id;
    this.attributes.id = id;
    this._persisted = true;

    console.log(`  ${this.constructor.name} Create (id: ${this.id})`);
    return true;
  }

  async _update() {
    const attrs = { ...this.attributes };

    console.debug(`  ${this.constructor.name} Update`, attrs);

    await this.constructor.table.put(attrs);

    console.log(`  ${this.constructor.name} Update (id: ${this.id})`);
    return true;
  }

  static _buildWhere(conditions) {
    // For Dexie, we return conditions directly
    return conditions;
  }

  static _resultToModels(rows) {
    return rows.map(row => new this(row));
  }
}
