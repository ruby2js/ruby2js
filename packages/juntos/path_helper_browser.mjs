/**
 * Path Helper for Ruby2JS-Rails (Browser Target)
 *
 * Creates callable path helpers with HTTP methods that return Response objects.
 * Used for browser targets where path helpers invoke client-side controllers
 * directly and return synthetic Response objects.
 * Default format is JSON (most common for RBX/React component data fetching).
 *
 * Usage:
 *   articles_path.get()                         // Invoke index action, return JSON
 *   articles_path.get({ page: 2 })              // Invoke index with params
 *   articles_path.post({ title: 'New' })        // Invoke create action
 *   article_path(1).patch({ title: 'Updated' }) // Invoke update action
 *   article_path(1).delete()                    // Invoke destroy action
 *   articles_path.get({ format: 'html' })       // Explicit HTML format
 *
 * Response convenience methods (shorthand for nested .then chains):
 *   articles_path.get().json(data => ...)       // Shorthand for .then(r => r.json().then(...))
 *   articles_path.get().text(html => ...)       // Shorthand for .then(r => r.text().then(...))
 *   articles_path.get().json()                  // Shorthand for .then(r => r.json())
 */

/**
 * PathHelperPromise wraps a Promise<Response> with convenience methods.
 * Provides .json(), .text(), .blob(), .arrayBuffer() that can accept optional callbacks.
 *
 * With callback:  promise.json(data => ...) is shorthand for promise.then(r => r.json().then(data => ...))
 * Without callback: promise.json() is shorthand for promise.then(r => r.json())
 */
class PathHelperPromise {
  constructor(promise) {
    this._promise = promise;
  }

  // Delegate standard Promise methods
  then(onFulfilled, onRejected) {
    return this._promise.then(onFulfilled, onRejected);
  }

  catch(onRejected) {
    return this._promise.catch(onRejected);
  }

  finally(onFinally) {
    return this._promise.finally(onFinally);
  }

  /**
   * Parse response as JSON, optionally passing to callback
   * @param {Function} [callback] - Optional callback to receive parsed JSON
   * @returns {Promise} - Promise resolving to JSON data or callback result
   */
  json(callback) {
    if (callback) {
      return this._promise.then(response => response.json().then(callback));
    }
    return this._promise.then(response => response.json());
  }

  /**
   * Get response as text, optionally passing to callback
   * @param {Function} [callback] - Optional callback to receive text
   * @returns {Promise} - Promise resolving to text or callback result
   */
  text(callback) {
    if (callback) {
      return this._promise.then(response => response.text().then(callback));
    }
    return this._promise.then(response => response.text());
  }

  /**
   * Get response as Blob, optionally passing to callback
   * @param {Function} [callback] - Optional callback to receive Blob
   * @returns {Promise} - Promise resolving to Blob or callback result
   */
  blob(callback) {
    if (callback) {
      return this._promise.then(response => response.blob().then(callback));
    }
    return this._promise.then(response => response.blob());
  }

  /**
   * Get response as ArrayBuffer, optionally passing to callback
   * @param {Function} [callback] - Optional callback to receive ArrayBuffer
   * @returns {Promise} - Promise resolving to ArrayBuffer or callback result
   */
  arrayBuffer(callback) {
    if (callback) {
      return this._promise.then(response => response.arrayBuffer().then(callback));
    }
    return this._promise.then(response => response.arrayBuffer());
  }
}

// Make PathHelperPromise thenable (works with await)
PathHelperPromise.prototype[Symbol.toStringTag] = 'PathHelperPromise';

// Lazy import Router to avoid circular dependency issues
// Router is imported on first use, after all modules are loaded
let Router = null;
let RouterPromise = null;

async function getRouter() {
  if (Router) return Router;
  if (!RouterPromise) {
    RouterPromise = import('juntos/targets/browser/rails.js').then(mod => {
      Router = mod.Router;
      return Router;
    });
  }
  return RouterPromise;
}

/**
 * Initialize path helpers with Router reference (legacy API)
 * Called during application setup
 * @param {Object} router - Router class with match() and route dispatch
 */
export function initPathHelpers(router) {
  Router = router;
}

/**
 * Create a synthetic Response object from controller result
 * @param {any} result - Controller action result
 * @param {string} format - Response format
 * @param {number} status - HTTP status code
 * @returns {Response-like} Object with Response interface
 */
function syntheticResponse(result, format = 'json', status = 200) {
  const body = format === 'json' ? JSON.stringify(result) : String(result ?? '');

  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: status === 200 ? 'OK' : 'Error',
    headers: new Headers({
      'Content-Type': format === 'json' ? 'application/json' : 'text/html'
    }),

    async json() {
      if (format === 'json') {
        return typeof result === 'string' ? JSON.parse(result) : result;
      }
      throw new Error('Response is not JSON');
    },

    async text() {
      return body;
    },

    async blob() {
      return new Blob([body], {
        type: format === 'json' ? 'application/json' : 'text/html'
      });
    },

    async arrayBuffer() {
      const encoder = new TextEncoder();
      return encoder.encode(body).buffer;
    }
  };
}

/**
 * Invoke a controller action based on path and method
 * @param {string} method - HTTP method (GET, POST, etc.)
 * @param {string} path - URL path
 * @param {string} format - Response format
 * @param {Object} params - Request parameters
 * @returns {Promise<Response-like>} Synthetic response
 */
async function invokeController(method, path, format, params) {
  // Lazy load Router on first use
  const router = await getRouter();
  if (!router) {
    throw new Error('Router not available. Ensure browser/rails.js is loaded.');
  }

  // Match the route
  const result = router.match(path, method);

  if (!result) {
    return syntheticResponse({ error: 'Not Found' }, format, 404);
  }

  const { route, match } = result;
  const { controller, action } = route;
  const actionMethod = action === 'new' ? '$new' : action;

  // Build context with params
  const context = {
    params: { ...params, format },
    contentFor: {},
    flash: { notice: null, alert: null }
  };

  try {
    let response;

    // Extract route params (e.g., :id from /articles/:id)
    const id = match[1] ? parseInt(match[1]) : null;

    // Invoke the appropriate controller action
    if (method === 'GET') {
      response = id
        ? await controller[actionMethod](context, id)
        : await controller[actionMethod](context);
    } else if (method === 'POST') {
      response = await controller.create(context, params);
    } else if (method === 'PATCH' || method === 'PUT') {
      response = await controller.update(context, id, params);
    } else if (method === 'DELETE') {
      response = await controller.destroy(context, id);
    }

    // Handle controller response
    if (response && typeof response === 'object') {
      if (response.redirect) {
        // Return redirect info in response
        return syntheticResponse({ redirect: response.redirect }, format, 302);
      }
      if (response.render) {
        // Re-render (validation error) - return the rendered content
        return syntheticResponse(response.render, 'html', 422);
      }
      if (response.json) {
        return syntheticResponse(response.json, 'json', 200);
      }
    }

    return syntheticResponse(response, format, 200);
  } catch (error) {
    console.error(`Controller error [${method} ${path}]:`, error);
    return syntheticResponse({ error: error.message }, format, 500);
  }
}

/**
 * Create a path helper with HTTP methods
 *
 * @param {string} path - The URL path
 * @returns {PathHelper} Object with get/post/put/patch/delete methods
 */
export function createPathHelper(path) {
  const helper = {
    // Preserve string coercion for backward compatibility
    toString() { return path; },
    valueOf() { return path; },

    /**
     * GET request - invokes index/show action
     * @param {Object} params - Query parameters
     * @returns {PathHelperPromise} - Promise with .json(), .text() convenience methods
     */
    get(params = {}) {
      const { format = 'json', ...query } = params;
      return new PathHelperPromise(invokeController('GET', path, format, query));
    },

    /**
     * POST request - invokes create action
     * @param {Object} params - Body parameters
     * @returns {PathHelperPromise} - Promise with .json(), .text() convenience methods
     */
    post(params = {}) {
      const { format = 'json', ...body } = params;
      return new PathHelperPromise(invokeController('POST', path, format, body));
    },

    /**
     * PUT request - invokes update action
     * @param {Object} params - Body parameters
     * @returns {PathHelperPromise} - Promise with .json(), .text() convenience methods
     */
    put(params = {}) {
      const { format = 'json', ...body } = params;
      return new PathHelperPromise(invokeController('PUT', path, format, body));
    },

    /**
     * PATCH request - invokes update action
     * @param {Object} params - Body parameters
     * @returns {PathHelperPromise} - Promise with .json(), .text() convenience methods
     */
    patch(params = {}) {
      const { format = 'json', ...body } = params;
      return new PathHelperPromise(invokeController('PATCH', path, format, body));
    },

    /**
     * DELETE request - invokes destroy action
     * @param {Object} params - Body parameters
     * @returns {PathHelperPromise} - Promise with .json(), .text() convenience methods
     */
    delete(params = {}) {
      const { format = 'json', ...body } = params;
      return new PathHelperPromise(invokeController('DELETE', path, format, body));
    }
  };

  return helper;
}
