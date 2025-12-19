// Rails-in-JS Micro Framework
// Provides routing, controller dispatch, and form handling

export class Router {
  static routes = [];
  static controllers = {};

  // Register RESTful routes for a resource
  static resources(name, controller, options = {}) {
    this.controllers[name] = controller;
    const nested = options.nested || [];
    const only = options.only;

    const actions = [
      { method: 'GET', path: `/${name}`, action: 'index' },
      { method: 'GET', path: `/${name}/new`, action: 'new' },
      { method: 'GET', path: `/${name}/:id`, action: 'show' },
      { method: 'GET', path: `/${name}/:id/edit`, action: 'edit' },
      { method: 'POST', path: `/${name}`, action: 'create' },
      { method: 'PATCH', path: `/${name}/:id`, action: 'update' },
      { method: 'DELETE', path: `/${name}/:id`, action: 'destroy' }
    ];

    actions.forEach(route => {
      if (only && !only.includes(route.action)) return;

      // Convert path to regex pattern
      const pattern = new RegExp('^' + route.path.replace(/:id/g, '(\\d+)') + '$');

      this.routes.push({
        method: route.method,
        pattern,
        controller,
        controllerName: name,
        action: route.action
      });
    });

    // Handle nested resources
    nested.forEach(nestedConfig => {
      this.nestedResources(name, nestedConfig.name, nestedConfig.controller, nestedConfig.only);
    });
  }

  // Register nested RESTful routes
  static nestedResources(parentName, name, controller, only) {
    this.controllers[name] = controller;

    const actions = [
      { method: 'GET', path: `/${parentName}/:parent_id/${name}`, action: 'index' },
      { method: 'GET', path: `/${parentName}/:parent_id/${name}/new`, action: 'new' },
      { method: 'GET', path: `/${parentName}/:parent_id/${name}/:id`, action: 'show' },
      { method: 'GET', path: `/${parentName}/:parent_id/${name}/:id/edit`, action: 'edit' },
      { method: 'POST', path: `/${parentName}/:parent_id/${name}`, action: 'create' },
      { method: 'PATCH', path: `/${parentName}/:parent_id/${name}/:id`, action: 'update' },
      { method: 'DELETE', path: `/${parentName}/:parent_id/${name}/:id`, action: 'destroy' }
    ];

    actions.forEach(route => {
      if (only && !only.includes(route.action)) return;

      const pattern = new RegExp('^' + route.path
        .replace(/:parent_id/g, '(\\d+)')
        .replace(/:id/g, '(\\d+)') + '$');

      this.routes.push({
        method: route.method,
        pattern,
        controller,
        controllerName: name,
        parentName,
        action: route.action,
        nested: true
      });
    });
  }

  // Add a simple redirect route
  static root(path) {
    this.routes.unshift({
      method: 'GET',
      pattern: /^\/$/,
      redirect: path
    });
  }

  // Find matching route for a path
  static match(path, method = 'GET') {
    for (const route of this.routes) {
      if (route.method !== method) continue;
      const match = path.match(route.pattern);
      if (match) {
        return { route, match };
      }
    }
    return null;
  }

  // Dispatch a path to the appropriate controller action
  static dispatch(path) {
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
        // Nested resource: first capture is parent_id, second is id
        const parentId = parseInt(match[1]);
        const id = match[2] ? parseInt(match[2]) : null;
        html = id ? controller[actionMethod](parentId, id) : controller[actionMethod](parentId);
      } else {
        // Regular resource: first capture is id
        const id = match[1] ? parseInt(match[1]) : null;
        html = id ? controller[actionMethod](id) : controller[actionMethod]();
      }

      console.log(`  Rendering ${controllerName}/${action}`);
      document.getElementById('content').innerHTML = html;
    } catch (e) {
      console.error('  Error:', e.message || e);
      document.getElementById('content').innerHTML = '<h1>Not Found</h1>';
    }
  }

  // Navigate to a new path
  static navigate(path) {
    history.pushState({}, '', path);
    this.dispatch(path);
  }
}

// Form submission handlers
export class FormHandler {
  // Handle resource creation
  static create(controllerName, event) {
    event.preventDefault();
    const controller = Router.controllers[controllerName];
    const form = event.target;
    const params = this.extractParams(form);

    console.log(`Processing ${controller.name}#create`);
    console.log('  Parameters:', params);

    const result = controller.create(params);
    this.handleResult(result, controllerName, 'new', controller);
    return false;
  }

  // Handle resource update
  static update(controllerName, event, id) {
    event.preventDefault();
    const controller = Router.controllers[controllerName];
    const form = event.target;
    const params = this.extractParams(form);

    console.log(`Processing ${controller.name}#update (id: ${id})`);
    console.log('  Parameters:', params);

    const result = controller.update(id, params);
    this.handleResult(result, controllerName, 'edit', controller, id);
    return false;
  }

  // Handle resource deletion
  static destroy(controllerName, id, confirmMsg = 'Are you sure?') {
    if (!confirm(confirmMsg)) return;

    const controller = Router.controllers[controllerName];
    console.log(`Processing ${controller.name}#destroy (id: ${id})`);

    controller.destroy(id);
    console.log(`  Redirected to /${controllerName}`);
    Router.navigate(`/${controllerName}`);
  }

  // Handle nested resource creation
  static createNested(controllerName, parentName, event, parentId) {
    event.preventDefault();
    const controller = Router.controllers[controllerName];
    const form = event.target;
    const params = this.extractParams(form);

    console.log(`Processing ${controller.name}#create (${parentName}_id: ${parentId})`);
    console.log('  Parameters:', params);

    controller.create(parentId, params);
    console.log(`  Redirected to /${parentName}/${parentId}`);
    Router.navigate(`/${parentName}/${parentId}`);
    return false;
  }

  // Handle nested resource deletion
  static destroyNested(controllerName, parentName, parentId, id, confirmMsg = 'Delete this item?') {
    if (!confirm(confirmMsg)) return;

    const controller = Router.controllers[controllerName];
    console.log(`Processing ${controller.name}#destroy (${parentName}_id: ${parentId}, id: ${id})`);

    controller.destroy(parentId, id);
    console.log(`  Redirected to /${parentName}/${parentId}`);
    Router.navigate(`/${parentName}/${parentId}`);
  }

  // Extract form parameters
  static extractParams(form) {
    const params = {};
    const inputs = form.querySelectorAll('input, textarea, select');
    inputs.forEach(input => {
      if (input.name && input.type !== 'submit') {
        params[input.name] = input.value;
      } else if (input.id && input.type !== 'submit') {
        // Fallback to id if no name
        params[input.id] = input.value;
      }
    });
    return params;
  }

  // Handle controller result (redirect or render)
  static handleResult(result, controllerName, action, controller, id = null) {
    if (result.redirect) {
      console.log(`  Redirected to ${result.redirect}`);
      Router.navigate(result.redirect);
    } else if (result.render) {
      console.log(`  Rendering ${controllerName}/${action} (validation failed)`);
      const actionMethod = action === 'new' ? '$new' : action;
      const html = id ? controller[actionMethod](id) : controller[actionMethod]();
      document.getElementById('content').innerHTML = html;
    }
  }
}

// Application base class
export class Application {
  static schema = null;
  static seeds = null;
  static sqlJsPath = '/node_modules/sql.js/dist';

  // Configure the application
  static configure(options) {
    if (options.schema) this.schema = options.schema;
    if (options.seeds) this.seeds = options.seeds;
    if (options.sqlJsPath) this.sqlJsPath = options.sqlJsPath;
  }

  // Initialize the database
  static async initDatabase() {
    const SQL = await window.initSqlJs({
      locateFile: file => `${this.sqlJsPath}/${file}`
    });
    window.DB = new SQL.Database();

    // Time polyfill for Ruby compatibility
    window.Time = {
      now() {
        return { toString() { return new Date().toISOString(); } };
      }
    };

    if (this.schema) {
      this.schema.create_tables(window.DB);
    }

    if (this.seeds) {
      this.seeds.run();
    }
  }

  // Start the application
  static async start() {
    try {
      await this.initDatabase();

      document.getElementById('loading').style.display = 'none';
      document.getElementById('app').style.display = 'block';

      // Handle browser back/forward
      window.addEventListener('popstate', () => {
        Router.dispatch(location.pathname);
      });

      // Expose helpers globally for onclick handlers
      window.navigate = navigate;
      window.submitForm = submitForm;
      window.truncate = truncate;

      // Initial route
      Router.dispatch(location.pathname || '/');
    } catch (e) {
      document.getElementById('loading').innerHTML =
        `<p style="color: red;">Error: ${e.message}</p><pre>${e.stack}</pre>`;
      console.error(e);
    }
  }
}

// Navigation helper - prevents default, catches errors, logs issues
// Usage: <a href="/path" onclick="return navigate(event, '/path')">
export function navigate(event, path) {
  event?.preventDefault?.();
  try {
    history.pushState({}, '', path);
    Router.dispatch(path);
  } catch (e) {
    console.error('Navigation error:', e);
  }
  return false;
}

// Form submission helper - prevents default, catches errors
// Usage: <form onsubmit="return submitForm(event, handler)">
export function submitForm(event, handler) {
  event?.preventDefault?.();
  try {
    const result = handler(event);
    if (result?.redirect) {
      console.log(`  Redirected to ${result.redirect}`);
      history.pushState({}, '', result.redirect);
      Router.dispatch(result.redirect);
    } else if (result?.render) {
      // Re-render handled by caller
    }
    return result;
  } catch (e) {
    console.error('Form submission error:', e);
  }
  return false;
}

// Text truncation helper (Rails view helper equivalent)
export function truncate(text, options = {}) {
  const length = options.length || 30;
  const omission = options.omission || '...';
  if (!text || text.length <= length) return text || '';
  return text.slice(0, length - omission.length) + omission;
}

// Extract form data from a submit event
// Returns a params object with all form field values
export function formData(event) {
  event?.preventDefault?.();
  const form = event?.target;
  if (!form) return {};
  return FormHandler.extractParams(form);
}

// Handle form submission result (redirect or render)
// Call this after the controller method returns
export function handleFormResult(result, rerenderFn = null) {
  if (result?.redirect) {
    console.log(`  Redirected to ${result.redirect}`);
    Router.navigate(result.redirect);
  } else if (result?.render && rerenderFn) {
    console.log(`  Re-rendering form (validation failed)`);
    rerenderFn();
  }
  return false;
}

// Convenience function to set up form handlers on window
// handlerName is pre-computed at transpile time using Ruby's Inflector
export function setupFormHandlers(config) {
  config.forEach(({ resource, handlerName, parent, confirmDelete }) => {
    if (parent) {
      // Nested resource handlers
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
      // Regular resource handlers
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
