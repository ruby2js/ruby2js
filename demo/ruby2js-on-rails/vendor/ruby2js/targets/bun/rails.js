// Ruby2JS-on-Rails Micro Framework - Bun Target
// Provides routing, controller dispatch, and form handling for Bun.serve

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

  // Dispatch a Fetch API request to the appropriate controller action
  static async dispatch(req) {
    const url = new URL(req.url);
    const path = url.pathname;
    const method = this.normalizeMethod(req, url);

    console.log(`Started ${method} "${path}"`);

    const result = this.match(path, method);

    if (!result) {
      console.warn('  No route matched');
      return new Response('<h1>404 Not Found</h1>', {
        status: 404,
        headers: { 'Content-Type': 'text/html' }
      });
    }

    const { route, match } = result;

    if (route.redirect) {
      return Response.redirect(route.redirect, 302);
    }

    const { controller, controllerName, action } = route;
    const actionMethod = action === 'new' ? '$new' : action;

    console.log(`Processing ${controller.name || controllerName}#${action}`);

    try {
      let html;
      let params = {};

      // Parse request body for POST/PATCH/DELETE
      if (['POST', 'PATCH', 'DELETE'].includes(method)) {
        params = await this.parseBody(req);
        console.log('  Parameters:', params);
      }

      // Handle different HTTP methods
      if (route.nested) {
        const parentId = parseInt(match[1]);
        const id = match[2] ? parseInt(match[2]) : null;

        if (method === 'POST') {
          const result = await controller.create(parentId, params);
          return this.handleResult(result, `/${route.parentName}/${parentId}`);
        } else if (method === 'PATCH') {
          const result = await controller.update(parentId, id, params);
          return this.handleResult(result, `/${route.parentName}/${parentId}`);
        } else if (method === 'DELETE') {
          await controller.destroy(parentId, id);
          return Response.redirect(`/${route.parentName}/${parentId}`, 302);
        } else {
          html = id ? await controller[actionMethod](parentId, id) : await controller[actionMethod](parentId);
        }
      } else {
        const id = match[1] ? parseInt(match[1]) : null;

        if (method === 'POST') {
          const result = await controller.create(params);
          return this.handleResult(result, `/${controllerName}`);
        } else if (method === 'PATCH') {
          const result = await controller.update(id, params);
          return this.handleResult(result, `/${controllerName}/${id}`);
        } else if (method === 'DELETE') {
          await controller.destroy(id);
          return Response.redirect(`/${controllerName}`, 302);
        } else {
          html = id ? await controller[actionMethod](id) : await controller[actionMethod]();
        }
      }

      console.log(`  Rendering ${controllerName}/${action}`);
      return this.htmlResponse(html);
    } catch (e) {
      console.error('  Error:', e.message || e);
      return new Response(`<h1>500 Internal Server Error</h1><pre>${e.stack}</pre>`, {
        status: 500,
        headers: { 'Content-Type': 'text/html' }
      });
    }
  }

  // Normalize HTTP method (handle _method override for browsers without PATCH/DELETE)
  static normalizeMethod(req, url) {
    let method = req.method.toUpperCase();
    // Check for _method override in query string
    const methodOverride = url.searchParams.get('_method');
    if (methodOverride) {
      method = methodOverride.toUpperCase();
    }
    return method;
  }

  // Parse request body (form data or JSON)
  static async parseBody(req) {
    const contentType = req.headers.get('content-type') || '';

    if (contentType.includes('application/json')) {
      try {
        return await req.json();
      } catch (e) {
        return {};
      }
    } else {
      // Parse URL-encoded form data
      const text = await req.text();
      const params = {};
      const pairs = text.split('&');
      for (const pair of pairs) {
        const [key, value] = pair.split('=');
        if (key) {
          params[decodeURIComponent(key)] = decodeURIComponent(value || '');
        }
      }
      return params;
    }
  }

  // Handle controller result (redirect or render)
  static handleResult(result, defaultRedirect) {
    if (result.redirect) {
      console.log(`  Redirected to ${result.redirect}`);
      return Response.redirect(result.redirect, 302);
    } else if (result.render) {
      // Validation failed, re-render form
      return this.htmlResponse(result.html || '<h1>Validation Error</h1>');
    } else {
      return Response.redirect(defaultRedirect, 302);
    }
  }

  // Create HTML response with proper headers
  static htmlResponse(html) {
    return new Response(html, {
      status: 200,
      headers: { 'Content-Type': 'text/html; charset=utf-8' }
    });
  }
}

// Application base class for Bun
export class Application {
  static schema = null;
  static seeds = null;
  static activeRecordModule = null;
  static layout = null;  // Function to wrap content in layout HTML

  // Configure the application
  static configure(options) {
    if (options.schema) this.schema = options.schema;
    if (options.seeds) this.seeds = options.seeds;
    if (options.layout) this.layout = options.layout;
  }

  // Initialize the database using the adapter
  static async initDatabase() {
    // Import the adapter (selected at build time)
    const adapter = await import('./active_record.mjs');
    this.activeRecordModule = adapter;

    // Initialize database connection
    await adapter.initDatabase({});

    // Run schema migrations - schema imports execSQL from adapter
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

  // Start the HTTP server using Bun.serve
  static async start(port = null) {
    const listenPort = port || process.env.PORT || 3000;

    try {
      await this.initDatabase();
      console.log('Database initialized');

      const server = Bun.serve({
        port: listenPort,
        async fetch(req) {
          return await Router.dispatch(req);
        }
      });

      console.log(`Server running at http://localhost:${server.port}/`);
      return server;
    } catch (e) {
      console.error('Failed to start server:', e);
      process.exit(1);
    }
  }
}

// Text truncation helper (Rails view helper equivalent)
export function truncate(text, options = {}) {
  const length = options.length || 30;
  const omission = options.omission || '...';
  if (!text || text.length <= length) return text || '';
  return text.slice(0, length - omission.length) + omission;
}

// Navigate helper - for Bun, this just returns the path
// Used in generated code to maintain API compatibility
export function navigate(event, path) {
  // In server context, navigation is handled via HTTP redirects
  // This function is here for API compatibility with browser version
  return path;
}

// Form submission helper - for Bun, forms are handled via HTTP
export function submitForm(event, handler) {
  // In server context, form submission is handled via HTTP POST
  // This function is here for API compatibility with browser version
  return false;
}

// Extract form data - for Bun, data comes from request body
export function formData(event) {
  // In server context, form data is parsed in Router.parseBody
  return {};
}

// Handle form result - for Bun, this is handled in Router.handleResult
export function handleFormResult(result, rerenderFn = null) {
  return false;
}

// Setup form handlers - no-op in Bun (forms handled via HTTP)
export function setupFormHandlers(config) {
  // Form handlers are handled by Router.dispatch in Bun
}
