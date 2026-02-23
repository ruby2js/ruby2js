// ActiveRecord adapter for MySQL (via mysql2)
// This file is copied to dist/lib/active_record.mjs at build time
// mysql2 is the standard MySQL client for Node.js

import mysql from 'mysql2/promise';

import { MySQLDialect, MYSQL_TYPE_MAP } from './dialects/mysql.mjs';
import { attr_accessor, initTimePolyfill, quoteId } from 'juntos/adapters/active_record_base.mjs';
import { modelRegistry, CollectionProxy, Reference, HasOneReference } from 'juntos/adapters/active_record_sql.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry, CollectionProxy, Reference, HasOneReference };

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

// Abstract DDL interface - creates MySQL tables from abstract schema
export async function createTable(tableName, columns, options = {}) {
  const columnDefs = columns.map(col => {
    const sqlType = MySQLDialect.getSqlType(col);
    let def = `${quoteId(col.name)} ${sqlType}`;

    if (col.primaryKey) {
      def += ' PRIMARY KEY';
      if (col.autoIncrement) def += ' AUTO_INCREMENT';
    }
    if (col.null === false) def += ' NOT NULL';
    if (col.default !== undefined) {
      def += ` DEFAULT ${MySQLDialect.formatDefaultValue(col.default)}`;
    }

    return def;
  });

  // Add foreign key constraints
  if (options.foreignKeys) {
    for (const fk of options.foreignKeys) {
      columnDefs.push(
        `FOREIGN KEY (${quoteId(fk.column)}) REFERENCES ${fk.references}(${quoteId(fk.primaryKey)})`
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
  const columnList = Array.isArray(columns) ? columns.map(c => quoteId(c)).join(', ') : quoteId(columns);

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
  const sql = `ALTER TABLE ${tableName} ADD COLUMN ${quoteId(columnName)} ${sqlType}`;
  const [result] = await pool.query(sql);
  return result;
}

export async function removeColumn(tableName, columnName) {
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${quoteId(columnName)}`;
  const [result] = await pool.query(sql);
  return result;
}

export async function dropTable(tableName) {
  const sql = `DROP TABLE IF EXISTS ${tableName}`;
  const [result] = await pool.query(sql);
  return result;
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
  const sql = `INSERT INTO ${tableName} (${keys.map(k => quoteId(k)).join(', ')}) VALUES (${placeholders.join(', ')})`;
  await pool.query(sql, values);
}

// Close the connection pool (for graceful shutdown)
export async function closeDatabase() {
  if (pool) {
    await pool.end();
    pool = null;
  }
}

// mysql2-specific ActiveRecord implementation
// Extends MySQLDialect which provides all finder/mutation methods
// Only needs to implement driver-specific execution
export class ActiveRecord extends MySQLDialect {
  // Execute SQL and return raw result
  static async _execute(sql, params = []) {
    const [rows, fields] = await pool.query(sql, params);
    // For SELECT queries, rows is array; for mutations, rows is ResultSetHeader
    if (Array.isArray(rows)) {
      return { rows, type: 'select' };
    } else {
      return { info: rows, type: 'run' };
    }
  }

  // Extract rows array from result
  static _getRows(result) {
    return result.rows || [];
  }

  // Get last insert ID from result
  static _getLastInsertId(result) {
    return result.info?.insertId;
  }
}
