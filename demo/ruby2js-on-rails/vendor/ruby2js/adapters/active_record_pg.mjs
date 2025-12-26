// ActiveRecord adapter for PostgreSQL (via node-postgres/pg)
// This file is copied to dist/lib/active_record.mjs at build time
// pg is the standard PostgreSQL client for Node.js

import pg from 'pg';
const { Pool } = pg;

// Configuration injected at build time
const DB_CONFIG = {};

let pool = null;

// Parse DATABASE_URL if provided (12-factor app pattern)
function parseDatabaseUrl(url) {
  const parsed = new URL(url);
  return {
    host: parsed.hostname,
    port: parseInt(parsed.port) || 5432,
    database: parsed.pathname.slice(1),
    user: parsed.username,
    password: parsed.password,
    ssl: parsed.searchParams.get('sslmode') === 'require' ? { rejectUnauthorized: false } : false
  };
}

// Initialize the database connection pool
export async function initDatabase(options = {}) {
  // Priority: runtime DATABASE_URL > build-time config > options
  const runtimeUrl = process.env.DATABASE_URL;
  const config = runtimeUrl
    ? { ...parseDatabaseUrl(runtimeUrl), ...options }
    : { ...DB_CONFIG, ...options };

  pool = new Pool({
    host: config.host || 'localhost',
    port: config.port || 5432,
    database: config.database || 'ruby2js_rails',
    user: config.user || config.username,
    password: config.password,
    max: config.pool || 10,
    ssl: config.ssl
  });

  // Test connection
  const client = await pool.connect();
  console.log(`Connected to PostgreSQL: ${config.database}@${config.host || 'localhost'}`);
  client.release();

  // Time polyfill for Ruby compatibility (Node.js global)
  globalThis.Time = {
    now() {
      return { toString() { return new Date().toISOString(); } };
    }
  };

  return pool;
}

// Execute raw SQL (for schema creation) - legacy, prefer createTable/addIndex
export async function execSQL(sql) {
  const result = await pool.query(sql);
  return result;
}

// PostgreSQL type mapping from abstract Rails types
const PG_TYPE_MAP = {
  string: 'VARCHAR(255)',
  text: 'TEXT',
  integer: 'INTEGER',
  bigint: 'BIGINT',
  float: 'DOUBLE PRECISION',
  decimal: 'DECIMAL',
  boolean: 'BOOLEAN',
  date: 'DATE',
  datetime: 'TIMESTAMP',
  time: 'TIME',
  timestamp: 'TIMESTAMP',
  binary: 'BYTEA',
  json: 'JSON',
  jsonb: 'JSONB'
};

// Abstract DDL interface - creates PostgreSQL tables from abstract schema
export async function createTable(tableName, columns, options = {}) {
  const columnDefs = columns.map(col => {
    let def;

    if (col.primaryKey && col.autoIncrement) {
      // PostgreSQL uses SERIAL for auto-incrementing primary keys
      def = `${col.name} SERIAL PRIMARY KEY`;
    } else {
      const sqlType = getPgType(col);
      def = `${col.name} ${sqlType}`;

      if (col.primaryKey) def += ' PRIMARY KEY';
      if (col.null === false) def += ' NOT NULL';
      if (col.default !== undefined) {
        def += ` DEFAULT ${formatDefaultValue(col.default, col.type)}`;
      }
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
  return pool.query(sql);
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.join(', ') : columns;

  const sql = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  return pool.query(sql);
}

function getPgType(col) {
  let baseType = PG_TYPE_MAP[col.type] || 'TEXT';

  // Handle precision/scale for decimal
  if (col.type === 'decimal' && (col.precision || col.scale)) {
    const precision = col.precision || 10;
    const scale = col.scale || 0;
    baseType = `DECIMAL(${precision}, ${scale})`;
  }

  // Handle limit for string
  if (col.type === 'string' && col.limit) {
    baseType = `VARCHAR(${col.limit})`;
  }

  return baseType;
}

function formatDefaultValue(value, type) {
  if (value === null) return 'NULL';
  if (typeof value === 'string') return `'${value.replace(/'/g, "''")}'`;
  if (typeof value === 'boolean') return value ? 'TRUE' : 'FALSE';
  return String(value);
}

// Get the raw database pool
export function getDatabase() {
  return pool;
}

// Close the connection pool (for graceful shutdown)
export async function closeDatabase() {
  if (pool) {
    await pool.end();
    pool = null;
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
    const result = await pool.query(`SELECT * FROM ${this.tableName}`);
    return result.rows.map(row => new this(row));
  }

  static async find(id) {
    const result = await pool.query(
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
    const result = await pool.query(
      `SELECT * FROM ${this.tableName} WHERE ${where} LIMIT 1`,
      values
    );
    return result.rows.length > 0 ? new this(result.rows[0]) : null;
  }

  static async where(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const result = await pool.query(
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
    const result = await pool.query(`SELECT COUNT(*) FROM ${this.tableName}`);
    return parseInt(result.rows[0].count);
  }

  static async first() {
    const result = await pool.query(
      `SELECT * FROM ${this.tableName} ORDER BY id ASC LIMIT 1`
    );
    return result.rows.length > 0 ? new this(result.rows[0]) : null;
  }

  static async last() {
    const result = await pool.query(
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
    await pool.query(
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

    const result = await pool.query(sql, values);

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

    await pool.query(sql, values);

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
