// ActiveRecord adapter for PGLite (PostgreSQL in WebAssembly)
// This file is copied to dist/lib/active_record.mjs at build time
// PGLite provides PostgreSQL compatibility in the browser with optional IndexedDB persistence

// Configuration injected at build time
const DB_CONFIG = {};

let db = null;

// Initialize the database
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };

  // Dynamic import of PGLite
  const { PGlite } = await import('@electric-sql/pglite');

  // Determine storage backend:
  // - idb://dbname for IndexedDB persistence (survives page refresh)
  // - memory:// for ephemeral in-memory storage
  let dataDir;
  if (config.persist !== false && config.database) {
    dataDir = `idb://${config.database}`;
  } else if (config.dataDir) {
    dataDir = config.dataDir;
  } else {
    dataDir = 'memory://';
  }

  // Create PGLite instance
  db = await PGlite.create(dataDir, {
    // Optional: relaxed durability for better performance (skip fsync)
    relaxedDurability: config.relaxedDurability ?? false,
    // Optional: debug logging (1-5)
    debug: config.debug
  });

  console.log(`Connected to PGLite: ${dataDir}`);

  // Time polyfill for Ruby compatibility
  if (typeof window !== 'undefined') {
    window.Time = {
      now() {
        return { toString() { return new Date().toISOString(); } };
      }
    };
  } else {
    globalThis.Time = {
      now() {
        return { toString() { return new Date().toISOString(); } };
      }
    };
  }

  return db;
}

// Execute raw SQL (for schema creation, migrations)
export async function execSQL(sql) {
  // exec() supports multiple statements, good for migrations
  return await db.exec(sql);
}

// Get the raw database instance
export function getDatabase() {
  return db;
}

// Close the database connection
export async function closeDatabase() {
  if (db) {
    await db.close();
    db = null;
  }
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

  static async all() {
    const result = await db.query(`SELECT * FROM ${this.tableName}`);
    return result.rows.map(row => new this(row));
  }

  static async find(id) {
    const result = await db.query(
      `SELECT * FROM ${this.tableName} WHERE id = $1`,
      [id]
    );
    if (result.rows.length === 0) {
      throw new Error(`${this.name} not found with id=${id}`);
    }
    return new this(result.rows[0]);
  }

  static async findBy(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const result = await db.query(
      `SELECT * FROM ${this.tableName} WHERE ${where} LIMIT 1`,
      values
    );
    return result.rows.length > 0 ? new this(result.rows[0]) : null;
  }

  static async where(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const result = await db.query(
      `SELECT * FROM ${this.tableName} WHERE ${where}`,
      values
    );
    return result.rows.map(row => new this(row));
  }

  static async create(attributes) {
    const record = new this(attributes);
    await record.save();
    return record;
  }

  static async count() {
    const result = await db.query(`SELECT COUNT(*) as count FROM ${this.tableName}`);
    return parseInt(result.rows[0].count);
  }

  static async first() {
    const result = await db.query(
      `SELECT * FROM ${this.tableName} ORDER BY id ASC LIMIT 1`
    );
    return result.rows.length > 0 ? new this(result.rows[0]) : null;
  }

  static async last() {
    const result = await db.query(
      `SELECT * FROM ${this.tableName} ORDER BY id DESC LIMIT 1`
    );
    return result.rows.length > 0 ? new this(result.rows[0]) : null;
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
    await db.query(
      `DELETE FROM ${this.constructor.tableName} WHERE id = $1`,
      [this.id]
    );
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

    const cols = [];
    const placeholders = [];
    const values = [];
    let paramIndex = 1;

    for (const [key, value] of Object.entries(this.attributes)) {
      if (key === 'id') continue;
      cols.push(key);
      placeholders.push(`$${paramIndex++}`);
      values.push(value);
    }

    const sql = `INSERT INTO ${this.constructor.tableName} (${cols.join(', ')}) VALUES (${placeholders.join(', ')}) RETURNING id`;
    console.debug(`  ${this.constructor.name} Create  ${sql}`, values);

    const result = await db.query(sql, values);

    this.id = result.rows[0].id;
    this.attributes.id = this.id;
    this._persisted = true;
    console.log(`  ${this.constructor.name} Create (id: ${this.id})`);
    return true;
  }

  async _update() {
    this.attributes.updated_at = new Date().toISOString();

    const sets = [];
    const values = [];
    let paramIndex = 1;

    for (const [key, value] of Object.entries(this.attributes)) {
      if (key === 'id') continue;
      sets.push(`${key} = $${paramIndex++}`);
      values.push(value);
    }
    values.push(this.id);

    const sql = `UPDATE ${this.constructor.tableName} SET ${sets.join(', ')} WHERE id = $${paramIndex}`;
    console.debug(`  ${this.constructor.name} Update  ${sql}`, values);

    await db.query(sql, values);

    console.log(`  ${this.constructor.name} Update (id: ${this.id})`);
    return true;
  }

  static _buildWhere(conditions) {
    const clauses = [];
    const values = [];
    let paramIndex = 1;
    for (const [key, value] of Object.entries(conditions)) {
      clauses.push(`${key} = $${paramIndex++}`);
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
