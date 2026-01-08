// MySQL Dialect for ActiveRecord SQL
//
// MySQL-specific settings:
// - Placeholders: ?
// - Booleans: 1/0 (TINYINT(1))
// - Auto-increment: AUTO_INCREMENT keyword
// - Last insert ID: insertId property
// - No RETURNING clause (uses insertId instead)
//
// Used by: mysql2, PlanetScale

import { ActiveRecordSQL } from 'ruby2js-rails/adapters/active_record_sql.mjs';

// MySQL type mapping from abstract Rails types
export const MYSQL_TYPE_MAP = {
  string: 'VARCHAR(255)',
  text: 'TEXT',
  integer: 'INT',
  bigint: 'BIGINT',
  float: 'DOUBLE',
  decimal: 'DECIMAL',
  boolean: 'TINYINT(1)',
  date: 'DATE',
  datetime: 'DATETIME',
  time: 'TIME',
  timestamp: 'TIMESTAMP',
  binary: 'BLOB',
  json: 'JSON',
  jsonb: 'JSON'
};

export class MySQLDialect extends ActiveRecordSQL {
  // MySQL uses ? placeholders (like SQLite)
  static get useNumberedParams() { return false; }

  // MySQL doesn't support RETURNING, uses insertId
  static get returningId() { return false; }

  // Type map for DDL operations
  static get typeMap() { return MYSQL_TYPE_MAP; }

  // Format value for binding (MySQL needs booleans as 0/1)
  static _formatValue(val) {
    if (typeof val === 'boolean') return val ? 1 : 0;
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
    let baseType = MYSQL_TYPE_MAP[col.type] || 'TEXT';

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
