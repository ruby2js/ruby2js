// ActiveRecord adapter for Dexie.js (IndexedDB wrapper)
// This file is copied to dist/lib/active_record.mjs at build time

import Dexie from 'dexie';

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
  const dbName = config.database || 'rails_in_js';

  db = new Dexie(dbName);

  // Time polyfill for Ruby compatibility
  window.Time = {
    now() {
      return { toString() { return new Date().toISOString(); } };
    }
  };

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

// Execute raw SQL - not supported in Dexie, provided for compatibility
export function execSQL(sql) {
  console.warn('execSQL not supported with Dexie adapter, use Dexie API directly');
  return [];
}

// Get the raw database instance
export function getDatabase() {
  return db;
}

// Base class for ActiveRecord models
export class ActiveRecord {
  static tableName = null;  // Override in subclass
  static columns = [];      // Override in subclass

  constructor(attributes = {}) {
    this.id = attributes.id || null;
    this.attributes = { ...attributes };
    this._persisted = !!attributes.id;
    this._changes = {};
  }

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
    const row = await this.table.get(id);
    if (!row) {
      throw new Error(`${this.name} not found with id=${id}`);
    }
    return new this(row);
  }

  static async findBy(conditions) {
    const row = await this.table.where(conditions).first();
    return row ? new this(row) : null;
  }

  static async where(conditions) {
    const rows = await this.table.where(conditions).toArray();
    return rows.map(row => new this(row));
  }

  static async create(attributes) {
    const record = new this(attributes);
    await record.save();
    return record;
  }

  static async count() {
    return await this.table.count();
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

  get persisted() {
    return this._persisted;
  }

  get newRecord() {
    return !this._persisted;
  }

  async save() {
    if (this._persisted) {
      return await this._update();
    } else {
      return await this._insert();
    }
  }

  async update(attributes) {
    Object.assign(this.attributes, attributes);
    return await this.save();
  }

  async destroy() {
    if (!this._persisted) return false;
    await this.constructor.table.delete(this.id);
    this._persisted = false;
    return true;
  }

  async reload() {
    if (!this.id) return this;
    const fresh = await this.constructor.find(this.id);
    this.attributes = fresh.attributes;
    return this;
  }

  // --- Association helpers ---

  async hasMany(modelClass, foreignKey) {
    return await modelClass.where({ [foreignKey]: this.id });
  }

  async belongsTo(modelClass, foreignKey) {
    const fkValue = this.attributes[foreignKey];
    if (!fkValue) return null;
    return await modelClass.find(fkValue);
  }

  // --- Private helpers ---

  async _insert() {
    const attrs = { ...this.attributes };
    delete attrs.id;  // Let Dexie auto-generate the id

    const id = await this.constructor.table.add(attrs);
    this.id = id;
    this.attributes.id = id;
    this._persisted = true;
    return true;
  }

  async _update() {
    const attrs = { ...this.attributes };
    await this.constructor.table.put(attrs);
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

// Helper to define attribute accessors
export function attr_accessor(klass, ...attrs) {
  for (const attr of attrs) {
    Object.defineProperty(klass.prototype, attr, {
      get() { return this.attributes[attr]; },
      set(value) {
        this.attributes[attr] = value;
        this._changes[attr] = value;
      },
      enumerable: true
    });
  }
}
