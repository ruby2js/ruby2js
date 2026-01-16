#!/usr/bin/env node
// Standalone test for notes demo - runs directly with Node.js
// This bypasses Vitest to verify the demo code works

import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { existsSync } from 'fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEMO_DIR = join(__dirname, '../../demo/notes');
const DIST_DIR = join(DEMO_DIR, 'dist');

if (!existsSync(join(DIST_DIR, 'lib/active_record.mjs'))) {
  console.error('Notes demo dist not found. Build with: JUNTOS_DATABASE=better_sqlite3 bundle exec juntos build');
  process.exit(1);
}

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    passed++;
    console.log(`  ✓ ${message}`);
  } else {
    failed++;
    console.log(`  ✗ ${message}`);
  }
}

async function runTests() {
  console.log('Loading modules...');

  // Import modules
  const activeRecord = await import(join(DIST_DIR, 'lib/active_record.mjs'));
  const { initDatabase, modelRegistry } = activeRecord;

  const rails = await import(join(DIST_DIR, 'lib/rails.js'));
  const { Application } = rails;

  const migrationsModule = await import(join(DIST_DIR, 'db/migrate/index.js'));
  const { migrations } = migrationsModule;

  const models = await import(join(DIST_DIR, 'app/models/index.js'));
  const { Note } = models;

  const notesCtrl = await import(join(DIST_DIR, 'app/controllers/notes_controller.js'));
  const { NotesController } = notesCtrl;

  const paths = await import(join(DIST_DIR, 'config/paths.js'));
  const { notes_path, note_path } = paths;

  // Configure Application
  Application.configure({ migrations });
  Application.registerModels({ Note });
  modelRegistry.Note = Note;

  // Initialize database
  await initDatabase({ database: ':memory:' });

  // Run migrations
  const adapter = await import(join(DIST_DIR, 'lib/active_record.mjs'));
  console.log('Running migrations...');
  console.log('Migrations to run:', migrations);
  console.log('Adapter methods:', Object.keys(adapter));
  await Application.runMigrations(adapter);
  console.log('Migrations complete.');

  // Debug: check tables
  const db = adapter.getDatabase();
  const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all();
  console.log('Tables after migration:', tables);

  console.log('\n--- Note Model Tests ---');

  // Test 1: Create note
  const note1 = await Note.create({
    title: 'Test Note',
    body: 'This is a test note body.'
  });
  assert(note1.id > 0, 'creates a note with valid attributes');
  assert(note1.title === 'Test Note', 'note has correct title');

  // Test 2: Validate title presence
  const invalidNote = new Note({ title: '', body: 'Valid body' });
  const saved = await invalidNote.save();
  assert(saved === false, 'validates title presence');
  assert(invalidNote.errors && invalidNote.errors.title, 'has title error');

  // Test 3: Find by id
  const found = await Note.find(note1.id);
  assert(found.title === 'Test Note', 'finds note by id');

  // Test 4: Update
  await note1.update({ title: 'Updated Title' });
  const reloaded = await Note.find(note1.id);
  assert(reloaded.title === 'Updated Title', 'updates a note');

  // Test 5: Destroy
  const toDelete = await Note.create({ title: 'To Delete', body: 'Will be deleted' });
  const deleteId = toDelete.id;
  await toDelete.destroy();
  const deleted = await Note.findBy({ id: deleteId });
  assert(deleted === null, 'destroys a note');

  console.log('\n--- Path Helper Tests ---');

  assert(String(notes_path()) === '/notes', 'notes_path returns correct path');
  const pathNote = await Note.create({ title: 'Path Test', body: 'Testing path' });
  assert(String(note_path(pathNote)) === `/notes/${pathNote.id}`, 'note_path returns correct path');

  console.log('\n--- Controller Tests ---');

  const createContext = (overrides = {}) => ({
    params: {},
    flash: {
      get: () => '',
      set: () => {},
      consumeNotice: () => ({ present: false }),
      consumeAlert: () => ''
    },
    contentFor: {},
    request: {
      headers: { accept: 'text/html' }
    },
    ...overrides
  });

  // Controller create
  const ctrlContext = createContext();
  const createResult = await NotesController.create(ctrlContext, {
    title: 'Controller Note',
    body: 'Created via controller'
  });
  assert(createResult.redirect !== undefined, 'create action returns redirect');

  // JSON API
  const jsonContext = {
    ...createContext(),
    request: { headers: { accept: 'application/json' } }
  };
  const indexResult = await NotesController.index(jsonContext);
  assert(indexResult && indexResult.json !== undefined, 'index returns JSON when Accept is application/json');

  console.log(`\n=== Results: ${passed} passed, ${failed} failed ===`);
  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(e => {
  console.error('Test error:', e);
  process.exit(1);
});
