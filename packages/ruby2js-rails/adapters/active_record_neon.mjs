// ActiveRecord adapter for Neon (Serverless Postgres)
// This file is copied to dist/lib/active_record.mjs at build time
// Neon uses HTTP/WebSocket, works in browser, Node.js, and edge runtimes

import { neon } from '@neondatabase/serverless';

import { ActiveRecordBase, attr_accessor, initTimePolyfill } from './active_record_base.mjs';

// Re-export shared utilities
export { attr_accessor };

// Configuration injected at build time
const DB_CONFIG = {};

let sql = null;

// Initialize the database connection
export async function initDatabase(options = {}) {
  // Priority: runtime DATABASE_URL > options.url > build-time config
  const connectionString = process.env.DATABASE_URL || options.url || DB_CONFIG.url;

  if (!connectionString) {
    throw new Error('Neon requires DATABASE_URL environment variable or url option');
  }

  sql = neon(connectionString);

  // Time polyfill for Ruby compatibility
  initTimePolyfill(globalThis);

  // Extract database name from connection string for logging
  const dbName = connectionString.match(/@[^/]+\/([^?]+)/)?.[1] || 'neon';
  console.log(`Connected to Neon: ${dbName}`);

  return sql;
}

// Execute raw SQL (for schema creation) - legacy, prefer createTable/addIndex
export async function execSQL(sqlString) {
  const result = await sql(sqlString);
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

  const ddl = `CREATE TABLE IF NOT EXISTS ${tableName} (${columnDefs.join(', ')})`;
  return sql(ddl);
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.join(', ') : columns;

  const ddl = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  return sql(ddl);
}

export async function addColumn(tableName, columnName, columnType) {
  const sqlType = PG_TYPE_MAP[columnType] || 'TEXT';
  const ddl = `ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${sqlType}`;
  return sql(ddl);
}

export async function removeColumn(tableName, columnName) {
  const ddl = `ALTER TABLE ${tableName} DROP COLUMN ${columnName}`;
  return sql(ddl);
}

export async function dropTable(tableName) {
  const ddl = `DROP TABLE IF EXISTS ${tableName}`;
  return sql(ddl);
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

// Get the raw database connection
export function getDatabase() {
  return sql;
}

// Close the connection (no-op for HTTP-based Neon)
export async function closeDatabase() {
  sql = null;
}

// Neon-specific ActiveRecord implementation
export class ActiveRecord extends ActiveRecordBase {
  // --- Class Methods (finders) ---

  static async all() {
    const rows = await sql(`SELECT * FROM ${this.tableName}`);
    return rows.map(row => new this(row));
  }

  static async find(id) {
    const rows = await sql(`SELECT * FROM ${this.tableName} WHERE id = $1`, [id]);
    if (rows.length === 0) {
      throw new Error(`${this.name} not found with id=${id}`);
    }
    return new this(rows[0]);
  }

  static async findBy(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const rows = await sql(`SELECT * FROM ${this.tableName} WHERE ${where} LIMIT 1`, values);
    return rows.length > 0 ? new this(rows[0]) : null;
  }

  static async where(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const rows = await sql(`SELECT * FROM ${this.tableName} WHERE ${where}`, values);
    return rows.map(row => new this(row));
  }

  static async count() {
    const rows = await sql(`SELECT COUNT(*) as count FROM ${this.tableName}`);
    return parseInt(rows[0].count);
  }

  static async first() {
    const rows = await sql(`SELECT * FROM ${this.tableName} ORDER BY id ASC LIMIT 1`);
    return rows.length > 0 ? new this(rows[0]) : null;
  }

  static async last() {
    const rows = await sql(`SELECT * FROM ${this.tableName} ORDER BY id DESC LIMIT 1`);
    return rows.length > 0 ? new this(rows[0]) : null;
  }

  // --- Instance Methods ---

  async destroy() {
    if (!this._persisted) return false;
    await sql(`DELETE FROM ${this.constructor.tableName} WHERE id = $1`, [this.id]);
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

    const query = `INSERT INTO ${this.constructor.tableName} (${cols.join(', ')}) VALUES (${placeholders.join(', ')}) RETURNING id`;
    console.debug(`  ${this.constructor.name} Create  ${query}`, values);

    const rows = await sql(query, values);

    this.id = rows[0].id;
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

    const query = `UPDATE ${this.constructor.tableName} SET ${sets.join(', ')} WHERE id = $${paramIndex}`;
    console.debug(`  ${this.constructor.name} Update  ${query}`, values);

    await sql(query, values);

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
