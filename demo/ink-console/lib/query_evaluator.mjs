// Query Evaluator - Transpiles Ruby AR queries to Knex.js and executes them
//
// Uses Ruby2JS self-hosting to transpile Ruby syntax to Knex.js queries,
// then executes against the database via Knex.

import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

// Ruby2JS will be loaded dynamically
let ruby2js = null;

// Knex instance
let knexInstance = null;

/**
 * Initialize Knex with the provided configuration.
 *
 * @param {Object} config - Knex configuration
 */
export async function initKnex(config = {}) {
  if (knexInstance) return knexInstance;

  const Knex = (await import('knex')).default;

  // Default to SQLite
  const knexConfig = {
    client: config.client || 'better-sqlite3',
    connection: config.connection || {
      filename: config.database || './db/development.sqlite3'
    },
    useNullAsDefault: true,
    ...config
  };

  knexInstance = Knex(knexConfig);
  return knexInstance;
}

/**
 * Get the Knex instance.
 */
export function getKnex() {
  return knexInstance;
}

/**
 * Initialize the query evaluator with Ruby2JS.
 * Must be called before evaluateQuery.
 */
export async function initQueryEvaluator() {
  if (ruby2js) return;

  try {
    // Try to load Ruby2JS from the selfhost bundle
    const selfhostPath = join(__dirname, '../../selfhost/ruby2js.js');
    ruby2js = await import(selfhostPath);
    // Initialize Prism WASM parser
    if (ruby2js.initPrism) {
      await ruby2js.initPrism();
    }
    // Load the Functions filter for Ruby method mappings
    await import('../../selfhost/filters/functions.js');
    // Load our Console filter for AR → Knex translation
    await import('./console_filter.mjs');
  } catch (e) {
    // Fall back to a simple pass-through for testing
    console.warn('Ruby2JS selfhost not available:', e.message);
    console.warn('Using passthrough mode');
    ruby2js = {
      convert: (source) => ({ toString: () => source })
    };
  }
}

/**
 * Evaluate a Ruby-like query string.
 *
 * @param {string} rubyQuery - The Ruby query (e.g., "Post.all" or "Post.where(published: true)")
 * @returns {Promise<any>} - The query result
 *
 * @example
 *   const result = await evaluateQuery("Post.where(published: true).limit(5)");
 */
export async function evaluateQuery(rubyQuery) {
  if (!ruby2js) {
    await initQueryEvaluator();
  }

  if (!knexInstance) {
    throw new Error('Knex not initialized. Call initKnex() first.');
  }

  // Handle empty queries
  if (!rubyQuery || !rubyQuery.trim()) {
    return null;
  }

  // Handle special commands
  const trimmed = rubyQuery.trim().toLowerCase();
  if (trimmed === 'exit' || trimmed === 'quit') {
    return { __command: 'exit' };
  }
  if (trimmed === 'help') {
    return { __command: 'help' };
  }
  if (trimmed === 'clear') {
    return { __command: 'clear' };
  }
  if (trimmed === 'tables' || trimmed === '.tables') {
    return { __command: 'tables' };
  }
  if (trimmed === 'schema' || trimmed === '.schema') {
    return { __command: 'schema' };
  }
  // .schema tablename or schema tablename
  const schemaMatch = trimmed.match(/^\.?schema\s+(\w+)$/);
  if (schemaMatch) {
    return { __command: 'schema_table', table: schemaMatch[1] };
  }

  try {
    // Transpile Ruby to JavaScript with Console and Functions filters
    const result = ruby2js.convert(rubyQuery, {
      eslevel: 2022,
      filters: ['Console', 'Functions']
    });
    // The converter object has toString() method
    const jsCode = String(result);

    // Debug: show transpiled code
    if (process.env.DEBUG) {
      console.log('Transpiled:', jsCode);
    }

    // Wrap in async IIFE to handle await
    const wrappedCode = `return (async () => { return ${jsCode}; })()`;

    // Create a function with knex in scope
    const fn = new Function('knex', wrappedCode);
    const queryResult = await fn(knexInstance);

    return queryResult;
  } catch (error) {
    throw new Error(`Query error: ${error.message}`);
  }
}

/**
 * Get list of tables in the database.
 */
export async function getTables() {
  if (!knexInstance) return [];

  // SQLite-specific query
  const result = await knexInstance.raw(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'knex_%' ORDER BY name"
  );

  return result.map(row => row.name);
}

/**
 * Get column information for a specific table.
 */
export async function getTableColumns(tableName) {
  if (!knexInstance) return [];

  // SQLite-specific: PRAGMA table_info
  const result = await knexInstance.raw(`PRAGMA table_info(${tableName})`);

  return result.map(col => ({
    name: col.name,
    type: col.type,
    nullable: col.notnull === 0,
    default: col.dflt_value,
    primaryKey: col.pk === 1
  }));
}

/**
 * Get full schema information for all tables.
 */
export async function getSchema() {
  const tables = await getTables();
  const schema = {};

  for (const tableName of tables) {
    schema[tableName] = await getTableColumns(tableName);
  }

  return schema;
}

/**
 * Get foreign key information for a table.
 */
export async function getForeignKeys(tableName) {
  if (!knexInstance) return [];

  const result = await knexInstance.raw(`PRAGMA foreign_key_list(${tableName})`);

  return result.map(fk => ({
    column: fk.from,
    referencesTable: fk.table,
    referencesColumn: fk.to
  }));
}

/**
 * Get index information for a table.
 */
export async function getIndexes(tableName) {
  if (!knexInstance) return [];

  const result = await knexInstance.raw(`PRAGMA index_list(${tableName})`);

  return result.map(idx => ({
    name: idx.name,
    unique: idx.unique === 1
  }));
}

/**
 * Format a query result for display.
 *
 * @param {any} result - The query result
 * @returns {Object} - Formatted result with type and data
 */
export function formatResult(result) {
  if (result === null || result === undefined) {
    return { type: 'null', data: null };
  }

  if (result.__command) {
    // Pass through additional properties like 'table' for schema_table command
    return { type: 'command', data: result.__command, ...result };
  }

  // Handle Knex count result: [{ 'count(* as count)': 5 }] or similar
  if (Array.isArray(result) && result.length === 1) {
    const first = result[0];
    const keys = Object.keys(first);
    if (keys.length === 1 && keys[0].includes('count')) {
      return { type: 'value', data: first[keys[0]] };
    }
  }

  if (Array.isArray(result)) {
    if (result.length === 0) {
      return { type: 'empty', data: [] };
    }

    // Array of row objects
    return {
      type: 'table',
      data: result,
      count: result.length
    };
  }

  // Single row object
  if (typeof result === 'object') {
    return {
      type: 'record',
      data: result
    };
  }

  // Primitive value
  return { type: 'value', data: result };
}

/**
 * Close the Knex connection.
 */
export async function closeKnex() {
  if (knexInstance) {
    await knexInstance.destroy();
    knexInstance = null;
  }
}

export default {
  initKnex,
  getKnex,
  initQueryEvaluator,
  evaluateQuery,
  getTables,
  getTableColumns,
  getSchema,
  getForeignKeys,
  getIndexes,
  formatResult,
  closeKnex
};
