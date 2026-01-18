/**
 * ruby2js-nuxt
 *
 * Nuxt module for Ruby2JS - transform .vue.rb files to Vue components
 *
 * Usage in nuxt.config.ts:
 *
 *   export default defineNuxtConfig({
 *     modules: ['ruby2js-nuxt'],
 *     ruby2js: {
 *       // options
 *     }
 *   });
 *
 * This enables writing Vue components in Ruby:
 *
 *   # pages/index.vue.rb
 *   @count = 0
 *
 *   def increment
 *     @count += 1
 *   end
 *   __END__
 *   <template>
 *     <button @click="increment">Count: {{ count }}</button>
 *   </template>
 */

import { defineNuxtModule, addVitePlugin } from '@nuxt/kit';

export default defineNuxtModule({
  meta: {
    name: 'ruby2js-nuxt',
    configKey: 'ruby2js',
    compatibility: {
      nuxt: '^3.0.0'
    }
  },

  defaults: {
    eslevel: 2022,
    camelCase: true
  },

  async setup(options, nuxt) {
    // Add .vue.rb to page extensions
    nuxt.options.extensions.push('.vue.rb');

    // Dynamically import vite-plugin-ruby2js
    const ruby2jsPlugin = await import('vite-plugin-ruby2js').then(m => m.default);

    // Add Vite plugin for transformation
    addVitePlugin(ruby2jsPlugin({
      sfc: true,
      ...options
    }));

    // Watch .vue.rb files for changes
    nuxt.hook('builder:watch', async (event, path) => {
      if (path.endsWith('.vue.rb')) {
        // Nuxt will automatically rebuild when watched files change
        console.log(`[ruby2js-nuxt] ${event}: ${path}`);
      }
    });

    console.log('[ruby2js-nuxt] Module loaded - .vue.rb files enabled');
  }
});
