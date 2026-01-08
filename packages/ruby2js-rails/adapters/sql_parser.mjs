// Simple SQL condition parser for Dexie compatibility
//
// Parses basic SQL WHERE conditions and extracts column, operator, and values.
// Only supports single-column conditions that can be translated to Dexie's API.
//
// Supported patterns:
//   'column > ?'           -> { column, op: '>', values: [val] }
//   'column >= ?'          -> { column, op: '>=', values: [val] }
//   'column < ?'           -> { column, op: '<', values: [val] }
//   'column <= ?'          -> { column, op: '<=', values: [val] }
//   'column = ?'           -> { column, op: '=', values: [val] }
//   'column != ?'          -> { column, op: '!=', values: [val] }
//   'column <> ?'          -> { column, op: '!=', values: [val] }
//   'column BETWEEN ? AND ?' -> { column, op: 'between', values: [low, high] }

// Regex patterns for supported operators
const COMPARISON_PATTERN = /^(\w+)\s*(>=|<=|!=|<>|>|<|=)\s*\?$/i;
const BETWEEN_PATTERN = /^(\w+)\s+BETWEEN\s+\?\s+AND\s+\?$/i;

/**
 * Parse a raw SQL condition string into a structured format.
 *
 * @param {string} sql - The SQL condition string (e.g., 'age > ?')
 * @param {Array} values - The values to bind to placeholders
 * @returns {Object|null} - Parsed condition or null if unsupported
 *   { column: string, op: string, values: Array }
 */
export function parseCondition(sql, values = []) {
  const trimmed = sql.trim();

  // Try BETWEEN pattern first (has two placeholders)
  let match = trimmed.match(BETWEEN_PATTERN);
  if (match) {
    if (values.length < 2) {
      throw new Error(`BETWEEN requires 2 values, got ${values.length}`);
    }
    return {
      column: match[1],
      op: 'between',
      values: [values[0], values[1]]
    };
  }

  // Try comparison operators
  match = trimmed.match(COMPARISON_PATTERN);
  if (match) {
    if (values.length < 1) {
      throw new Error(`Comparison requires 1 value, got ${values.length}`);
    }
    let op = match[2];
    // Normalize <> to !=
    if (op === '<>') op = '!=';
    return {
      column: match[1],
      op,
      values: [values[0]]
    };
  }

  // Unsupported pattern
  return null;
}

/**
 * Check if a raw SQL condition can be parsed.
 *
 * @param {string} sql - The SQL condition string
 * @returns {boolean}
 */
export function canParse(sql) {
  const trimmed = sql.trim();
  return COMPARISON_PATTERN.test(trimmed) || BETWEEN_PATTERN.test(trimmed);
}

/**
 * Apply a parsed condition to a Dexie table.
 *
 * @param {Object} table - Dexie table instance
 * @param {Object} condition - Parsed condition from parseCondition()
 * @returns {Object} - Dexie Collection
 */
export function applyToDexie(table, condition) {
  const { column, op, values } = condition;

  switch (op) {
    case '>':
      return table.where(column).above(values[0]);
    case '>=':
      return table.where(column).aboveOrEqual(values[0]);
    case '<':
      return table.where(column).below(values[0]);
    case '<=':
      return table.where(column).belowOrEqual(values[0]);
    case '=':
      return table.where(column).equals(values[0]);
    case '!=':
      return table.where(column).notEqual(values[0]);
    case 'between':
      // Dexie's between is inclusive by default: [low, high]
      // Use { includeLower: true, includeUpper: true } for SQL BETWEEN semantics
      return table.where(column).between(values[0], values[1], true, true);
    default:
      throw new Error(`Unsupported operator: ${op}`);
  }
}

/**
 * Apply a parsed condition as a filter function.
 * Use this for secondary conditions after the first indexed query.
 *
 * @param {Object} condition - Parsed condition from parseCondition()
 * @returns {Function} - Filter function (record) => boolean
 */
export function toFilterFunction(condition) {
  const { column, op, values } = condition;

  switch (op) {
    case '>':
      return (record) => record[column] > values[0];
    case '>=':
      return (record) => record[column] >= values[0];
    case '<':
      return (record) => record[column] < values[0];
    case '<=':
      return (record) => record[column] <= values[0];
    case '=':
      return (record) => record[column] === values[0];
    case '!=':
      return (record) => record[column] !== values[0];
    case 'between':
      return (record) => record[column] >= values[0] && record[column] <= values[1];
    default:
      throw new Error(`Unsupported operator: ${op}`);
  }
}
