// ActiveRecord adapter for PGLite (PostgreSQL in WebAssembly)
// This file is copied to dist/lib/active_record.mjs at build time
// PGLite provides PostgreSQL compatibility in the browser with optional IndexedDB persistence

import { PostgresDialect, PG_TYPE_MAP } from './dialects/postgres.mjs';
import { attr_accessor, initTimePolyfill } from 'ruby2js-rails/adapters/active_record_base.mjs';

// Re-export shared utilities
export { attr_accessor };

// Configuration injected at build time
const DB_CONFIG = {};

let db = null;

// Initialize the database
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };

  // Dynamic import of PGLite
  const { PGlite } = await import('@electric-sql/pglite');

  // Determine storage backend:
  // - idb://dbname for IndexedDB persistence (survives page refresh)
  // - memory:// for ephemeral in-memory storage
  let dataDir;
  if (config.persist !== false && config.database) {
    dataDir = `idb://${config.database}`;
  } else if (config.dataDir) {
    dataDir = config.dataDir;
  } else {
    dataDir = 'memory://';
  }

  // Create PGLite instance
  db = await PGlite.create(dataDir, {
    // Optional: relaxed durability for better performance (skip fsync)
    relaxedDurability: config.relaxedDurability ?? false,
    // Optional: debug logging (1-5)
    debug: config.debug
  });

  console.log(`Connected to PGLite: ${dataDir}`);

  // Time polyfill for Ruby compatibility
  if (typeof window !== 'undefined') {
    initTimePolyfill(window);
  } else {
    initTimePolyfill(globalThis);
  }

  return db;
}

// Execute raw SQL (for schema creation, migrations) - legacy, prefer createTable/addIndex
export async function execSQL(sql) {
  // exec() supports multiple statements, good for migrations
  return await db.exec(sql);
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
  return db.exec(sql);
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.join(', ') : columns;

  const sql = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  return db.exec(sql);
}

export async function addColumn(tableName, columnName, columnType) {
  const sqlType = PG_TYPE_MAP[columnType] || 'TEXT';
  const sql = `ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${sqlType}`;
  return db.exec(sql);
}

export async function removeColumn(tableName, columnName) {
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${columnName}`;
  return db.exec(sql);
}

export async function dropTable(tableName) {
  const sql = `DROP TABLE IF EXISTS ${tableName}`;
  return db.exec(sql);
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

// Get the raw database instance
export function getDatabase() {
  return db;
}

// Query interface for rails_base.js migration system
export async function query(sql, params = []) {
  const result = await db.query(sql, params);
  return result.rows;
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  const result = await db.query(sql, params);
  return { changes: result.affectedRows || 0 };
}

// Insert a row - PostgreSQL uses $1, $2, ... placeholders
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map((_, i) => `$${i + 1}`);
  const sql = `INSERT INTO ${tableName} (${keys.join(', ')}) VALUES (${placeholders.join(', ')})`;
  await db.query(sql, values);
}

// Close the database connection
export async function closeDatabase() {
  if (db) {
    await db.close();
    db = null;
  }
}

// PGLite-specific ActiveRecord implementation
// Extends PostgresDialect which provides all finder/mutation methods
// Only needs to implement driver-specific execution
export class ActiveRecord extends PostgresDialect {
  // Execute SQL and return raw result
  static async _execute(sql, params = []) {
    return await db.query(sql, params);
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
