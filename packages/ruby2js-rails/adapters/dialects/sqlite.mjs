// SQLite Dialect for ActiveRecord SQL
//
// SQLite-specific settings:
// - Placeholders: ?
// - Booleans: 1/0 (INTEGER)
// - Auto-increment: AUTOINCREMENT keyword
// - Last insert ID: lastInsertRowid property
// - No RETURNING clause (uses lastInsertRowid instead)
//
// Used by: better-sqlite3, Turso, D1, sql.js

import { ActiveRecordSQL } from 'ruby2js-rails/adapters/active_record_sql.mjs';

// SQLite type mapping from abstract Rails types
export const SQLITE_TYPE_MAP = {
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

export class SQLiteDialect extends ActiveRecordSQL {
  // SQLite uses ? placeholders
  static get useNumberedParams() { return false; }

  // SQLite doesn't support RETURNING, uses lastInsertRowid
  static get returningId() { return false; }

  // Type map for DDL operations
  static get typeMap() { return SQLITE_TYPE_MAP; }

  // Format boolean for SQL (SQLite uses 1/0)
  static formatBoolean(val) {
    return val ? 1 : 0;
  }

  // Format value for binding (SQLite needs booleans as 0/1, objects as JSON)
  static _formatValue(val) {
    if (typeof val === 'boolean') return val ? 1 : 0;
    if (val instanceof Date) return val.toISOString();
    // Serialize objects/arrays to JSON (e.g., JSON columns)
    // Use a replacer to convert model instances to their IDs
    if (val !== null && typeof val === 'object') {
      return JSON.stringify(val, (key, v) => {
        if (v && typeof v === 'object' && v.constructor?.tableName && v.id) {
          return v.id;
        }
        return v;
      });
    }
    return val;
  }

  // Format default value for CREATE TABLE
  static formatDefaultValue(value) {
    if (value === null) return 'NULL';
    if (typeof value === 'string') return `'${value.replace(/'/g, "''")}'`;
    if (typeof value === 'boolean') return value ? '1' : '0';
    return String(value);
  }

  // Get SQL type for column definition
  static getSqlType(col) {
    let baseType = SQLITE_TYPE_MAP[col.type] || 'TEXT';
    // SQLite doesn't use precision/scale for most types
    return baseType;
  }
}
