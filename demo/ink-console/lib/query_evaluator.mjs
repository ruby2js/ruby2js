// Query Evaluator - Transpiles and executes Ruby-like queries
//
// Uses Ruby2JS self-hosting to transpile Ruby syntax to JavaScript,
// then executes against the loaded models.

import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

// Ruby2JS will be loaded dynamically
let ruby2js = null;

/**
 * Initialize the query evaluator with Ruby2JS.
 * Must be called before evaluateQuery.
 */
export async function initQueryEvaluator() {
  if (ruby2js) return;

  try {
    // Try to load Ruby2JS from the selfhost bundle
    const selfhostPath = join(__dirname, '../../../selfhost/dist/ruby2js.mjs');
    ruby2js = await import(selfhostPath);
  } catch (e) {
    // Fall back to a simple pass-through for testing
    console.warn('Ruby2JS selfhost not available, using passthrough mode');
    ruby2js = {
      convert: (source) => ({ to_s: () => source })
    };
  }
}

/**
 * Evaluate a Ruby-like query string against the provided models.
 *
 * @param {string} rubyQuery - The Ruby query (e.g., "Post.all" or "Post.where(published: true)")
 * @param {Object} models - Object mapping model names to model classes
 * @returns {Promise<any>} - The query result
 *
 * @example
 *   const result = await evaluateQuery("Post.where(published: true).limit(5)", { Post });
 */
export async function evaluateQuery(rubyQuery, models = {}) {
  if (!ruby2js) {
    await initQueryEvaluator();
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

  try {
    // Transpile Ruby to JavaScript
    const result = ruby2js.convert(rubyQuery, {
      filters: ['functions'],
      autoreturn: true
    });
    const jsCode = result.to_s ? result.to_s() : result.toString();

    // Create a function with models in scope
    const modelNames = Object.keys(models);
    const modelValues = Object.values(models);

    // Wrap in async IIFE to handle await
    const wrappedCode = `return (async () => { return ${jsCode}; })()`;

    const fn = new Function(...modelNames, wrappedCode);
    const queryResult = await fn(...modelValues);

    return queryResult;
  } catch (error) {
    throw new Error(`Query error: ${error.message}`);
  }
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
    return { type: 'command', data: result.__command };
  }

  if (Array.isArray(result)) {
    if (result.length === 0) {
      return { type: 'empty', data: [] };
    }

    // Check if it's an array of model instances
    if (result[0] && result[0].attributes) {
      return {
        type: 'table',
        data: result.map(r => r.attributes),
        count: result.length
      };
    }

    return { type: 'array', data: result };
  }

  // Single model instance
  if (result.attributes) {
    return {
      type: 'record',
      data: result.attributes,
      model: result.constructor.name
    };
  }

  // Primitive or other object
  return { type: 'value', data: result };
}

export default {
  initQueryEvaluator,
  evaluateQuery,
  formatResult
};
