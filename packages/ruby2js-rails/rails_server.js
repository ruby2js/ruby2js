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

import { getCSRF } from './rpc/server.mjs';

// Lazy-loaded ReactDOMServer for rendering React elements
// Only imported when needed (apps with RBX/JSX views)
let ReactDOMServer = null;
async function getReactDOMServer() {
  if (!ReactDOMServer) {
    ReactDOMServer = await import('react-dom/server');
  }
  return ReactDOMServer;
}

// Resolve view content to HTML string
// Handles: strings, Promises, and React elements
// Exported for use by target-specific htmlResponse overrides
export async function resolveContent(content) {
  // Await if content is a promise (async ERB or async React component)
  const resolved = await Promise.resolve(content);

  // Convert to HTML string based on type
  if (typeof resolved === 'string') {
    return resolved;
  } else {
    // React element - render to string
    const ReactDOMServer = await getReactDOMServer();
    return ReactDOMServer.renderToString(resolved);
  }
}

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

// Extract nested Rails-style param key: article[title] -> title
// Exported for use by target-specific parseBody implementations
export function extractNestedKey(key) {
  const match = key.match(/\[([^\]]+)\]$/);
  return match ? match[1] : key;
}

// Create a fresh request context (like Rails' view context)
// Each request gets its own context with isolated state
// For Fetch API requests (Bun, Deno, Cloudflare, rails_server.js)
export function createContext(req, params = {}) {
  const url = parseRequestUrl(req);
  const cookieHeader = getHeader(req, 'cookie') || '';

  // Convert headers to plain object for property access (controllers use headers.accept, not headers.get('accept'))
  // This works with both Fetch API Headers and Node.js plain object headers
  const headers = {};
  if (typeof req.headers.get === 'function') {
    // Fetch API Headers - extract common headers
    headers.accept = req.headers.get('accept') || '';
    headers.contentType = req.headers.get('content-type') || '';
    headers.cookie = req.headers.get('cookie') || '';
  } else {
    // Plain object (Node.js style)
    headers.accept = req.headers.accept || req.headers['accept'] || '';
    headers.contentType = req.headers['content-type'] || '';
    headers.cookie = req.headers.cookie || '';
  }

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
      headers: headers
    },

    // CSRF token for form authenticity
    authenticityToken: getCSRF().generateToken()
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

    // Validate CSRF token for mutating requests
    if (['POST', 'PATCH', 'PUT', 'DELETE'].includes(method)) {
      const token = getHeader(req, 'x-csrf-token') || params.authenticity_token;
      const csrf = getCSRF();
      if (!csrf.validateToken(token)) {
        console.warn('  CSRF token invalid');
        return new Response('<h1>422 Invalid Authenticity Token</h1>', {
          status: 422,
          headers: { 'Content-Type': 'text/html' }
        });
      }
      // Remove token from params so it doesn't pollute controller params
      delete params.authenticity_token;
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
          const decodedKey = decodeURIComponent(key.replace(/\+/g, ' '));
          params[extractNestedKey(decodedKey)] =
            decodeURIComponent((value || '').replace(/\+/g, ' '));
        }
      }
      return params;
    }
  }

  // Handle controller result (redirect, render, or turbo_stream)
  static async handleResult(context, result, defaultRedirect) {
    if (result.turbo_stream) {
      // Turbo Stream response - return with proper content type
      console.log('  Rendering turbo_stream response');
      return this.turboStreamResponse(context, result.turbo_stream);
    } else if (result.redirect) {
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
      // Return 422 Unprocessable Entity so Turbo Drive renders the response
      console.log('  Re-rendering form (validation failed)');
      return await this.htmlResponse(context, result.render, 422);
    } else {
      return this.redirect(context, defaultRedirect);
    }
  }

  // Create Turbo Stream response with proper content type
  static turboStreamResponse(context, html) {
    const headers = { 'Content-Type': 'text/vnd.turbo-stream.html; charset=utf-8' };

    // Clear flash cookie after it's been consumed
    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers['Set-Cookie'] = flashCookie;
    }

    return new Response(html, {
      status: 200,
      headers
    });
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
  // Handles both sync and async views, and both string and React element returns
  static async htmlResponse(context, content, status = 200) {
    const html = await resolveContent(content);
    const fullHtml = Application.wrapInLayout(context, html);
    const headers = { 'Content-Type': 'text/html; charset=utf-8' };

    // Clear flash cookie after it's been consumed
    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers['Set-Cookie'] = flashCookie;
    }

    return new Response(fullHtml, {
      status,
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

// Turbo Streams Broadcasting for server targets
// Manages WebSocket connections and channel subscriptions
// Platform-specific targets provide the WebSocket server, this handles the protocol
//
// Implements Action Cable protocol for compatibility with @hotwired/turbo-rails:
// - Client sends: {"command":"subscribe","identifier":"{\"channel\":\"Turbo::StreamsChannel\",\"signed_stream_name\":\"...\"}"}
// - Server sends: {"type":"confirm_subscription","identifier":"..."}
// - Server broadcasts: {"identifier":"...","message":"<turbo-stream>...</turbo-stream>"}
//
// The signed_stream_name is base64-encoded JSON of the stream name. We decode it
// but don't verify the signature (no shared secret needed for our use case).
export class TurboBroadcast {
  // Map of channel name -> Set of WebSocket connections
  static channels = new Map();

  // Map of WebSocket -> Set of channel names (for cleanup on disconnect)
  static subscriptions = new Map();

  // Map of WebSocket -> Map of channel name -> identifier string (for Action Cable responses)
  static identifiers = new Map();

  // Decode Action Cable signed_stream_name to get the actual stream name
  // Format: base64(JSON.stringify(streamName)) + "--" + signature
  // We ignore the signature since we're not verifying it
  static decodeStreamName(signedName) {
    // Remove signature if present (everything after --)
    const base64Part = signedName.split('--')[0];
    try {
      // Decode base64 and parse JSON
      const decoded = atob(base64Part);
      return JSON.parse(decoded);
    } catch (e) {
      // If decoding fails, use as-is (might be plain stream name)
      return signedName;
    }
  }

  // Create an Action Cable identifier for a stream name
  static createIdentifier(streamName) {
    const signedName = btoa(JSON.stringify(streamName));
    return JSON.stringify({
      channel: 'Turbo::StreamsChannel',
      signed_stream_name: signedName
    });
  }

  // Send welcome message when client connects
  static sendWelcome(ws) {
    try {
      ws.send(JSON.stringify({ type: 'welcome' }));
    } catch (e) {
      // Ignore send errors
    }
  }

  // Subscribe a WebSocket to a channel
  // Called by handleMessage when client sends subscribe command
  static subscribe(ws, channel, identifier) {
    // Add to channel's subscriber set
    if (!this.channels.has(channel)) {
      this.channels.set(channel, new Set());
    }
    this.channels.get(channel).add(ws);

    // Track subscription for this WebSocket
    if (!this.subscriptions.has(ws)) {
      this.subscriptions.set(ws, new Set());
    }
    this.subscriptions.get(ws).add(channel);

    // Store the identifier for this channel (needed for broadcast messages)
    if (!this.identifiers.has(ws)) {
      this.identifiers.set(ws, new Map());
    }
    this.identifiers.get(ws).set(channel, identifier);

    console.log(`  Subscribed to channel: ${channel}`);

    // Send confirmation (Action Cable protocol)
    try {
      ws.send(JSON.stringify({
        type: 'confirm_subscription',
        identifier: identifier
      }));
    } catch (e) {
      // Ignore send errors
    }
  }

  // Unsubscribe a WebSocket from a channel
  static unsubscribe(ws, channel) {
    const subscribers = this.channels.get(channel);
    if (subscribers) {
      subscribers.delete(ws);
      if (subscribers.size === 0) {
        this.channels.delete(channel);
      }
    }

    const wsChannels = this.subscriptions.get(ws);
    if (wsChannels) {
      wsChannels.delete(channel);
    }

    const wsIdentifiers = this.identifiers.get(ws);
    if (wsIdentifiers) {
      wsIdentifiers.delete(channel);
    }

    console.log(`  Unsubscribed from channel: ${channel}`);
  }

  // Clean up all subscriptions for a WebSocket (on disconnect)
  static cleanup(ws) {
    const wsChannels = this.subscriptions.get(ws);
    if (wsChannels) {
      for (const channel of wsChannels) {
        const subscribers = this.channels.get(channel);
        if (subscribers) {
          subscribers.delete(ws);
          if (subscribers.size === 0) {
            this.channels.delete(channel);
          }
        }
      }
      this.subscriptions.delete(ws);
    }
    this.identifiers.delete(ws);
  }

  // Broadcast a turbo-stream message to all subscribers of a channel
  // Called by model broadcast_*_to methods
  // Uses Action Cable message format for compatibility with @hotwired/turbo-rails
  static broadcast(channel, html) {
    const subscribers = this.channels.get(channel);
    if (!subscribers || subscribers.size === 0) {
      return;
    }

    console.log(`  Broadcasting to ${channel} (${subscribers.size} subscribers)`);

    for (const ws of subscribers) {
      try {
        // Get the identifier this client used when subscribing
        const wsIdentifiers = this.identifiers.get(ws);
        const identifier = wsIdentifiers?.get(channel) || this.createIdentifier(channel);

        // Action Cable message format
        const message = JSON.stringify({
          identifier: identifier,
          message: html
        });

        ws.send(message);
      } catch (e) {
        // Connection may have closed, clean up
        this.cleanup(ws);
      }
    }
  }

  // Handle incoming WebSocket message
  // Supports both Action Cable protocol and our legacy simple protocol
  static handleMessage(ws, data) {
    try {
      const msg = typeof data === 'string' ? JSON.parse(data) : data;

      // Action Cable protocol uses "command" field
      if (msg.command) {
        switch (msg.command) {
          case 'subscribe': {
            // Parse the identifier to get the stream name
            const identifierObj = JSON.parse(msg.identifier);
            const streamName = this.decodeStreamName(identifierObj.signed_stream_name);
            this.subscribe(ws, streamName, msg.identifier);
            break;
          }
          case 'unsubscribe': {
            const identifierObj = JSON.parse(msg.identifier);
            const streamName = this.decodeStreamName(identifierObj.signed_stream_name);
            this.unsubscribe(ws, streamName);
            break;
          }
          case 'message':
            // Client-to-server messages - not used for Turbo Streams (server->client only)
            break;
        }
        return;
      }

      // Legacy simple protocol (for backwards compatibility)
      switch (msg.type) {
        case 'subscribe':
          // Simple format: { type: 'subscribe', stream: 'articles' }
          this.subscribe(ws, msg.stream, this.createIdentifier(msg.stream));
          break;
        case 'unsubscribe':
          this.unsubscribe(ws, msg.stream);
          break;
        case 'ping':
          ws.send(JSON.stringify({ type: 'pong' }));
          break;
      }
    } catch (e) {
      console.error('TurboBroadcast message error:', e);
    }
  }
}

// Export BroadcastChannel as alias for model broadcast methods (server-side)
// Models call: BroadcastChannel.broadcast("channel", html)
export { TurboBroadcast as BroadcastChannel };

// Helper function for views to subscribe to turbo streams
// Renders a <turbo-cable-stream-source> element that turbo-rails JavaScript picks up
// The turbo-rails JS sees this element and subscribes via Action Cable WebSocket
// Usage in ERB: <%= turbo_stream_from "chat_room" %>
export function turbo_stream_from(streamName) {
  // Create signed_stream_name in same format as Rails (base64-encoded JSON)
  // We omit the HMAC signature since our server doesn't verify it
  const signedName = btoa(JSON.stringify(streamName));
  return `<turbo-cable-stream-source channel="Turbo::StreamsChannel" signed-stream-name="${signedName}"></turbo-cable-stream-source>`;
}
