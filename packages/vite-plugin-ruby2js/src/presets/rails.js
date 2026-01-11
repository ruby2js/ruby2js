/**
 * Rails preset for vite-plugin-ruby2js
 *
 * Provides:
 * - Stimulus controller transformation
 * - ERB view transformation
 * - Rails helper methods
 * - HMR for Stimulus controllers
 *
 * Usage:
 *   import { rails } from 'vite-plugin-ruby2js/presets/rails';
 *
 *   export default defineConfig({
 *     plugins: [rails()]
 *   });
 */

import ruby2js from '../index.js';

// Import Rails-specific filters
import 'ruby2js/filters/stimulus.js';
import 'ruby2js/filters/erb.js';
import 'ruby2js/filters/rails/helpers.js';

/**
 * @typedef {Object} RailsPresetOptions
 * @property {number} [eslevel] - ES level to target (default: 2022)
 * @property {boolean} [hmr] - Enable HMR for Stimulus controllers (default: true)
 * @property {Object} [aliases] - Path aliases for Rails directories
 */

/**
 * Create a Rails preset with Stimulus, ERB, and HMR support.
 *
 * @param {RailsPresetOptions} options
 * @returns {import('vite').Plugin[]}
 */
export function rails(options = {}) {
  const {
    eslevel = 2022,
    hmr = true,
    aliases = {},
    ...ruby2jsOptions
  } = options;

  const defaultAliases = {
    '@controllers': 'app/javascript/controllers',
    '@models': 'app/models',
    '@views': 'app/views',
    ...aliases
  };

  const plugins = [
    // Core Ruby transformation with Rails filters
    ruby2js({
      filters: [
        'Stimulus',
        'ESM',
        'Functions',
        'Return'
      ],
      eslevel,
      ...ruby2jsOptions
    }),

    // Path aliases for Rails conventions
    {
      name: 'ruby2js-rails-config',
      config() {
        return {
          resolve: {
            alias: defaultAliases
          }
        };
      }
    }
  ];

  // Add HMR support if enabled
  if (hmr) {
    plugins.push({
      name: 'ruby2js-rails-hmr',

      handleHotUpdate({ file, server, modules }) {
        // Handle Stimulus controller updates
        if (file.endsWith('_controller.rb')) {
          const controllerName = extractControllerName(file);

          server.ws.send({
            type: 'custom',
            event: 'ruby2js:stimulus-update',
            data: {
              file,
              controller: controllerName
            }
          });

          // Return modules to trigger HMR for the file itself
          return modules;
        }
      },

      // Inject HMR runtime for Stimulus
      transformIndexHtml(html) {
        return {
          html,
          tags: [
            {
              tag: 'script',
              attrs: { type: 'module' },
              children: STIMULUS_HMR_RUNTIME,
              injectTo: 'head'
            }
          ]
        };
      }
    });
  }

  return plugins;
}

/**
 * Extract controller name from file path.
 * e.g., 'app/javascript/controllers/chat_controller.rb' -> 'chat'
 *
 * @param {string} filePath
 * @returns {string}
 */
function extractControllerName(filePath) {
  const fileName = filePath.split('/').pop() || '';
  return fileName
    .replace('_controller.rb', '')
    .replace(/_/g, '-');
}

/**
 * HMR runtime script for Stimulus controllers.
 * Injected into the page to handle controller hot updates.
 */
const STIMULUS_HMR_RUNTIME = `
if (import.meta.hot) {
  import.meta.hot.on('ruby2js:stimulus-update', async (data) => {
    const { file, controller } = data;

    try {
      // Import the updated module with cache bust
      const timestamp = Date.now();
      const modulePath = file.replace(/\\.rb$/, '.js');
      const newModule = await import(/* @vite-ignore */ modulePath + '?t=' + timestamp);

      // Re-register with Stimulus if available
      if (window.Stimulus && newModule.default) {
        // Unregister existing controller
        const existingController = window.Stimulus.router.modulesByIdentifier.get(controller);
        if (existingController) {
          window.Stimulus.unload(existingController);
        }

        // Register updated controller
        window.Stimulus.register(controller, newModule.default);
        console.log('[ruby2js] Hot updated Stimulus controller:', controller);
      }
    } catch (error) {
      console.error('[ruby2js] Failed to hot update controller:', controller, error);
      // Fall back to full reload
      import.meta.hot.invalidate();
    }
  });
}
`;

export default rails;
