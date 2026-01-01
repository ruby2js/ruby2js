// Ruby2JS-on-Rails Micro Framework - Cloudflare Workers Target
// Extends server module with Worker fetch handler pattern

import {
  Router as RouterServer,
  Application as ApplicationServer,
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

// Router with Cloudflare-specific redirect handling
export class Router extends RouterServer {
  // Override redirect to use full URL (Cloudflare requires absolute URLs)
  static redirect(context, path) {
    const url = new URL(path, context.request.url);
    const headers = new Headers({ 'Location': url.href });

    // Add flash cookie if there are pending messages
    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers.set('Set-Cookie', flashCookie);
    }

    return new Response(null, { status: 302, headers });
  }

  // Override parseBody to handle multipart/form-data
  static async parseBody(req) {
    const contentType = req.headers.get('content-type') || '';

    try {
      if (contentType.includes('application/json')) {
        return await req.json();
      } else if (contentType.includes('application/x-www-form-urlencoded')) {
        const formData = await req.formData();
        const params = {};
        for (const [key, value] of formData.entries()) {
          params[key] = value;
        }
        return params;
      } else if (contentType.includes('multipart/form-data')) {
        const formData = await req.formData();
        const params = {};
        for (const [key, value] of formData.entries()) {
          // Skip file uploads for now, just get string values
          if (typeof value === 'string') {
            params[key] = value;
          }
        }
        return params;
      }
    } catch (e) {
      console.warn('Failed to parse request body:', e.message);
    }

    return {};
  }

  // Override handleResult to use full URL for redirects
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
      console.log('  Re-rendering form (validation failed)');
      return this.htmlResponse(context, result.render);
    } else {
      return this.redirect(context, defaultRedirect);
    }
  }

  // Override htmlResponse to use the correct Application class
  // (Parent class references its own Application which doesn't have layoutFn set)
  static htmlResponse(context, html) {
    const fullHtml = Application.wrapInLayout(context, html);
    const headers = { 'Content-Type': 'text/html; charset=utf-8' };

    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers['Set-Cookie'] = flashCookie;
    }

    return new Response(fullHtml, { status: 200, headers });
  }
}

// Application with Cloudflare Worker pattern
export class Application extends ApplicationServer {
  static _initialized = false;

  // Initialize the database using the adapter
  // env contains the D1 binding (e.g., env.DB)
  static async initDatabase(env) {
    if (this._initialized) return;

    // Import the adapter (selected at build time)
    const adapter = await import('./active_record.mjs');
    this.activeRecordModule = adapter;

    // Initialize database connection with D1 binding
    await adapter.initDatabase({ binding: env.DB });

    // Run migrations
    await this.runMigrations();

    // Run seeds if present (seeds check internally if data already exists)
    if (this.seeds) {
      await this.seeds.run();
    }

    this._initialized = true;
  }

  // Create the Worker fetch handler
  // Usage in worker entry point:
  //   import { Application, Router } from './lib/rails.js';
  //   export default Application.worker();
  static worker() {
    const app = this;
    return {
      async fetch(request, env, ctx) {
        try {
          // Initialize database on first request
          await app.initDatabase(env);

          // Dispatch the request
          return await Router.dispatch(request);
        } catch (e) {
          console.error('Worker error:', e);
          return new Response(`<h1>500 Internal Server Error</h1><pre>${e.stack}</pre>`, {
            status: 500,
            headers: { 'Content-Type': 'text/html' }
          });
        }
      }
    };
  }
}
