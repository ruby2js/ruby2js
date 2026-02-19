// Ruby2JS-on-Rails Micro Framework - Deno Target
// Extends server module with Deno.serve() startup
// Includes native WebSocket support for Turbo Streams broadcasting

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
  setupFormHandlers,
  TurboBroadcast,
  turbo_stream_from,
  stylesheetLinkTag,
  getAssetPath
} from 'juntos/rails_server.js';

// Re-export everything from server module
export { createContext, createFlash, truncate, pluralize, dom_id, navigate, submitForm, formData, handleFormResult, setupFormHandlers, turbo_stream_from, stylesheetLinkTag, getAssetPath };

// Re-export TurboBroadcast and alias as BroadcastChannel for model compatibility
export { TurboBroadcast, TurboBroadcast as BroadcastChannel };

// Router with Deno-specific static file serving
export class Router extends RouterServer {
  // Override dispatch to serve static files first
  static async dispatch(req) {
    const fileInfo = this.getStaticFileInfo(req);
    if (fileInfo) {
      // Try multiple locations for static files:
      // 1. dist/ directory (server runs from project root, assets in dist/)
      // 2. Current directory (when running directly from dist/)
      // 3. public/ subdirectory (Rails convention)
      const searchPaths = [
        join(Deno.cwd(), 'dist', fileInfo.path),
        join(Deno.cwd(), fileInfo.path),
        join(Deno.cwd(), 'dist', 'public', fileInfo.path),
        join(Deno.cwd(), 'public', fileInfo.path)
      ];

      for (const filePath of searchPaths) {
        try {
          const content = await Deno.readFile(filePath);
          return new Response(content, {
            headers: { 'Content-Type': fileInfo.contentType }
          });
        } catch {
          // Continue to next path
        }
      }
    }
    return super.dispatch(req);
  }
}

// Application with Deno-specific startup
export class Application extends ApplicationServer {
  // Start the HTTP server using Deno.serve
  // Includes native WebSocket support for Turbo Streams broadcasting
  static async start(port = null) {
    const listenPort = port || Number(Deno.env.get("PORT")) || 3000;

    try {
      await this.initDatabase();
      console.log('Database initialized');

      const server = Deno.serve({ port: listenPort }, async (req) => {
        const url = new URL(req.url);

        // Handle WebSocket upgrade for /cable path
        if (url.pathname === '/cable') {
          if (req.headers.get('upgrade') === 'websocket') {
            const { socket, response } = Deno.upgradeWebSocket(req);

            socket.onopen = () => {
              console.log('WebSocket connected');
              // Send Action Cable welcome message
              TurboBroadcast.sendWelcome(socket);
            };

            socket.onmessage = (event) => {
              TurboBroadcast.handleMessage(socket, event.data);
            };

            socket.onclose = () => {
              TurboBroadcast.cleanup(socket);
              console.log('WebSocket disconnected');
            };

            socket.onerror = (error) => {
              console.error('WebSocket error:', error);
              TurboBroadcast.cleanup(socket);
            };

            return response;
          }
          return new Response('WebSocket upgrade required', { status: 400 });
        }

        return await Router.dispatch(req);
      });

      console.log(`Server running at http://localhost:${listenPort}/`);
      console.log(`WebSocket available at ws://localhost:${listenPort}/cable`);
      return server;
    } catch (e) {
      console.error('Failed to start server:', e);
      Deno.exit(1);
    }
  }
}
