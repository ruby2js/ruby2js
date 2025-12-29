// Ruby2JS-on-Rails Micro Framework - Deno Target
// Extends server module with Deno.serve() startup

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

// Router - use server implementation directly
export class Router extends RouterServer {}

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
