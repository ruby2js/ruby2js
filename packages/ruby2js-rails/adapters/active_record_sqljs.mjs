// ActiveRecord adapter for sql.js (SQLite in WebAssembly)
// This file is copied to dist/lib/active_record.mjs at build time

import { ActiveRecordBase, attr_accessor, initTimePolyfill } from './active_record_base.mjs';

// Re-export shared utilities
export { attr_accessor };

// Configuration injected at build time
const DB_CONFIG = {};

let db = null;

// Dynamically load sql-wasm.js if not already loaded
async function loadSqlJs(scriptPath) {
  if (typeof window !== 'undefined' && window.initSqlJs) {
    return; // Already loaded
  }

  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = scriptPath;
    script.onload = resolve;
    script.onerror = () => reject(new Error(`Failed to load sql.js from ${scriptPath}`));
    document.head.appendChild(script);
  });
}

// Initialize the database
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };

  // Determine sql.js path based on environment
  // Priority: config option > base href detection > default path
  let sqlJsPath = config.sqlJsPath;
  if (!sqlJsPath) {
    // Check for <base href> tag (used in hosted demo)
    const baseTag = document.querySelector('base[href]');
    if (baseTag) {
      const baseHref = baseTag.getAttribute('href');
      sqlJsPath = `${baseHref}node_modules/sql.js/dist`;
    } else {
      sqlJsPath = '/node_modules/sql.js/dist';
    }
  }

  // Load sql-wasm.js dynamically if needed
  await loadSqlJs(`${sqlJsPath}/sql-wasm.js`);

  const SQL = await window.initSqlJs({
    locateFile: file => `${sqlJsPath}/${file}`
  });

  db = new SQL.Database();

  // Time polyfill for Ruby compatibility
  initTimePolyfill(window);

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
  // sql.js uses SQLite which supports DROP COLUMN in 3.35.0+
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
  stmt.bind(params);
  const results = [];
  while (stmt.step()) {
    results.push(stmt.getAsObject());
  }
  stmt.free();
  return results;
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  db.run(sql, params);
  return { changes: db.getRowsModified() };
}

// Insert a row - SQLite uses ? placeholders
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map(() => '?');
  const sql = `INSERT INTO ${tableName} (${keys.join(', ')}) VALUES (${placeholders.join(', ')})`;
  db.run(sql, values);
}

// sql.js-specific ActiveRecord implementation
export class ActiveRecord extends ActiveRecordBase {
  // --- Class Methods (finders) ---

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
    const result = db.exec(`SELECT * FROM ${this.tableName} ORDER BY ${column} ${direction}`);
    if (!result.length) return [];
    return this._resultToModels(result[0]);
  }

  // --- Instance Methods ---

  async destroy() {
    if (!this._persisted) return false;
    db.run(`DELETE FROM ${this.constructor.tableName} WHERE id = ?`, [this.id]);
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

  _insert() {
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
