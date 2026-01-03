// Ruby2JS-on-Rails Micro Framework - Bun Target
// Extends server module with Bun.serve() startup
// Includes native WebSocket support for Turbo Streams broadcasting

import { join } from 'path';

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
  setupFormHandlers,
  TurboBroadcast
} from './rails_server.js';

// Re-export everything from server module
export { createContext, createFlash, truncate, pluralize, dom_id, navigate, submitForm, formData, handleFormResult, setupFormHandlers };

// Re-export TurboBroadcast and alias as BroadcastChannel for model compatibility
export { TurboBroadcast, TurboBroadcast as BroadcastChannel };

// Router with Bun-specific static file serving
export class Router extends RouterServer {
  // Override dispatch to serve static files first
  static async dispatch(req) {
    const fileInfo = this.getStaticFileInfo(req);
    if (fileInfo) {
      try {
        const file = Bun.file(join(process.cwd(), fileInfo.path));
        if (await file.exists()) {
          return new Response(file, {
            headers: { 'Content-Type': fileInfo.contentType }
          });
        }
      } catch (err) {
        // File not found, fall through to routing
      }
    }
    return super.dispatch(req);
  }
}

// Application with Bun-specific startup
export class Application extends ApplicationServer {
  // Start the HTTP server using Bun.serve
  // Includes native WebSocket support for Turbo Streams broadcasting
  static async start(port = null) {
    const listenPort = port || process.env.PORT || 3000;

    try {
      await this.initDatabase();
      console.log('Database initialized');

      const server = Bun.serve({
        port: listenPort,

        // Handle HTTP requests
        async fetch(req, server) {
          const url = new URL(req.url);

          // Handle WebSocket upgrade for /cable path
          if (url.pathname === '/cable') {
            const upgraded = server.upgrade(req);
            if (upgraded) {
              return undefined; // Bun handles the response
            }
            return new Response('WebSocket upgrade failed', { status: 400 });
          }

          return await Router.dispatch(req);
        },

        // WebSocket handlers for Turbo Streams
        websocket: {
          open(ws) {
            console.log('WebSocket connected');
          },

          message(ws, data) {
            TurboBroadcast.handleMessage(ws, data.toString());
          },

          close(ws) {
            TurboBroadcast.cleanup(ws);
            console.log('WebSocket disconnected');
          },

          error(ws, error) {
            console.error('WebSocket error:', error);
            TurboBroadcast.cleanup(ws);
          }
        }
      });

      console.log(`Server running at http://localhost:${server.port}/`);
      console.log(`WebSocket available at ws://localhost:${server.port}/cable`);
      return server;
    } catch (e) {
      console.error('Failed to start server:', e);
      process.exit(1);
    }
  }
}
