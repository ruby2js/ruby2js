// ActiveRecord adapter for better-sqlite3 (Node.js synchronous SQLite)
// This file is copied to dist/lib/active_record.mjs at build time
// better-sqlite3 is a fast, synchronous SQLite3 binding for Node.js

import Database from 'better-sqlite3';

import { ActiveRecordBase, attr_accessor, initTimePolyfill } from './active_record_base.mjs';

// Re-export shared utilities
export { attr_accessor };

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
  initTimePolyfill(globalThis);

  return db;
}

// Execute raw SQL (for schema creation) - legacy, prefer createTable/addIndex
export function execSQL(sql) {
  return db.exec(sql);
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
export function createTable(tableName, columns, options = {}) {
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
  return db.exec(sql);
}

export function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.join(', ') : columns;

  const sql = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  return db.exec(sql);
}

export function addColumn(tableName, columnName, columnType) {
  const sqlType = SQLITE_TYPE_MAP[columnType] || 'TEXT';
  const sql = `ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${sqlType}`;
  return db.exec(sql);
}

export function removeColumn(tableName, columnName) {
  // SQLite doesn't support DROP COLUMN directly in older versions
  // For SQLite 3.35.0+ (2021-03-12), this works:
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${columnName}`;
  return db.exec(sql);
}

export function dropTable(tableName) {
  const sql = `DROP TABLE IF EXISTS ${tableName}`;
  return db.exec(sql);
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

// Query interface for rails_base.js migration system
export async function query(sql, params = []) {
  const stmt = db.prepare(sql);
  return stmt.all(...params);
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  const stmt = db.prepare(sql);
  return stmt.run(...params);
}

// Insert a row - SQLite uses ? placeholders
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map(() => '?');
  const sql = `INSERT INTO ${tableName} (${keys.join(', ')}) VALUES (${placeholders.join(', ')})`;
  const stmt = db.prepare(sql);
  stmt.run(...values);
}

// better-sqlite3-specific ActiveRecord implementation
export class ActiveRecord extends ActiveRecordBase {
  // --- Class Methods (finders) ---

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
