// Ruby2JS-on-Rails Micro Framework - Server Module
// Shared HTTP dispatch logic for server targets (Node, Bun, Deno, Cloudflare)
// Uses Fetch API Request/Response where possible

import {
  RouterBase,
  ApplicationBase,
  createFlash,
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
export { createFlash, truncate, pluralize, dom_id, navigate, submitForm, formData, handleFormResult, setupFormHandlers };

// MIME types for static file serving (shared across all server targets)
export const MIME_TYPES = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.map': 'application/json'
};

// Parse URL from request - handles both full URLs and path-only (Vercel Node.js)
function parseRequestUrl(req) {
  if (req.url.startsWith('http')) {
    return new URL(req.url);
  }
  // Handle both Fetch API Headers (.get) and Node.js headers (plain object)
  const host = typeof req.headers.get === 'function'
    ? req.headers.get('host')
    : req.headers.host || req.headers['host'];
  return new URL(req.url, `https://${host || 'localhost'}`);
}

// Get header value - works with both Fetch API and Node.js request objects
function getHeader(req, name) {
  if (typeof req.headers.get === 'function') {
    return req.headers.get(name);
  }
  return req.headers[name.toLowerCase()];
}

// Create a fresh request context (like Rails' view context)
// Each request gets its own context with isolated state
// For Fetch API requests (Bun, Deno, Cloudflare, rails_server.js)
export function createContext(req, params = {}) {
  const url = parseRequestUrl(req);
  const cookieHeader = getHeader(req, 'cookie') || '';

  return {
    // Content for layout (like Rails content_for)
    contentFor: {},

    // Flash messages - parsed from request cookie
    flash: createFlash(cookieHeader),

    // Request parameters (from URL and body)
    params: params,

    // Request info
    request: {
      path: url.pathname,
      method: req.method,
      url: url.href,  // Full URL for redirect base
      headers: req.headers
    }
  };
}

// Server Router with HTTP dispatch
export class Router extends RouterBase {
  // Check if request is for a static file. Returns { path, contentType } or null.
  // Used by runtime-specific targets to serve static files.
  static getStaticFileInfo(req) {
    const url = parseRequestUrl(req);
    const path = url.pathname;

    // Security: prevent directory traversal
    if (path.includes('..')) {
      return null;
    }

    // Only serve files with extensions (not routes like /articles/1)
    const lastDot = path.lastIndexOf('.');
    if (lastDot === -1) {
      return null;
    }

    const ext = path.slice(lastDot);
    const contentType = MIME_TYPES[ext];
    if (!contentType) {
      return null;
    }

    return { path, contentType };
  }

  // Dispatch a Fetch API request to the appropriate controller action
  // Returns a Response object
  static async dispatch(req) {
    const url = parseRequestUrl(req);
    // Normalize path: remove trailing slash (except for root)
    let path = url.pathname;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.slice(0, -1);
    }
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

    // Create request context with flash, params, etc.
    const context = createContext(req, params);

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
      return this.redirect(context, route.redirect);
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
          const result = await controller.create(context, parentId, params);
          return this.handleResult(context, result, `/${route.parentName}/${parentId}`);
        } else if (method === 'PATCH') {
          const result = await controller.update(context, parentId, id, params);
          return this.handleResult(context, result, `/${route.parentName}/${parentId}`);
        } else if (method === 'DELETE') {
          await controller.destroy(context, parentId, id);
          return this.redirect(context, `/${route.parentName}/${parentId}`);
        } else {
          html = id ? await controller[actionMethod](context, parentId, id) : await controller[actionMethod](context, parentId);
        }
      } else {
        const id = match[1] ? parseInt(match[1]) : null;

        if (method === 'POST') {
          const result = await controller.create(context, params);
          return this.handleResult(context, result, `/${controllerName}`);
        } else if (method === 'PATCH') {
          const result = await controller.update(context, id, params);
          return this.handleResult(context, result, `/${controllerName}/${id}`);
        } else if (method === 'DELETE') {
          await controller.destroy(context, id);
          return this.redirect(context, `/${controllerName}`);
        } else {
          html = id ? await controller[actionMethod](context, id) : await controller[actionMethod](context);
        }
      }

      console.log(`  Rendering ${controllerName}/${action}`);
      return this.htmlResponse(context, html);
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
  static handleResult(context, result, defaultRedirect) {
    if (result.redirect) {
      // Set flash notice if present in result
      if (result.notice) {
        context.flash.set('notice', result.notice);
      }
      if (result.alert) {
        context.flash.set('alert', result.alert);
      }
      console.log(`  Redirected to ${result.redirect}`);
      return this.redirect(context, result.redirect);
    } else if (result.render) {
      // Validation failed - render contains pre-rendered HTML from the view
      console.log('  Re-rendering form (validation failed)');
      return this.htmlResponse(context, result.render);
    } else {
      return this.redirect(context, defaultRedirect);
    }
  }

  // Create redirect response with flash cookie
  static redirect(context, path) {
    const headers = new Headers({ 'Location': path });

    // Add flash cookie if there are pending messages
    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers.set('Set-Cookie', flashCookie);
    }

    return new Response(null, {
      status: 302,
      headers
    });
  }

  // Create HTML response with proper headers, wrapped in layout
  static htmlResponse(context, html) {
    const fullHtml = Application.wrapInLayout(context, html);
    const headers = { 'Content-Type': 'text/html; charset=utf-8' };

    // Clear flash cookie after it's been consumed
    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers['Set-Cookie'] = flashCookie;
    }

    return new Response(fullHtml, {
      status: 200,
      headers
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
