#!/usr/bin/env node
// Rails-in-JS Demo - Node.js Server Entry Point
//
// This script starts a Node.js HTTP server using the transpiled Rails demo app.
// It uses the built output from dist/ with the Node.js target runtime.
//
// Usage:
//   DATABASE=better_sqlite3 npm run build  # Build for Node.js
//   node server.mjs                        # Start server
//
// Or with npm script:
//   npm run dev:node
//
// Environment variables:
//   PORT            - HTTP port (default: 3000)
//   DATABASE_URL    - Database connection URL (for pg adapter)

import { Application } from './dist/config/routes.js';

const port = process.env.PORT || 3000;

console.log('Starting Rails-in-JS Node.js Server...');
console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);

// Start the application
Application.start(port).catch(err => {
  console.error('Failed to start server:', err);
  process.exit(1);
});
