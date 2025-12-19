// ActiveRecord adapter for Dexie.js (IndexedDB wrapper)
// This file is copied to dist/lib/active_record.mjs at build time
// Dexie is ~50KB vs sql.js at ~2.7MB WASM

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
  static table_name = null;  // Override in subclass (Ruby convention)
  static columns = [];       // Override in subclass

  // Getter to support both tableName and table_name (JS vs Ruby convention)
  static get tableName() {
    return this.table_name;
  }

  constructor(attributes = {}) {
    this.id = attributes.id || null;
    this.attributes = { ...attributes };
    this._persisted = !!attributes.id;
    this._changes = {};
    this._errors = [];

    // Set attribute accessors for direct property access (article.title)
    for (const [key, value] of Object.entries(attributes)) {
      if (key !== 'id' && !(key in this)) {
        this[key] = value;
      }
    }
  }

  // Get the Dexie table for this model
  static get table() {
    return db.table(this.tableName);
  }

  // --- Validation ---

  get errors() {
    return this._errors;
  }

  get isValid() {
    this._errors = [];
    this.validate();
    if (this._errors.length > 0) {
      console.warn('  Validation failed:', this._errors);
    }
    return this._errors.length === 0;
  }

  // Override in subclass to add validations
  validate() {}

  validates_presence_of(field) {
    const value = this.attributes[field];
    if (value == null || String(value).trim().length === 0) {
      this._errors.push(`${field} can't be blank`);
    }
  }

  validates_length_of(field, options) {
    const value = String(this.attributes[field] || '');
    if (options.minimum && value.length < options.minimum) {
      this._errors.push(`${field} is too short (minimum is ${options.minimum} characters)`);
    }
    if (options.maximum && value.length > options.maximum) {
      this._errors.push(`${field} is too long (maximum is ${options.maximum} characters)`);
    }
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
    if (!this.isValid) return false;

    if (this._persisted) {
      return await this._update();
    } else {
      return await this._insert();
    }
  }

  async update(attributes) {
    Object.assign(this.attributes, attributes);
    // Also update direct properties
    for (const [key, value] of Object.entries(attributes)) {
      if (key !== 'id') {
        this[key] = value;
      }
    }
    return await this.save();
  }

  async destroy() {
    if (!this._persisted) return false;
    await this.constructor.table.delete(this.id);
    this._persisted = false;
    console.log(`  ${this.constructor.name} Destroy (id: ${this.id})`);
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
    const now = new Date().toISOString();
    this.attributes.created_at = now;
    this.attributes.updated_at = now;

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
    this.attributes.updated_at = new Date().toISOString();

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
