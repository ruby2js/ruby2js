// ActiveRecord adapter for PlanetScale (Serverless MySQL)
// This file is copied to dist/lib/active_record.mjs at build time
// PlanetScale uses HTTP, works in browser, Node.js, and edge runtimes

import { connect } from '@planetscale/database';

import { MySQLDialect, MYSQL_TYPE_MAP } from './dialects/mysql.mjs';
import { attr_accessor, initTimePolyfill, quoteId } from 'juntos/adapters/active_record_base.mjs';
import { modelRegistry, CollectionProxy, Reference, HasOneReference } from 'juntos/adapters/active_record_sql.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry, CollectionProxy, Reference, HasOneReference };

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

  // Note: PlanetScale doesn't support foreign key constraints by default
  // (uses Vitess which requires careful FK handling)

  const sql = `CREATE TABLE IF NOT EXISTS ${tableName} (${columnDefs.join(', ')}) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`;
  return await connection.execute(sql);
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.map(c => quoteId(c)).join(', ') : quoteId(columns);

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
  const sql = `ALTER TABLE ${tableName} ADD COLUMN ${quoteId(columnName)} ${sqlType}`;
  return await connection.execute(sql);
}

export async function removeColumn(tableName, columnName) {
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${quoteId(columnName)}`;
  return await connection.execute(sql);
}

export async function dropTable(tableName) {
  const sql = `DROP TABLE IF EXISTS ${tableName}`;
  return await connection.execute(sql);
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
  const sql = `INSERT INTO ${tableName} (${keys.map(k => quoteId(k)).join(', ')}) VALUES (${placeholders.join(', ')})`;
  await connection.execute(sql, values);
}

// Close the connection (no-op for HTTP-based PlanetScale)
export async function closeDatabase() {
  connection = null;
}

// PlanetScale-specific ActiveRecord implementation
// Extends MySQLDialect which provides all finder/mutation methods
// Only needs to implement driver-specific execution
export class ActiveRecord extends MySQLDialect {
  // Execute SQL and return raw result
  static async _execute(sql, params = []) {
    const result = await connection.execute(sql, params);
    // PlanetScale returns { rows, insertId, rowsAffected }
    if (sql.trim().toUpperCase().startsWith('SELECT')) {
      return { rows: result.rows, type: 'select' };
    } else {
      return { info: result, type: 'run' };
    }
  }

  // Extract rows array from result
  static _getRows(result) {
    return result.rows || [];
  }

  // Get last insert ID from result
  static _getLastInsertId(result) {
    return Number(result.info?.insertId);
  }
}
