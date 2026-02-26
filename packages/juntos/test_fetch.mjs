// Fetch interceptor for Juntos test runtime
//
// Overrides globalThis.fetch to route HTTP calls through RouterBase.match(),
// enabling Stimulus controllers and Turbo to reach controller actions
// in jsdom tests without a real server.
//
// Usage:
//   import { installFetchInterceptor } from 'juntos/test_fetch.mjs';
//   installFetchInterceptor();
//
//   // Now fetch() calls from Stimulus controllers route to controller actions:
//   fetch('/messages', { method: 'POST', body: formData })
//   // → RouterBase.match('/messages', 'POST') → MessagesController.create(context, params)

import { RouterBase, createFlash } from 'juntos/rails_base.js';

let _originalFetch = null;

/**
 * Install the fetch interceptor.
 * Overrides globalThis.fetch to route requests through RouterBase.
 * Calls that don't match any route fall through to the original fetch
 * (or throw if no original fetch exists).
 */
export function installFetchInterceptor() {
  if (_originalFetch) return; // already installed
  _originalFetch = globalThis.fetch;

  globalThis.fetch = async (input, init = {}) => {
    const url = new URL(
      typeof input === 'string' ? input : input.url,
      'http://localhost'
    );
    const method = (init.method || 'GET').toUpperCase();
    const path = url.pathname;

    const result = RouterBase.match(path, method);
    if (!result) {
      // No matching route — fall through to original fetch or error
      if (_originalFetch) return _originalFetch(input, init);
      throw new Error(`No route matches ${method} ${path}`);
    }

    const { route, match } = result;
    const context = {
      params: {},
      flash: createFlash(),
      contentFor: {},
      request: { headers: { accept: init.headers?.accept || 'text/html' } }
    };

    // Extract params from request body
    const params = extractParams(init.body);

    // Build action args: context, [parentId], [id], [params]
    const args = [context];
    if (route.nested && match[1]) args.push(parseInt(match[1]));
    const idIndex = route.nested ? 2 : 1;
    if (match[idIndex]) args.push(parseInt(match[idIndex]));
    if (params && ['create', 'update'].includes(route.action)) args.push(params);

    const actionName = route.action === 'new' ? '$new' : route.action;
    const action = route.controller[actionName];
    if (!action) {
      return new Response(`Action ${route.action} not found on controller`, { status: 500 });
    }

    try {
      const controllerResult = await action(...args);
      return buildResponse(controllerResult, context);
    } catch (error) {
      return new Response(error.message, { status: 500 });
    }
  };
}

/**
 * Uninstall the fetch interceptor, restoring the original fetch.
 */
export function uninstallFetchInterceptor() {
  if (_originalFetch) {
    globalThis.fetch = _originalFetch;
    _originalFetch = null;
  }
}

/**
 * Extract params from a request body.
 * Handles FormData, URLSearchParams, JSON strings, and plain objects.
 */
function extractParams(body) {
  if (!body) return null;

  if (typeof FormData !== 'undefined' && body instanceof FormData) {
    const params = {};
    for (const [key, value] of body.entries()) {
      // Handle Rails-style nested params: message[body] → { message: { body: value } }
      const nested = key.match(/^(\w+)\[(\w+)\]$/);
      if (nested) {
        if (!params[nested[1]]) params[nested[1]] = {};
        params[nested[1]][nested[2]] = value;
      } else {
        params[key] = value;
      }
    }
    return params;
  }

  if (typeof URLSearchParams !== 'undefined' && body instanceof URLSearchParams) {
    const params = {};
    for (const [key, value] of body.entries()) {
      const nested = key.match(/^(\w+)\[(\w+)\]$/);
      if (nested) {
        if (!params[nested[1]]) params[nested[1]] = {};
        params[nested[1]][nested[2]] = value;
      } else {
        params[key] = value;
      }
    }
    return params;
  }

  if (typeof body === 'string') {
    try {
      return JSON.parse(body);
    } catch {
      // Try as URL-encoded form data
      const params = {};
      for (const [key, value] of new URLSearchParams(body).entries()) {
        const nested = key.match(/^(\w+)\[(\w+)\]$/);
        if (nested) {
          if (!params[nested[1]]) params[nested[1]] = {};
          params[nested[1]][nested[2]] = value;
        } else {
          params[key] = value;
        }
      }
      return Object.keys(params).length > 0 ? params : null;
    }
  }

  if (typeof body === 'object') return body;

  return null;
}

/**
 * Wrap a controller result in a Response object.
 * Handles the same result types as testing.mjs executeRequest():
 * - string → HTML response (200)
 * - { redirect } → redirect response (302)
 * - { render } → HTML response (200)
 * - { json } → JSON response (200)
 * - { turbo_stream } → Turbo Stream response (200)
 */
function buildResponse(result, context) {
  const headers = new Headers();

  // Set flash cookie if flash has pending messages
  if (context.flash?.hasPending?.()) {
    const cookie = context.flash.getResponseCookie();
    if (cookie) headers.set('Set-Cookie', cookie);
  }

  if (typeof result === 'string') {
    headers.set('Content-Type', 'text/html');
    return new Response(result, { status: 200, headers });
  }

  if (result && typeof result === 'object') {
    if (result.redirect) {
      headers.set('Location', String(result.redirect));
      // Include notice in response for flash handling
      const body = result.notice ? JSON.stringify({ notice: result.notice }) : '';
      return new Response(body, { status: 302, headers });
    }

    if (result.render) {
      headers.set('Content-Type', 'text/html');
      return new Response(result.render, { status: result.status || 200, headers });
    }

    if (result.json) {
      headers.set('Content-Type', 'application/json');
      return new Response(JSON.stringify(result.json), { status: 200, headers });
    }

    if (result.turbo_stream) {
      headers.set('Content-Type', 'text/vnd.turbo-stream.html');
      return new Response(result.turbo_stream, { status: 200, headers });
    }
  }

  // Default: treat as HTML
  headers.set('Content-Type', 'text/html');
  return new Response(result || '', { status: 200, headers });
}
