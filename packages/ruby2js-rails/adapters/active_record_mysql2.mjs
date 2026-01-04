// ActiveRecord adapter for MySQL (via mysql2)
// This file is copied to dist/lib/active_record.mjs at build time
// mysql2 is the standard MySQL client for Node.js

import mysql from 'mysql2/promise';

import { ActiveRecordBase, attr_accessor, initTimePolyfill } from './active_record_base.mjs';

// Re-export shared utilities
export { attr_accessor };

// Configuration injected at build time
const DB_CONFIG = {};

let pool = null;

// Parse DATABASE_URL if provided (12-factor app pattern)
function parseDatabaseUrl(url) {
  const parsed = new URL(url);
  return {
    host: parsed.hostname,
    port: parseInt(parsed.port) || 3306,
    database: parsed.pathname.slice(1),
    user: parsed.username,
    password: parsed.password,
    ssl: parsed.searchParams.get('ssl') === 'true' ? {} : undefined
  };
}

// Initialize the database connection pool
export async function initDatabase(options = {}) {
  // Priority: runtime DATABASE_URL > build-time config > options
  const runtimeUrl = process.env.DATABASE_URL;
  const config = runtimeUrl
    ? { ...parseDatabaseUrl(runtimeUrl), ...options }
    : { ...DB_CONFIG, ...options };

  pool = mysql.createPool({
    host: config.host || 'localhost',
    port: config.port || 3306,
    database: config.database || 'ruby2js_rails',
    user: config.user || config.username,
    password: config.password,
    connectionLimit: config.pool || 10,
    ssl: config.ssl
  });

  // Test connection
  const connection = await pool.getConnection();
  console.log(`Connected to MySQL: ${config.database}@${config.host || 'localhost'}`);
  connection.release();

  // Time polyfill for Ruby compatibility (Node.js global)
  initTimePolyfill(globalThis);

  return pool;
}

// Execute raw SQL (for schema creation) - legacy, prefer createTable/addIndex
export async function execSQL(sql) {
  const [result] = await pool.query(sql);
  return result;
}

// MySQL type mapping from abstract Rails types
const MYSQL_TYPE_MAP = {
  string: 'VARCHAR(255)',
  text: 'TEXT',
  integer: 'INT',
  bigint: 'BIGINT',
  float: 'DOUBLE',
  decimal: 'DECIMAL',
  boolean: 'TINYINT(1)',
  date: 'DATE',
  datetime: 'DATETIME',
  time: 'TIME',
  timestamp: 'TIMESTAMP',
  binary: 'BLOB',
  json: 'JSON',
  jsonb: 'JSON'
};

// Abstract DDL interface - creates MySQL tables from abstract schema
export async function createTable(tableName, columns, options = {}) {
  const columnDefs = columns.map(col => {
    const sqlType = getMysqlType(col);
    let def = `${col.name} ${sqlType}`;

    if (col.primaryKey) {
      def += ' PRIMARY KEY';
      if (col.autoIncrement) def += ' AUTO_INCREMENT';
    }
    if (col.null === false) def += ' NOT NULL';
    if (col.default !== undefined) {
      def += ` DEFAULT ${formatDefaultValue(col.default, col.type)}`;
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

  const sql = `CREATE TABLE IF NOT EXISTS ${tableName} (${columnDefs.join(', ')}) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`;
  const [result] = await pool.query(sql);
  return result;
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.join(', ') : columns;

  // MySQL doesn't support IF NOT EXISTS for CREATE INDEX, so we check first
  const sql = `CREATE ${unique}INDEX ${indexName} ON ${tableName}(${columnList})`;
  try {
    const [result] = await pool.query(sql);
    return result;
  } catch (e) {
    // Ignore duplicate key name error (index already exists)
    if (e.code !== 'ER_DUP_KEYNAME') throw e;
  }
}

export async function addColumn(tableName, columnName, columnType) {
  const sqlType = MYSQL_TYPE_MAP[columnType] || 'TEXT';
  const sql = `ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${sqlType}`;
  const [result] = await pool.query(sql);
  return result;
}

export async function removeColumn(tableName, columnName) {
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${columnName}`;
  const [result] = await pool.query(sql);
  return result;
}

export async function dropTable(tableName) {
  const sql = `DROP TABLE IF EXISTS ${tableName}`;
  const [result] = await pool.query(sql);
  return result;
}

function getMysqlType(col) {
  let baseType = MYSQL_TYPE_MAP[col.type] || 'TEXT';

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
  if (typeof value === 'boolean') return value ? '1' : '0';
  return String(value);
}

// Get the raw database pool
export function getDatabase() {
  return pool;
}

// Query interface for rails_base.js migration system
export async function query(sql, params = []) {
  const [rows] = await pool.query(sql, params);
  return rows;
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  const [result] = await pool.query(sql, params);
  return { changes: result.affectedRows || 0 };
}

// Insert a row - MySQL uses ? placeholders
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map(() => '?');
  const sql = `INSERT INTO ${tableName} (${keys.join(', ')}) VALUES (${placeholders.join(', ')})`;
  await pool.query(sql, values);
}

// Close the connection pool (for graceful shutdown)
export async function closeDatabase() {
  if (pool) {
    await pool.end();
    pool = null;
  }
}

// MySQL-specific ActiveRecord implementation
export class ActiveRecord extends ActiveRecordBase {
  // --- Class Methods (finders) ---

  static async all() {
    const [rows] = await pool.query(`SELECT * FROM ${this.tableName}`);
    return rows.map(row => new this(row));
  }

  static async find(id) {
    const [rows] = await pool.query(
      `SELECT * FROM ${this.tableName} WHERE id = ?`,
      [id]
    );
    if (rows.length === 0) {
      throw new Error(`${this.name} not found with id=${id}`);
    }
    return new this(rows[0]);
  }

  static async findBy(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const [rows] = await pool.query(
      `SELECT * FROM ${this.tableName} WHERE ${where} LIMIT 1`,
      values
    );
    return rows.length > 0 ? new this(rows[0]) : null;
  }

  static async where(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const [rows] = await pool.query(
      `SELECT * FROM ${this.tableName} WHERE ${where}`,
      values
    );
    return rows.map(row => new this(row));
  }

  static async count() {
    const [rows] = await pool.query(`SELECT COUNT(*) as count FROM ${this.tableName}`);
    return parseInt(rows[0].count);
  }

  static async first() {
    const [rows] = await pool.query(
      `SELECT * FROM ${this.tableName} ORDER BY id ASC LIMIT 1`
    );
    return rows.length > 0 ? new this(rows[0]) : null;
  }

  static async last() {
    const [rows] = await pool.query(
      `SELECT * FROM ${this.tableName} ORDER BY id DESC LIMIT 1`
    );
    return rows.length > 0 ? new this(rows[0]) : null;
  }

  // Order records by column - returns array of models
  // Usage: Message.order({created_at: 'asc'}) or Message.order('created_at')
  static async order(options) {
    let column, direction;
    if (typeof options === 'string') {
      column = options;
      direction = 'ASC';
    } else {
      column = Object.keys(options)[0];
      direction = (options[column] === 'desc' || options[column] === ':desc') ? 'DESC' : 'ASC';
    }
    const [rows] = await pool.query(`SELECT * FROM ${this.tableName} ORDER BY ${column} ${direction}`);
    return rows.map(row => new this(row));
  }

  // --- Instance Methods ---

  async destroy() {
    if (!this._persisted) return false;
    await pool.query(
      `DELETE FROM ${this.constructor.tableName} WHERE id = ?`,
      [this.id]
    );
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

    const [result] = await pool.query(sql, values);

    this.id = result.insertId;
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

    await pool.query(sql, values);

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
