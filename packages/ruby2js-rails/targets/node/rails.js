// Ruby2JS-on-Rails Micro Framework - Node.js Target
// Extends server module with Node http.createServer() startup
// Uses Node's http module instead of Fetch API for request/response

import http from 'node:http';
import { parse as parseUrl } from 'node:url';
import { StringDecoder } from 'node:string_decoder';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

import {
  Router as RouterServer,
  Application as ApplicationServer,
  MIME_TYPES,
  extractNestedKey,
  createContext,
  createFlash,
  truncate,
  pluralize,
  dom_id,
  navigate,
  submitForm,
  formData,
  handleFormResult,
  setupFormHandlers,
  TurboBroadcast
} from './rails_server.js';

import { createRPCHandler, getRegistry, csrfMetaTag } from 'ruby2js-rails/rpc/server.mjs';

// RPC handler instance (initialized when models are registered)
let rpcHandler = null;

// Re-export everything from server module
export { createContext, createFlash, truncate, pluralize, dom_id, navigate, submitForm, formData, handleFormResult, setupFormHandlers };

// Re-export RPC utilities for layout integration
export { csrfMetaTag, getRegistry as getRPCRegistry };

// Re-export TurboBroadcast and alias as BroadcastChannel for model compatibility
export { TurboBroadcast, TurboBroadcast as BroadcastChannel };

// Set global BroadcastChannel for ActiveRecord broadcast methods
globalThis.BroadcastChannel = TurboBroadcast;

// Router with Node.js-specific dispatch (uses req/res instead of Fetch API)
export class Router extends RouterServer {
  // Try to serve a static file, returns true if served
  // Node.js uses req/res objects, so we need a separate implementation
  static async serveStatic(req, res) {
    const parsedUrl = parseUrl(req.url, true);
    const path = parsedUrl.pathname;

    // Security: prevent directory traversal
    if (path.includes('..')) {
      return false;
    }

    // Only serve files with extensions (not routes like /articles/1)
    const lastDot = path.lastIndexOf('.');
    if (lastDot === -1) {
      return false;
    }

    const ext = path.slice(lastDot);
    const contentType = MIME_TYPES[ext];
    if (!contentType) {
      return false;
    }

    try {
      const content = await readFile(join(process.cwd(), path));
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(content);
      return true;
    } catch (err) {
      // Try public/ subdirectory (Rails convention for static assets)
      try {
        const content = await readFile(join(process.cwd(), 'public', path));
        res.writeHead(200, { 'Content-Type': contentType });
        res.end(content);
        return true;
      } catch {
        // File not found, let routing handle it
        return false;
      }
    }
  }

  // Create context from Node.js request (different cookie access than Fetch API)
  static createContextNode(req, params) {
    const parsedUrl = parseUrl(req.url, true);
    // Node.js uses req.headers.cookie (string) vs Fetch API's req.headers.get('cookie')
    const cookieHeader = req.headers.cookie || '';

    return {
      contentFor: {},
      flash: createFlash(cookieHeader),  // Use shared flash creation
      params: params,
      request: {
        path: parsedUrl.pathname,
        method: req.method,
        url: req.url,
        headers: req.headers
      }
    };
  }

  // Dispatch an HTTP request to the appropriate controller action
  // Node.js version using req/res objects
  static async dispatch(req, res) {
    // Try static files first (CSS, JS, images, etc.)
    if (await this.serveStatic(req, res)) {
      return;
    }

    // Handle RPC requests (model operations from browser)
    if (rpcHandler && req.headers['x-rpc-action']) {
      const handled = await rpcHandler(req, res);
      if (handled) return;
    }

    const parsedUrl = parseUrl(req.url, true);
    const path = parsedUrl.pathname;
    let method = this.normalizeMethodNode(req, parsedUrl);
    let params = {};

    // Parse request body for POST requests (may contain _method override)
    if (req.method === 'POST') {
      params = await this.parseBodyNode(req);
      if (params._method) {
        method = params._method.toUpperCase();
        delete params._method;
      }
    } else if (['PATCH', 'PUT', 'DELETE'].includes(method)) {
      params = await this.parseBodyNode(req);
    }

    // Create request context
    const context = this.createContextNode(req, params);

    console.log(`Started ${method} "${path}"`);
    if (Object.keys(params).length > 0) {
      console.log('  Parameters:', params);
    }

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

      if (route.nested) {
        const parentId = parseInt(match[1]);
        const id = match[2] ? parseInt(match[2]) : null;

        if (method === 'POST') {
          const result = await controller.create(context, parentId, params);
          return this.handleResultNode(context, res, result, `/${route.parentName}/${parentId}`);
        } else if (method === 'PATCH') {
          const result = await controller.update(context, parentId, id, params);
          return this.handleResultNode(context, res, result, `/${route.parentName}/${parentId}`);
        } else if (method === 'DELETE') {
          await controller.destroy(context, parentId, id);
          this.redirectNode(context, res, `/${route.parentName}/${parentId}`);
          return;
        } else {
          html = id ? await controller[actionMethod](context, parentId, id) : await controller[actionMethod](context, parentId);
        }
      } else {
        const id = match[1] ? parseInt(match[1]) : null;

        if (method === 'POST') {
          const result = await controller.create(context, params);
          return this.handleResultNode(context, res, result, `/${controllerName}`);
        } else if (method === 'PATCH') {
          const result = await controller.update(context, id, params);
          return this.handleResultNode(context, res, result, `/${controllerName}/${id}`);
        } else if (method === 'DELETE') {
          await controller.destroy(context, id);
          this.redirectNode(context, res, `/${controllerName}`);
          return;
        } else {
          html = id ? await controller[actionMethod](context, id) : await controller[actionMethod](context);
        }
      }

      console.log(`  Rendering ${controllerName}/${action}`);
      this.sendHtml(context, res, html);
    } catch (e) {
      console.error('  Error:', e.message || e);
      res.writeHead(500, { 'Content-Type': 'text/html' });
      res.end(`<h1>500 Internal Server Error</h1><pre>${e.stack}</pre>`);
    }
  }

  // Normalize HTTP method for Node.js
  static normalizeMethodNode(req, parsedUrl) {
    let method = req.method.toUpperCase();
    if (parsedUrl.query._method) {
      method = parsedUrl.query._method.toUpperCase();
    }
    return method;
  }

  // Parse request body for Node.js (using StringDecoder)
  static parseBodyNode(req) {
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
              const decodedKey = decodeURIComponent(key.replace(/\+/g, ' '));
              params[extractNestedKey(decodedKey)] =
                decodeURIComponent((value || '').replace(/\+/g, ' '));
            }
          }
          resolve(params);
        }
      });

      req.on('error', reject);
    });
  }

  // Handle controller result for Node.js
  static handleResultNode(context, res, result, defaultRedirect) {
    if (result.turbo_stream) {
      // Turbo Stream response - return with proper content type
      console.log('  Rendering turbo_stream response');
      this.sendTurboStream(context, res, result.turbo_stream);
    } else if (result.redirect) {
      // Set flash notice if present in result
      if (result.notice) {
        context.flash.set('notice', result.notice);
      }
      if (result.alert) {
        context.flash.set('alert', result.alert);
      }
      console.log(`  Redirected to ${result.redirect}`);
      this.redirectNode(context, res, result.redirect);
    } else if (result.render) {
      // Return 422 Unprocessable Entity so Turbo Drive renders the response
      console.log('  Re-rendering form (validation failed)');
      this.sendHtml(context, res, result.render, 422);
    } else {
      this.redirectNode(context, res, defaultRedirect);
    }
  }

  // Send Turbo Stream response with proper content type
  static sendTurboStream(context, res, html) {
    const headers = { 'Content-Type': 'text/vnd.turbo-stream.html; charset=utf-8' };

    // Clear flash cookie after it's been consumed
    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers['Set-Cookie'] = flashCookie;
    }

    res.writeHead(200, headers);
    res.end(html);
  }

  // Redirect with flash cookie
  static redirectNode(context, res, path) {
    const headers = { 'Location': path };

    // Add flash cookie if there are pending messages
    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers['Set-Cookie'] = flashCookie;
    }

    res.writeHead(302, headers);
    res.end();
  }

  // Send HTML response with proper headers, wrapped in layout
  static sendHtml(context, res, html, status = 200) {
    const fullHtml = Application.wrapInLayout(context, html);
    const headers = { 'Content-Type': 'text/html; charset=utf-8' };

    // Clear flash cookie after it's been consumed
    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers['Set-Cookie'] = flashCookie;
    }

    res.writeHead(status, headers);
    res.end(fullHtml);
  }
}

// Application with Node.js-specific startup
export class Application extends ApplicationServer {
  static wsServer = null;

  // Register models with RPC registry for remote model operations
  // Call this after registering models to enable RPC access
  static registerModelsForRPC(models) {
    const registry = getRegistry();
    for (const [name, Model] of Object.entries(models)) {
      registry.registerModel(name, Model);
      console.log(`  Registered RPC handlers for ${name}`);
    }
    // Initialize RPC handler after models are registered
    rpcHandler = createRPCHandler({ registry });
    console.log('RPC handler initialized');
  }

  // Start the HTTP server using http.createServer
  // Includes WebSocket support for Turbo Streams broadcasting
  static async start(port = null) {
    const listenPort = port || process.env.PORT || 3000;

    try {
      await this.initDatabase();
      console.log('Database initialized');

      const server = http.createServer(async (req, res) => {
        await Router.dispatch(req, res);
      });

      // Set up WebSocket server for Turbo Streams
      await this.setupWebSocket(server);

      server.listen(listenPort, () => {
        console.log(`Server running at http://localhost:${listenPort}/`);
        if (this.wsServer) {
          console.log(`WebSocket available at ws://localhost:${listenPort}/cable`);
        }
      });

      return server;
    } catch (e) {
      console.error('Failed to start server:', e);
      process.exit(1);
    }
  }

  // Set up WebSocket server for Turbo Streams broadcasting
  static async setupWebSocket(server) {
    try {
      // Dynamically import ws package (optional dependency)
      const { WebSocketServer } = await import('ws');

      this.wsServer = new WebSocketServer({ noServer: true });

      // Handle WebSocket connections
      this.wsServer.on('connection', (ws, req) => {
        console.log('WebSocket connected');

        ws.on('message', (data) => {
          TurboBroadcast.handleMessage(ws, data.toString());
        });

        ws.on('close', () => {
          TurboBroadcast.cleanup(ws);
          console.log('WebSocket disconnected');
        });

        ws.on('error', (err) => {
          console.error('WebSocket error:', err);
          TurboBroadcast.cleanup(ws);
        });
      });

      // Handle upgrade requests for /cable path
      server.on('upgrade', (req, socket, head) => {
        const url = parseUrl(req.url, true);

        if (url.pathname === '/cable') {
          this.wsServer.handleUpgrade(req, socket, head, (ws) => {
            this.wsServer.emit('connection', ws, req);
          });
        } else {
          socket.destroy();
        }
      });

      console.log('WebSocket server initialized');
    } catch (e) {
      // ws package not installed - WebSocket disabled
      console.log('WebSocket disabled (ws package not installed)');
    }
  }
}
