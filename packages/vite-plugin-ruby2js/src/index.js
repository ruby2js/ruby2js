/**
 * vite-plugin-ruby2js
 *
 * Transform Ruby files to JavaScript using the Ruby2JS selfhost transpiler.
 *
 * Usage:
 *   import ruby2js from 'vite-plugin-ruby2js';
 *
 *   export default defineConfig({
 *     plugins: [ruby2js()]
 *   });
 */

import { convert, initPrism } from 'ruby2js';

// Import commonly used filters so they're registered
// Filter names are PascalCase (e.g., 'Functions', 'ESM', 'Return')
import 'ruby2js/filters/functions.js';
import 'ruby2js/filters/esm.js';
import 'ruby2js/filters/cjs.js';
import 'ruby2js/filters/camelCase.js';
import 'ruby2js/filters/return.js';

// Initialize Prism lazily
let prismInitialized = false;
async function ensurePrism() {
  if (!prismInitialized) {
    await initPrism();
    prismInitialized = true;
  }
}

/**
 * @typedef {Object} Ruby2JSOptions
 * @property {string[]} [filters] - Filters to apply (default: ['functions', 'esm', 'return'])
 * @property {number} [eslevel] - ES level to target (default: 2022)
 * @property {string[]} [include] - Glob patterns to include
 * @property {string[]} [exclude] - Glob patterns to exclude
 */

/**
 * Create a Vite plugin that transforms Ruby files to JavaScript.
 *
 * @param {Ruby2JSOptions} options
 * @returns {import('vite').Plugin}
 */
// Map lowercase filter names to PascalCase
const FILTER_MAP = {
  'functions': 'Functions',
  'esm': 'ESM',
  'cjs': 'CJS',
  'return': 'Return',
  'camelcase': 'CamelCase',
  'camelCase': 'CamelCase',
  'stimulus': 'Stimulus',
  'erb': 'Erb',
  'phlex': 'Phlex',
  'react': 'React',
  'jsx': 'JSX',
  'vue': 'Vue',
  'astro': 'Astro',
  'lit': 'Lit'
};

function normalizeFilters(filters) {
  return filters.map(f => FILTER_MAP[f] || f);
}

export default function ruby2js(options = {}) {
  const {
    filters = ['Functions', 'ESM', 'Return'],
    eslevel = 2022,
    include = ['**/*.rb'],
    exclude = [],
    ...ruby2jsOptions
  } = options;

  // Normalize filter names to PascalCase
  const normalizedFilters = normalizeFilters(filters);

  return {
    name: 'vite-plugin-ruby2js',

    async transform(code, id) {
      // Only process .rb files
      if (!id.endsWith('.rb')) return null;

      // Check exclude patterns
      for (const pattern of exclude) {
        if (id.includes(pattern)) return null;
      }

      // Ensure Prism is initialized
      await ensurePrism();

      try {
        const result = convert(code, {
          filters: normalizedFilters,
          eslevel,
          file: id,
          ...ruby2jsOptions
        });

        const js = result.toString();
        const map = result.sourcemap;

        // Ensure source map has correct source reference
        if (map) {
          map.sources = [id];
          map.sourcesContent = [code];
        }

        return {
          code: js,
          map
        };
      } catch (error) {
        // Enhance error with file information
        const enhancedError = new Error(
          `Ruby2JS transform error in ${id}: ${error.message}`
        );
        enhancedError.id = id;
        enhancedError.plugin = 'vite-plugin-ruby2js';

        // Try to extract line/column from error message
        const lineMatch = error.message?.match(/line (\d+)/i);
        if (lineMatch) {
          enhancedError.loc = {
            file: id,
            line: parseInt(lineMatch[1], 10),
            column: 0
          };
        }

        throw enhancedError;
      }
    }
  };
}

// Named export for convenience
export { ruby2js };
