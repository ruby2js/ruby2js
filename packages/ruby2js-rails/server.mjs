#!/usr/bin/env node
// Ruby2JS-on-Rails - Node.js Server Entry Point
//
// This script starts a Node.js HTTP server using the transpiled Rails app.
// It uses the built output from dist/ with the Node.js target runtime.
//
// Usage:
//   DATABASE=better_sqlite3 npm run build  # Build for Node.js
//   node node_modules/ruby2js-rails/server.mjs  # Start server
//
// Or with npm script:
//   npm run start:node
//
// Environment variables:
//   PORT            - HTTP port (default: 3000)
//   DATABASE_URL    - Database connection URL (for pg adapter)

import { join } from 'path';
import { pathToFileURL } from 'url';

// Import Application from the current directory (npm scripts run from dist/)
const routesPath = join(process.cwd(), 'config/routes.js');
const { Application } = await import(pathToFileURL(routesPath).href);

const port = process.env.PORT || 3000;

console.log('Starting Ruby2JS-on-Rails Node.js Server...');
console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);

// Start the application
Application.start(port).catch(err => {
  console.error('Failed to start server:', err);
  process.exit(1);
});
