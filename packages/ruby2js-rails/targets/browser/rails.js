// Ruby2JS-on-Rails Micro Framework - Browser Target
// Extends base module with DOM-based routing and form handling

import {
  RouterBase,
  ApplicationBase,
  truncate,
  pluralize,
  dom_id
} from './rails_base.js';

// Re-export base helpers
export { truncate, pluralize, dom_id };

// Flash message store - holds messages across redirects
export const flash = {
  _notice: null,

  setNotice(message) {
    this._notice = message;
  },

  consumeNotice() {
    const message = this._notice || '';
    this._notice = null;
    return message;
  }
};

// Browser Router with DOM-based dispatch
export class Router extends RouterBase {
  // Dispatch a path to the appropriate controller action
  static async dispatch(path) {
    console.log(`Started GET "${path}"`);

    const result = this.match(path, 'GET');

    if (!result) {
      console.warn('  No route matched');
      document.getElementById('content').innerHTML = '<h1>404 Not Found</h1>';
      return;
    }

    const { route, match } = result;

    if (route.redirect) {
      this.navigate(route.redirect);
      return;
    }

    const { controller, controllerName, action } = route;
    const actionMethod = action === 'new' ? '$new' : action;

    console.log(`Processing ${controller.name || controllerName}#${action}`);

    try {
      let html;
      if (route.nested) {
        const parentId = parseInt(match[1]);
        const id = match[2] ? parseInt(match[2]) : null;
        html = id ? await controller[actionMethod](parentId, id) : await controller[actionMethod](parentId);
      } else {
        const id = match[1] ? parseInt(match[1]) : null;
        html = id ? await controller[actionMethod](id) : await controller[actionMethod]();
      }

      console.log(`  Rendering ${controllerName}/${action}`);
      document.getElementById('content').innerHTML = html;
    } catch (e) {
      console.error('  Error:', e.message || e);
      document.getElementById('content').innerHTML = '<h1>Not Found</h1>';
    }
  }

  // Navigate to a new path, optionally with a notice message
  static async navigate(path, notice = null) {
    if (notice) {
      flash.setNotice(notice);
    }
    history.pushState({}, '', path);
    await this.dispatch(path);
  }
}

// Form submission handlers
export class FormHandler {
  // Handle resource creation
  static async create(controllerName, event) {
    event.preventDefault();
    const controller = Router.controllers[controllerName];
    const form = event.target;
    const params = this.extractParams(form);

    console.log(`Processing ${controller.name}#create`);
    console.log('  Parameters:', params);

    const result = await controller.create(params);
    await this.handleResult(result, controllerName, 'new', controller);
    return false;
  }

  // Handle resource update
  static async update(controllerName, event, id) {
    event.preventDefault();
    const controller = Router.controllers[controllerName];
    const form = event.target;
    const params = this.extractParams(form);

    console.log(`Processing ${controller.name}#update (id: ${id})`);
    console.log('  Parameters:', params);

    const result = await controller.update(id, params);
    await this.handleResult(result, controllerName, 'edit', controller, id);
    return false;
  }

  // Handle resource deletion
  static async destroy(controllerName, id, confirmMsg = 'Are you sure?') {
    if (!confirm(confirmMsg)) return;

    const controller = Router.controllers[controllerName];
    console.log(`Processing ${controller.name}#destroy (id: ${id})`);

    await controller.destroy(id);
    console.log(`  Redirected to /${controllerName}`);
    await Router.navigate(`/${controllerName}`);
  }

  // Handle nested resource creation
  static async createNested(controllerName, parentName, event, parentId) {
    event.preventDefault();
    const controller = Router.controllers[controllerName];
    const form = event.target;
    const params = this.extractParams(form);

    console.log(`Processing ${controller.name}#create (${parentName}_id: ${parentId})`);
    console.log('  Parameters:', params);

    await controller.create(parentId, params);
    console.log(`  Redirected to /${parentName}/${parentId}`);
    await Router.navigate(`/${parentName}/${parentId}`);
    return false;
  }

  // Handle nested resource deletion
  static async destroyNested(controllerName, parentName, parentId, id, confirmMsg = 'Delete this item?') {
    if (!confirm(confirmMsg)) return;

    const controller = Router.controllers[controllerName];
    console.log(`Processing ${controller.name}#destroy (${parentName}_id: ${parentId}, id: ${id})`);

    await controller.destroy(parentId, id);
    console.log(`  Redirected to /${parentName}/${parentId}`);
    await Router.navigate(`/${parentName}/${parentId}`);
  }

  // Extract form parameters
  // Handles Rails-style nested params: article[title] -> title
  static extractParams(form) {
    const params = {};
    const inputs = form.querySelectorAll('input, textarea, select');
    inputs.forEach(input => {
      if (input.name && input.type !== 'submit') {
        const match = input.name.match(/\[([^\]]+)\]$/);
        const key = match ? match[1] : input.name;
        params[key] = input.value;
      } else if (input.id && input.type !== 'submit') {
        params[input.id] = input.value;
      }
    });
    return params;
  }

  // Handle controller result (redirect or render)
  static async handleResult(result, controllerName, action, controller, id = null) {
    if (result.redirect) {
      console.log(`  Redirected to ${result.redirect}`);
      await Router.navigate(result.redirect, result.notice);
    } else if (result.render) {
      console.log(`  Rendering ${controllerName}/${action} (validation failed)`);
      document.getElementById('content').innerHTML = result.render;
    }
  }
}

// Browser Application
export class Application extends ApplicationBase {
  static sqlJsPath = '/node_modules/sql.js/dist';

  // Configure the application
  static configure(options) {
    super.configure(options);
    if (options.sqlJsPath) this.sqlJsPath = options.sqlJsPath;
  }

  // Initialize the database using the adapter
  static async initDatabase() {
    // Import the adapter (selected at build time)
    const adapter = await import('./active_record.mjs');
    this.activeRecordModule = adapter;

    // Initialize with config
    await adapter.initDatabase({ sqlJsPath: this.sqlJsPath });

    // For Dexie adapter: define schema and open database
    if (adapter.defineSchema) {
      if (this.schema && this.schema.tableSchemas) {
        for (const [table, schema] of Object.entries(this.schema.tableSchemas)) {
          adapter.registerSchema(table, schema);
        }
      } else {
        // Fallback for demo
        adapter.registerSchema('articles', '++id, title, created_at, updated_at');
        adapter.registerSchema('comments', '++id, article_id, created_at, updated_at');
      }
      adapter.defineSchema(1);
      await adapter.openDatabase();
    }

    // Make DB available globally for sql.js compatibility
    window.DB = adapter.getDatabase();

    // Run schema migrations
    if (this.schema && this.schema.create_tables) {
      this.schema.create_tables();
    }

    // Run seeds if present
    if (this.seeds) {
      if (this.seeds.run.constructor.name === 'AsyncFunction') {
        await this.seeds.run();
      } else {
        this.seeds.run();
      }
    }
  }

  // Start the application
  static async start() {
    try {
      await this.initDatabase();

      document.getElementById('loading').style.display = 'none';
      document.getElementById('app').style.display = 'block';

      // Handle browser back/forward
      window.addEventListener('popstate', async () => {
        await Router.dispatch(location.pathname);
      });

      // Expose helpers globally for onclick handlers
      window.navigate = navigate;
      window.submitForm = submitForm;

      // Initial route
      await Router.dispatch(location.pathname || '/');
    } catch (e) {
      document.getElementById('loading').innerHTML =
        `<p style="color: red;">Error: ${e.message}</p><pre>${e.stack}</pre>`;
      console.error(e);
    }
  }
}

// Navigation helper - prevents default, catches errors
export async function navigate(event, path) {
  event?.preventDefault?.();
  try {
    history.pushState({}, '', path);
    await Router.dispatch(path);
  } catch (e) {
    console.error('Navigation error:', e);
  }
  return false;
}

// Form submission helper - prevents default, catches errors
export async function submitForm(event, handler) {
  event?.preventDefault?.();
  try {
    const result = await handler(event);
    if (result?.redirect) {
      console.log(`  Redirected to ${result.redirect}`);
      if (result.notice) {
        flash.setNotice(result.notice);
      }
      history.pushState({}, '', result.redirect);
      await Router.dispatch(result.redirect);
    }
    return result;
  } catch (e) {
    console.error('Form submission error:', e);
  }
  return false;
}

// Extract form data from a submit event
export function formData(event) {
  event?.preventDefault?.();
  const form = event?.target;
  if (!form) return {};
  return FormHandler.extractParams(form);
}

// Handle form submission result
export function handleFormResult(result, rerenderFn = null) {
  if (result?.redirect) {
    console.log(`  Redirected to ${result.redirect}`);
    Router.navigate(result.redirect, result.notice);
  } else if (result?.render) {
    console.log(`  Re-rendering form (validation failed)`);
    document.getElementById('content').innerHTML = result.render;
  }
  return false;
}

// Set up form handlers on window
export function setupFormHandlers(config) {
  config.forEach(({ resource, handlerName, parent, confirmDelete }) => {
    if (parent) {
      window[`create${handlerName}`] = function(event, parentId) {
        event.preventDefault();
        try {
          FormHandler.createNested(resource, parent, event, parentId);
        } catch(e) {
          console.error(`Error in create${handlerName}:`, e);
        }
        return false;
      };
      window[`delete${handlerName}`] = (parentId, id) =>
        FormHandler.destroyNested(resource, parent, parentId, id, confirmDelete);
    } else {
      window[`create${handlerName}`] = function(event) {
        event.preventDefault();
        try {
          FormHandler.create(resource, event);
        } catch(e) {
          console.error(`Error in create${handlerName}:`, e);
        }
        return false;
      };
      window[`update${handlerName}`] = function(event, id) {
        event.preventDefault();
        try {
          FormHandler.update(resource, event, id);
        } catch(e) {
          console.error(`Error in update${handlerName}:`, e);
        }
        return false;
      };
      window[`delete${handlerName}`] = (id) =>
        FormHandler.destroy(resource, id, confirmDelete);
    }
  });
}
