// Rails-in-JS Micro Framework - Node.js Target
// Provides routing, controller dispatch, and form handling for HTTP servers

import http from 'http';
import { parse as parseUrl } from 'url';
import { StringDecoder } from 'string_decoder';

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
  static async dispatch(req, res) {
    const parsedUrl = parseUrl(req.url, true);
    const path = parsedUrl.pathname;
    const method = this.normalizeMethod(req);

    console.log(`Started ${method} "${path}"`);

    const result = this.match(path, method);

    if (!result) {
      console.warn('  No route matched');
      res.writeHead(404, { 'Content-Type': 'text/html' });
      res.end('<h1>404 Not Found</h1>');
      return;
    }

    const { route, match } = result;

    if (route.redirect) {
      res.writeHead(302, { Location: route.redirect });
      res.end();
      return;
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
          return this.handleResult(res, result, `/${route.parentName}/${parentId}`);
        } else if (method === 'PATCH') {
          const result = await controller.update(parentId, id, params);
          return this.handleResult(res, result, `/${route.parentName}/${parentId}`);
        } else if (method === 'DELETE') {
          await controller.destroy(parentId, id);
          res.writeHead(302, { Location: `/${route.parentName}/${parentId}` });
          res.end();
          return;
        } else {
          html = id ? await controller[actionMethod](parentId, id) : await controller[actionMethod](parentId);
        }
      } else {
        const id = match[1] ? parseInt(match[1]) : null;

        if (method === 'POST') {
          const result = await controller.create(params);
          return this.handleResult(res, result, `/${controllerName}`);
        } else if (method === 'PATCH') {
          const result = await controller.update(id, params);
          return this.handleResult(res, result, `/${controllerName}/${id}`);
        } else if (method === 'DELETE') {
          await controller.destroy(id);
          res.writeHead(302, { Location: `/${controllerName}` });
          res.end();
          return;
        } else {
          html = id ? await controller[actionMethod](id) : await controller[actionMethod]();
        }
      }

      console.log(`  Rendering ${controllerName}/${action}`);
      this.sendHtml(res, html);
    } catch (e) {
      console.error('  Error:', e.message || e);
      res.writeHead(500, { 'Content-Type': 'text/html' });
      res.end(`<h1>500 Internal Server Error</h1><pre>${e.stack}</pre>`);
    }
  }

  // Normalize HTTP method (handle _method override for browsers without PATCH/DELETE)
  static normalizeMethod(req) {
    let method = req.method.toUpperCase();
    // Check for _method override in query string
    const parsedUrl = parseUrl(req.url, true);
    if (parsedUrl.query._method) {
      method = parsedUrl.query._method.toUpperCase();
    }
    return method;
  }

  // Parse request body (form data or JSON)
  static parseBody(req) {
    return new Promise((resolve, reject) => {
      const decoder = new StringDecoder('utf-8');
      let body = '';

      req.on('data', chunk => {
        body += decoder.write(chunk);
      });

      req.on('end', () => {
        body += decoder.end();

        const contentType = req.headers['content-type'] || '';

        if (contentType.includes('application/json')) {
          try {
            resolve(JSON.parse(body));
          } catch (e) {
            resolve({});
          }
        } else {
          // Parse URL-encoded form data
          const params = {};
          const pairs = body.split('&');
          for (const pair of pairs) {
            const [key, value] = pair.split('=');
            if (key) {
              params[decodeURIComponent(key)] = decodeURIComponent(value || '');
            }
          }
          resolve(params);
        }
      });

      req.on('error', reject);
    });
  }

  // Handle controller result (redirect or render)
  static handleResult(res, result, defaultRedirect) {
    if (result.redirect) {
      console.log(`  Redirected to ${result.redirect}`);
      res.writeHead(302, { Location: result.redirect });
      res.end();
    } else if (result.render) {
      // Validation failed, re-render form
      this.sendHtml(res, result.html || '<h1>Validation Error</h1>');
    } else {
      res.writeHead(302, { Location: defaultRedirect });
      res.end();
    }
  }

  // Send HTML response with proper headers
  static sendHtml(res, html) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(html);
  }
}

// Application base class for Node.js
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

    // For adapters with schema migration support
    if (this.schema && this.schema.create_tables && adapter.getDatabase) {
      const db = adapter.getDatabase();
      this.schema.create_tables(db);
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

  // Start the HTTP server
  static async start(port = null) {
    const listenPort = port || process.env.PORT || 3000;

    try {
      await this.initDatabase();
      console.log('Database initialized');

      const server = http.createServer(async (req, res) => {
        await Router.dispatch(req, res);
      });

      server.listen(listenPort, () => {
        console.log(`Server running at http://localhost:${listenPort}/`);
      });

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

// Navigate helper - for Node.js, this just returns the path
// Used in generated code to maintain API compatibility
export function navigate(event, path) {
  // In Node.js context, navigation is handled via HTTP redirects
  // This function is here for API compatibility with browser version
  return path;
}

// Form submission helper - for Node.js, forms are handled via HTTP
export function submitForm(event, handler) {
  // In Node.js context, form submission is handled via HTTP POST
  // This function is here for API compatibility with browser version
  return false;
}

// Extract form data - for Node.js, data comes from request body
export function formData(event) {
  // In Node.js context, form data is parsed in Router.parseBody
  return {};
}

// Handle form result - for Node.js, this is handled in Router.handleResult
export function handleFormResult(result, rerenderFn = null) {
  return false;
}

// Setup form handlers - no-op in Node.js (forms handled via HTTP)
export function setupFormHandlers(config) {
  // Form handlers are handled by Router.dispatch in Node.js
}
