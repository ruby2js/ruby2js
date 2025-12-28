// Ruby2JS-on-Rails Micro Framework - Cloudflare Workers Target
// Extends server module with Worker fetch handler pattern

import {
  Router as RouterServer,
  Application as ApplicationServer,
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
export { truncate, pluralize, dom_id, navigate, submitForm, formData, handleFormResult, setupFormHandlers };

// Router with Cloudflare-specific redirect handling
export class Router extends RouterServer {
  // Override redirect to use full URL (Cloudflare requires absolute URLs)
  static redirect(req, path) {
    return Response.redirect(new URL(path, req.url), 302);
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
  static handleResult(req, result, defaultRedirect) {
    if (result.redirect) {
      console.log(`  Redirected to ${result.redirect}`);
      return Response.redirect(new URL(result.redirect, req.url), 302);
    } else if (result.render) {
      console.log('  Re-rendering form (validation failed)');
      return this.htmlResponse(result.render);
    } else {
      return Response.redirect(new URL(defaultRedirect, req.url), 302);
    }
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

    // Run schema migrations
    if (this.schema && this.schema.create_tables) {
      await this.schema.create_tables();
    }

    // Run seeds if present (typically only in development)
    if (this.seeds && env.RUN_SEEDS) {
      if (this.seeds.run.constructor.name === 'AsyncFunction') {
        await this.seeds.run();
      } else {
        this.seeds.run();
      }
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
