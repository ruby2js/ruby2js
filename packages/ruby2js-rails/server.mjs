#!/usr/bin/env node
// Ruby2JS-on-Rails - Node.js Server Entry Point
//
// This script starts a Node.js HTTP server using the transpiled Rails app.
// It uses the built output from dist/ with the Node.js target runtime.
//
// Usage:
//   DATABASE=better_sqlite3 npm run build  # Build for Node.js
//   node dist/index.js  # Start server
//
// Or with npm script:
//   npm run start:node
//
// Environment variables:
//   PORT            - HTTP port (default: 3000)
//   DATABASE_URL    - Database connection URL (for pg adapter)

import { join, dirname } from 'path';
import { pathToFileURL, fileURLToPath } from 'url';

// Import Application from the dist directory (relative to this file)
const __dirname = dirname(fileURLToPath(import.meta.url));
const routesPath = join(__dirname, 'config/routes.js');
const { Application } = await import(pathToFileURL(routesPath).href);

const port = process.env.PORT || 3000;

console.log('Starting Ruby2JS-on-Rails Node.js Server...');
console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);

// Start the application
Application.start(port).catch(err => {
  console.error('Failed to start server:', err);
  process.exit(1);
});
