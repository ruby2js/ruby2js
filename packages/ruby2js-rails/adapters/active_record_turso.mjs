// ActiveRecord adapter for Turso (libSQL - SQLite at the edge)
// This file is copied to dist/lib/active_record.mjs at build time
// Turso uses HTTP/WebSocket, works in browser, Node.js, and edge runtimes

import { createClient } from '@libsql/client';

import { ActiveRecordBase, attr_accessor, initTimePolyfill } from './active_record_base.mjs';

// Re-export shared utilities
export { attr_accessor };

// Configuration injected at build time
const DB_CONFIG = {};

let client = null;

// Initialize the database connection
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };

  // Connection URL: runtime env > options > build-time config
  const url = process.env.TURSO_DATABASE_URL || config.url || config.database_url;
  const authToken = process.env.TURSO_AUTH_TOKEN || config.auth_token || config.authToken;

  if (!url) {
    throw new Error('Turso requires TURSO_DATABASE_URL environment variable or url option');
  }

  const clientConfig = { url };

  // Auth token required for remote databases (not for local file:// URLs)
  if (authToken) {
    clientConfig.authToken = authToken;
  }

  // Embedded replica support (local SQLite that syncs with remote)
  // Useful for read-heavy workloads with local caching
  if (config.syncUrl || config.sync_url) {
    clientConfig.syncUrl = config.syncUrl || config.sync_url;
    clientConfig.syncInterval = config.syncInterval || config.sync_interval || 60;
  }

  client = createClient(clientConfig);

  // Time polyfill for Ruby compatibility
  initTimePolyfill(globalThis);

  // Extract database name from URL for logging
  const dbName = url.match(/libsql:\/\/([^.]+)/)?.[1] || url.split('/').pop() || 'turso';
  console.log(`Connected to Turso: ${dbName}`);

  return client;
}

// Execute raw SQL (for schema creation, migrations)
export async function execSQL(sql) {
  // Handle multiple statements separated by semicolons
  const statements = sql.split(';').filter(s => s.trim());
  for (const stmt of statements) {
    if (stmt.trim()) {
      await client.execute(stmt);
    }
  }
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
  return await client.execute(sql);
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.join(', ') : columns;

  const sql = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  return await client.execute(sql);
}

export async function addColumn(tableName, columnName, columnType) {
  const sqlType = SQLITE_TYPE_MAP[columnType] || 'TEXT';
  const sql = `ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${sqlType}`;
  return await client.execute(sql);
}

export async function removeColumn(tableName, columnName) {
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${columnName}`;
  return await client.execute(sql);
}

export async function dropTable(tableName) {
  const sql = `DROP TABLE IF EXISTS ${tableName}`;
  return await client.execute(sql);
}

function formatDefaultValue(value) {
  if (value === null) return 'NULL';
  if (typeof value === 'string') return `'${value.replace(/'/g, "''")}'`;
  if (typeof value === 'boolean') return value ? '1' : '0';
  return String(value);
}

// Get the raw database client
export function getDatabase() {
  return client;
}

// Query interface for rails_base.js migration system
export async function query(sql, params = []) {
  const result = await client.execute({ sql, args: params });
  return result.rows.map(row => {
    // Convert row to plain object
    const obj = {};
    for (const [key, value] of Object.entries(row)) {
      obj[key] = value;
    }
    return obj;
  });
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  const result = await client.execute({ sql, args: params });
  return { changes: result.rowsAffected || 0 };
}

// Close the connection
export async function closeDatabase() {
  if (client) {
    client.close();
    client = null;
  }
}

// Turso-specific ActiveRecord implementation
export class ActiveRecord extends ActiveRecordBase {
  // --- Class Methods (finders) ---

  static async all() {
    const result = await client.execute(`SELECT * FROM ${this.tableName}`);
    return result.rows.map(row => new this(this._rowToObject(row)));
  }

  static async find(id) {
    const result = await client.execute({
      sql: `SELECT * FROM ${this.tableName} WHERE id = ?`,
      args: [id]
    });
    if (result.rows.length === 0) {
      throw new Error(`${this.name} not found with id=${id}`);
    }
    return new this(this._rowToObject(result.rows[0]));
  }

  static async findBy(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const result = await client.execute({
      sql: `SELECT * FROM ${this.tableName} WHERE ${where} LIMIT 1`,
      args: values
    });
    return result.rows.length > 0 ? new this(this._rowToObject(result.rows[0])) : null;
  }

  static async where(conditions) {
    const { where, values } = this._buildWhere(conditions);
    const result = await client.execute({
      sql: `SELECT * FROM ${this.tableName} WHERE ${where}`,
      args: values
    });
    return result.rows.map(row => new this(this._rowToObject(row)));
  }

  static async count() {
    const result = await client.execute(`SELECT COUNT(*) as count FROM ${this.tableName}`);
    return Number(result.rows[0].count);
  }

  static async first() {
    const result = await client.execute(`SELECT * FROM ${this.tableName} ORDER BY id ASC LIMIT 1`);
    return result.rows.length > 0 ? new this(this._rowToObject(result.rows[0])) : null;
  }

  static async last() {
    const result = await client.execute(`SELECT * FROM ${this.tableName} ORDER BY id DESC LIMIT 1`);
    return result.rows.length > 0 ? new this(this._rowToObject(result.rows[0])) : null;
  }

  // --- Instance Methods ---

  async destroy() {
    if (!this._persisted) return false;
    await client.execute({
      sql: `DELETE FROM ${this.constructor.tableName} WHERE id = ?`,
      args: [this.id]
    });
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

    for (const [key, value] of Object.entries(this.attributes)) {
      if (key === 'id') continue;
      cols.push(key);
      placeholders.push('?');
      values.push(value);
    }

    const sql = `INSERT INTO ${this.constructor.tableName} (${cols.join(', ')}) VALUES (${placeholders.join(', ')}) RETURNING id`;
    console.debug(`  ${this.constructor.name} Create  ${sql}`, values);

    const result = await client.execute({ sql, args: values });

    // libSQL returns lastInsertRowid for inserts
    this.id = result.rows[0]?.id ?? Number(result.lastInsertRowid);
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

    await client.execute({ sql, args: values });

    console.log(`  ${this.constructor.name} Update (id: ${this.id})`);
    return true;
  }

  // Convert libSQL row (array-like with column names) to plain object
  static _rowToObject(row) {
    // libSQL rows are already object-like, but may need normalization
    if (Array.isArray(row)) {
      // Shouldn't happen with default config, but handle it
      return row;
    }
    // Row is already an object with column names as keys
    return { ...row };
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
    return rows.map(row => new this(this._rowToObject(row)));
  }
}
