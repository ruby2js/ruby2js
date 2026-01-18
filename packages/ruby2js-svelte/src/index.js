/**
 * ruby2js-svelte
 *
 * SvelteKit preprocessor for Ruby2JS - transform .svelte.rb files to Svelte components
 *
 * Usage in svelte.config.js:
 *
 *   import { ruby2jsPreprocess } from 'ruby2js-svelte';
 *
 *   export default {
 *     preprocess: [ruby2jsPreprocess()],
 *     extensions: ['.svelte', '.svelte.rb'],
 *     kit: { ... }
 *   };
 *
 * This enables writing Svelte components in Ruby:
 *
 *   # src/routes/+page.svelte.rb
 *   @count = 0
 *
 *   def increment
 *     @count += 1
 *   end
 *   __END__
 *   <button on:click={increment}>
 *     Count: {count}
 *   </button>
 */

import { SvelteComponentTransformer } from 'ruby2js/svelte';
import { initPrism } from 'ruby2js';

let prismReady = false;

async function ensurePrism() {
  if (!prismReady) {
    await initPrism();
    prismReady = true;
  }
}

/**
 * Create the SvelteKit preprocessor
 */
export function ruby2jsPreprocess(options = {}) {
  return {
    name: 'ruby2js-svelte',

    async markup({ content, filename }) {
      // Only process .svelte.rb files
      if (!filename || !filename.endsWith('.svelte.rb')) {
        return;
      }

      await ensurePrism();

      try {
        const result = SvelteComponentTransformer.transform(content, {
          eslevel: 2022,
          camelCase: true,
          ...options
        });

        if (result.errors?.length > 0) {
          const errorMsg = result.errors
            .map(e => typeof e === 'string' ? e : JSON.stringify(e))
            .join(', ');
          throw new Error(`Transform errors: ${errorMsg}`);
        }

        return {
          code: result.component,
          // TODO: source map support
        };
      } catch (error) {
        throw new Error(`ruby2js-svelte: Error transforming ${filename}: ${error.message}`);
      }
    }
  };
}

// Default export for convenience
export default ruby2jsPreprocess;

// Named exports
export { ruby2jsPreprocess as preprocess };
