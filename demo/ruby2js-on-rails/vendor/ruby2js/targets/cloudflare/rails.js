// Ruby2JS-on-Rails Micro Framework - Cloudflare Workers Target
// Provides routing, controller dispatch, and form handling for Cloudflare Workers
// Uses Web standard Request/Response APIs

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

  // Dispatch an HTTP request to the appropriate controller action
  // Returns a Response object
  static async dispatch(request) {
    const url = new URL(request.url);
    const path = url.pathname;
    let method = await this.normalizeMethod(request);
    let params = {};

    // Parse request body for POST/PATCH/PUT/DELETE requests
    if (['POST', 'PATCH', 'PUT', 'DELETE'].includes(request.method)) {
      params = await this.parseBody(request);
      // Check for _method override in body (Rails convention for PATCH/DELETE)
      if (params._method) {
        method = params._method.toUpperCase();
        delete params._method;
      }
    }

    console.log(`Started ${method} "${path}"`);
    if (Object.keys(params).length > 0) {
      console.log('  Parameters:', params);
    }

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
      return Response.redirect(new URL(route.redirect, request.url), 302);
    }

    const { controller, controllerName, action } = route;
    const actionMethod = action === 'new' ? '$new' : action;

    console.log(`Processing ${controller.name || controllerName}#${action}`);

    try {
      let html;

      // Handle different HTTP methods
      if (route.nested) {
        const parentId = parseInt(match[1]);
        const id = match[2] ? parseInt(match[2]) : null;

        if (method === 'POST') {
          const result = await controller.create(parentId, params);
          return this.handleResult(request, result, `/${route.parentName}/${parentId}`);
        } else if (method === 'PATCH') {
          const result = await controller.update(parentId, id, params);
          return this.handleResult(request, result, `/${route.parentName}/${parentId}`);
        } else if (method === 'DELETE') {
          await controller.destroy(parentId, id);
          return Response.redirect(new URL(`/${route.parentName}/${parentId}`, request.url), 302);
        } else {
          html = id ? await controller[actionMethod](parentId, id) : await controller[actionMethod](parentId);
        }
      } else {
        const id = match[1] ? parseInt(match[1]) : null;

        if (method === 'POST') {
          const result = await controller.create(params);
          return this.handleResult(request, result, `/${controllerName}`);
        } else if (method === 'PATCH') {
          const result = await controller.update(id, params);
          return this.handleResult(request, result, `/${controllerName}/${id}`);
        } else if (method === 'DELETE') {
          await controller.destroy(id);
          return Response.redirect(new URL(`/${controllerName}`, request.url), 302);
        } else {
          html = id ? await controller[actionMethod](id) : await controller[actionMethod]();
        }
      }

      console.log(`  Rendering ${controllerName}/${action}`);
      return this.sendHtml(html);
    } catch (e) {
      console.error('  Error:', e.message || e);
      return new Response(`<h1>500 Internal Server Error</h1><pre>${e.stack}</pre>`, {
        status: 500,
        headers: { 'Content-Type': 'text/html' }
      });
    }
  }

  // Normalize HTTP method (handle _method override for browsers without PATCH/DELETE)
  static async normalizeMethod(request) {
    let method = request.method.toUpperCase();
    // Check for _method override in query string
    const url = new URL(request.url);
    if (url.searchParams.get('_method')) {
      method = url.searchParams.get('_method').toUpperCase();
    }
    return method;
  }

  // Parse request body (form data or JSON)
  static async parseBody(request) {
    const contentType = request.headers.get('content-type') || '';

    try {
      if (contentType.includes('application/json')) {
        return await request.json();
      } else if (contentType.includes('application/x-www-form-urlencoded')) {
        const formData = await request.formData();
        const params = {};
        for (const [key, value] of formData.entries()) {
          params[key] = value;
        }
        return params;
      } else if (contentType.includes('multipart/form-data')) {
        const formData = await request.formData();
        const params = {};
        for (const [key, value] of formData.entries()) {
          // Skip file uploads for now, just get string values
          if (typeof value === 'string') {
            params[key] = value;
          }
        }
        return params;
      }
    } catch (e) {
      console.warn('Failed to parse request body:', e.message);
    }

    return {};
  }

  // Handle controller result (redirect or render)
  static handleResult(request, result, defaultRedirect) {
    if (result.redirect) {
      console.log(`  Redirected to ${result.redirect}`);
      return Response.redirect(new URL(result.redirect, request.url), 302);
    } else if (result.render) {
      // Validation failed, re-render form
      return this.sendHtml(result.html || '<h1>Validation Error</h1>');
    } else {
      return Response.redirect(new URL(defaultRedirect, request.url), 302);
    }
  }

  // Send HTML response with proper headers, wrapped in layout
  static sendHtml(html) {
    const fullHtml = Application.wrapInLayout(html);
    return new Response(fullHtml, {
      status: 200,
      headers: { 'Content-Type': 'text/html; charset=utf-8' }
    });
  }
}

// Application base class for Cloudflare Workers
export class Application {
  static schema = null;
  static seeds = null;
  static activeRecordModule = null;
  static layoutFn = null;  // Layout function loaded from views/layouts/application.js
  static _initialized = false;

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
    // Fallback if no layout loaded
    return content;
  }

  // Initialize the database using the adapter
  // env contains the D1 binding (e.g., env.DB)
  static async initDatabase(env) {
    if (this._initialized) return;

    // Import the adapter (selected at build time)
    const adapter = await import('./active_record.mjs');
    this.activeRecordModule = adapter;

    // Initialize database connection with D1 binding
    await adapter.initDatabase({ binding: env.DB });

    // Run schema migrations - schema imports execSQL from adapter
    if (this.schema && this.schema.create_tables) {
      await this.schema.create_tables();
    }

    // Run seeds if present (typically only in development)
    if (this.seeds && env.RUN_SEEDS) {
      if (this.seeds.run.constructor.name === 'AsyncFunction') {
        await this.seeds.run();
      } else {
        this.seeds.run();
      }
    }

    this._initialized = true;
  }

  // Create the Worker fetch handler
  // Usage in worker entry point:
  //   import { Application, Router } from './lib/rails.js';
  //   export default Application.worker();
  static worker() {
    const app = this;
    return {
      async fetch(request, env, ctx) {
        try {
          // Initialize database on first request
          await app.initDatabase(env);

          // Dispatch the request
          return await Router.dispatch(request);
        } catch (e) {
          console.error('Worker error:', e);
          return new Response(`<h1>500 Internal Server Error</h1><pre>${e.stack}</pre>`, {
            status: 500,
            headers: { 'Content-Type': 'text/html' }
          });
        }
      }
    };
  }
}

// Text truncation helper (Rails view helper equivalent)
export function truncate(text, options = {}) {
  const length = options.length || 30;
  const omission = options.omission || '...';
  if (!text || text.length <= length) return text || '';
  return text.slice(0, length - omission.length) + omission;
}

// Pluralize helper (Rails view helper equivalent)
export function pluralize(count, singular, plural = null) {
  const word = count === 1 ? singular : (plural || singular + 's');
  return `${count} ${word}`;
}

// DOM ID helper (Rails view helper equivalent)
export function dom_id(record, prefix = null) {
  const modelName = (record.constructor?.modelName || record.constructor?.name || 'record').toLowerCase();

  if (record.id) {
    return prefix ? `${prefix}_${modelName}_${record.id}` : `${modelName}_${record.id}`;
  } else {
    return prefix ? `${prefix}_new_${modelName}` : `new_${modelName}`;
  }
}

// Navigate helper - for Workers, this just returns the path
// Used in generated code to maintain API compatibility
export function navigate(event, path) {
  return path;
}

// Form submission helper - for Workers, forms are handled via HTTP
export function submitForm(event, handler) {
  return false;
}

// Extract form data - for Workers, data comes from request body
export function formData(event) {
  return {};
}

// Handle form result - for Workers, this is handled in Router.handleResult
export function handleFormResult(result, rerenderFn = null) {
  return false;
}

// Setup form handlers - no-op in Workers (forms handled via HTTP)
export function setupFormHandlers(config) {
  // Form handlers are handled by Router.dispatch in Workers
}
