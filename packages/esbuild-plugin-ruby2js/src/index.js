/**
 * esbuild-plugin-ruby2js
 *
 * Transform Ruby files to JavaScript using the Ruby2JS selfhost transpiler.
 *
 * Usage:
 *   import ruby2js from 'esbuild-plugin-ruby2js';
 *
 *   esbuild.build({
 *     entryPoints: ['src/index.rb'],
 *     plugins: [ruby2js()],
 *     bundle: true,
 *     outfile: 'dist/index.js'
 *   });
 */

import fs from 'node:fs';
import path from 'node:path';
import { convert, initPrism } from 'ruby2js';

// Import commonly used filters so they're registered
import 'ruby2js/filters/functions.js';
import 'ruby2js/filters/esm.js';
import 'ruby2js/filters/cjs.js';
import 'ruby2js/filters/camelCase.js';
import 'ruby2js/filters/return.js';

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

// Initialize Prism lazily
let prismReady = false;
async function ensurePrism() {
  if (!prismReady) {
    await initPrism();
    prismReady = true;
  }
}

/**
 * @typedef {Object} Ruby2JSOptions
 * @property {string[]} [filters] - Filters to apply (default: ['Functions', 'ESM', 'Return'])
 * @property {number} [eslevel] - ES level to target (default: 2022)
 * @property {string[]} [exclude] - Glob patterns to exclude
 */

/**
 * Create an esbuild plugin that transforms Ruby files to JavaScript.
 *
 * @param {Ruby2JSOptions} options
 * @returns {import('esbuild').Plugin}
 */
export default function ruby2js(options = {}) {
  const {
    filters = ['Functions', 'ESM', 'Return'],
    eslevel = 2022,
    exclude = [],
    ...ruby2jsOptions
  } = options;

  // Normalize filter names to PascalCase
  const normalizedFilters = normalizeFilters(filters);

  return {
    name: 'ruby2js',

    setup(build) {
      // Transform .rb files
      build.onLoad({ filter: /\.rb$/ }, async (args) => {
        // Check exclude patterns
        for (const pattern of exclude) {
          if (args.path.includes(pattern)) {
            return null;
          }
        }

        await ensurePrism();

        let source;
        try {
          source = await fs.promises.readFile(args.path, 'utf8');
        } catch (err) {
          return {
            errors: [{
              text: `Failed to read file: ${err.message}`,
              location: { file: args.path }
            }]
          };
        }

        try {
          const result = convert(source, {
            filters: normalizedFilters,
            eslevel,
            file: args.path,
            ...ruby2jsOptions
          });

          return {
            contents: result.toString(),
            loader: 'js',
            resolveDir: path.dirname(args.path)
          };
        } catch (error) {
          // Extract line/column from error if available
          const lineMatch = error.message?.match(/line (\d+)/i);
          const line = lineMatch ? parseInt(lineMatch[1], 10) : 1;

          return {
            errors: [{
              text: error.message,
              location: {
                file: args.path,
                line,
                column: 0
              }
            }]
          };
        }
      });
    }
  };
}

// Named export for convenience
export { ruby2js };
