// ActiveRecord adapter for Dexie.js (IndexedDB wrapper)
// This file is copied to dist/lib/active_record.mjs at build time
// Dexie is ~50KB vs sql.js at ~2.7MB WASM

import Dexie from 'dexie';
import { ActiveRecordBase, attr_accessor, initTimePolyfill } from './active_record_base.mjs';
import { parseCondition, applyToDexie, toFilterFunction, canParse } from './sql_parser.mjs';

// Re-export shared utilities
export { attr_accessor };

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

  // Time polyfill for Ruby compatibility
  initTimePolyfill(window);

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

// Dexie-specific ActiveRecord implementation
export class ActiveRecord extends ActiveRecordBase {
  // Get the Dexie table for this model
  static get table() {
    return db.table(this.tableName);
  }

  // --- Class Methods (finders) ---

  static async all() {
    const rows = await this.table.toArray();
    return rows.map(row => new this(row));
  }

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

  // where({active: true}) - hash conditions
  // where('updated_at > ?', timestamp) - raw SQL with placeholder
  static async where(conditionOrSql, ...values) {
    let rows;

    if (typeof conditionOrSql === 'string') {
      // Raw SQL condition - parse and apply to Dexie
      const parsed = parseCondition(conditionOrSql, values);
      if (!parsed) {
        throw new Error(`Unsupported raw SQL condition for Dexie: ${conditionOrSql}. ` +
          `Supported patterns: 'col > ?', 'col >= ?', 'col < ?', 'col <= ?', 'col = ?', 'col != ?', 'col BETWEEN ? AND ?'`);
      }
      rows = await applyToDexie(this.table, parsed).toArray();
    } else {
      // Hash conditions
      rows = await this.table.where(conditionOrSql).toArray();
    }

    return rows.map(row => new this(row));
  }

  static async count() {
    return await this.table.count();
  }

  // Order records by column - returns array of models
  // Usage: Message.order({created_at: 'asc'}) or Message.order('created_at')
  static async order(options) {
    let column, direction;
    if (typeof options === 'string') {
      column = options;
      direction = 'asc';
    } else {
      column = Object.keys(options)[0];
      direction = options[column];
    }

    let collection = this.table.orderBy(column);
    if (direction === 'desc' || direction === ':desc') {
      collection = collection.reverse();
    }
    const rows = await collection.toArray();
    return rows.map(row => new this(row));
  }

  static async first() {
    const row = await this.table.orderBy('id').first();
    return row ? new this(row) : null;
  }

  static async last() {
    const row = await this.table.orderBy('id').last();
    return row ? new this(row) : null;
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
