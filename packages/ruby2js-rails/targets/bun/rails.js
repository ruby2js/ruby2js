// Ruby2JS-on-Rails Micro Framework - Bun Target
// Extends server module with Bun.serve() startup

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

// Application with Bun-specific startup
export class Application extends ApplicationServer {
  // Start the HTTP server using Bun.serve
  static async start(port = null) {
    const listenPort = port || process.env.PORT || 3000;

    try {
      await this.initDatabase();
      console.log('Database initialized');

      const server = Bun.serve({
        port: listenPort,
        async fetch(req) {
          return await Router.dispatch(req);
        }
      });

      console.log(`Server running at http://localhost:${server.port}/`);
      return server;
    } catch (e) {
      console.error('Failed to start server:', e);
      process.exit(1);
    }
  }
}
