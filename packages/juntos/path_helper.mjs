/**
 * Path Helper for Ruby2JS-Rails (Server Target)
 *
 * Creates callable path helpers with HTTP methods that return Response objects.
 * Used for server targets where path helpers make fetch() calls to the server.
 * Default format is JSON (most common for RBX/React component data fetching).
 *
 * Usage:
 *   articles_path.get()                         // GET /articles.json
 *   articles_path.get({ page: 2 })              // GET /articles.json?page=2
 *   articles_path.post({ title: 'New' })        // POST /articles.json with JSON body
 *   article_path(1).patch({ title: 'Updated' }) // PATCH /articles/1.json with JSON body
 *   article_path(1).delete()                    // DELETE /articles/1.json
 *   articles_path.get({ format: 'html' })       // GET /articles.html (explicit HTML)
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

/**
 * Get CSRF token from meta tag
 * @returns {string|null} Token value or null if not found
 */
function getCSRFToken() {
  if (typeof document === 'undefined') return null;
  return document.querySelector('meta[name="csrf-token"]')?.content;
}

/**
 * Build URL with format extension and query string
 * @param {string} path - Base path
 * @param {string} format - Format extension (json, html, turbo_stream) - defaults to 'json'
 * @param {Object} query - Query parameters for GET requests
 * @returns {string} Complete URL
 */
function buildUrl(path, format = 'json', query = {}) {
  let url = path;

  // Append format extension
  url += `.${format}`;

  // Append query string
  const entries = Object.entries(query).filter(([_, v]) => v != null);
  if (entries.length > 0) {
    const queryString = new URLSearchParams(entries).toString();
    url += `?${queryString}`;
  }

  return url;
}

/**
 * Get Accept header value for format
 * @param {string|undefined} format - Format name (defaults to 'json')
 * @returns {string} Accept header value
 */
function acceptHeader(format = 'json') {
  switch (format) {
    case 'json': return 'application/json';
    case 'turbo_stream': return 'text/vnd.turbo-stream.html';
    case 'html': return 'text/html';
    default: return 'application/json';
  }
}

/**
 * Make a mutating request (POST/PUT/PATCH/DELETE)
 * @param {string} method - HTTP method
 * @param {string} path - URL path
 * @param {Object} params - Parameters (format extracted, rest becomes body)
 * @returns {Promise<Response>} Fetch response
 */
async function mutatingRequest(method, path, params) {
  const { format, ...body } = params;
  const url = buildUrl(path, format);

  const headers = {
    'Content-Type': 'application/json',
    'Accept': acceptHeader(format)
  };

  const token = getCSRFToken();
  if (token) {
    headers['X-Authenticity-Token'] = token;
  }

  return fetch(url, {
    method,
    headers,
    credentials: 'same-origin',
    body: Object.keys(body).length > 0 ? JSON.stringify(body) : undefined
  });
}

/**
 * Create a path helper with HTTP methods
 *
 * @param {string} path - The URL path
 * @returns {PathHelper} Object with get/post/put/patch/delete methods
 *
 * @example
 * const helper = createPathHelper('/articles');
 * await helper.get({ format: 'json' });
 * await helper.post({ article: { title: 'New' } });
 */
export function createPathHelper(path) {
  const helper = {
    // Preserve string coercion for backward compatibility
    // Allows: <a href={articles_path}> and `${articles_path}`
    toString() { return path; },
    valueOf() { return path; },

    /**
     * GET request - params become query string
     * @param {Object} params - Query parameters (format is special)
     * @returns {PathHelperPromise} - Promise with .json(), .text() convenience methods
     */
    get(params = {}) {
      const { format, ...query } = params;
      const url = buildUrl(path, format, query);
      const promise = fetch(url, {
        method: 'GET',
        headers: { 'Accept': acceptHeader(format) },
        credentials: 'same-origin'
      });
      return new PathHelperPromise(promise);
    },

    /**
     * POST request - params become JSON body
     * @param {Object} params - Body parameters (format is special)
     * @returns {PathHelperPromise} - Promise with .json(), .text() convenience methods
     */
    post(params = {}) {
      return new PathHelperPromise(mutatingRequest('POST', path, params));
    },

    /**
     * PUT request - params become JSON body
     * @param {Object} params - Body parameters (format is special)
     * @returns {PathHelperPromise} - Promise with .json(), .text() convenience methods
     */
    put(params = {}) {
      return new PathHelperPromise(mutatingRequest('PUT', path, params));
    },

    /**
     * PATCH request - params become JSON body
     * @param {Object} params - Body parameters (format is special)
     * @returns {PathHelperPromise} - Promise with .json(), .text() convenience methods
     */
    patch(params = {}) {
      return new PathHelperPromise(mutatingRequest('PATCH', path, params));
    },

    /**
     * DELETE request - params become JSON body
     * @param {Object} params - Body parameters (format is special)
     * @returns {PathHelperPromise} - Promise with .json(), .text() convenience methods
     */
    delete(params = {}) {
      return new PathHelperPromise(mutatingRequest('DELETE', path, params));
    }
  };

  return helper;
}
