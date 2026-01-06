#!/usr/bin/env node
// Standalone migration runner for serverless deployment
// Run this during build/deploy to initialize the database schema
//
// Usage: node migrate.mjs [options]
//
// Options:
//   --migrate-only  Run only migrations (no seeds)
//   --seed-only     Run only seeds (no migrations)
//   (default)       Run migrations, then seeds if database was fresh
//
// Environment variables:
//   DATABASE_URL - Database connection URL (required for most adapters)
//   TURSO_URL, TURSO_TOKEN - For Turso adapter
//   NEON_DATABASE_URL - For Neon adapter
//   PLANETSCALE_URL - For PlanetScale adapter
//   JUNTOS_MIGRATE_VIA_PG - Use direct Postgres connection for migrations (for Supabase)

import { pathToFileURL } from 'url';
import path from 'path';
import fs from 'fs';

// Direct Postgres adapter for migrations (used by Supabase)
// Supabase's PostgREST doesn't support DDL, so we use pg directly for schema changes
async function createPgMigrationAdapter() {
  const pg = await import('pg');
  const client = new pg.default.Client(process.env.DATABASE_URL);
  await client.connect();

  return {
    query: async (sql, params = []) => {
      const result = await client.query(sql, params);
      return result.rows;
    },
    execute: async (sql, params = []) => {
      await client.query(sql, params);
      return { changes: 0 };
    },
    insert: async (table, data) => {
      const keys = Object.keys(data);
      const values = Object.values(data);
      const placeholders = keys.map((_, i) => `$${i + 1}`).join(', ');
      await client.query(
        `INSERT INTO ${table} (${keys.join(', ')}) VALUES (${placeholders})`,
        values
      );
    },
    closeDatabase: async () => {
      await client.end();
    }
  };
}

async function main() {
  const args = process.argv.slice(2);
  const migrateOnly = args.includes('--migrate-only');
  const seedOnly = args.includes('--seed-only');

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

    // Choose adapter based on mode:
    // - JUNTOS_MIGRATE_VIA_PG: Use direct Postgres for migrations (Supabase)
    // - Otherwise: Use the app's configured adapter
    const usePgForMigrations = process.env.JUNTOS_MIGRATE_VIA_PG === '1';

    let adapter;
    let migrationAdapter;

    if (usePgForMigrations) {
      console.log('Using direct Postgres connection for migrations...');
      migrationAdapter = await createPgMigrationAdapter();

      // For seeds, still use the app's adapter (Supabase PostgREST)
      if (!migrateOnly) {
        const adapterPath = pathToFileURL(path.join(appRoot, 'lib/active_record.mjs')).href;
        adapter = await import(adapterPath);
        await adapter.initDatabase();
      }
    } else {
      // Import the active_record adapter
      const adapterPath = pathToFileURL(path.join(appRoot, 'lib/active_record.mjs')).href;
      adapter = await import(adapterPath);
      migrationAdapter = adapter;

      // Initialize the database connection
      console.log('Initializing database connection...');
      await adapter.initDatabase();
    }

    // Run migrations and track if database was fresh
    let wasFresh = true;

    if (!seedOnly) {
      if (Application.migrations && Application.migrations.length > 0) {
        console.log(`Found ${Application.migrations.length} migration(s)\n`);

        // Get already-run migrations
        let appliedVersions = new Set();
        try {
          const applied = await migrationAdapter.query('SELECT version FROM schema_migrations');
          appliedVersions = new Set(applied.map(r => r.version));
          wasFresh = appliedVersions.size === 0;
          console.log(`Already applied: ${appliedVersions.size} migration(s)`);
        } catch (e) {
          // Table doesn't exist - create it (fresh database)
          console.log('Creating schema_migrations table...');
          await migrationAdapter.execute('CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY)');
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
            await migration.up(migrationAdapter);
            await migrationAdapter.insert('schema_migrations', { version: migration.version });
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
    }

    // Run seeds based on mode
    if (!migrateOnly && Application.seeds) {
      if (seedOnly) {
        // Explicit seed-only mode: always run seeds
        console.log('\nRunning seeds...');
        await Application.seeds.run();
        console.log('Seeds completed');
      } else if (wasFresh) {
        // Default mode: only seed fresh databases
        console.log('\nRunning seeds (fresh database)...');
        await Application.seeds.run();
        console.log('Seeds completed');
      } else {
        console.log('\nSkipping seeds (existing database)');
      }
    }

    // Close database connections
    if (migrationAdapter && migrationAdapter.closeDatabase) {
      await migrationAdapter.closeDatabase();
    }
    if (adapter && adapter !== migrationAdapter && adapter.closeDatabase) {
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
