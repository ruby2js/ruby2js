// Ruby2JS-on-Rails Micro Framework - Deno Target
// Extends server module with Deno.serve() startup

import { join } from 'node:path';

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

// Router with Deno-specific static file serving
export class Router extends RouterServer {
  // Override dispatch to serve static files first
  static async dispatch(req) {
    const fileInfo = this.getStaticFileInfo(req);
    if (fileInfo) {
      try {
        const content = await Deno.readFile(join(Deno.cwd(), fileInfo.path));
        return new Response(content, {
          headers: { 'Content-Type': fileInfo.contentType }
        });
      } catch (err) {
        // File not found, fall through to routing
      }
    }
    return super.dispatch(req);
  }
}

// Application with Deno-specific startup
export class Application extends ApplicationServer {
  // Start the HTTP server using Deno.serve
  static async start(port = null) {
    const listenPort = port || Number(Deno.env.get("PORT")) || 3000;

    try {
      await this.initDatabase();
      console.log('Database initialized');

      const server = Deno.serve({ port: listenPort }, async (req) => {
        return await Router.dispatch(req);
      });

      console.log(`Server running at http://localhost:${listenPort}/`);
      return server;
    } catch (e) {
      console.error('Failed to start server:', e);
      Deno.exit(1);
    }
  }
}
