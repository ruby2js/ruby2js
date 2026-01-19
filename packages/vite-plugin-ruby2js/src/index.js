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
 *
 * For SFC (Single File Component) support with __END__ templates:
 *   export default defineConfig({
 *     plugins: [ruby2js({ sfc: true })]
 *   });
 *
 * This enables automatic transformation of:
 *   - .vue.rb files (Ruby script + Vue template)
 *   - .svelte.rb files (Ruby script + Svelte template)
 *   - .astro.rb files (Ruby script + Astro template)
 *   - .jsx.rb files (Ruby with inline JSX → JSX output)
 *   - .erb.rb files (Ruby with ERB-style __END__ template → JSX output)
 */

import { convert, initPrism } from 'ruby2js';

// Import commonly used filters so they're registered
// Filter names are PascalCase (e.g., 'Functions', 'ESM', 'Return')
import 'ruby2js/filters/functions.js';
import 'ruby2js/filters/esm.js';
import 'ruby2js/filters/cjs.js';
import 'ruby2js/filters/camelCase.js';
import 'ruby2js/filters/return.js';

// Import React/JSX filters for .jsx.rb support
import 'ruby2js/filters/react.js';
import 'ruby2js/filters/jsx.js';

// Import SFC component transformers (lazy loaded when needed)
let VueComponentTransformer = null;
let SvelteComponentTransformer = null;
let AstroComponentTransformer = null;
let ErbPnodeTransformer = null;

async function getVueTransformer() {
  if (!VueComponentTransformer) {
    const mod = await import('ruby2js/vue');
    VueComponentTransformer = mod.VueComponentTransformer;
  }
  return VueComponentTransformer;
}

async function getSvelteTransformer() {
  if (!SvelteComponentTransformer) {
    const mod = await import('ruby2js/svelte');
    SvelteComponentTransformer = mod.SvelteComponentTransformer;
  }
  return SvelteComponentTransformer;
}

async function getAstroTransformer() {
  if (!AstroComponentTransformer) {
    const mod = await import('ruby2js/astro');
    AstroComponentTransformer = mod.AstroComponentTransformer;
  }
  return AstroComponentTransformer;
}

async function getErbTransformer() {
  if (!ErbPnodeTransformer) {
    const mod = await import('ruby2js/erb');
    ErbPnodeTransformer = mod.ErbPnodeTransformer;
  }
  return ErbPnodeTransformer;
}

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
    sfc = false,
    ...ruby2jsOptions
  } = options;

  // Normalize filter names to PascalCase
  const normalizedFilters = normalizeFilters(filters);

  return {
    name: 'vite-plugin-ruby2js',

    async transform(code, id) {
      // Only process .rb files
      if (!id.endsWith('.rb')) return null;

      // Check exclude patterns (supports glob patterns like **/*.jsx.rb)
      for (const pattern of exclude) {
        // Handle glob patterns
        if (pattern.includes('*')) {
          // Convert glob to regex: ** -> .*, * -> [^/]*, . -> \.
          const regexStr = pattern
            .replace(/\./g, '\\.')
            .replace(/\*\*/g, '.*')
            .replace(/\*/g, '[^/]*');
          if (new RegExp(regexStr + '$').test(id)) return null;
        } else {
          // Simple substring match
          if (id.includes(pattern)) return null;
        }
      }

      // Ensure Prism is initialized
      await ensurePrism();

      // Handle SFC files (.vue.rb, .svelte.rb, .astro.rb)
      if (sfc || id.endsWith('.vue.rb') || id.endsWith('.svelte.rb') || id.endsWith('.astro.rb')) {
        return await this.transformSFC(code, id, eslevel, ruby2jsOptions);
      }

      // Handle .jsx.rb files - Ruby with inline JSX → JSX output
      // Uses React + JSX filters to output actual JSX syntax
      if (id.endsWith('.jsx.rb')) {
        return await this.transformJSX(code, id, eslevel, ruby2jsOptions);
      }

      // Handle .erb.rb files - Ruby with ERB-style __END__ template → JSX output
      // Uses ErbPnodeTransformer to convert ERB templates to JSX
      if (id.endsWith('.erb.rb')) {
        return await this.transformERB(code, id, eslevel, ruby2jsOptions);
      }

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
    },

    async transformSFC(code, id, eslevel, ruby2jsOptions) {
      try {
        let Transformer;
        let framework;

        if (id.endsWith('.vue.rb')) {
          Transformer = await getVueTransformer();
          framework = 'Vue';
        } else if (id.endsWith('.svelte.rb')) {
          Transformer = await getSvelteTransformer();
          framework = 'Svelte';
        } else if (id.endsWith('.astro.rb')) {
          Transformer = await getAstroTransformer();
          framework = 'Astro';
        } else {
          return null;
        }

        const result = Transformer.transform(code, {
          eslevel,
          ...ruby2jsOptions
        });

        if (result.errors && result.errors.length > 0) {
          const errorMsg = result.errors.map(e =>
            typeof e === 'string' ? e : JSON.stringify(e)
          ).join(', ');
          throw new Error(`${framework} transform errors: ${errorMsg}`);
        }

        return {
          code: result.component,
          map: null
        };
      } catch (error) {
        const enhancedError = new Error(
          `Ruby2JS SFC transform error in ${id}: ${error.message}`
        );
        enhancedError.id = id;
        enhancedError.plugin = 'vite-plugin-ruby2js';
        throw enhancedError;
      }
    },

    // Transform .erb.rb files - Ruby with ERB-style __END__ template to JSX output
    // Uses ErbPnodeTransformer to convert ERB templates to Preact/React JSX
    async transformERB(code, id, eslevel, ruby2jsOptions) {
      try {
        const Transformer = await getErbTransformer();

        const result = Transformer.transform(code, {
          eslevel,
          react: ruby2jsOptions.react || 'Preact',
          ...ruby2jsOptions
        });

        if (result.errors && result.errors.length > 0) {
          const errorMsg = result.errors.map(e =>
            typeof e === 'string' ? e : JSON.stringify(e)
          ).join(', ');
          throw new Error(`ERB transform errors: ${errorMsg}`);
        }

        return {
          code: result.component,
          map: null
        };
      } catch (error) {
        const enhancedError = new Error(
          `Ruby2JS ERB transform error in ${id}: ${error.message}`
        );
        enhancedError.id = id;
        enhancedError.plugin = 'vite-plugin-ruby2js';
        throw enhancedError;
      }
    },

    // Transform .jsx.rb files - Ruby with inline JSX to JSX output
    // Uses React + JSX filters to produce actual JSX syntax that Vite can process
    async transformJSX(code, id, eslevel, ruby2jsOptions) {
      try {
        // Use React + JSX filters for JSX output
        // JSX filter causes React filter to output xnode AST which serializes to JSX syntax
        const jsxFilters = ['React', 'JSX', 'Functions', 'ESM', 'CamelCase'];

        const result = convert(code, {
          filters: jsxFilters,
          eslevel,
          file: id,
          ...ruby2jsOptions
        });

        const jsx = result.toString();
        const map = result.sourcemap;

        // Ensure source map has correct source reference
        if (map) {
          map.sources = [id];
          map.sourcesContent = [code];
        }

        return {
          code: jsx,
          map
        };
      } catch (error) {
        const enhancedError = new Error(
          `Ruby2JS JSX transform error in ${id}: ${error.message}`
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
