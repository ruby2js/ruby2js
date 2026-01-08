// ActiveRecord adapter for Neon (Serverless Postgres)
// This file is copied to dist/lib/active_record.mjs at build time
// Neon uses HTTP/WebSocket, works in browser, Node.js, and edge runtimes

import { neon } from '@neondatabase/serverless';

import { PostgresDialect, PG_TYPE_MAP } from './dialects/postgres.mjs';
import { attr_accessor, initTimePolyfill } from 'ruby2js-rails/adapters/active_record_base.mjs';
import { modelRegistry } from 'ruby2js-rails/adapters/active_record_sql.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry };

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

  const ddl = `CREATE TABLE IF NOT EXISTS ${tableName} (${columnDefs.join(', ')})`;
  // Pass empty array as params - neon requires this for non-parameterized queries
  return sql(ddl, []);
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.join(', ') : columns;

  const ddl = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  return sql(ddl, []);
}

export async function addColumn(tableName, columnName, columnType) {
  const sqlType = PG_TYPE_MAP[columnType] || 'TEXT';
  const ddl = `ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${sqlType}`;
  return sql(ddl, []);
}

export async function removeColumn(tableName, columnName) {
  const ddl = `ALTER TABLE ${tableName} DROP COLUMN ${columnName}`;
  return sql(ddl, []);
}

export async function dropTable(tableName) {
  const ddl = `DROP TABLE IF EXISTS ${tableName}`;
  return sql(ddl, []);
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

// Get the raw database connection
export function getDatabase() {
  return sql;
}

// Query interface for rails_base.js migration system
export async function query(sqlString, params = []) {
  const rows = await sql(sqlString, params);
  return rows;
}

// Execute interface for rails_base.js migration system
export async function execute(sqlString, params = []) {
  await sql(sqlString, params);
  return { changes: 0 }; // Neon doesn't return rowCount easily
}

// Insert a row - adapter handles SQL dialect
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map((_, i) => `$${i + 1}`);
  const sqlString = `INSERT INTO ${tableName} (${keys.join(', ')}) VALUES (${placeholders.join(', ')})`;
  await sql(sqlString, values);
}

// Close the connection (no-op for HTTP-based Neon)
export async function closeDatabase() {
  sql = null;
}

// Neon-specific ActiveRecord implementation
// Extends PostgresDialect which provides all finder/mutation methods
// Only needs to implement driver-specific execution
export class ActiveRecord extends PostgresDialect {
  // Execute SQL and return raw result
  // Neon's sql() function returns rows directly for queries
  static async _execute(query, params = []) {
    const rows = await sql(query, params);
    // Wrap in result object to match expected format
    return { rows };
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
