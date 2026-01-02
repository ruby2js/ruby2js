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
  setupFormHandlers
} from './rails_server.js';

// Re-export everything from server module
export { createContext, createFlash, truncate, pluralize, dom_id, navigate, submitForm, formData, handleFormResult, setupFormHandlers };

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
    if (result.redirect) {
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
      console.log('  Re-rendering form (validation failed)');
      this.sendHtml(context, res, result.render);
    } else {
      this.redirectNode(context, res, defaultRedirect);
    }
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
  static sendHtml(context, res, html) {
    const fullHtml = Application.wrapInLayout(context, html);
    const headers = { 'Content-Type': 'text/html; charset=utf-8' };

    // Clear flash cookie after it's been consumed
    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers['Set-Cookie'] = flashCookie;
    }

    res.writeHead(200, headers);
    res.end(fullHtml);
  }
}

// Application with Node.js-specific startup
export class Application extends ApplicationServer {
  // Start the HTTP server using http.createServer
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
