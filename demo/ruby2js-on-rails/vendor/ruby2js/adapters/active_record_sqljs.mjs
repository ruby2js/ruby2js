// ActiveRecord adapter for sql.js (SQLite in WebAssembly)
// This file is copied to dist/lib/active_record.mjs at build time

// Configuration injected at build time
const DB_CONFIG = {};

let db = null;

// Initialize the database
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };
  // Check for global path override (for hosted environments like ruby2js.com)
  const sqlJsPath = (typeof window !== 'undefined' && window.SQL_WASM_PATH)
    || config.sqlJsPath
    || '/node_modules/sql.js/dist';

  const SQL = await window.initSqlJs({
    locateFile: file => `${sqlJsPath}/${file}`
  });

  db = new SQL.Database();

  // Time polyfill for Ruby compatibility
  window.Time = {
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
  // All methods are async for consistency with other adapters (Dexie, pg, etc.)

  static async all() {
    const sql = `SELECT * FROM ${this.tableName}`;
    const result = db.exec(sql);
    if (!result.length) return [];
    return this._resultToModels(result[0]);
  }

  static async find(id) {
    const stmt = db.prepare(`SELECT * FROM ${this.tableName} WHERE id = ?`);
    stmt.bind([id]);
    if (stmt.step()) {
      const obj = stmt.getAsObject();
      stmt.free();
      return new this(obj);
    }
    stmt.free();
    throw new Error(`${this.name} not found with id=${id}`);
  }

  static async findBy(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const stmt = db.prepare(`SELECT * FROM ${this.tableName} WHERE ${where} LIMIT 1`);
    stmt.bind(values);
    if (stmt.step()) {
      const obj = stmt.getAsObject();
      stmt.free();
      return new this(obj);
    }
    stmt.free();
    return null;
  }

  static async where(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const sql = `SELECT * FROM ${this.tableName} WHERE ${where}`;
    const stmt = db.prepare(sql);
    stmt.bind(values);

    const results = [];
    while (stmt.step()) {
      results.push(new this(stmt.getAsObject()));
    }
    stmt.free();
    return results;
  }

  static async create(attributes) {
    const record = new this(attributes);
    await record.save();
    return record;
  }

  static async count() {
    const result = db.exec(`SELECT COUNT(*) FROM ${this.tableName}`);
    return result[0].values[0][0];
  }

  static async first() {
    const result = db.exec(`SELECT * FROM ${this.tableName} ORDER BY id ASC LIMIT 1`);
    if (!result.length || !result[0].values.length) return null;
    return this._resultToModels(result[0])[0];
  }

  static async last() {
    const result = db.exec(`SELECT * FROM ${this.tableName} ORDER BY id DESC LIMIT 1`);
    if (!result.length || !result[0].values.length) return null;
    return this._resultToModels(result[0])[0];
  }

  // --- Instance Methods ---
  // All methods are async for consistency with other adapters

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
    return this.save();
  }

  async destroy() {
    if (!this._persisted) return false;
    db.run(`DELETE FROM ${this.constructor.tableName} WHERE id = ?`, [this.id]);
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
    db.run(sql, values);

    const idResult = db.exec('SELECT last_insert_rowid()');
    this.id = idResult[0].values[0][0];
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
    db.run(sql, values);
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

  static _resultToModels(result) {
    const { columns, values } = result;
    return values.map(row => {
      const obj = {};
      columns.forEach((col, i) => obj[col] = row[i]);
      return new this(obj);
    });
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
