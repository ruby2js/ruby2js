// Test setup for Vitest
// Initializes the database before each test

import { beforeAll, beforeEach } from 'vitest';

beforeAll(async () => {
  // Import models (registers them with Application and modelRegistry)
  await import('juntos:models');

  // Configure migrations
  const rails = await import('juntos:rails');
  const migrations = await import('juntos:migrations');
  rails.Application.configure({ migrations: migrations.migrations });
});

beforeEach(async () => {
  // Fresh in-memory database for each test
  const activeRecord = await import('juntos:active-record');
  await activeRecord.initDatabase({ database: ':memory:' });

  const rails = await import('juntos:rails');
  await rails.Application.runMigrations(activeRecord);
});
