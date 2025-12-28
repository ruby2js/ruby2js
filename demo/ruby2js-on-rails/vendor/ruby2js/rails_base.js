// Ruby2JS-on-Rails Micro Framework - Base Module
// Shared routing and helper functionality for all targets

// Base Router class with route registration and matching
export class RouterBase {
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
}

// Base Application class with shared configuration
export class ApplicationBase {
  static schema = null;
  static seeds = null;
  static activeRecordModule = null;
  static layoutFn = null;

  // Configure the application
  static configure(options) {
    if (options.schema) this.schema = options.schema;
    if (options.seeds) this.seeds = options.seeds;
    if (options.layout) this.layoutFn = options.layout;
  }

  // Wrap content in HTML layout
  static wrapInLayout(content) {
    if (this.layoutFn) {
      return this.layoutFn(content);
    }
    return content;
  }

  // Initialize the database using the adapter
  static async initDatabase(options = {}) {
    // Import the adapter (selected at build time)
    const adapter = await import('./active_record.mjs');
    this.activeRecordModule = adapter;

    // Initialize database connection
    await adapter.initDatabase(options);

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
}

// --- Helper Functions ---

// Text truncation helper (Rails view helper equivalent)
export function truncate(text, options = {}) {
  const length = options.length || 30;
  const omission = options.omission || '...';
  if (!text || text.length <= length) return text || '';
  return text.slice(0, length - omission.length) + omission;
}

// Pluralize helper (Rails view helper equivalent)
// pluralize(1, 'error') => '1 error'
// pluralize(2, 'error') => '2 errors'
// pluralize(2, 'error', 'mistakes') => '2 mistakes'
export function pluralize(count, singular, plural = null) {
  const word = count === 1 ? singular : (plural || singular + 's');
  return `${count} ${word}`;
}

// DOM ID helper (Rails view helper equivalent)
// dom_id(article) => 'article_1'
// dom_id(article, 'edit') => 'edit_article_1'
// dom_id(new Article()) => 'new_article'
export function dom_id(record, prefix = null) {
  const modelName = (record.constructor?.modelName || record.constructor?.name || 'record').toLowerCase();

  if (record.id) {
    return prefix ? `${prefix}_${modelName}_${record.id}` : `${modelName}_${record.id}`;
  } else {
    return prefix ? `${prefix}_new_${modelName}` : `new_${modelName}`;
  }
}

// --- Stub functions for API compatibility ---
// These are overridden by browser target but provide no-ops for server targets

export function navigate(event, path) {
  // Server targets handle navigation via HTTP redirects
  return path;
}

export function submitForm(event, handler) {
  // Server targets handle forms via HTTP POST
  return false;
}

export function formData(event) {
  // Server targets parse form data from request body
  return {};
}

export function handleFormResult(result, rerenderFn = null) {
  // Server targets handle results in Router.handleResult
  return false;
}

export function setupFormHandlers(config) {
  // Server targets handle forms via HTTP, no client-side handlers needed
}
