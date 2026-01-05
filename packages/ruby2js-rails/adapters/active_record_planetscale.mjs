// ActiveRecord adapter for PlanetScale (Serverless MySQL)
// This file is copied to dist/lib/active_record.mjs at build time
// PlanetScale uses HTTP, works in browser, Node.js, and edge runtimes

import { connect } from '@planetscale/database';

import { ActiveRecordBase, attr_accessor, initTimePolyfill } from './active_record_base.mjs';

// Re-export shared utilities
export { attr_accessor };

// Configuration injected at build time
const DB_CONFIG = {};

let connection = null;

// Initialize the database connection
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };

  // Connection URL: runtime env > options > build-time config
  const url = process.env.DATABASE_URL || config.url || config.database_url;

  if (url) {
    // Parse DATABASE_URL format: mysql://user:pass@host/database?ssl=...
    connection = connect({ url });
  } else {
    // Individual credentials
    const host = process.env.PLANETSCALE_HOST || config.host;
    const username = process.env.PLANETSCALE_USERNAME || config.username || config.user;
    const password = process.env.PLANETSCALE_PASSWORD || config.password;

    if (!host || !username || !password) {
      throw new Error('PlanetScale requires DATABASE_URL or host/username/password configuration');
    }

    connection = connect({ host, username, password });
  }

  // Time polyfill for Ruby compatibility
  initTimePolyfill(globalThis);

  // Extract database info for logging
  const dbInfo = url ? new URL(url).pathname.slice(1) : config.host;
  console.log(`Connected to PlanetScale: ${dbInfo}`);

  return connection;
}

// Execute raw SQL (for schema creation)
export async function execSQL(sql) {
  const result = await connection.execute(sql);
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
  // Note: PlanetScale doesn't support foreign key constraints by default
  // (uses Vitess which requires careful FK handling)
  // We include them for compatibility but they may be ignored

  const sql = `CREATE TABLE IF NOT EXISTS ${tableName} (${columnDefs.join(', ')}) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`;
  return await connection.execute(sql);
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.join(', ') : columns;

  const sql = `CREATE ${unique}INDEX ${indexName} ON ${tableName}(${columnList})`;
  try {
    return await connection.execute(sql);
  } catch (e) {
    // Ignore duplicate key name error (index already exists)
    if (!e.message?.includes('Duplicate')) throw e;
  }
}

export async function addColumn(tableName, columnName, columnType) {
  const sqlType = MYSQL_TYPE_MAP[columnType] || 'TEXT';
  const sql = `ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${sqlType}`;
  return await connection.execute(sql);
}

export async function removeColumn(tableName, columnName) {
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${columnName}`;
  return await connection.execute(sql);
}

export async function dropTable(tableName) {
  const sql = `DROP TABLE IF EXISTS ${tableName}`;
  return await connection.execute(sql);
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

// Get the raw database connection
export function getDatabase() {
  return connection;
}

// Query interface for rails_base.js migration system
export async function query(sql, params = []) {
  const result = await connection.execute(sql, params);
  return result.rows;
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  const result = await connection.execute(sql, params);
  return { changes: result.rowsAffected || 0 };
}

// Insert a row - MySQL uses ? placeholders
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map(() => '?');
  const sql = `INSERT INTO ${tableName} (${keys.join(', ')}) VALUES (${placeholders.join(', ')})`;
  await connection.execute(sql, values);
}

// Close the connection (no-op for HTTP-based PlanetScale)
export async function closeDatabase() {
  connection = null;
}

// PlanetScale-specific ActiveRecord implementation
export class ActiveRecord extends ActiveRecordBase {
  // --- Class Methods (finders) ---

  static async all() {
    const result = await connection.execute(`SELECT * FROM ${this.tableName}`);
    return result.rows.map(row => new this(row));
  }

  static async find(id) {
    const result = await connection.execute(
      `SELECT * FROM ${this.tableName} WHERE id = ?`,
      [id]
    );
    if (result.rows.length === 0) {
      throw new Error(`${this.name} not found with id=${id}`);
    }
    return new this(result.rows[0]);
  }

  static async findBy(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const result = await connection.execute(
      `SELECT * FROM ${this.tableName} WHERE ${where} LIMIT 1`,
      values
    );
    return result.rows.length > 0 ? new this(result.rows[0]) : null;
  }

  static async where(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const result = await connection.execute(
      `SELECT * FROM ${this.tableName} WHERE ${where}`,
      values
    );
    return result.rows.map(row => new this(row));
  }

  static async count() {
    const result = await connection.execute(`SELECT COUNT(*) as count FROM ${this.tableName}`);
    return parseInt(result.rows[0].count);
  }

  static async first() {
    const result = await connection.execute(
      `SELECT * FROM ${this.tableName} ORDER BY id ASC LIMIT 1`
    );
    return result.rows.length > 0 ? new this(result.rows[0]) : null;
  }

  static async last() {
    const result = await connection.execute(
      `SELECT * FROM ${this.tableName} ORDER BY id DESC LIMIT 1`
    );
    return result.rows.length > 0 ? new this(result.rows[0]) : null;
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
    const result = await connection.execute(`SELECT * FROM ${this.tableName} ORDER BY ${column} ${direction}`);
    return result.rows.map(row => new this(row));
  }

  // --- Instance Methods ---

  async destroy() {
    if (!this._persisted) return false;
    await connection.execute(
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

    const result = await connection.execute(sql, values);

    this.id = Number(result.insertId);
    this.attributes.id = this.id;
    this._persisted = true;
    console.log(`  ${this.constructor.name} Create (id: ${this.id})`);
    return true;
  }

  async _update() {
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

    await connection.execute(sql, values);

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
