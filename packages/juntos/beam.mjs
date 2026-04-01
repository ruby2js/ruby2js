// Ruby2JS-on-Rails - BEAM (QuickBEAM) Entry Point
//
// This script is the JS entry point loaded by QuickBEAM.
// It initializes the application and exposes the request handler
// as a global function for the Elixir host to call.
//
// Usage:
//   juntos build -d sqlite_napi -t beam
//   cd dist && mix deps.get && mix run --no-halt

// Import Application from the routes (registers all routes and models)
// Use a variable to prevent Vite from resolving the dynamic import at build time
const routesPath = ['./config', 'routes.js'].join('/');
const { Application, initDatabase } = await import(routesPath);

// Initialize database
const dbPath = globalThis.__JUNTOS_DB_PATH || 'blog.db';
await initDatabase({ database: dbPath });
console.log(`Database initialized: ${dbPath}`);

// Expose the handler globally for the Elixir host to call
globalThis.handler = Application.handler();
console.log('Juntos BEAM application ready');
