// Test setup for Vitest - ejected version
import { beforeAll, beforeEach } from 'vitest';

beforeAll(async () => {
  // Import models (registers them with Application and modelRegistry)
  await import('../app/models/index.js');

  // Configure migrations
  const { Application } = await import('ruby2js-rails/targets/node/rails.js');
  const { migrations } = await import('../db/migrate/index.js');
  Application.configure({ migrations });
});

beforeEach(async () => {
  // Fresh in-memory database for each test
  const activeRecord = await import('ruby2js-rails/adapters/active_record_better_sqlite3.mjs');
  await activeRecord.initDatabase({ database: ':memory:' });

  const { Application } = await import('ruby2js-rails/targets/node/rails.js');
  await Application.runMigrations(activeRecord);
});
