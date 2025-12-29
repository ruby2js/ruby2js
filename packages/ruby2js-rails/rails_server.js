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

// Flash messages - cookie-based like Rails
// Messages are set before redirect, read on next request, then cleared
export const flash = {
  _pending: {},   // Messages to be set in response cookie
  _current: {},   // Messages read from request cookie

  // Set a flash message (will be sent in response cookie)
  set(key, value) {
    this._pending[key] = value;
  },

  // Get and consume a flash message
  get(key) {
    const msg = this._current[key];
    delete this._current[key];
    return msg || '';
  },

  // Convenience methods
  consumeNotice() { return this.get('notice'); },
  consumeAlert() { return this.get('alert'); },

  // Parse flash from request cookies
  parseFromRequest(req) {
    this._current = {};
    this._pending = {};

    const cookieHeader = req.headers.get('cookie') || '';
    const cookies = cookieHeader.split(';').map(c => c.trim());

    for (const cookie of cookies) {
      if (cookie.startsWith('_flash=')) {
        try {
          const value = cookie.substring(7);
          this._current = JSON.parse(decodeURIComponent(value));
        } catch (e) {
          // Invalid flash cookie, ignore
        }
        break;
      }
    }
  },

  // Get cookie header for response (if there are pending messages)
  getResponseCookie() {
    if (Object.keys(this._pending).length === 0) {
      // Clear the flash cookie if no pending messages
      if (Object.keys(this._current).length > 0) {
        return '_flash=; Path=/; Max-Age=0';
      }
      return null;
    }

    const value = encodeURIComponent(JSON.stringify(this._pending));
    return `_flash=${value}; Path=/; HttpOnly; SameSite=Lax`;
  },

  // Check if there are pending messages
  hasPending() {
    return Object.keys(this._pending).length > 0;
  }
};

// Server Router with HTTP dispatch
export class Router extends RouterBase {
  // Dispatch a Fetch API request to the appropriate controller action
  // Returns a Response object
  static async dispatch(req) {
    const url = new URL(req.url);
    const path = url.pathname;
    let method = this.normalizeMethod(req, url);
    let params = {};

    // Parse flash messages from request cookie
    flash.parseFromRequest(req);

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
      // Set flash notice if present in result
      if (result.notice) {
        flash.set('notice', result.notice);
      }
      if (result.alert) {
        flash.set('alert', result.alert);
      }
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

  // Create redirect response with flash cookie
  static redirect(req, path) {
    const headers = new Headers({ 'Location': path });

    // Add flash cookie if there are pending messages
    const flashCookie = flash.getResponseCookie();
    if (flashCookie) {
      headers.set('Set-Cookie', flashCookie);
    }

    return new Response(null, {
      status: 302,
      headers
    });
  }

  // Create HTML response with proper headers, wrapped in layout
  static htmlResponse(html) {
    const fullHtml = Application.wrapInLayout(html);
    const headers = { 'Content-Type': 'text/html; charset=utf-8' };

    // Clear flash cookie after it's been consumed
    const flashCookie = flash.getResponseCookie();
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
