// Main entry point for ejected Node.js server
import { Application, Router } from 'ruby2js-rails/targets/node/rails.js';
import * as activeRecord from 'ruby2js-rails/adapters/active_record_better_sqlite3.mjs';

// Import models (registers them)
import './app/models/index.js';

// Import migrations and seeds
import { migrations } from './db/migrate/index.js';
import { Seeds } from './db/seeds.js';

// Import routes (sets up the router)
import './config/routes.js';

async function main() {
  // Configure application
  Application.configure({ migrations });

  // Initialize database
  console.log('Initializing database...');
  await activeRecord.initDatabase({ adapter: 'better_sqlite3', database: './db/development.sqlite3' });

  // Run migrations
  console.log('Running migrations...');
  await Application.runMigrations(activeRecord);

  // Run seeds if database is fresh
  if (Seeds && typeof Seeds.run === 'function') {
    console.log('Running seeds...');
    await Seeds.run();
  }

  // Start server
  const port = process.env.PORT || 3000;
  console.log(`Starting server on http://localhost:${port}`);

  // Create HTTP server with Router dispatch
  const { createServer } = await import('http');
  const server = createServer(async (req, res) => {
    await Router.dispatch(req, res);
  });

  server.listen(port);
}

main().catch(console.error);
