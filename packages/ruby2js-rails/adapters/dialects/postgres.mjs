// PostgreSQL Dialect for ActiveRecord SQL
//
// PostgreSQL-specific settings:
// - Placeholders: $1, $2, $3...
// - Booleans: TRUE/FALSE
// - Auto-increment: SERIAL type
// - Last insert ID: RETURNING id clause
//
// Used by: pg (node-postgres), Neon, PGlite

import { ActiveRecordSQL } from 'ruby2js-rails/adapters/active_record_sql.mjs';

// PostgreSQL type mapping from abstract Rails types
export const PG_TYPE_MAP = {
  string: 'VARCHAR(255)',
  text: 'TEXT',
  integer: 'INTEGER',
  bigint: 'BIGINT',
  float: 'DOUBLE PRECISION',
  decimal: 'DECIMAL',
  boolean: 'BOOLEAN',
  date: 'DATE',
  datetime: 'TIMESTAMP',
  time: 'TIME',
  timestamp: 'TIMESTAMP',
  binary: 'BYTEA',
  json: 'JSON',
  jsonb: 'JSONB'
};

export class PostgresDialect extends ActiveRecordSQL {
  // PostgreSQL uses $1, $2 style placeholders
  static get useNumberedParams() { return true; }

  // PostgreSQL supports RETURNING clause
  static get returningId() { return true; }

  // Type map for DDL operations
  static get typeMap() { return PG_TYPE_MAP; }

  // Format boolean for SQL (PostgreSQL uses TRUE/FALSE)
  static formatBoolean(val) {
    return val ? 'TRUE' : 'FALSE';
  }

  // Format default value for CREATE TABLE
  static formatDefaultValue(value, type) {
    if (value === null) return 'NULL';
    if (typeof value === 'string') return `'${value.replace(/'/g, "''")}'`;
    if (typeof value === 'boolean') return value ? 'TRUE' : 'FALSE';
    return String(value);
  }

  // Get SQL type for column definition
  static getSqlType(col) {
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
}
