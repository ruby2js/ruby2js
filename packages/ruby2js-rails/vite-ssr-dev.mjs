#!/usr/bin/env node
// Vite SSR Development Server for Ruby2JS-on-Rails
//
// Uses Vite in middleware mode for instant server-side updates.
// Changes to Ruby files are reflected immediately without rebuilding.
//
// Usage:
//   node node_modules/ruby2js-rails/vite-ssr-dev.mjs
//
// Or via juntos CLI:
//   juntos dev --vite --target node

import { createServer } from 'http';
import { createServer as createViteServer } from 'vite';
import { join } from 'path';

const port = process.env.PORT || 3000;
const appRoot = process.env.JUNTOS_APP_ROOT || join(process.cwd(), '..');

async function startServer() {
  // Create Vite server in middleware mode
  const vite = await createViteServer({
    server: { middlewareMode: true },
    appType: 'custom',
    root: process.cwd(),
    configFile: join(process.cwd(), 'vite.config.js')
  });

  // Create HTTP server
  const server = createServer(async (req, res) => {
    try {
      // Let Vite handle static assets and HMR
      const handled = await new Promise((resolve) => {
        vite.middlewares(req, res, () => resolve(false));
        // If middleware calls next(), it wasn't handled
        // We need to check if response was sent
        res.on('finish', () => resolve(true));
      });

      if (res.writableEnded) return;

      // Load Application fresh on each request (instant updates)
      const routesPath = join(process.cwd(), 'config/routes.js');
      const { Application } = await vite.ssrLoadModule(routesPath);

      // Handle the request with the Rails-like application
      await Application.handleRequest(req, res);

    } catch (error) {
      // Vite-style error overlay
      vite.ssrFixStacktrace(error);
      console.error(error);

      if (!res.headersSent) {
        res.statusCode = 500;
        res.setHeader('Content-Type', 'text/html');
        res.end(`
          <!DOCTYPE html>
          <html>
            <head><title>Server Error</title></head>
            <body>
              <h1>Server Error</h1>
              <pre style="background: #f0f0f0; padding: 1em; overflow: auto;">${escapeHtml(error.stack || error.message)}</pre>
            </body>
          </html>
        `);
      }
    }
  });

  server.listen(port, () => {
    console.log('');
    console.log('\x1b[1m=== Ruby2JS-on-Rails Vite SSR Dev Server ===\x1b[0m');
    console.log('');
    console.log(`  \x1b[32m➜\x1b[0m  Local:   http://localhost:${port}/`);
    console.log(`  \x1b[36m➜\x1b[0m  Mode:    SSR with Vite middleware`);
    console.log(`  \x1b[35m➜\x1b[0m  HMR:     Enabled (ssrLoadModule)`);
    console.log('');
    console.log('Server-side changes are instant. No rebuild required.');
    console.log('Press Ctrl+C to stop');
    console.log('');
  });

  // Graceful shutdown
  process.on('SIGINT', async () => {
    console.log('\n\x1b[33m[shutdown]\x1b[0m Stopping server...');
    await vite.close();
    server.close();
    process.exit(0);
  });
}

function escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

startServer().catch(err => {
  console.error('Failed to start Vite SSR dev server:', err);
  process.exit(1);
});
