// ActiveRecord adapter for PostgreSQL (via node-postgres/pg)
// This file is copied to dist/lib/active_record.mjs at build time
// pg is the standard PostgreSQL client for Node.js

import pg from 'pg';
const { Pool } = pg;

import { PostgresDialect, PG_TYPE_MAP } from './dialects/postgres.mjs';
import { attr_accessor, initTimePolyfill } from 'juntos/adapters/active_record_base.mjs';
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
  initTimePolyfill(globalThis);

  return pool;
}

// Execute raw SQL (for schema creation) - legacy, prefer createTable/addIndex
export async function execSQL(sql) {
  const result = await pool.query(sql);
  return result;
}

// Abstract DDL interface - creates PostgreSQL tables from abstract schema
export async function createTable(tableName, columns, options = {}) {
  const columnDefs = columns.map(col => {
    let def;

    if (col.primaryKey && col.autoIncrement) {
      // PostgreSQL uses SERIAL for auto-incrementing primary keys
      def = `${col.name} SERIAL PRIMARY KEY`;
    } else {
      const sqlType = getSqlType(col);
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

export async function addColumn(tableName, columnName, columnType) {
  const sqlType = PG_TYPE_MAP[columnType] || 'TEXT';
  const sql = `ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${sqlType}`;
  return pool.query(sql);
}

export async function removeColumn(tableName, columnName) {
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${columnName}`;
  return pool.query(sql);
}

export async function dropTable(tableName) {
  const sql = `DROP TABLE IF EXISTS ${tableName}`;
  return pool.query(sql);
}

function getSqlType(col) {
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

// Query interface for rails_base.js migration system
export async function query(sql, params = []) {
  const result = await pool.query(sql, params);
  return result.rows;
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  const result = await pool.query(sql, params);
  return { changes: result.rowCount || 0 };
}

// Insert a row - PostgreSQL uses $1, $2, ... placeholders
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map((_, i) => `$${i + 1}`);
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

// PostgreSQL-specific ActiveRecord implementation
// Extends PostgresDialect which provides all finder/mutation methods
// Only needs to implement driver-specific execution
export class ActiveRecord extends PostgresDialect {
  // Execute SQL and return raw result
  static async _execute(sql, params = []) {
    return await pool.query(sql, params);
  }

  // Extract rows array from result
  static _getRows(result) {
    return result.rows || [];
  }

  // Get last insert ID from result (PostgreSQL uses RETURNING id)
  static _getLastInsertId(result) {
    return result.rows?.[0]?.id;
  }
}
