// ActiveRecord adapter for PostgreSQL via Beam.callSync → Postgrex (Elixir)
// All SQL execution happens on the Elixir side; JS only builds queries.
// Used with the BEAM (QuickBEAM) target.

import { PostgresDialect, PG_TYPE_MAP } from './dialects/postgres.mjs';
import { attr_accessor, initTimePolyfill, quoteId } from 'juntos/adapters/active_record_base.mjs';
import { modelRegistry, CollectionProxy, Reference, HasOneReference } from 'juntos/adapters/active_record_sql.mjs';

// Re-export shared utilities
export { attr_accessor, modelRegistry, CollectionProxy, Reference, HasOneReference };

// Configuration injected at build time
const DB_CONFIG = {};

// Initialize the database connection (Elixir side)
export async function initDatabase(options = {}) {
  const config = { ...DB_CONFIG, ...options };
  Beam.callSync('__db_init', config);

  // Time polyfill for Ruby compatibility
  initTimePolyfill(globalThis);

  console.log(`Connected to PostgreSQL via Postgrex`);
}

// Execute raw SQL (for schema creation)
export async function execSQL(sql) {
  return Beam.callSync('__db_execute', sql, []);
}

// Abstract DDL interface - creates PostgreSQL tables from abstract schema
export async function createTable(tableName, columns, options = {}) {
  const columnDefs = columns.map(col => {
    let def;

    if (col.primaryKey && col.autoIncrement) {
      def = `${quoteId(col.name)} SERIAL PRIMARY KEY`;
    } else {
      const sqlType = getSqlType(col);
      def = `${quoteId(col.name)} ${sqlType}`;

      if (col.primaryKey) def += ' PRIMARY KEY';
      if (col.null === false) def += ' NOT NULL';
      if (col.default !== undefined) {
        def += ` DEFAULT ${formatDefaultValue(col.default, col.type)}`;
      }
    }

    return def;
  });

  if (options.foreignKeys) {
    for (const fk of options.foreignKeys) {
      columnDefs.push(
        `FOREIGN KEY (${quoteId(fk.column)}) REFERENCES ${fk.references}(${quoteId(fk.primaryKey)})`
      );
    }
  }

  const sql = `CREATE TABLE IF NOT EXISTS ${tableName} (${columnDefs.join(', ')})`;
  return Beam.callSync('__db_execute', sql, []);
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.map(c => quoteId(c)).join(', ') : quoteId(columns);

  const sql = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  return Beam.callSync('__db_execute', sql, []);
}

export async function addColumn(tableName, columnName, columnType) {
  const sqlType = PG_TYPE_MAP[columnType] || 'TEXT';
  const sql = `ALTER TABLE ${tableName} ADD COLUMN ${quoteId(columnName)} ${sqlType}`;
  return Beam.callSync('__db_execute', sql, []);
}

export async function removeColumn(tableName, columnName) {
  const sql = `ALTER TABLE ${tableName} DROP COLUMN ${quoteId(columnName)}`;
  return Beam.callSync('__db_execute', sql, []);
}

export async function dropTable(tableName) {
  const sql = `DROP TABLE IF EXISTS ${tableName}`;
  return Beam.callSync('__db_execute', sql, []);
}

function getSqlType(col) {
  let baseType = PG_TYPE_MAP[col.type] || 'TEXT';

  if (col.type === 'decimal' && (col.precision || col.scale)) {
    const precision = col.precision || 10;
    const scale = col.scale || 0;
    baseType = `DECIMAL(${precision}, ${scale})`;
  }

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

// Get the raw database connection (not applicable for bridge adapter)
export function getDatabase() {
  return null;
}

// Query interface for rails_base.js migration system
export async function query(sql, params = []) {
  return Beam.callSync('__db_query', sql, params);
}

// Execute interface for rails_base.js migration system
export async function execute(sql, params = []) {
  return Beam.callSync('__db_execute', sql, params);
}

// Insert a row - PostgreSQL uses $1, $2, ... placeholders
export async function insert(tableName, data) {
  const keys = Object.keys(data);
  const values = Object.values(data);
  const placeholders = keys.map((_, i) => `$${i + 1}`);
  const sql = `INSERT INTO ${tableName} (${keys.map(k => quoteId(k)).join(', ')}) VALUES (${placeholders.join(', ')})`;
  Beam.callSync('__db_execute', sql, values);
}

// Close the database connection
export async function closeDatabase() {
  Beam.callSync('__db_close');
}

// PostgreSQL ActiveRecord implementation via Beam bridge
export class ActiveRecord extends PostgresDialect {
  // Execute SQL and return raw result
  static async _execute(sql, params = []) {
    if (sql.trim().toUpperCase().startsWith('SELECT')) {
      const rows = Beam.callSync('__db_query', sql, params);
      return { rows, type: 'select' };
    } else {
      const result = Beam.callSync('__db_execute', sql, params);
      return { ...result, type: 'run' };
    }
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
