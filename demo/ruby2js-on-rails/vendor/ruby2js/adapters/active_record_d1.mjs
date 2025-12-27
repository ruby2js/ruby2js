// ActiveRecord adapter for Cloudflare D1 (SQLite at the edge)
// This file is copied to dist/lib/active_record.mjs at build time
// D1 is Cloudflare's serverless SQLite database, accessed via Worker bindings

// Configuration injected at build time
const DB_CONFIG = {};

let db = null;

// Initialize the database with D1 binding from Worker env
// Called with env.DB from the Worker's fetch handler
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };

  // D1 binding must be passed in - it comes from the Worker's env
  if (config.binding) {
    db = config.binding;
  } else if (config.env && config.env[config.bindingName || 'DB']) {
    db = config.env[config.bindingName || 'DB'];
  } else {
    throw new Error('D1 binding not provided. Pass { binding: env.DB } or { env, bindingName: "DB" }');
  }

  // Time polyfill for Ruby compatibility
  globalThis.Time = {
    now() {
      return { toString() { return new Date().toISOString(); } };
    }
  };

  console.log('Connected to Cloudflare D1');
  return db;
}

// Execute raw SQL (for schema creation, migrations)
export async function execSQL(sql) {
  // D1's exec() supports multiple statements
  return await db.exec(sql);
}

// SQLite type mapping from abstract Rails types
const SQLITE_TYPE_MAP = {
  string: 'TEXT',
  text: 'TEXT',
  integer: 'INTEGER',
  bigint: 'INTEGER',
  float: 'REAL',
  decimal: 'REAL',
  boolean: 'INTEGER',
  date: 'TEXT',
  datetime: 'TEXT',
  time: 'TEXT',
  timestamp: 'TEXT',
  binary: 'BLOB',
  json: 'TEXT',
  jsonb: 'TEXT'
};

// Abstract DDL interface - creates SQLite tables from abstract schema
export async function createTable(tableName, columns, options = {}) {
  const columnDefs = columns.map(col => {
    const sqlType = SQLITE_TYPE_MAP[col.type] || 'TEXT';
    let def = `${col.name} ${sqlType}`;

    if (col.primaryKey) {
      def += ' PRIMARY KEY';
      if (col.autoIncrement) def += ' AUTOINCREMENT';
    }
    if (col.null === false) def += ' NOT NULL';
    if (col.default !== undefined) {
      def += ` DEFAULT ${formatDefaultValue(col.default)}`;
    }

    return def;
  });

  // Add foreign key constraints
  if (options.foreignKeys) {
    for (const fk of options.foreignKeys) {
      columnDefs.push(
        `FOREIGN KEY (${fk.column}) REFERENCES ${fk.references}(${fk.primaryKey})`
      );
    }
  }

  const sql = `CREATE TABLE IF NOT EXISTS ${tableName} (${columnDefs.join(', ')})`;
  return await db.exec(sql);
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.join(', ') : columns;

  const sql = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  return await db.exec(sql);
}

function formatDefaultValue(value) {
  if (value === null) return 'NULL';
  if (typeof value === 'string') return `'${value.replace(/'/g, "''")}'`;
  if (typeof value === 'boolean') return value ? '1' : '0';
  return String(value);
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

  static async all() {
    const result = await db.prepare(`SELECT * FROM ${this.tableName}`).all();
    return result.results.map(row => new this(row));
  }

  static async find(id) {
    const result = await db.prepare(`SELECT * FROM ${this.tableName} WHERE id = ?`).bind(id).first();
    if (!result) {
      throw new Error(`${this.name} not found with id=${id}`);
    }
    return new this(result);
  }

  static async findBy(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const stmt = db.prepare(`SELECT * FROM ${this.tableName} WHERE ${where} LIMIT 1`);
    const result = await stmt.bind(...values).first();
    return result ? new this(result) : null;
  }

  static async where(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const stmt = db.prepare(`SELECT * FROM ${this.tableName} WHERE ${where}`);
    const result = await stmt.bind(...values).all();
    return result.results.map(row => new this(row));
  }

  static async create(attributes) {
    const record = new this(attributes);
    await record.save();
    return record;
  }

  static async count() {
    const result = await db.prepare(`SELECT COUNT(*) as count FROM ${this.tableName}`).first();
    return result.count;
  }

  static async first() {
    const result = await db.prepare(`SELECT * FROM ${this.tableName} ORDER BY id ASC LIMIT 1`).first();
    return result ? new this(result) : null;
  }

  static async last() {
    const result = await db.prepare(`SELECT * FROM ${this.tableName} ORDER BY id DESC LIMIT 1`).first();
    return result ? new this(result) : null;
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
    await db.prepare(`DELETE FROM ${this.constructor.tableName} WHERE id = ?`).bind(this.id).run();
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

    for (const [key, value] of Object.entries(this.attributes)) {
      if (key === 'id') continue;
      cols.push(key);
      placeholders.push('?');
      values.push(value);
    }

    const sql = `INSERT INTO ${this.constructor.tableName} (${cols.join(', ')}) VALUES (${placeholders.join(', ')}) RETURNING id`;
    console.debug(`  ${this.constructor.name} Create  ${sql}`, values);

    const stmt = db.prepare(sql);
    const result = await stmt.bind(...values).first();

    this.id = result.id;
    this.attributes.id = this.id;
    this._persisted = true;
    console.log(`  ${this.constructor.name} Create (id: ${this.id})`);
    return true;
  }

  async _update() {
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
    await stmt.bind(...values).run();

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
