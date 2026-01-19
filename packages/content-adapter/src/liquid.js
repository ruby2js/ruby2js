/**
 * Liquid Template Compiler
 *
 * Transforms Liquid templates with Ruby expressions to Liquid templates with JavaScript expressions.
 *
 * Transforms:
 * - `{{ ruby_expr }}` interpolations → `{{ jsExpr }}`
 * - `{% for item in ruby_collection %}` → `{% for item in jsCollection %}`
 * - `{% if ruby_condition %}` → `{% if jsCondition %}`
 * - `{% unless ruby_condition %}` → `{% unless jsCondition %}`
 * - `{% elsif ruby_condition %}` → `{% elsif jsCondition %}`
 * - `{% case ruby_expr %}` → `{% case jsExpr %}`
 * - `{% when ruby_value %}` → `{% when jsValue %}`
 * - `{% assign var = ruby_expr %}` → `{% assign var = jsExpr %}`
 *
 * Usage:
 *   import { compileLiquid } from '@ruby2js/content-adapter/liquid';
 *
 *   const result = await compileLiquid(template, { eslevel: 2022 });
 *   result.template  // => compiled Liquid template
 *   result.errors    // => any compilation errors
 */

import { convert, initPrism } from 'ruby2js';
import 'ruby2js/filters/functions.js';
import 'ruby2js/filters/camelCase.js';

let prismInitialized = false;

async function ensurePrism() {
  if (!prismInitialized) {
    await initPrism();
    prismInitialized = true;
  }
}

/**
 * Convert a Ruby expression to JavaScript using Ruby2JS.
 *
 * @param {string} rubyExpr - Ruby expression to convert
 * @param {Object} options - Conversion options
 * @returns {string} - JavaScript expression
 */
function convertExpression(rubyExpr, options = {}) {
  const { eslevel = 2022 } = options;

  // Wrap expression in array to avoid bare identifier issues
  // [expr] becomes [jsExpr] in JS
  const wrapped = `[${rubyExpr}]`;

  try {
    const result = convert(wrapped, {
      eslevel,
      filters: ['Functions', 'CamelCase']
    });

    let js = result.toString().trim();

    // Remove trailing semicolon
    if (js.endsWith(';')) {
      js = js.slice(0, -1).trim();
    }

    // Extract the expression from the array: [expr] -> expr
    if (js.startsWith('[') && js.endsWith(']')) {
      js = js.slice(1, -1).trim();
    }

    return js;
  } catch (error) {
    throw new Error(`Failed to convert expression "${rubyExpr}": ${error.message}`);
  }
}

/**
 * Process {{ expression }} interpolations.
 *
 * @param {string} template - Liquid template
 * @param {Object} options - Conversion options
 * @param {Array} errors - Error accumulator
 * @returns {string} - Template with converted interpolations
 */
function processInterpolations(template, options, errors) {
  // Match {{ ... }} but be careful with nested braces
  return template.replace(/\{\{\s*(.+?)\s*\}\}/gs, (match, rubyExpr) => {
    // Skip if it looks like it's already JavaScript (contains => or function)
    if (rubyExpr.includes('=>') || rubyExpr.includes('function')) {
      return match;
    }

    // Skip Liquid filters (expr | filter) - we only transform the expression part
    const parts = rubyExpr.split(/\s*\|\s*/);
    const mainExpr = parts[0];
    const filters = parts.slice(1);

    try {
      const jsExpr = convertExpression(mainExpr, options);

      if (filters.length > 0) {
        // Reassemble with filters
        return `{{ ${jsExpr} | ${filters.join(' | ')} }}`;
      }
      return `{{ ${jsExpr} }}`;
    } catch (error) {
      errors.push({
        type: 'interpolation',
        expression: rubyExpr,
        error: error.message
      });
      return match;
    }
  });
}

/**
 * Process {% for item in collection %} tags.
 *
 * @param {string} template - Liquid template
 * @param {Object} options - Conversion options
 * @param {Array} errors - Error accumulator
 * @returns {string} - Template with converted for loops
 */
function processForLoops(template, options, errors) {
  // Match {% for var in collection %} with optional limit/offset
  // Pattern: {% for item in items %} or {% for item in items limit:5 offset:2 %}
  return template.replace(
    /\{%\s*for\s+(\w+)\s+in\s+(.+?)\s*%\}/g,
    (match, varName, rest) => {
      // Split collection from optional parameters (limit, offset, reversed)
      const parts = rest.split(/\s+(?=limit:|offset:|reversed)/);
      const rubyCollection = parts[0].trim();
      const params = parts.slice(1).join(' ');

      try {
        const jsCollection = convertExpression(rubyCollection, options);
        const paramStr = params ? ` ${params}` : '';
        return `{% for ${varName} in ${jsCollection}${paramStr} %}`;
      } catch (error) {
        errors.push({
          type: 'for',
          expression: rubyCollection,
          error: error.message
        });
        return match;
      }
    }
  );
}

/**
 * Process {% if condition %}, {% elsif condition %}, {% unless condition %} tags.
 *
 * @param {string} template - Liquid template
 * @param {Object} options - Conversion options
 * @param {Array} errors - Error accumulator
 * @returns {string} - Template with converted conditionals
 */
function processConditionals(template, options, errors) {
  let result = template;

  // Process {% if condition %}
  result = result.replace(
    /\{%\s*if\s+(.+?)\s*%\}/g,
    (match, rubyCondition) => processConditionalTag('if', rubyCondition, match, options, errors)
  );

  // Process {% elsif condition %}
  result = result.replace(
    /\{%\s*elsif\s+(.+?)\s*%\}/g,
    (match, rubyCondition) => processConditionalTag('elsif', rubyCondition, match, options, errors)
  );

  // Process {% unless condition %}
  result = result.replace(
    /\{%\s*unless\s+(.+?)\s*%\}/g,
    (match, rubyCondition) => processConditionalTag('unless', rubyCondition, match, options, errors)
  );

  return result;
}

/**
 * Helper to process a conditional tag.
 */
function processConditionalTag(tag, rubyCondition, original, options, errors) {
  try {
    const jsCondition = convertExpression(rubyCondition, options);
    return `{% ${tag} ${jsCondition} %}`;
  } catch (error) {
    errors.push({
      type: tag,
      expression: rubyCondition,
      error: error.message
    });
    return original;
  }
}

/**
 * Process {% case expr %} and {% when value %} tags.
 *
 * @param {string} template - Liquid template
 * @param {Object} options - Conversion options
 * @param {Array} errors - Error accumulator
 * @returns {string} - Template with converted case statements
 */
function processCaseStatements(template, options, errors) {
  let result = template;

  // Process {% case expression %}
  result = result.replace(
    /\{%\s*case\s+(.+?)\s*%\}/g,
    (match, rubyExpr) => {
      try {
        const jsExpr = convertExpression(rubyExpr, options);
        return `{% case ${jsExpr} %}`;
      } catch (error) {
        errors.push({
          type: 'case',
          expression: rubyExpr,
          error: error.message
        });
        return match;
      }
    }
  );

  // Process {% when value %} - can have multiple comma-separated values
  result = result.replace(
    /\{%\s*when\s+(.+?)\s*%\}/g,
    (match, rubyValues) => {
      try {
        // Handle comma-separated values
        const values = rubyValues.split(/\s*,\s*/);
        const jsValues = values.map(v => convertExpression(v.trim(), options));
        return `{% when ${jsValues.join(', ')} %}`;
      } catch (error) {
        errors.push({
          type: 'when',
          expression: rubyValues,
          error: error.message
        });
        return match;
      }
    }
  );

  return result;
}

/**
 * Process {% assign var = expr %} and {% capture var %} tags.
 *
 * @param {string} template - Liquid template
 * @param {Object} options - Conversion options
 * @param {Array} errors - Error accumulator
 * @returns {string} - Template with converted assignments
 */
function processAssignments(template, options, errors) {
  // Process {% assign var = expression %}
  return template.replace(
    /\{%\s*assign\s+(\w+)\s*=\s*(.+?)\s*%\}/g,
    (match, varName, rubyExpr) => {
      try {
        const jsExpr = convertExpression(rubyExpr, options);
        return `{% assign ${varName} = ${jsExpr} %}`;
      } catch (error) {
        errors.push({
          type: 'assign',
          expression: rubyExpr,
          error: error.message
        });
        return match;
      }
    }
  );
}

/**
 * Compile a Liquid template with Ruby expressions to Liquid with JavaScript expressions.
 *
 * @param {string} template - Liquid template with Ruby expressions
 * @param {Object} options - Compilation options
 * @param {number} [options.eslevel=2022] - ECMAScript level for output
 * @returns {Promise<{template: string, errors: Array}>} - Compiled template and any errors
 */
export async function compileLiquid(template, options = {}) {
  await ensurePrism();

  const errors = [];
  let result = template;

  // Process in order: interpolations, for loops, conditionals, case, assignments
  result = processInterpolations(result, options, errors);
  result = processForLoops(result, options, errors);
  result = processConditionals(result, options, errors);
  result = processCaseStatements(result, options, errors);
  result = processAssignments(result, options, errors);

  return {
    template: result,
    errors
  };
}

/**
 * Synchronous version (requires Prism to be already initialized).
 */
export function compileLiquidSync(template, options = {}) {
  const errors = [];
  let result = template;

  result = processInterpolations(result, options, errors);
  result = processForLoops(result, options, errors);
  result = processConditionals(result, options, errors);
  result = processCaseStatements(result, options, errors);
  result = processAssignments(result, options, errors);

  return {
    template: result,
    errors
  };
}

export { convertExpression };
