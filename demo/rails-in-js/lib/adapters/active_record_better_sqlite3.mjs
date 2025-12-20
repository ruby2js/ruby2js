// ActiveRecord adapter for better-sqlite3 (Node.js synchronous SQLite)
// This file is copied to dist/lib/active_record.mjs at build time
// better-sqlite3 is a fast, synchronous SQLite3 binding for Node.js

import Database from 'better-sqlite3';

// Configuration injected at build time
const DB_CONFIG = {};

let db = null;

// Initialize the database
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };
  const dbPath = config.database || ':memory:';

  db = new Database(dbPath, {
    verbose: config.verbose ? console.log : null
  });

  // Enable WAL mode for better concurrent read performance
  db.pragma('journal_mode = WAL');

  // Time polyfill for Ruby compatibility (Node.js global)
  globalThis.Time = {
    now() {
      return { toString() { return new Date().toISOString(); } };
    }
  };

  return db;
}

// Execute raw SQL (for schema creation)
export function execSQL(sql) {
  return db.exec(sql);
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
  // All methods are async for API consistency with other adapters

  static async all() {
    const stmt = db.prepare(`SELECT * FROM ${this.tableName}`);
    const rows = stmt.all();
    return rows.map(row => new this(row));
  }

  static async find(id) {
    const stmt = db.prepare(`SELECT * FROM ${this.tableName} WHERE id = ?`);
    const row = stmt.get(id);
    if (!row) {
      throw new Error(`${this.name} not found with id=${id}`);
    }
    return new this(row);
  }

  static async findBy(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const stmt = db.prepare(`SELECT * FROM ${this.tableName} WHERE ${where} LIMIT 1`);
    const row = stmt.get(...values);
    return row ? new this(row) : null;
  }

  static async where(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const stmt = db.prepare(`SELECT * FROM ${this.tableName} WHERE ${where}`);
    const rows = stmt.all(...values);
    return rows.map(row => new this(row));
  }

  static async create(attributes) {
    const record = new this(attributes);
    await record.save();
    return record;
  }

  static async count() {
    const stmt = db.prepare(`SELECT COUNT(*) as count FROM ${this.tableName}`);
    const result = stmt.get();
    return result.count;
  }

  static async first() {
    const stmt = db.prepare(`SELECT * FROM ${this.tableName} ORDER BY id ASC LIMIT 1`);
    const row = stmt.get();
    return row ? new this(row) : null;
  }

  static async last() {
    const stmt = db.prepare(`SELECT * FROM ${this.tableName} ORDER BY id DESC LIMIT 1`);
    const row = stmt.get();
    return row ? new this(row) : null;
  }

  // --- Instance Methods ---
  // All methods are async for API consistency

  get persisted() {
    return this._persisted;
  }

  get newRecord() {
    return !this._persisted;
  }

  async save() {
    if (!this.isValid) return false;

    if (this._persisted) {
      return this._update();
    } else {
      return this._insert();
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
    return this.save();
  }

  async destroy() {
    if (!this._persisted) return false;
    const stmt = db.prepare(`DELETE FROM ${this.constructor.tableName} WHERE id = ?`);
    stmt.run(this.id);
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
    return modelClass.where({ [foreignKey]: this.id });
  }

  async belongsTo(modelClass, foreignKey) {
    const fkValue = this.attributes[foreignKey];
    if (!fkValue) return null;
    return modelClass.find(fkValue);
  }

  // --- Private helpers ---

  _insert() {
    const now = new Date().toISOString();
    this.attributes.created_at = now;
    this.attributes.updated_at = now;

    const cols = [];
    const placeholders = [];
    const values = [];

    for (const [key, value] of Object.entries(this.attributes)) {
      if (key === 'id') continue;
      cols.push(key);
      placeholders.push('?');
      values.push(value);
    }

    const sql = `INSERT INTO ${this.constructor.tableName} (${cols.join(', ')}) VALUES (${placeholders.join(', ')})`;
    console.debug(`  ${this.constructor.name} Create  ${sql}`, values);

    const stmt = db.prepare(sql);
    const result = stmt.run(...values);

    this.id = result.lastInsertRowid;
    this.attributes.id = this.id;
    this._persisted = true;
    console.log(`  ${this.constructor.name} Create (id: ${this.id})`);
    return true;
  }

  _update() {
    this.attributes.updated_at = new Date().toISOString();

    const sets = [];
    const values = [];

    for (const [key, value] of Object.entries(this.attributes)) {
      if (key === 'id') continue;
      sets.push(`${key} = ?`);
      values.push(value);
    }
    values.push(this.id);

    const sql = `UPDATE ${this.constructor.tableName} SET ${sets.join(', ')} WHERE id = ?`;
    console.debug(`  ${this.constructor.name} Update  ${sql}`, values);

    const stmt = db.prepare(sql);
    stmt.run(...values);

    console.log(`  ${this.constructor.name} Update (id: ${this.id})`);
    return true;
  }

  static _buildWhere(conditions) {
    const clauses = [];
    const values = [];
    for (const [key, value] of Object.entries(conditions)) {
      clauses.push(`${key} = ?`);
      values.push(value);
    }
    return { where: clauses.join(' AND '), values };
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
