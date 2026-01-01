#!/usr/bin/env node
// Standalone migration runner for serverless deployment
// Run this during build/deploy to initialize the database schema
//
// Usage: node migrate.mjs
//
// Seeds automatically run on fresh databases (no prior migrations).
// This matches the behavior of browser and Node.js targets.
//
// Environment variables:
//   DATABASE_URL - Database connection URL (required for most adapters)
//   TURSO_URL, TURSO_TOKEN - For Turso adapter
//   NEON_DATABASE_URL - For Neon adapter
//   PLANETSCALE_URL - For PlanetScale adapter

import { pathToFileURL } from 'url';
import path from 'path';
import fs from 'fs';

async function main() {
  console.log('Ruby2JS Migration Runner');
  console.log('========================\n');

  // Find the application root (where config/routes.js exists)
  let appRoot = process.cwd();

  // Check if we're in dist/ or the app root
  if (!fs.existsSync(path.join(appRoot, 'config/routes.js'))) {
    if (fs.existsSync(path.join(appRoot, 'dist/config/routes.js'))) {
      appRoot = path.join(appRoot, 'dist');
    } else {
      console.error('Error: Cannot find config/routes.js');
      console.error('Run this from your app root or dist/ directory');
      process.exit(1);
    }
  }

  console.log(`App root: ${appRoot}\n`);

  try {
    // Import the routes module which sets up Application
    const routesPath = pathToFileURL(path.join(appRoot, 'config/routes.js')).href;
    const { Application } = await import(routesPath);

    // Import the active_record adapter
    const adapterPath = pathToFileURL(path.join(appRoot, 'lib/active_record.mjs')).href;
    const adapter = await import(adapterPath);

    // Initialize the database connection
    console.log('Initializing database connection...');
    await adapter.initDatabase();

    // Run migrations and track if database was fresh
    let wasFresh = true;

    if (Application.migrations && Application.migrations.length > 0) {
      console.log(`Found ${Application.migrations.length} migration(s)\n`);

      // Get already-run migrations
      let appliedVersions = new Set();
      try {
        const applied = await adapter.query('SELECT version FROM schema_migrations');
        appliedVersions = new Set(applied.map(r => r.version));
        wasFresh = appliedVersions.size === 0;
        console.log(`Already applied: ${appliedVersions.size} migration(s)`);
      } catch (e) {
        // Table doesn't exist - create it (fresh database)
        console.log('Creating schema_migrations table...');
        await adapter.execute('CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY)');
        wasFresh = true;
      }

      // Run pending migrations
      let ran = 0;
      for (const migration of Application.migrations) {
        if (appliedVersions.has(migration.version)) {
          continue;
        }

        console.log(`Running migration ${migration.version}...`);
        try {
          await migration.up();
          await adapter.insert('schema_migrations', { version: migration.version });
          ran++;
          console.log(`  ✓ Completed`);
        } catch (e) {
          console.error(`  ✗ Failed: ${e.message}`);
          throw e;
        }
      }

      if (ran > 0) {
        console.log(`\nRan ${ran} migration(s) successfully`);
      } else {
        console.log('\nNo pending migrations');
      }
    } else {
      // Legacy: use schema if no migrations
      if (Application.schema && Application.schema.create_tables) {
        console.log('Running schema creation (legacy mode)...');
        await Application.schema.create_tables();
        console.log('Schema created');
      } else {
        console.log('No migrations or schema found');
      }
    }

    // Run seeds only on fresh database (matches browser/Node.js behavior)
    if (wasFresh && Application.seeds) {
      console.log('\nRunning seeds (fresh database)...');
      await Application.seeds.run();
      console.log('Seeds completed');
    } else if (Application.seeds) {
      console.log('\nSkipping seeds (existing database)');
    }

    // Close database connection
    if (adapter.closeDatabase) {
      await adapter.closeDatabase();
    }

    console.log('\n✓ Migration complete');
    process.exit(0);
  } catch (error) {
    console.error('\n✗ Migration failed:', error.message);
    if (process.env.DEBUG) {
      console.error(error.stack);
    }
    process.exit(1);
  }
}

main();
