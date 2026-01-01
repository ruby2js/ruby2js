// ActiveRecord adapter for PGLite (PostgreSQL in WebAssembly)
// This file is copied to dist/lib/active_record.mjs at build time
// PGLite provides PostgreSQL compatibility in the browser with optional IndexedDB persistence

import { ActiveRecordBase, attr_accessor, initTimePolyfill } from './active_record_base.mjs';

// Re-export shared utilities
export { attr_accessor };

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
    initTimePolyfill(window);
  } else {
    initTimePolyfill(globalThis);
  }

  return db;
}

// Execute raw SQL (for schema creation, migrations) - legacy, prefer createTable/addIndex
export async function execSQL(sql) {
  // exec() supports multiple statements, good for migrations
  return await db.exec(sql);
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
  return db.exec(sql);
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.join(', ') : columns;

  const sql = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  return db.exec(sql);
}

export async function addColumn(tableName, columnName, columnType) {
  const sqlType = PG_TYPE_MAP[columnType] || 'TEXT';
  const sql = `ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${sqlType}`;
  return db.exec(sql);
}

export async function removeColumn(tableName, columnName) {
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${columnName}`;
  return db.exec(sql);
}

export async function dropTable(tableName) {
  const sql = `DROP TABLE IF EXISTS ${tableName}`;
  return db.exec(sql);
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

// Get the raw database instance
export function getDatabase() {
  return db;
}

// Query interface for rails_base.js migration system
export async function query(sql, params = []) {
  const result = await db.query(sql, params);
  return result.rows;
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  const result = await db.query(sql, params);
  return { changes: result.affectedRows || 0 };
}

// Insert a row - PostgreSQL uses $1, $2, ... placeholders
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map((_, i) => `$${i + 1}`);
  const sql = `INSERT INTO ${tableName} (${keys.join(', ')}) VALUES (${placeholders.join(', ')})`;
  await db.query(sql, values);
}

// Close the database connection
export async function closeDatabase() {
  if (db) {
    await db.close();
    db = null;
  }
}

// PGLite-specific ActiveRecord implementation
export class ActiveRecord extends ActiveRecordBase {
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
