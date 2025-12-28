// Ruby2JS-on-Rails Micro Framework - Server Module
// Shared HTTP dispatch logic for server targets (Node, Bun, Deno, Cloudflare)
// Uses Fetch API Request/Response where possible

import {
  RouterBase,
  ApplicationBase,
  truncate,
  pluralize,
  dom_id,
  navigate,
  submitForm,
  formData,
  handleFormResult,
  setupFormHandlers
} from './rails_base.js';

// Re-export base helpers
export { truncate, pluralize, dom_id, navigate, submitForm, formData, handleFormResult, setupFormHandlers };

// Server Router with HTTP dispatch
export class Router extends RouterBase {
  // Dispatch a Fetch API request to the appropriate controller action
  // Returns a Response object
  static async dispatch(req) {
    const url = new URL(req.url);
    const path = url.pathname;
    let method = this.normalizeMethod(req, url);
    let params = {};

    // Parse request body for POST requests (may contain _method override)
    if (req.method === 'POST') {
      params = await this.parseBody(req);
      // Check for _method override in body (Rails convention for PATCH/DELETE)
      if (params._method) {
        method = params._method.toUpperCase();
        delete params._method;
      }
    } else if (['PATCH', 'PUT', 'DELETE'].includes(method)) {
      params = await this.parseBody(req);
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
      return this.redirect(req, route.redirect);
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
          return this.handleResult(req, result, `/${route.parentName}/${parentId}`);
        } else if (method === 'PATCH') {
          const result = await controller.update(parentId, id, params);
          return this.handleResult(req, result, `/${route.parentName}/${parentId}`);
        } else if (method === 'DELETE') {
          await controller.destroy(parentId, id);
          return this.redirect(req, `/${route.parentName}/${parentId}`);
        } else {
          html = id ? await controller[actionMethod](parentId, id) : await controller[actionMethod](parentId);
        }
      } else {
        const id = match[1] ? parseInt(match[1]) : null;

        if (method === 'POST') {
          const result = await controller.create(params);
          return this.handleResult(req, result, `/${controllerName}`);
        } else if (method === 'PATCH') {
          const result = await controller.update(id, params);
          return this.handleResult(req, result, `/${controllerName}/${id}`);
        } else if (method === 'DELETE') {
          await controller.destroy(id);
          return this.redirect(req, `/${controllerName}`);
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
      // Note: + represents space in form data, must replace before decodeURIComponent
      const params = {};
      const pairs = text.split('&');
      for (const pair of pairs) {
        const [key, value] = pair.split('=');
        if (key) {
          params[decodeURIComponent(key.replace(/\+/g, ' '))] =
            decodeURIComponent((value || '').replace(/\+/g, ' '));
        }
      }
      return params;
    }
  }

  // Handle controller result (redirect or render)
  static handleResult(req, result, defaultRedirect) {
    if (result.redirect) {
      console.log(`  Redirected to ${result.redirect}`);
      return this.redirect(req, result.redirect);
    } else if (result.render) {
      // Validation failed - render contains pre-rendered HTML from the view
      console.log('  Re-rendering form (validation failed)');
      return this.htmlResponse(result.render);
    } else {
      return this.redirect(req, defaultRedirect);
    }
  }

  // Create redirect response - can be overridden by subclasses
  static redirect(req, path) {
    return Response.redirect(path, 302);
  }

  // Create HTML response with proper headers, wrapped in layout
  static htmlResponse(html) {
    const fullHtml = Application.wrapInLayout(html);
    return new Response(fullHtml, {
      status: 200,
      headers: { 'Content-Type': 'text/html; charset=utf-8' }
    });
  }
}

// Server Application base class
export class Application extends ApplicationBase {
  // Server targets can override this to customize startup
  static async start(port = 3000) {
    throw new Error('Application.start() must be implemented by runtime-specific target');
  }
}
